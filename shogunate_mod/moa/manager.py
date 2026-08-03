#!/usr/bin/env python3
"""Configure and run one Shogunate role as a temporary MoA deployment.

AGMSG is intentionally only a notification transport. Assignments, proposals,
the representative's final artifact, and provenance receipts remain under the
Shogunate runtime root.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Mapping, Protocol, Sequence

import yaml

try:
    import fcntl
except ImportError:  # pragma: no cover - supported runtime uses WSL/macOS
    fcntl = None  # type: ignore[assignment]


SCHEMA_VERSION = 1
STATE_SCHEMA_VERSION = 1
MAX_MEMBERS = 8
MAX_ARTIFACT_BYTES = 1_000_000
IDENTIFIER_RE = re.compile(r"^[a-z][a-z0-9_-]{0,63}$")
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$")
SECRET_RE = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|credential|bearer)"
)
ALLOWED_MEMBER_TYPES = frozenset(
    {
        "antigravity",
        "claude",
        "codex",
        "copilot",
        "cursor",
        "gemini",
        "grok",
        "opencode",
    }
)
AGMSG_TYPE_MAP = {
    "antigravity": "antigravity",
    "claude": "claude-code",
    "codex": "codex",
    "copilot": "copilot",
    "cursor": "cursor",
    "gemini": "gemini",
    "grok": "grok-build",
    "opencode": "opencode",
}
DECISION_POLICIES = frozenset({"representative", "critical_veto"})
DISSOLVE_POLICIES = frozenset({"finalized", "manual"})


class MoaError(ValueError):
    """Invalid MoA configuration, provenance, or lifecycle transition."""


class MoaTransport(Protocol):
    def send(self, sender: str, target: str, pointer: str) -> tuple[bool, str]:
        """Deliver a non-authoritative pointer and return status without raising."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _canonical_json(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def _digest(value: Any) -> str:
    return hashlib.sha256(_canonical_json(value)).hexdigest()


def _text_digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _identifier(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not IDENTIFIER_RE.fullmatch(value):
        raise MoaError(f"{field}: invalid identifier")
    return value


def _task_id(value: Any) -> str:
    if not isinstance(value, str) or not TASK_ID_RE.fullmatch(value):
        raise MoaError("task_id: invalid identifier")
    return value


def _bounded_string(value: Any, *, field: str, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise MoaError(f"{field}: must be a string")
    result = value.strip()
    if not result and not allow_empty:
        raise MoaError(f"{field}: must not be empty")
    if len(result) > 256:
        raise MoaError(f"{field}: too long")
    if any(ord(char) < 0x20 or ord(char) == 0x7F for char in result):
        raise MoaError(f"{field}: control characters are not allowed")
    return result


def _reject_secret_keys(value: Any, *, path: str = "") -> None:
    if isinstance(value, Mapping):
        for key, nested in value.items():
            name = str(key)
            current = f"{path}.{name}" if path else name
            if SECRET_RE.search(name):
                raise MoaError(f"{current}: secret-like key is not allowed")
            _reject_secret_keys(nested, path=current)
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            _reject_secret_keys(nested, path=f"{path}[{index}]")


@dataclass(frozen=True)
class MemberProfile:
    alias: str
    agent: str
    type: str
    model: str
    runtime: str

    @property
    def diversity_fingerprint(self) -> str:
        return _digest(
            {
                "type": self.type,
                "model": self.model or "<default>",
                "runtime": self.runtime,
            }
        )

    def to_dict(self) -> dict[str, str]:
        return {
            "agent": self.agent,
            "type": self.type,
            "model": self.model,
            "runtime": self.runtime,
        }


@dataclass(frozen=True)
class RoleProfile:
    mode: str
    representative: str | None
    members: dict[str, MemberProfile]
    quorum: int
    decision_policy: str
    dissolve_after: str

    @classmethod
    def single(cls) -> "RoleProfile":
        return cls(
            mode="single",
            representative=None,
            members={},
            quorum=0,
            decision_policy="representative",
            dissolve_after="manual",
        )

    def to_dict(self) -> dict[str, Any]:
        if self.mode == "single":
            return {"mode": "single"}
        return {
            "mode": "moa",
            "representative": self.representative,
            "members": {
                alias: member.to_dict() for alias, member in self.members.items()
            },
            "quorum": self.quorum,
            "decision_policy": self.decision_policy,
            "dissolve_after": self.dissolve_after,
        }


@dataclass(frozen=True)
class MoaConfig:
    roles: dict[str, RoleProfile]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": SCHEMA_VERSION,
            "roles": {role: profile.to_dict() for role, profile in self.roles.items()},
        }


def _parse_member(alias: str, raw: Any, *, field: str) -> MemberProfile:
    _identifier(alias, field=f"{field}.alias")
    if not isinstance(raw, Mapping):
        raise MoaError(f"{field}: must be a mapping")
    unknown = set(raw) - {"agent", "type", "model", "runtime"}
    missing = {"agent", "type", "model", "runtime"} - set(raw)
    if unknown:
        raise MoaError(f"{field}: unknown field '{sorted(unknown)[0]}'")
    if missing:
        raise MoaError(f"{field}: missing field '{sorted(missing)[0]}'")
    agent = _identifier(raw["agent"], field=f"{field}.agent")
    cli_type = _bounded_string(raw["type"], field=f"{field}.type").lower()
    if cli_type not in ALLOWED_MEMBER_TYPES:
        raise MoaError(f"{field}.type: unsupported CLI '{cli_type}'")
    model = _bounded_string(raw["model"], field=f"{field}.model", allow_empty=True)
    runtime = _bounded_string(raw["runtime"], field=f"{field}.runtime")
    return MemberProfile(alias, agent, cli_type, model, runtime)


def parse_role_profile(raw: Any, *, field: str) -> RoleProfile:
    if not isinstance(raw, Mapping):
        raise MoaError(f"{field}: must be a mapping")
    _reject_secret_keys(raw, path=field)
    mode = _bounded_string(raw.get("mode"), field=f"{field}.mode").lower()
    if mode == "single":
        unknown = set(raw) - {"mode"}
        if unknown:
            raise MoaError(f"{field}: single mode only accepts mode")
        return RoleProfile.single()
    if mode != "moa":
        raise MoaError(f"{field}.mode: must be single or moa")

    allowed = {
        "mode",
        "representative",
        "members",
        "quorum",
        "decision_policy",
        "dissolve_after",
    }
    unknown = set(raw) - allowed
    missing = allowed - set(raw)
    if unknown:
        raise MoaError(f"{field}: unknown field '{sorted(unknown)[0]}'")
    if missing:
        raise MoaError(f"{field}: missing field '{sorted(missing)[0]}'")

    raw_members = raw["members"]
    if not isinstance(raw_members, Mapping):
        raise MoaError(f"{field}.members: must be a mapping")
    if not 2 <= len(raw_members) <= MAX_MEMBERS:
        raise MoaError(f"{field}.members: must contain 2 to {MAX_MEMBERS} members")
    members = {
        str(alias): _parse_member(
            str(alias), details, field=f"{field}.members.{alias}"
        )
        for alias, details in raw_members.items()
    }
    agents = [item.agent for item in members.values()]
    if len(agents) != len(set(agents)):
        raise MoaError(f"{field}.members: duplicate AGMSG agent identity")
    fingerprints = [item.diversity_fingerprint for item in members.values()]
    if len(fingerprints) != len(set(fingerprints)):
        raise MoaError(f"{field}.members: same model and runtime cannot count twice")

    representative = _identifier(
        raw["representative"], field=f"{field}.representative"
    )
    if representative not in members:
        raise MoaError(f"{field}.representative must be a member")
    quorum = raw["quorum"]
    if isinstance(quorum, bool) or not isinstance(quorum, int):
        raise MoaError(f"{field}.quorum: must be an integer")
    if not 2 <= quorum <= len(members):
        raise MoaError(f"{field}.quorum: must be between 2 and member count")
    decision_policy = _bounded_string(
        raw["decision_policy"], field=f"{field}.decision_policy"
    ).lower()
    if decision_policy not in DECISION_POLICIES:
        raise MoaError(f"{field}.decision_policy: unsupported policy")
    dissolve_after = _bounded_string(
        raw["dissolve_after"], field=f"{field}.dissolve_after"
    ).lower()
    if dissolve_after not in DISSOLVE_POLICIES:
        raise MoaError(f"{field}.dissolve_after: unsupported policy")
    return RoleProfile(
        mode="moa",
        representative=representative,
        members=members,
        quorum=quorum,
        decision_policy=decision_policy,
        dissolve_after=dissolve_after,
    )


def parse_member_specs(specs: Sequence[str]) -> dict[str, MemberProfile]:
    members: dict[str, MemberProfile] = {}
    for index, spec in enumerate(specs):
        if not isinstance(spec, str) or "=" not in spec:
            raise MoaError(
                f"--member[{index}] must be ALIAS=AGENT,TYPE,MODEL,RUNTIME"
            )
        alias, details = spec.split("=", 1)
        if alias in members:
            raise MoaError(f"duplicate member alias: {alias}")
        parts = details.split(",")
        if len(parts) != 4:
            raise MoaError(
                f"--member[{index}] must be ALIAS=AGENT,TYPE,MODEL,RUNTIME"
            )
        agent, cli_type, model, runtime = parts
        if model == "-":
            model = ""
        members[alias] = _parse_member(
            alias,
            {
                "agent": agent,
                "type": cli_type,
                "model": model,
                "runtime": runtime,
            },
            field=f"--member[{index}]",
        )
    return members


def load_moa_config(path: Path) -> MoaConfig:
    if not path.is_file():
        return MoaConfig(roles={})
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError) as exc:
        raise MoaError(f"failed to load MoA config: {path}") from exc
    if not isinstance(raw, Mapping):
        raise MoaError("MoA config root must be a mapping")
    _reject_secret_keys(raw)
    unknown = set(raw) - {"schema_version", "roles"}
    if unknown:
        raise MoaError(f"MoA config: unknown field '{sorted(unknown)[0]}'")
    if raw.get("schema_version") != SCHEMA_VERSION:
        raise MoaError(f"MoA config schema_version must be {SCHEMA_VERSION}")
    raw_roles = raw.get("roles")
    if not isinstance(raw_roles, Mapping):
        raise MoaError("MoA config roles must be a mapping")
    roles: dict[str, RoleProfile] = {}
    for raw_role, raw_profile in raw_roles.items():
        role = _identifier(str(raw_role), field="role")
        roles[role] = parse_role_profile(raw_profile, field=f"roles.{role}")
    return MoaConfig(roles=roles)


def _atomic_yaml(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            yaml.safe_dump(value, stream, allow_unicode=True, sort_keys=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def _atomic_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class AgmsgTransport:
    """Invoke AGMSG's official send script without inspecting its database."""

    def __init__(self, runtime_root: Path) -> None:
        self.runtime_root = runtime_root
        self.team = "shogunate"
        self.skill_dir = Path.home() / ".agents/skills/agmsg"
        settings = runtime_root / "config/settings.yaml"
        if settings.is_file():
            try:
                raw = yaml.safe_load(settings.read_text(encoding="utf-8")) or {}
                transport = raw.get("transport") if isinstance(raw, Mapping) else None
                agmsg = transport.get("agmsg") if isinstance(transport, Mapping) else None
                if isinstance(agmsg, Mapping):
                    team = agmsg.get("team")
                    skill_dir = agmsg.get("skill_dir")
                    if isinstance(team, str) and team.strip():
                        self.team = team.strip()
                    if isinstance(skill_dir, str) and skill_dir.strip():
                        self.skill_dir = Path(skill_dir.strip()).expanduser()
            except (OSError, yaml.YAMLError):
                pass
        override = os.environ.get("AGMSG_SKILL_DIR")
        if override:
            self.skill_dir = Path(override).expanduser()

    def send(self, sender: str, target: str, pointer: str) -> tuple[bool, str]:
        send_script = self.skill_dir / "scripts/send.sh"
        if not send_script.is_file():
            return False, f"send.sh not found: {send_script}"
        try:
            result = subprocess.run(
                ["bash", str(send_script), self.team, sender, target, pointer],
                cwd=self.runtime_root,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return False, type(exc).__name__
        if result.returncode:
            return False, f"send.sh exited {result.returncode}"
        return True, "sent"


class MoaManager:
    def __init__(
        self,
        project_root: Path,
        runtime_root: Path,
        *,
        config_path: Path | None = None,
        transport: MoaTransport | None = None,
    ) -> None:
        self.project_root = project_root.resolve()
        self.runtime_root = runtime_root.resolve()
        self.config_path = (
            config_path.resolve()
            if config_path
            else self.runtime_root / "config/moa.yaml"
        )
        try:
            self.config_path.relative_to(self.runtime_root)
        except ValueError as exc:
            raise MoaError("MoA config must be inside the Shogunate runtime") from exc
        self.transport = transport or AgmsgTransport(self.runtime_root)

    @contextmanager
    def _lock(self, role: str, task_id: str) -> Iterator[None]:
        lock_path = self.runtime_root / "queue/moa" / role / task_id / ".lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("a+", encoding="utf-8") as stream:
            if fcntl is not None:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                if fcntl is not None:
                    fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    def configure(self, role: str, profile: RoleProfile) -> dict[str, Any]:
        return self.configure_many({role: profile})

    def configure_many(
        self, profiles: Mapping[str, RoleProfile]
    ) -> dict[str, Any]:
        """Atomically replace several role defaults from one configure session."""
        if not profiles:
            raise MoaError("at least one role profile is required")
        validated_profiles: dict[str, RoleProfile] = {}
        for raw_role, profile in profiles.items():
            role = _identifier(raw_role, field="role")
            if not isinstance(profile, RoleProfile):
                raise MoaError(f"roles.{role}: invalid role profile")
            # Round-trip through the strict parser so callers cannot construct an
            # invalid dataclass and bypass the public configuration contract.
            validated_profiles[role] = parse_role_profile(
                profile.to_dict(), field=f"roles.{role}"
            )
        config = load_moa_config(self.config_path)
        roles = dict(config.roles)
        roles.update(validated_profiles)
        result = MoaConfig(roles=roles).to_dict()
        _atomic_yaml(self.config_path, result)
        return result

    def show(self, role: str | None = None) -> dict[str, Any]:
        config = load_moa_config(self.config_path)
        if role is None:
            return config.to_dict()
        normalized = _identifier(role, field="role")
        if normalized not in config.roles:
            return RoleProfile.single().to_dict()
        return config.roles[normalized].to_dict()

    def resolve_profile(
        self, role: str, override: RoleProfile | None = None
    ) -> RoleProfile:
        role = _identifier(role, field="role")
        profile = override or load_moa_config(self.config_path).roles.get(role)
        if profile is None or profile.mode == "single":
            raise MoaError(f"role '{role}' is configured as single")
        return parse_role_profile(profile.to_dict(), field=f"roles.{role}")

    def _task_root(self, role: str, task_id: str) -> Path:
        return self._runtime_path(
            Path("queue/moa") / role / task_id, field="MoA task path"
        )

    def _runtime_path(self, relative: Path | str, *, field: str) -> Path:
        candidate = (self.runtime_root / relative).resolve()
        try:
            candidate.relative_to(self.runtime_root)
        except ValueError as exc:
            raise MoaError(f"{field} escapes the Shogunate runtime") from exc
        return candidate

    def _read_yaml_mapping(self, path: Path, *, field: str) -> dict[str, Any]:
        try:
            raw = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            raise MoaError(f"failed to read {field}: {path}") from exc
        if not isinstance(raw, dict):
            raise MoaError(f"{field}: must be a mapping")
        return raw

    def _current_state(self, role: str, task_id: str) -> dict[str, Any]:
        current_path = self._task_root(role, task_id) / "current.yaml"
        if not current_path.is_file():
            raise MoaError("MoA deployment not found")
        current = self._read_yaml_mapping(current_path, field="current pointer")
        if current.get("role") != role or current.get("task_id") != task_id:
            raise MoaError("current pointer provenance mismatch")
        state_rel = current.get("state_path")
        if not isinstance(state_rel, str):
            raise MoaError("current pointer state_path is invalid")
        state_path = self._runtime_path(state_rel, field="current pointer")
        state = self._read_yaml_mapping(state_path, field="deployment state")
        if (
            state.get("schema_version") != STATE_SCHEMA_VERSION
            or state.get("role") != role
            or state.get("task_id") != task_id
            or state.get("generation") != current.get("generation")
        ):
            raise MoaError("deployment state provenance mismatch")
        state["_state_path"] = state_rel
        return state

    def _write_state(self, state: dict[str, Any]) -> None:
        state_rel = state.pop("_state_path", None)
        if not isinstance(state_rel, str):
            generation = state["generation"]
            state_rel = (
                Path("queue/moa")
                / state["role"]
                / state["task_id"]
                / f"generation-{generation}"
                / "state.yaml"
            ).as_posix()
        _atomic_yaml(self._runtime_path(state_rel, field="deployment state"), state)
        state["_state_path"] = state_rel

    def _safe_project_text(self, path: Path, *, field: str) -> str:
        resolved = path.resolve()
        try:
            relative = resolved.relative_to(self.project_root)
        except ValueError as exc:
            raise MoaError(f"{field} must be inside the project") from exc
        if any(SECRET_RE.search(part) for part in relative.parts):
            raise MoaError(f"{field}: secret-like path is not allowed")
        try:
            size = resolved.stat().st_size
            if size > MAX_ARTIFACT_BYTES:
                raise MoaError(f"{field}: file is too large")
            return resolved.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            raise MoaError(f"failed to read {field}: {resolved}") from exc

    def deploy(
        self,
        role: str,
        task_id: str,
        brief_file: Path,
        *,
        sender: str,
        override: RoleProfile | None = None,
    ) -> dict[str, Any]:
        role = _identifier(role, field="role")
        task_id = _task_id(task_id)
        sender = _identifier(sender, field="sender")
        profile = self.resolve_profile(role, override)
        brief = self._safe_project_text(brief_file, field="brief file")
        profile_dict = profile.to_dict()
        profile_digest = _digest(profile_dict)
        brief_digest = _text_digest(brief)
        task_root = self._task_root(role, task_id)

        with self._lock(role, task_id):
            current_path = task_root / "current.yaml"
            generation = 1
            if current_path.is_file():
                current = self._current_state(role, task_id)
                if current["status"] in {"active", "finalized"}:
                    if (
                        current["status"] == "active"
                        and current["profile_digest"] == profile_digest
                        and current["brief_digest"] == brief_digest
                    ):
                        current.pop("_state_path", None)
                        return current
                    raise MoaError("active deployment already exists with different input")
                generation = int(current["generation"]) + 1

            generation_root = task_root / f"generation-{generation}"
            if generation_root.exists():
                raise MoaError("generation directory already exists")
            generation_root.mkdir(parents=True)
            _atomic_text(generation_root / "brief.txt", brief)
            deployment_id = f"{role}-{task_id}-g{generation}"
            assignments: dict[str, Any] = {}
            issued_at = utc_now()
            brief_rel = (generation_root / "brief.txt").relative_to(
                self.runtime_root
            ).as_posix()
            for alias, member_profile in profile.members.items():
                assignment = {
                    "schema_version": STATE_SCHEMA_VERSION,
                    "deployment_id": deployment_id,
                    "role": role,
                    "task_id": task_id,
                    "generation": generation,
                    "member": alias,
                    "member_profile": member_profile.to_dict(),
                    "representative": profile.representative,
                    "representative_agent": profile.members[
                        profile.representative or ""
                    ].agent,
                    "profile_digest": profile_digest,
                    "brief_path": brief_rel,
                    "issued_at": issued_at,
                    "authority": "Shogunate YAML is authoritative; AGMSG is notification only.",
                    "submission": {
                        "command": (
                            f"shogunate moa submit {role} --task-id {task_id} "
                            f"--member {alias} --assignment-digest "
                            "<assignment_digest> --artifact-file <proposal-file>"
                        ),
                        "required_agent_id": member_profile.agent,
                    },
                }
                if alias == profile.representative:
                    assignment["finalization"] = {
                        "command": (
                            f"shogunate moa finalize {role} --task-id {task_id} "
                            "--artifact-file <final-file>"
                        ),
                        "requires_quorum": profile.quorum,
                    }
                assignment_digest = _digest(assignment)
                assignment["assignment_digest"] = assignment_digest
                relative = (
                    generation_root
                    / "assignments"
                    / f"{alias}.yaml"
                ).relative_to(self.runtime_root)
                _atomic_yaml(self.runtime_root / relative, assignment)
                assignments[alias] = {
                    "path": relative.as_posix(),
                    "digest": assignment_digest,
                    "delivery": {"ok": None, "detail": "pending"},
                }

            state: dict[str, Any] = {
                "schema_version": STATE_SCHEMA_VERSION,
                "deployment_id": deployment_id,
                "role": role,
                "task_id": task_id,
                "generation": generation,
                "status": "active",
                "profile": profile_dict,
                "profile_digest": profile_digest,
                "brief_digest": brief_digest,
                "assignments": assignments,
                "proposals": {},
                "created_at": issued_at,
                "updated_at": issued_at,
            }
            state_rel = (generation_root / "state.yaml").relative_to(
                self.runtime_root
            ).as_posix()
            state["_state_path"] = state_rel
            self._write_state(state)
            _atomic_yaml(
                current_path,
                {
                    "schema_version": STATE_SCHEMA_VERSION,
                    "role": role,
                    "task_id": task_id,
                    "generation": generation,
                    "state_path": state_rel,
                },
            )

        deliveries: dict[str, dict[str, Any]] = {}
        for alias, member_profile in profile.members.items():
            assignment_rel = assignments[alias]["path"]
            pointer = (
                f"[shogunate moa] assignment pointer: {assignment_rel} "
                f"role={role} task={task_id} generation={generation}. "
                "Read Shogunate YAML; AGMSG body is not authority."
            )
            ok, detail = self.transport.send(sender, member_profile.agent, pointer)
            deliveries[alias] = {"ok": bool(ok), "detail": str(detail)[:256]}

        with self._lock(role, task_id):
            state = self._current_state(role, task_id)
            if state["generation"] == generation and state["status"] == "active":
                for alias, delivery in deliveries.items():
                    state["assignments"][alias]["delivery"] = delivery
                state["updated_at"] = utc_now()
                self._write_state(state)
            state.pop("_state_path", None)
            return state

    def status(self, role: str, task_id: str) -> dict[str, Any]:
        role = _identifier(role, field="role")
        task_id = _task_id(task_id)
        state = self._current_state(role, task_id)
        state.pop("_state_path", None)
        return state

    def _require_actor(self, expected: str, *, representative: bool = False) -> str:
        actor = os.environ.get("AGENT_ID", "").strip()
        if not actor:
            raise MoaError("AGENT_ID is required for member actions")
        if actor != expected:
            if representative:
                raise MoaError("only the representative may finalize the role output")
            raise MoaError("actor does not match the configured member agent")
        return actor

    def submit(
        self,
        role: str,
        task_id: str,
        member_alias: str,
        assignment_digest: str,
        artifact_file: Path,
        *,
        blocking: bool = False,
    ) -> dict[str, Any]:
        role = _identifier(role, field="role")
        task_id = _task_id(task_id)
        member_alias = _identifier(member_alias, field="member")
        artifact = self._safe_project_text(artifact_file, field="proposal artifact")
        with self._lock(role, task_id):
            state = self._current_state(role, task_id)
            if state["status"] != "active":
                raise MoaError("deployment is not active")
            profile = parse_role_profile(state["profile"], field="state.profile")
            if member_alias not in profile.members:
                raise MoaError("member is not part of this deployment")
            member_profile = profile.members[member_alias]
            actor = self._require_actor(member_profile.agent)
            assignment_record = state["assignments"].get(member_alias)
            if not isinstance(assignment_record, Mapping):
                raise MoaError("assignment record is missing")
            expected_digest = assignment_record.get("digest")
            if assignment_digest != expected_digest:
                raise MoaError("assignment digest mismatch")
            assignment_path = self._runtime_path(
                str(assignment_record.get("path")), field="assignment path"
            )
            assignment = self._read_yaml_mapping(
                assignment_path, field="member assignment"
            )
            stored_assignment_digest = assignment.pop("assignment_digest", None)
            if (
                stored_assignment_digest != expected_digest
                or _digest(assignment) != expected_digest
                or assignment.get("deployment_id") != state["deployment_id"]
                or assignment.get("role") != role
                or assignment.get("task_id") != task_id
                or assignment.get("generation") != state["generation"]
                or assignment.get("member") != member_alias
                or assignment.get("profile_digest") != state["profile_digest"]
            ):
                raise MoaError("assignment provenance mismatch")
            artifact_digest = _text_digest(artifact)
            existing = state["proposals"].get(member_alias)
            if isinstance(existing, Mapping):
                if existing.get("artifact_digest") == artifact_digest:
                    state.pop("_state_path", None)
                    return state
                raise MoaError("member proposal already submitted for this generation")
            generation_root = (
                self._task_root(role, task_id)
                / f"generation-{state['generation']}"
            )
            artifact_rel = (
                generation_root / "proposals" / f"{member_alias}.txt"
            ).relative_to(self.runtime_root)
            _atomic_text(self.runtime_root / artifact_rel, artifact)
            receipt = {
                "member": member_alias,
                "agent": actor,
                "assignment_digest": expected_digest,
                "artifact_digest": artifact_digest,
                "artifact_path": artifact_rel.as_posix(),
                "diversity_fingerprint": member_profile.diversity_fingerprint,
                "blocking": bool(blocking),
                "submitted_at": utc_now(),
            }
            receipt_rel = (
                generation_root / "proposals" / f"{member_alias}.yaml"
            ).relative_to(self.runtime_root)
            _atomic_yaml(self.runtime_root / receipt_rel, receipt)
            receipt["receipt_path"] = receipt_rel.as_posix()
            state["proposals"][member_alias] = receipt
            state["updated_at"] = utc_now()
            self._write_state(state)
            state.pop("_state_path", None)
            return state

    def finalize(
        self, role: str, task_id: str, artifact_file: Path
    ) -> dict[str, Any]:
        role = _identifier(role, field="role")
        task_id = _task_id(task_id)
        artifact = self._safe_project_text(artifact_file, field="final artifact")
        with self._lock(role, task_id):
            state = self._current_state(role, task_id)
            if state["status"] != "active":
                raise MoaError("deployment is not active")
            profile = parse_role_profile(state["profile"], field="state.profile")
            representative = profile.representative or ""
            representative_agent = profile.members[representative].agent
            actor = self._require_actor(representative_agent, representative=True)
            proposals = state.get("proposals")
            if not isinstance(proposals, Mapping):
                raise MoaError("proposal state is invalid")
            fingerprints = {
                str(proposal.get("diversity_fingerprint"))
                for proposal in proposals.values()
                if isinstance(proposal, Mapping)
            }
            if len(proposals) < profile.quorum or len(fingerprints) < profile.quorum:
                raise MoaError("quorum not met")
            if profile.decision_policy == "critical_veto" and any(
                bool(proposal.get("blocking"))
                for proposal in proposals.values()
                if isinstance(proposal, Mapping)
            ):
                raise MoaError("critical veto is unresolved")

            generation_root = (
                self._task_root(role, task_id)
                / f"generation-{state['generation']}"
            )
            final_rel = (generation_root / "final.txt").relative_to(
                self.runtime_root
            )
            _atomic_text(self.runtime_root / final_rel, artifact)
            receipt = {
                "schema_version": STATE_SCHEMA_VERSION,
                "deployment_id": state["deployment_id"],
                "role": role,
                "task_id": task_id,
                "generation": state["generation"],
                "representative": representative,
                "representative_agent": actor,
                "profile_digest": state["profile_digest"],
                "brief_digest": state["brief_digest"],
                "proposal_digests": {
                    alias: proposal["artifact_digest"]
                    for alias, proposal in proposals.items()
                },
                "final_digest": _text_digest(artifact),
                "final_path": final_rel.as_posix(),
                "decision_policy": profile.decision_policy,
                "finalized_at": utc_now(),
            }
            receipt_rel = (generation_root / "receipt.yaml").relative_to(
                self.runtime_root
            )
            _atomic_yaml(self.runtime_root / receipt_rel, receipt)
            state["final"] = {
                "artifact_path": final_rel.as_posix(),
                "artifact_digest": receipt["final_digest"],
                "receipt_path": receipt_rel.as_posix(),
            }
            state["status"] = (
                "dissolved"
                if profile.dissolve_after == "finalized"
                else "finalized"
            )
            state["updated_at"] = utc_now()
            if state["status"] == "dissolved":
                state["dissolved_at"] = state["updated_at"]
            self._write_state(state)
            state.pop("_state_path", None)
            return state

    def dissolve(self, role: str, task_id: str) -> dict[str, Any]:
        role = _identifier(role, field="role")
        task_id = _task_id(task_id)
        with self._lock(role, task_id):
            state = self._current_state(role, task_id)
            if state["status"] == "dissolved":
                state.pop("_state_path", None)
                return state
            if state["status"] not in {"active", "finalized"}:
                raise MoaError("deployment cannot be dissolved from its current state")
            state["status"] = "dissolved"
            state["updated_at"] = utc_now()
            state["dissolved_at"] = state["updated_at"]
            self._write_state(state)
            state.pop("_state_path", None)
            return state

    def agmsg_setup(self, role: str | None = None) -> dict[str, Any]:
        config = load_moa_config(self.config_path)
        selected: dict[str, RoleProfile]
        if role is not None:
            normalized = _identifier(role, field="role")
            profile = config.roles.get(normalized)
            if profile is None or profile.mode != "moa":
                raise MoaError(f"role '{normalized}' has no default MoA profile")
            selected = {normalized: profile}
        else:
            selected = {
                name: profile
                for name, profile in config.roles.items()
                if profile.mode == "moa"
            }
        transport = AgmsgTransport(self.runtime_root)
        join_script = transport.skill_dir / "scripts/join.sh"
        if not join_script.is_file():
            raise MoaError(f"AGMSG join.sh not found: {join_script}")
        results: dict[str, Any] = {}
        seen: set[str] = set()
        for role_name, profile in selected.items():
            for alias, item in profile.members.items():
                if item.agent in seen:
                    continue
                seen.add(item.agent)
                agmsg_type = AGMSG_TYPE_MAP[item.type]
                try:
                    result = subprocess.run(
                        [
                            "bash",
                            str(join_script),
                            transport.team,
                            item.agent,
                            agmsg_type,
                            str(self.project_root),
                        ],
                        cwd=self.runtime_root,
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=15,
                        check=False,
                    )
                    results[item.agent] = {
                        "ok": result.returncode == 0,
                        "role": role_name,
                        "member": alias,
                        "detail": (
                            "joined"
                            if result.returncode == 0
                            else f"join.sh exited {result.returncode}"
                        ),
                    }
                except (OSError, subprocess.TimeoutExpired) as exc:
                    results[item.agent] = {
                        "ok": False,
                        "role": role_name,
                        "member": alias,
                        "detail": type(exc).__name__,
                    }
        return {"team": transport.team, "members": results}


def _profile_from_args(args: argparse.Namespace) -> RoleProfile:
    if args.mode == "single":
        return RoleProfile.single()
    members = parse_member_specs(args.member)
    raw = {
        "mode": "moa",
        "representative": args.representative,
        "members": {alias: item.to_dict() for alias, item in members.items()},
        "quorum": args.quorum,
        "decision_policy": args.decision_policy,
        "dissolve_after": args.dissolve_after,
    }
    return parse_role_profile(raw, field=f"roles.{args.role}")


def _add_profile_arguments(parser: argparse.ArgumentParser, *, mode: bool) -> None:
    if mode:
        parser.add_argument("--mode", choices=("single", "moa"), required=True)
    parser.add_argument(
        "--member",
        action="append",
        default=[],
        metavar="ALIAS=AGENT,TYPE,MODEL,RUNTIME",
    )
    parser.add_argument("--representative")
    parser.add_argument("--quorum", type=int, default=2)
    parser.add_argument(
        "--decision-policy", choices=sorted(DECISION_POLICIES), default="representative"
    )
    parser.add_argument(
        "--dissolve-after", choices=sorted(DISSOLVE_POLICIES), default="finalized"
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Role-scoped Shogunate MoA")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--runtime-root", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--json", action="store_true")
    commands = parser.add_subparsers(dest="command", required=True)

    configure = commands.add_parser("configure")
    configure.add_argument("role")
    _add_profile_arguments(configure, mode=True)

    show = commands.add_parser("show")
    show.add_argument("role", nargs="?")

    deploy = commands.add_parser("deploy")
    deploy.add_argument("role")
    deploy.add_argument("--task-id", required=True)
    deploy.add_argument("--brief-file", type=Path, required=True)
    deploy.add_argument("--sender", default=os.environ.get("AGENT_ID") or "shogun")
    _add_profile_arguments(deploy, mode=False)

    status = commands.add_parser("status")
    status.add_argument("role")
    status.add_argument("--task-id", required=True)

    submit = commands.add_parser("submit")
    submit.add_argument("role")
    submit.add_argument("--task-id", required=True)
    submit.add_argument("--member", required=True)
    submit.add_argument("--assignment-digest", required=True)
    submit.add_argument("--artifact-file", type=Path, required=True)
    submit.add_argument("--blocking", action="store_true")

    finalize = commands.add_parser("finalize")
    finalize.add_argument("role")
    finalize.add_argument("--task-id", required=True)
    finalize.add_argument("--artifact-file", type=Path, required=True)

    dissolve = commands.add_parser("dissolve")
    dissolve.add_argument("role")
    dissolve.add_argument("--task-id", required=True)

    setup = commands.add_parser("agmsg-setup")
    setup.add_argument("role", nargs="?")
    return parser


def _print_result(value: Any, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(value, ensure_ascii=False, sort_keys=True))
    else:
        print(yaml.safe_dump(value, allow_unicode=True, sort_keys=False).rstrip())


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    project_root = args.project_root.resolve()
    runtime_root = (
        args.runtime_root.resolve()
        if args.runtime_root
        else Path(os.environ.get("SHOGUNATE_RUNTIME_DIR") or project_root).resolve()
    )
    manager = MoaManager(
        project_root,
        runtime_root,
        config_path=args.config,
    )
    if args.command == "configure":
        result = manager.configure(args.role, _profile_from_args(args))
    elif args.command == "show":
        result = manager.show(args.role)
    elif args.command == "deploy":
        has_override = bool(args.member or args.representative)
        if has_override:
            args.mode = "moa"
            override = _profile_from_args(args)
        else:
            override = None
        result = manager.deploy(
            args.role,
            args.task_id,
            args.brief_file,
            sender=args.sender,
            override=override,
        )
    elif args.command == "status":
        result = manager.status(args.role, args.task_id)
    elif args.command == "submit":
        result = manager.submit(
            args.role,
            args.task_id,
            args.member,
            args.assignment_digest,
            args.artifact_file,
            blocking=args.blocking,
        )
    elif args.command == "finalize":
        result = manager.finalize(args.role, args.task_id, args.artifact_file)
    elif args.command == "dissolve":
        result = manager.dissolve(args.role, args.task_id)
    else:
        result = manager.agmsg_setup(args.role)
    _print_result(result, as_json=args.json)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except MoaError as exc:
        print(f"[shogunate moa] {exc}", file=os.sys.stderr)
        raise SystemExit(64) from exc
