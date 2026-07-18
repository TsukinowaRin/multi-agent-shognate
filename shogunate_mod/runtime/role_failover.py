#!/usr/bin/env python3
"""Non-LLM Primary/Fallback role failover controller.

Persists role slot state under queue/runtime/role_failover.yaml and returns only
fixed action enums. Never executes shell commands from state or events.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, MutableMapping, Optional
from urllib.parse import urlsplit

try:
    import fcntl
except ImportError:  # pragma: no cover - Windows path kept import-safe
    fcntl = None  # type: ignore[assignment]

import yaml

SCHEMA_VERSION = 1
STATE_RELATIVE = Path("queue/runtime/role_failover.yaml")
AUDIT_RELATIVE = Path("queue/runtime/role_failover_audit.yaml")
OUTBOX_RELATIVE = Path("queue/runtime/app_outbox.yaml")

ALLOWED_CLIS = frozenset(
    {"codex", "antigravity", "claude", "opencode", "kilo", "localapi", "kimi", "copilot", "cursor", "grok"}
)
LEGACY_CLI_ALIASES = {"gemini": "antigravity", "agy": "antigravity"}

CORE_ROLES = frozenset({"shogun", "gunkan", "karo", "gunshi"})
UPPER_SAFE_STOP_ROLES = frozenset({"gunkan", "karo", "gunshi"})
ASHIGARU_RE = re.compile(r"^ashigaru([1-9][0-9]*)$")

SLOT_PRIMARY = "primary"
SLOT_FALLBACK = "fallback"
SLOTS = frozenset({SLOT_PRIMARY, SLOT_FALLBACK})

STATUS_READY = "ready"
STATUS_RESTARTING = "restarting"
STATUS_SWITCHING = "switching"
STATUS_STOPPED = "stopped"
STATUS_SAFE_STOPPED = "safe_stopped"
STATUS_EMERGENCY = "emergency"
STATUS_AWAITING_HANDOFF = "awaiting_handoff"
STATUS_WARNING = "warning"
VALID_STATUSES = frozenset(
    {
        STATUS_READY, STATUS_RESTARTING, STATUS_SWITCHING, STATUS_STOPPED, STATUS_SAFE_STOPPED,
        STATUS_EMERGENCY, STATUS_AWAITING_HANDOFF, STATUS_WARNING,
    }
)

ACTION_NONE = "none"
ACTION_RESTART_PRIMARY = "restart_primary"
ACTION_ACTIVATE_FALLBACK = "activate_fallback"
ACTION_SAFE_STOP = "safe_stop"
ACTION_REQUEST_REASSIGNMENT = "request_reassignment"
ACTION_ENTER_EMERGENCY = "enter_emergency"
ACTION_WARN = "warn"
ACTION_MARK_HANDOFF_REQUIRED = "mark_handoff_required"
ACTION_RESUME_AFTER_HANDOFF = "resume_after_handoff"
ACTION_RESTORE_PRIMARY = "restore_primary"
ACTION_AUTHORIZE = "authorize"
ACTION_REJECT = "reject"

KNOWN_ACTIONS = frozenset(
    {
        ACTION_NONE,
        ACTION_RESTART_PRIMARY,
        ACTION_ACTIVATE_FALLBACK,
        ACTION_SAFE_STOP,
        ACTION_REQUEST_REASSIGNMENT,
        ACTION_ENTER_EMERGENCY,
        ACTION_WARN,
        ACTION_MARK_HANDOFF_REQUIRED,
        ACTION_RESUME_AFTER_HANDOFF,
        ACTION_RESTORE_PRIMARY,
        ACTION_AUTHORIZE,
        ACTION_REJECT,
    }
)

EVENT_PROCESS_EXIT = "process_exit"
EVENT_EXPLICIT_FAILURE = "explicit_failure"
EVENT_NO_PROGRESS = "no_progress"
EVENT_PROGRESS = "progress"
EVENT_WORK_STATE_UPDATE = "work_state_update"
EVENT_WORK_COMPLETE = "work_complete"
EVENT_HANDOFF_VALIDATE = "handoff_validate"
EVENT_HANDOFF_COMPLETE = "handoff_complete"
EVENT_PRIMARY_RECOVERED = "primary_recovered"
EVENT_EMERGENCY_PLAN_COMPLETE = "emergency_plan_complete"
EVENT_EMERGENCY_OUT_OF_SCOPE = "emergency_out_of_scope"
EVENT_EMERGENCY_AUTHORIZE_WORK = "emergency_authorize_work"
EVENT_INIT_ROLE = "init_role"
EVENT_USER_STOP = "user_stop"

EXPLICIT_FAILURE_REASONS = frozenset(
    {"rate_limit", "auth_error", "model_unavailable", "config_error"}
)

HANDOFF_REQUIRED_FIELDS = (
    "role",
    "generation",
    "work_id",
    "purpose",
    "acceptance_criteria",
    "approved_plan_id",
    "approved_plan_revision",
    "progress",
    "scope",
    "next_step",
)
WORK_STATE_FIELDS = frozenset(
    {
        "work_id", "command_id", "task_id", "purpose", "acceptance_criteria", "priority",
        "approved_scope", "approved_plan_id", "approved_plan_revision", "approved_changes",
        "denied_changes", "pending_deviations", "progress", "scope", "ownership", "conflicts",
        "tests", "blockers", "constraints", "failure_notes", "directions", "unread_messages",
        "report_target", "next_step", "lease_id",
    }
)
HANDOFF_ALLOWED_FIELDS = WORK_STATE_FIELDS | {"role", "generation", "failure_reason"}

SECRET_KEY_RE = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|"
    r"credential|auth[_-]?token|bearer|session[_-]?key)"
)
MAX_MODEL_LEN = 128
MAX_REASONING_LEN = 64
MAX_ENDPOINT_LEN = 512
MAX_EVENT_ID_LEN = 128
MAX_EVENT_REASON_LEN = 64
MAX_AUDIT_EVENTS = 500
MAX_OUTBOX_EVENTS = 200

KNOWN_EVENT_TYPES = frozenset(
    {
        EVENT_PROCESS_EXIT,
        EVENT_EXPLICIT_FAILURE,
        EVENT_NO_PROGRESS,
        EVENT_PROGRESS,
        EVENT_WORK_STATE_UPDATE,
        EVENT_WORK_COMPLETE,
        EVENT_HANDOFF_VALIDATE,
        EVENT_HANDOFF_COMPLETE,
        EVENT_PRIMARY_RECOVERED,
        EVENT_EMERGENCY_PLAN_COMPLETE,
        EVENT_EMERGENCY_OUT_OF_SCOPE,
        EVENT_EMERGENCY_AUTHORIZE_WORK,
        EVENT_INIT_ROLE,
        EVENT_USER_STOP,
    }
)

# Reasons cross the controller's durable audit/app boundary, so accept only
# protocol vocabulary here. The shell runner has the same check, but callers
# can invoke apply-event directly and must not be able to persist free text.
EVENT_REASON_ALLOWLIST = {
    EVENT_PROCESS_EXIT: frozenset({"process_exit", "shell_return", *EXPLICIT_FAILURE_REASONS}),
    EVENT_EXPLICIT_FAILURE: EXPLICIT_FAILURE_REASONS,
    EVENT_NO_PROGRESS: frozenset({"no_progress"}),
    EVENT_PROGRESS: frozenset({"progress"}),
    EVENT_PRIMARY_RECOVERED: frozenset({"primary_recovered"}),
    EVENT_USER_STOP: frozenset({"intentional_stop"}),
}
EVENT_REASON_DEFAULTS = {
    EVENT_PROCESS_EXIT: "process_exit",
    EVENT_NO_PROGRESS: "no_progress",
    EVENT_PROGRESS: "progress",
    EVENT_PRIMARY_RECOVERED: "primary_recovered",
    EVENT_USER_STOP: "intentional_stop",
}

_ROLE_RE = re.compile(r"^(shogun|gunkan|karo(?:[1-9][0-9]*)?|gunshi|ashigaru[1-9][0-9]*)$")


class FailoverError(ValueError):
    """Base validation or transition error."""


class FailoverConflict(FailoverError):
    """Stale generation or concurrent mutation conflict."""


class FailoverSecurityError(FailoverError):
    """Secret-like data or disallowed payload."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def is_role_name(value: Any) -> bool:
    return isinstance(value, str) and bool(_ROLE_RE.fullmatch(value))


def is_ashigaru(role: str) -> bool:
    return bool(ASHIGARU_RE.fullmatch(role))


def normalize_event_reason(event_type: str, raw_reason: Any) -> Optional[str]:
    if event_type not in KNOWN_EVENT_TYPES:
        raise FailoverError(f"unsupported event type: {event_type}")
    if raw_reason is None:
        if event_type == EVENT_EXPLICIT_FAILURE:
            raise FailoverError("event.reason is required for explicit_failure")
        return EVENT_REASON_DEFAULTS.get(event_type)
    if not isinstance(raw_reason, str):
        raise FailoverError("event.reason must be a string")
    if not raw_reason or len(raw_reason) > MAX_EVENT_REASON_LEN:
        raise FailoverError("event.reason is invalid")
    if any(ord(ch) < 0x20 or ord(ch) == 0x7F for ch in raw_reason):
        raise FailoverError("event.reason contains control characters")
    allowed = EVENT_REASON_ALLOWLIST.get(event_type)
    if allowed is None or raw_reason not in allowed:
        raise FailoverError(f"event.reason is not allowed for {event_type}")
    return raw_reason


def _reject_secret_keys(mapping: Mapping[str, Any], *, path: str = "") -> None:
    for key, value in mapping.items():
        key_s = str(key)
        full = f"{path}.{key_s}" if path else key_s
        if SECRET_KEY_RE.search(key_s):
            raise FailoverSecurityError(f"secret-like key rejected: {full}")
        if isinstance(value, Mapping):
            _reject_secret_keys(value, path=full)
        elif isinstance(value, list):
            for idx, item in enumerate(value):
                if isinstance(item, Mapping):
                    _reject_secret_keys(item, path=f"{full}[{idx}]")


def normalize_cli(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise FailoverError(f"{field}: CLI type is required")
    normalized = LEGACY_CLI_ALIASES.get(value.strip().lower(), value.strip().lower())
    if normalized not in ALLOWED_CLIS:
        raise FailoverError(f"{field}: unsupported CLI '{value}'")
    return normalized


def normalize_optional_str(value: Any, *, field: str, max_len: int) -> Optional[str]:
    if value is None:
        return None
    if not isinstance(value, str):
        raise FailoverError(f"{field}: must be a string")
    text = value.strip()
    if not text:
        return None
    if len(text) > max_len:
        raise FailoverError(f"{field}: exceeds max length {max_len}")
    if any(ord(char) < 32 or ord(char) == 127 for char in text):
        raise FailoverError(f"{field}: control characters are not allowed")
    return text


def normalize_thinking(value: Any) -> Optional[bool]:
    if value is None:
        return None
    # bool is a subclass of int; accept only real booleans.
    if type(value) is bool:
        return value
    raise FailoverError("thinking must be a boolean or null")


def normalize_endpoint(value: Any, *, field: str) -> Optional[str]:
    endpoint = normalize_optional_str(value, field=field, max_len=MAX_ENDPOINT_LEN)
    if endpoint is None:
        return None
    parsed = urlsplit(endpoint)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise FailoverSecurityError(f"{field}: endpoint must be an http(s) URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise FailoverSecurityError(f"{field}: credentials, query, and fragment are not allowed")
    return endpoint


@dataclass(frozen=True)
class RoleProfile:
    type: str
    model: Optional[str] = None
    reasoning_effort: Optional[str] = None
    thinking: Optional[bool] = None
    effort: Optional[str] = None
    variant: Optional[str] = None
    endpoint: Optional[str] = None
    recommended_model: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        data: dict[str, Any] = {"type": self.type}
        if self.model is not None:
            data["model"] = self.model
        if self.reasoning_effort is not None:
            data["reasoning_effort"] = self.reasoning_effort
        if self.thinking is not None:
            data["thinking"] = self.thinking
        if self.effort is not None:
            data["effort"] = self.effort
        if self.variant is not None:
            data["variant"] = self.variant
        if self.endpoint is not None:
            data["endpoint"] = self.endpoint
        if self.recommended_model is not None:
            data["recommended_model"] = self.recommended_model
        return data

    @classmethod
    def from_mapping(cls, raw: Any, *, field: str) -> "RoleProfile":
        if isinstance(raw, str):
            return cls(type=normalize_cli(raw, field=f"{field}.type"))
        if not isinstance(raw, Mapping):
            raise FailoverError(f"{field}: must be a mapping or CLI string")
        _reject_secret_keys(raw, path=field)
        allowed = {
            "type", "model", "reasoning_effort", "thinking", "effort", "variant", "endpoint",
            "recommended_model",
        }
        unknown = set(raw) - allowed
        if unknown:
            raise FailoverError(f"{field}: unknown keys {sorted(unknown)}")
        return cls(
            type=normalize_cli(raw.get("type"), field=f"{field}.type"),
            model=normalize_optional_str(raw.get("model"), field=f"{field}.model", max_len=MAX_MODEL_LEN),
            reasoning_effort=normalize_optional_str(
                raw.get("reasoning_effort"), field=f"{field}.reasoning_effort", max_len=MAX_REASONING_LEN
            ),
            thinking=normalize_thinking(raw.get("thinking")),
            effort=normalize_optional_str(raw.get("effort"), field=f"{field}.effort", max_len=MAX_REASONING_LEN),
            variant=normalize_optional_str(raw.get("variant"), field=f"{field}.variant", max_len=MAX_REASONING_LEN),
            endpoint=normalize_endpoint(raw.get("endpoint"), field=f"{field}.endpoint"),
            recommended_model=normalize_optional_str(
                raw.get("recommended_model"), field=f"{field}.recommended_model", max_len=MAX_MODEL_LEN
            ),
        )


@dataclass(frozen=True)
class RoleConfig:
    role: str
    primary: RoleProfile
    fallback: Optional[RoleProfile]

    def to_dict(self) -> dict[str, Any]:
        data = self.primary.to_dict()
        data["fallback"] = None if self.fallback is None else self.fallback.to_dict()
        return data


def parse_role_config(role: str, raw: Any) -> RoleConfig:
    if not is_role_name(role):
        raise FailoverError(f"invalid role name: {role!r}")
    if isinstance(raw, str):
        primary = RoleProfile.from_mapping(raw, field=f"cli.agents.{role}")
        return RoleConfig(role=role, primary=primary, fallback=None)
    if not isinstance(raw, Mapping):
        raise FailoverError(f"cli.agents.{role}: must be mapping or string")
    _reject_secret_keys(raw, path=f"cli.agents.{role}")
    data = dict(raw)
    fallback_raw = data.pop("fallback", None)
    primary = RoleProfile.from_mapping(data, field=f"cli.agents.{role}")
    if fallback_raw is None:
        fallback = None
    else:
        fallback = RoleProfile.from_mapping(fallback_raw, field=f"cli.agents.{role}.fallback")
    return RoleConfig(role=role, primary=primary, fallback=fallback)


def parse_settings_roles(settings: Mapping[str, Any]) -> dict[str, RoleConfig]:
    cli = settings.get("cli") if isinstance(settings.get("cli"), Mapping) else {}
    agents = cli.get("agents") if isinstance(cli, Mapping) else {}
    if not isinstance(agents, Mapping):
        return {}
    roles: dict[str, RoleConfig] = {}
    for role, raw in agents.items():
        if not is_role_name(str(role)):
            continue
        roles[str(role)] = parse_role_config(str(role), raw)
    return roles


def role_config_for(role: str, configs: Mapping[str, RoleConfig]) -> Optional[RoleConfig]:
    cfg = configs.get(role)
    if cfg is None and re.fullmatch(r"karo[1-9][0-9]*", role):
        base = configs.get("karo")
        if base is not None:
            cfg = RoleConfig(role=role, primary=base.primary, fallback=base.fallback)
    return cfg


def empty_role_state(role: str, *, now: str, primary: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    return {
        "role": role,
        "active_slot": SLOT_PRIMARY,
        "generation": 1,
        "status": STATUS_READY,
        "no_progress_count": 0,
        "primary_restart_count": 0,
        "current_work": None,
        "handoff": None,
        "handoff_complete": False,
        "failure_reason": None,
        "army_mode": "normal",
        "emergency": None,
        "primary_profile": primary,
        "fallback_profile": None,
        "updated_at": now,
        "initialized_at": now,
        "last_event_id": None,
    }


def empty_state(*, now: Optional[str] = None) -> dict[str, Any]:
    stamp = now or utc_now()
    return {
        "schema_version": SCHEMA_VERSION,
        "updated_at": stamp,
        "army_mode": "normal",
        "processed_event_ids": [],
        "roles": {},
        "pending_reassignments": [],
    }


def _ensure_int(value: Any, *, field: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise FailoverError(f"{field} must be an integer")
    if value < minimum:
        raise FailoverError(f"{field} must be >= {minimum}")
    return value


def _saved_mapping(value: Any, *, field: str, allowed: frozenset[str]) -> Optional[dict[str, Any]]:
    if value is None:
        return None
    if not isinstance(value, Mapping):
        raise FailoverError(f"{field} must be a mapping or null")
    _reject_secret_keys(value, path=field)
    unknown = set(value) - allowed
    if unknown:
        raise FailoverError(f"{field}: unknown keys {sorted(unknown)}")
    return dict(value)


def normalize_state(raw: Any) -> dict[str, Any]:
    if raw is None or raw == {}:
        return empty_state()
    if not isinstance(raw, Mapping):
        raise FailoverError("state root must be a mapping")
    _reject_secret_keys(raw, path="state")
    schema = raw.get("schema_version", SCHEMA_VERSION)
    if schema != SCHEMA_VERSION:
        raise FailoverError(f"unsupported schema_version: {schema}")
    state = empty_state(now=str(raw.get("updated_at") or utc_now()))
    army = raw.get("army_mode", "normal")
    if army not in {"normal", "safe_stopped", "emergency"}:
        raise FailoverError("army_mode invalid")
    state["army_mode"] = army
    processed = raw.get("processed_event_ids") or []
    if not isinstance(processed, list):
        raise FailoverError("processed_event_ids must be a list")
    normalized_ids = [str(x) for x in processed]
    if any(not value or len(value) > MAX_EVENT_ID_LEN for value in normalized_ids):
        raise FailoverError("processed_event_ids contains an invalid event id")
    state["processed_event_ids"] = normalized_ids[-200:]
    pending = raw.get("pending_reassignments") or []
    if not isinstance(pending, list):
        raise FailoverError("pending_reassignments must be a list")
    normalized_pending = []
    pending_fields = frozenset(
        {"from_role", "generation", "failed_generation", "lease_revoked", "work", "reason", "created_at", "target"}
    )
    for idx, item in enumerate(pending):
        normalized = _saved_mapping(item, field=f"pending_reassignments[{idx}]", allowed=pending_fields)
        if normalized is None:
            raise FailoverError(f"pending_reassignments[{idx}] must be a mapping")
        normalized_pending.append(normalized)
    state["pending_reassignments"] = normalized_pending
    roles_raw = raw.get("roles") or {}
    if not isinstance(roles_raw, Mapping):
        raise FailoverError("roles must be a mapping")
    for role, role_raw in roles_raw.items():
        if not is_role_name(str(role)):
            continue
        if not isinstance(role_raw, Mapping):
            raise FailoverError(f"roles.{role} must be a mapping")
        rs = empty_role_state(str(role), now=str(role_raw.get("updated_at") or state["updated_at"]))
        rs["active_slot"] = role_raw.get("active_slot", SLOT_PRIMARY)
        if rs["active_slot"] not in SLOTS:
            raise FailoverError(f"roles.{role}.active_slot invalid")
        rs["generation"] = _ensure_int(role_raw.get("generation", 1), field=f"roles.{role}.generation", minimum=1)
        status = role_raw.get("status", STATUS_READY)
        if status not in VALID_STATUSES:
            raise FailoverError(f"roles.{role}.status invalid")
        rs["status"] = status
        rs["no_progress_count"] = _ensure_int(
            role_raw.get("no_progress_count", 0), field=f"roles.{role}.no_progress_count"
        )
        rs["primary_restart_count"] = _ensure_int(
            role_raw.get("primary_restart_count", 0), field=f"roles.{role}.primary_restart_count"
        )
        rs["current_work"] = _saved_mapping(
            role_raw.get("current_work"), field=f"roles.{role}.current_work", allowed=WORK_STATE_FIELDS
        )
        rs["handoff"] = _saved_mapping(
            role_raw.get("handoff"), field=f"roles.{role}.handoff", allowed=HANDOFF_ALLOWED_FIELDS
        )
        rs["handoff_complete"] = bool(role_raw.get("handoff_complete", False))
        rs["failure_reason"] = role_raw.get("failure_reason")
        rs["army_mode"] = role_raw.get("army_mode", "normal")
        if rs["army_mode"] not in {"normal", "safe_stopped", "emergency"}:
            raise FailoverError(f"roles.{role}.army_mode invalid")
        rs["emergency"] = _saved_mapping(
            role_raw.get("emergency"),
            field=f"roles.{role}.emergency",
            allowed=frozenset({"mode", "plan_id", "revision", "on_complete", "on_out_of_scope", "fixed_at"}),
        )
        primary_profile = role_raw.get("primary_profile")
        fallback_profile = role_raw.get("fallback_profile")
        rs["primary_profile"] = (
            None if primary_profile is None else RoleProfile.from_mapping(primary_profile, field=f"roles.{role}.primary_profile").to_dict()
        )
        rs["fallback_profile"] = (
            None if fallback_profile is None else RoleProfile.from_mapping(fallback_profile, field=f"roles.{role}.fallback_profile").to_dict()
        )
        rs["last_event_id"] = role_raw.get("last_event_id")
        rs["initialized_at"] = str(role_raw.get("initialized_at") or rs["updated_at"])
        state["roles"][str(role)] = rs
    return state


def atomic_write_yaml(path: Path, data: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.safe_dump(dict(data), fh, allow_unicode=True, sort_keys=False)
        os.replace(tmp_path, path)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        finally:
            raise


def load_yaml(path: Path) -> Any:
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def validate_work_state(work: Any) -> dict[str, Any]:
    if not isinstance(work, Mapping):
        raise FailoverError("work_state must be a mapping")
    _reject_secret_keys(work, path="work_state")
    unknown = set(work) - WORK_STATE_FIELDS
    if unknown:
        raise FailoverError(f"work_state: unknown keys {sorted(unknown)}")
    required = ("work_id", "purpose", "acceptance_criteria", "approved_plan_id", "approved_plan_revision", "progress", "scope", "next_step")
    nullable = {"approved_plan_id", "approved_plan_revision"}
    missing = [key for key in required if key not in work or (key not in nullable and work[key] in (None, "", []))]
    if missing:
        raise FailoverError(f"work_state missing required fields: {', '.join(missing)}")
    plan_id = work["approved_plan_id"]
    revision = work["approved_plan_revision"]
    if (plan_id is None) != (revision is None):
        raise FailoverError("work_state approved plan id and revision must both be set or null")
    if revision is not None and (isinstance(revision, bool) or not isinstance(revision, int) or revision < 1):
        raise FailoverError("work_state.approved_plan_revision must be a positive integer")
    return dict(work)


def validate_handoff(handoff: Any) -> dict[str, Any]:
    if not isinstance(handoff, Mapping):
        raise FailoverError("handoff must be a mapping")
    _reject_secret_keys(handoff, path="handoff")
    unknown = set(handoff) - HANDOFF_ALLOWED_FIELDS
    if unknown:
        raise FailoverError(f"handoff: unknown keys {sorted(unknown)}")
    nullable = {"approved_plan_id", "approved_plan_revision"}
    missing = [
        key for key in HANDOFF_REQUIRED_FIELDS
        if key not in handoff or (key not in nullable and handoff[key] in (None, "", []))
    ]
    if missing:
        raise FailoverError(f"handoff missing required fields: {', '.join(missing)}")
    if not is_role_name(str(handoff["role"])):
        raise FailoverError("handoff.role invalid")
    gen = handoff["generation"]
    if isinstance(gen, bool) or not isinstance(gen, int) or gen < 1:
        raise FailoverError("handoff.generation must be a positive integer")
    validate_work_state({key: value for key, value in handoff.items() if key in WORK_STATE_FIELDS})
    return dict(handoff)


@dataclass
class TransitionResult:
    action: str
    state: dict[str, Any]
    rejected: bool = False
    reason: Optional[str] = None
    audit: list[dict[str, Any]] = field(default_factory=list)
    outbox: list[dict[str, Any]] = field(default_factory=list)
    side_effects: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "action": self.action,
            "rejected": self.rejected,
            "reason": self.reason,
            "state": self.state,
            "audit": self.audit,
            "outbox": self.outbox,
            "side_effects": self.side_effects,
        }


class RoleFailoverController:
    """Pure-ish controller: apply event → new state + fixed action."""

    def __init__(
        self,
        state: Optional[Mapping[str, Any]] = None,
        *,
        role_configs: Optional[Mapping[str, RoleConfig]] = None,
        clock: Optional[Callable[[], str]] = None,
    ) -> None:
        self.clock = clock or utc_now
        self.role_configs = dict(role_configs or {})
        self.state = normalize_state(state)

    def ensure_role(self, role: str) -> dict[str, Any]:
        if not is_role_name(role):
            raise FailoverError(f"invalid role: {role}")
        roles = self.state.setdefault("roles", {})
        if role not in roles:
            primary = None
            cfg = role_config_for(role, self.role_configs)
            if cfg is not None:
                primary = cfg.primary.to_dict()
            roles[role] = empty_role_state(role, now=self.clock(), primary=primary)
            if cfg is not None and cfg.fallback is not None:
                roles[role]["fallback_profile"] = cfg.fallback.to_dict()
            elif cfg is not None:
                roles[role]["fallback_profile"] = None
        return roles[role]

    def active_profile(self, role: str) -> Optional[dict[str, Any]]:
        rs = self.ensure_role(role)
        if rs["active_slot"] == SLOT_FALLBACK:
            return rs.get("fallback_profile")
        return rs.get("primary_profile")

    def apply_event(self, event: Mapping[str, Any]) -> TransitionResult:
        if not isinstance(event, Mapping):
            raise FailoverError("event must be a mapping")
        event = dict(event)
        _reject_secret_keys(event, path="event")
        event_id = event.get("event_id")
        if not isinstance(event_id, str) or not event_id.strip() or len(event_id) > MAX_EVENT_ID_LEN:
            raise FailoverError("event_id is required")
        event_id = event_id.strip()
        event_type = event.get("type")
        if not isinstance(event_type, str) or not event_type:
            raise FailoverError("event.type is required")
        reason = normalize_event_reason(event_type, event.get("reason"))
        if reason is not None:
            event["reason"] = reason
        role = event.get("role")
        if not is_role_name(role):
            raise FailoverError("event.role is required")

        before = copy.deepcopy(self.state)
        if event_id in self.state.get("processed_event_ids", []):
            return TransitionResult(
                action=ACTION_NONE,
                state=copy.deepcopy(self.state),
                reason="duplicate_event",
            )

        rs = self.ensure_role(str(role))
        expected = event.get("expected_generation")
        if event_type != EVENT_INIT_ROLE:
            if isinstance(expected, bool) or not isinstance(expected, int):
                raise FailoverError("expected_generation must be an integer")
            if expected != rs["generation"]:
                # Stale generation: no side effects, state unchanged.
                self.state = before
                return TransitionResult(
                    action=ACTION_REJECT,
                    state=copy.deepcopy(before),
                    rejected=True,
                    reason="stale_generation",
                )

        now = self.clock()
        result = self._dispatch(event_type, str(role), rs, event, now)
        if result.rejected and result.action == ACTION_REJECT and result.reason == "stale_generation":
            self.state = before
            return result

        if result.action not in KNOWN_ACTIONS:
            raise FailoverError(f"unknown action produced: {result.action}")

        # Persist processed event only when not rejected for generation.
        if not result.rejected:
            processed = list(self.state.get("processed_event_ids") or [])
            processed.append(event_id)
            self.state["processed_event_ids"] = processed[-200:]
            rs["last_event_id"] = event_id
            rs["updated_at"] = now
            self.state["updated_at"] = now
            result.state = copy.deepcopy(self.state)
            if result.audit or result.action not in {ACTION_NONE, ACTION_REJECT}:
                audit_entry = {
                    "timestamp": now,
                    "event_id": event_id,
                    "role": role,
                    "type": event_type,
                    "action": result.action,
                    "generation": rs["generation"],
                    "reason": result.reason or event.get("reason"),
                }
                result.audit = [audit_entry, *result.audit]
                if result.action in {
                    ACTION_RESTART_PRIMARY,
                    ACTION_ACTIVATE_FALLBACK,
                    ACTION_SAFE_STOP,
                    ACTION_ENTER_EMERGENCY,
                    ACTION_REQUEST_REASSIGNMENT,
                    ACTION_RESTORE_PRIMARY,
                }:
                    result.outbox = [
                        {
                            "timestamp": now,
                            "kind": "role_failover",
                            "role": role,
                            "action": result.action,
                            "generation": rs["generation"],
                            "reason": result.reason or event.get("reason"),
                        },
                        *result.outbox,
                    ]
        else:
            result.state = copy.deepcopy(self.state)
        return result

    def _dispatch(
        self,
        event_type: str,
        role: str,
        rs: dict[str, Any],
        event: Mapping[str, Any],
        now: str,
    ) -> TransitionResult:
        if event_type == EVENT_INIT_ROLE:
            return self._init_role(role, rs, event, now)
        if event_type == EVENT_PROCESS_EXIT:
            return self._process_exit(role, rs, event, now)
        if event_type == EVENT_EXPLICIT_FAILURE:
            return self._explicit_failure(role, rs, event, now)
        if event_type == EVENT_NO_PROGRESS:
            return self._no_progress(role, rs, event, now)
        if event_type == EVENT_PROGRESS:
            return self._progress(role, rs, now)
        if event_type == EVENT_WORK_STATE_UPDATE:
            return self._work_state_update(role, rs, event)
        if event_type == EVENT_WORK_COMPLETE:
            rs["current_work"] = None
            rs["handoff"] = None
            rs["handoff_complete"] = False
            rs["no_progress_count"] = 0
            return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="work_complete")
        if event_type == EVENT_HANDOFF_VALIDATE:
            return self._handoff_validate(role, rs, event, now)
        if event_type == EVENT_HANDOFF_COMPLETE:
            return self._handoff_complete(role, rs, event, now)
        if event_type == EVENT_PRIMARY_RECOVERED:
            return self._primary_recovered(role, rs, event, now)
        if event_type == EVENT_EMERGENCY_PLAN_COMPLETE:
            return self._emergency_stop(role, rs, "plan_complete", now)
        if event_type == EVENT_EMERGENCY_OUT_OF_SCOPE:
            return self._emergency_stop(role, rs, "out_of_scope", now)
        if event_type == EVENT_EMERGENCY_AUTHORIZE_WORK:
            return self._emergency_authorize_work(role, rs, event, now)
        if event_type == EVENT_USER_STOP:
            return self._user_stop(role, rs, now)
        raise FailoverError(f"unsupported event type: {event_type}")

    def _bind_profiles(self, role: str, rs: dict[str, Any], event: Mapping[str, Any]) -> None:
        cfg = role_config_for(role, self.role_configs)
        if "primary_profile" in event:
            rs["primary_profile"] = RoleProfile.from_mapping(event["primary_profile"], field="primary_profile").to_dict()
        elif cfg is not None:
            rs["primary_profile"] = cfg.primary.to_dict()
        if "fallback_profile" in event:
            fb = event["fallback_profile"]
            rs["fallback_profile"] = (
                None if fb is None else RoleProfile.from_mapping(fb, field="fallback_profile").to_dict()
            )
        elif cfg is not None:
            rs["fallback_profile"] = None if cfg.fallback is None else cfg.fallback.to_dict()

    def _init_role(self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str) -> TransitionResult:
        self._bind_profiles(role, rs, event)
        if rs.get("generation", 0) < 1:
            rs["generation"] = 1
        if event.get("reset"):
            self.state["army_mode"] = "normal"
            rs["generation"] = 1
            rs["active_slot"] = SLOT_PRIMARY
            rs["status"] = STATUS_READY
            rs["no_progress_count"] = 0
            rs["primary_restart_count"] = 0
            rs["handoff"] = None
            rs["handoff_complete"] = False
            rs["failure_reason"] = None
            rs["army_mode"] = "normal"
            rs["emergency"] = None
            rs["initialized_at"] = now
        rs["updated_at"] = now
        return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="initialized")

    def _bump_generation(self, rs: dict[str, Any]) -> None:
        rs["generation"] = int(rs["generation"]) + 1
        rs["handoff_complete"] = False

    def _user_stop(self, role: str, rs: dict[str, Any], now: str) -> TransitionResult:
        self._bump_generation(rs)
        rs["status"] = STATUS_STOPPED
        rs["failure_reason"] = "user_stop"
        if is_ashigaru(role):
            return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="user_stop")
        return self._safe_stop_army(reason=f"{role}_user_stop", now=now, trigger_role=role)

    def _has_fallback(self, rs: dict[str, Any]) -> bool:
        return isinstance(rs.get("fallback_profile"), Mapping)

    def _activate_fallback(self, role: str, rs: dict[str, Any], *, reason: str, now: str) -> TransitionResult:
        if not self._has_fallback(rs):
            return self._role_terminal_failure(role, rs, reason=reason, now=now)
        rs["active_slot"] = SLOT_FALLBACK
        rs["status"] = STATUS_AWAITING_HANDOFF
        rs["failure_reason"] = reason
        rs["primary_restart_count"] = 0
        rs["no_progress_count"] = 0
        self._bump_generation(rs)
        handoff = rs.get("handoff")
        if isinstance(handoff, Mapping):
            handoff = dict(handoff)
            handoff["generation"] = rs["generation"]
            handoff["role"] = role
            rs["handoff"] = handoff
        return TransitionResult(
            action=ACTION_ACTIVATE_FALLBACK,
            state=copy.deepcopy(self.state),
            reason=reason,
            side_effects=[{"kind": "require_handoff", "role": role, "generation": rs["generation"]}],
        )

    def _restart_primary(self, role: str, rs: dict[str, Any], *, reason: str, now: str) -> TransitionResult:
        rs["active_slot"] = SLOT_PRIMARY
        rs["status"] = STATUS_RESTARTING
        rs["primary_restart_count"] = int(rs.get("primary_restart_count") or 0) + 1
        rs["failure_reason"] = reason
        rs["no_progress_count"] = 0
        self._bump_generation(rs)
        return TransitionResult(
            action=ACTION_RESTART_PRIMARY,
            state=copy.deepcopy(self.state),
            reason=reason,
        )

    def _safe_stop_army(self, *, reason: str, now: str, trigger_role: str) -> TransitionResult:
        self.state["army_mode"] = "safe_stopped"
        for role_name, role_state in self.state.get("roles", {}).items():
            self._bump_generation(role_state)
            if role_state.get("status") not in {STATUS_STOPPED, STATUS_SAFE_STOPPED}:
                role_state["status"] = STATUS_SAFE_STOPPED
                role_state["army_mode"] = "safe_stopped"
                role_state["failure_reason"] = reason
                role_state["updated_at"] = now
        trigger = self.ensure_role(trigger_role)
        trigger["status"] = STATUS_SAFE_STOPPED
        trigger["failure_reason"] = reason
        return TransitionResult(
            action=ACTION_SAFE_STOP,
            state=copy.deepcopy(self.state),
            reason=reason,
            side_effects=[{"kind": "army_safe_stop", "trigger_role": trigger_role, "reason": reason}],
        )

    def _request_reassignment(self, role: str, rs: dict[str, Any], *, reason: str, now: str) -> TransitionResult:
        failed_generation = int(rs["generation"])
        self._bump_generation(rs)
        rs["status"] = STATUS_STOPPED
        rs["failure_reason"] = reason
        rs["active_slot"] = rs.get("active_slot") or SLOT_PRIMARY
        work = rs.get("current_work")
        item = {
            "from_role": role,
            "generation": rs["generation"],
            "failed_generation": failed_generation,
            "lease_revoked": True,
            "work": work,
            "reason": reason,
            "created_at": now,
            "target": "karo",
        }
        pending = list(self.state.get("pending_reassignments") or [])
        pending.append(item)
        self.state["pending_reassignments"] = pending
        return TransitionResult(
            action=ACTION_REQUEST_REASSIGNMENT,
            state=copy.deepcopy(self.state),
            reason=reason,
            side_effects=[{"kind": "reassignment_request", **item}],
        )

    def _enter_emergency(self, role: str, rs: dict[str, Any], *, reason: str, now: str) -> TransitionResult:
        gunkan = self.ensure_role("gunkan")
        if gunkan.get("status") in {STATUS_STOPPED, STATUS_SAFE_STOPPED}:
            return self._safe_stop_army(reason="shogun_down_gunkan_unavailable", now=now, trigger_role=role)
        plan = None
        if isinstance(rs.get("handoff"), Mapping):
            plan = {
                "plan_id": rs["handoff"].get("approved_plan_id"),
                "revision": rs["handoff"].get("approved_plan_revision"),
            }
        elif isinstance(rs.get("current_work"), Mapping):
            plan = {
                "plan_id": rs["current_work"].get("approved_plan_id"),
                "revision": rs["current_work"].get("approved_plan_revision"),
            }
        plan_id = None if plan is None else plan.get("plan_id")
        revision = None if plan is None else plan.get("revision")
        if not isinstance(plan_id, str) or not plan_id.strip() or isinstance(revision, bool) or not isinstance(revision, int) or revision < 1:
            return self._safe_stop_army(reason="shogun_down_no_approved_plan", now=now, trigger_role=role)
        policy = {
            "mode": "approved_plan_only",
            "plan_id": plan_id,
            "revision": revision,
            "on_complete": "safe_stop",
            "on_out_of_scope": "safe_stop",
            "fixed_at": now,
        }
        rs["status"] = STATUS_STOPPED
        rs["failure_reason"] = reason
        self.state["army_mode"] = "emergency"
        gunkan["status"] = STATUS_EMERGENCY
        gunkan["army_mode"] = "emergency"
        gunkan["emergency"] = policy
        gunkan["updated_at"] = now
        return TransitionResult(
            action=ACTION_ENTER_EMERGENCY,
            state=copy.deepcopy(self.state),
            reason=reason,
            side_effects=[{"kind": "gunkan_emergency", "policy": policy}],
        )

    def _role_terminal_failure(
        self, role: str, rs: dict[str, Any], *, reason: str, now: str
    ) -> TransitionResult:
        rs["failure_reason"] = reason
        if is_ashigaru(role):
            return self._request_reassignment(role, rs, reason=reason, now=now)
        if role == "shogun":
            self._bump_generation(rs)
            return self._enter_emergency(role, rs, reason=reason, now=now)
        if role in UPPER_SAFE_STOP_ROLES:
            return self._safe_stop_army(reason=f"{role}_unrecoverable", now=now, trigger_role=role)
        return self._safe_stop_army(reason=reason, now=now, trigger_role=role)

    def _process_exit(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        if event.get("intentional") or event.get("user_stop"):
            self._bump_generation(rs)
            rs["status"] = STATUS_STOPPED
            rs["failure_reason"] = "intentional_stop"
            return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="intentional_stop")
        reason = str(event.get("reason") or "process_exit")
        if reason in EXPLICIT_FAILURE_REASONS:
            return self._fail_active_slot(role, rs, reason=reason, now=now, skip_primary_restart=True)
        if rs.get("active_slot") == SLOT_PRIMARY and int(rs.get("primary_restart_count") or 0) < 1:
            return self._restart_primary(role, rs, reason=reason, now=now)
        if rs.get("active_slot") == SLOT_PRIMARY:
            return self._activate_fallback(role, rs, reason=reason, now=now)
        # Fallback process exit → terminal for role
        return self._role_terminal_failure(role, rs, reason=reason, now=now)

    def _explicit_failure(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        reason = str(event["reason"])
        return self._fail_active_slot(role, rs, reason=reason, now=now, skip_primary_restart=True)

    def _fail_active_slot(
        self,
        role: str,
        rs: dict[str, Any],
        *,
        reason: str,
        now: str,
        skip_primary_restart: bool,
    ) -> TransitionResult:
        if rs.get("active_slot") == SLOT_PRIMARY:
            if not skip_primary_restart and int(rs.get("primary_restart_count") or 0) < 1:
                return self._restart_primary(role, rs, reason=reason, now=now)
            return self._activate_fallback(role, rs, reason=reason, now=now)
        return self._role_terminal_failure(role, rs, reason=reason, now=now)

    def _no_progress(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        count = int(rs.get("no_progress_count") or 0) + 1
        rs["no_progress_count"] = count
        if count == 3:
            rs["status"] = STATUS_WARNING
            return TransitionResult(action=ACTION_WARN, state=copy.deepcopy(self.state), reason="no_progress_warning")
        if count >= 6:
            return self._fail_active_slot(role, rs, reason="no_progress", now=now, skip_primary_restart=False)
        return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="no_progress_count")

    def _progress(self, role: str, rs: dict[str, Any], now: str) -> TransitionResult:
        rs["no_progress_count"] = 0
        if rs.get("status") == STATUS_WARNING:
            rs["status"] = STATUS_READY
        if rs.get("status") == STATUS_RESTARTING:
            rs["status"] = STATUS_READY
        return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="progress_reset")

    def _work_state_update(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any]
    ) -> TransitionResult:
        if self.state.get("army_mode") == "safe_stopped" or rs.get("status") in {
            STATUS_STOPPED, STATUS_SAFE_STOPPED, STATUS_AWAITING_HANDOFF,
        }:
            return TransitionResult(action=ACTION_REJECT, state=copy.deepcopy(self.state), rejected=True, reason="role_not_ready")
        work = validate_work_state(event.get("work_state"))
        rs["current_work"] = work
        rs["handoff"] = {"role": role, "generation": rs["generation"], **work}
        return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="work_state_saved")

    def _handoff_validate(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        handoff = event.get("handoff", rs.get("handoff"))
        try:
            validated = validate_handoff(handoff)
        except (FailoverError, FailoverSecurityError) as exc:
            rs["handoff_complete"] = False
            rs["status"] = STATUS_AWAITING_HANDOFF
            return TransitionResult(
                action=ACTION_MARK_HANDOFF_REQUIRED,
                state=copy.deepcopy(self.state),
                rejected=False,
                reason=str(exc),
            )
        if int(validated["generation"]) != int(rs["generation"]):
            return TransitionResult(
                action=ACTION_REJECT,
                state=copy.deepcopy(self.state),
                rejected=True,
                reason="handoff_generation_mismatch",
            )
        if str(validated["role"]) != role:
            return TransitionResult(
                action=ACTION_REJECT,
                state=copy.deepcopy(self.state),
                rejected=True,
                reason="handoff_role_mismatch",
            )
        rs["handoff"] = validated
        rs["status"] = STATUS_AWAITING_HANDOFF
        return TransitionResult(
            action=ACTION_MARK_HANDOFF_REQUIRED,
            state=copy.deepcopy(self.state),
            reason="handoff_valid_pending_complete",
        )

    def _handoff_complete(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        handoff = event.get("handoff", rs.get("handoff"))
        try:
            validated = validate_handoff(handoff)
        except (FailoverError, FailoverSecurityError) as exc:
            rs["handoff_complete"] = False
            return TransitionResult(
                action=ACTION_MARK_HANDOFF_REQUIRED,
                state=copy.deepcopy(self.state),
                rejected=False,
                reason=str(exc),
            )
        if int(validated["generation"]) != int(rs["generation"]) or str(validated["role"]) != role:
            return TransitionResult(
                action=ACTION_REJECT,
                state=copy.deepcopy(self.state),
                rejected=True,
                reason="handoff_mismatch",
            )
        rs["handoff"] = validated
        rs["handoff_complete"] = True
        rs["status"] = STATUS_READY
        rs["current_work"] = {
            "work_id": validated.get("work_id"),
            "purpose": validated.get("purpose"),
            "approved_plan_id": validated.get("approved_plan_id"),
            "approved_plan_revision": validated.get("approved_plan_revision"),
        }
        return TransitionResult(
            action=ACTION_RESUME_AFTER_HANDOFF,
            state=copy.deepcopy(self.state),
            reason="handoff_complete",
        )

    def _primary_recovered(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        if rs.get("active_slot") != SLOT_FALLBACK:
            return TransitionResult(action=ACTION_NONE, state=copy.deepcopy(self.state), reason="not_on_fallback")
        busy = bool(rs.get("current_work")) and rs.get("status") == STATUS_READY and rs.get("handoff_complete")
        if busy and not event.get("force_after_checkpoint"):
            # Keep fallback until current work finishes; restore only after checkpoint.
            return TransitionResult(
                action=ACTION_NONE,
                state=copy.deepcopy(self.state),
                reason="fallback_busy_keep_until_checkpoint",
            )
        rs["active_slot"] = SLOT_PRIMARY
        rs["status"] = STATUS_READY
        rs["primary_restart_count"] = 0
        rs["no_progress_count"] = 0
        rs["failure_reason"] = None
        self._bump_generation(rs)
        return TransitionResult(
            action=ACTION_RESTORE_PRIMARY,
            state=copy.deepcopy(self.state),
            reason="primary_restored",
        )

    def _emergency_stop(
        self, role: str, rs: dict[str, Any], reason: str, now: str
    ) -> TransitionResult:
        if self.state.get("army_mode") != "emergency" and rs.get("status") != STATUS_EMERGENCY:
            return TransitionResult(
                action=ACTION_NONE,
                state=copy.deepcopy(self.state),
                reason="not_in_emergency",
            )
        return self._safe_stop_army(reason=reason, now=now, trigger_role=role)

    def _emergency_authorize_work(
        self, role: str, rs: dict[str, Any], event: Mapping[str, Any], now: str
    ) -> TransitionResult:
        if self.state.get("army_mode") != "emergency" or rs.get("status") != STATUS_EMERGENCY:
            return TransitionResult(action=ACTION_REJECT, state=copy.deepcopy(self.state), rejected=True, reason="not_in_emergency")
        policy = rs.get("emergency")
        if not isinstance(policy, Mapping):
            return self._safe_stop_army(reason="missing_emergency_policy", now=now, trigger_role=role)
        if event.get("complete"):
            return self._safe_stop_army(reason="plan_complete", now=now, trigger_role=role)
        if event.get("deviation"):
            return self._safe_stop_army(reason="emergency_deviation", now=now, trigger_role=role)
        if event.get("plan_id") != policy.get("plan_id") or event.get("plan_revision") != policy.get("revision"):
            return self._safe_stop_army(reason="out_of_scope", now=now, trigger_role=role)
        task_id = event.get("task_id")
        if not isinstance(task_id, str) or not task_id.strip() or len(task_id) > 128:
            raise FailoverError("task_id is required")
        return TransitionResult(action=ACTION_AUTHORIZE, state=copy.deepcopy(self.state), reason="emergency_work_authorized")


class RoleFailoverStore:
    """Atomic YAML persistence with optional flock."""

    def __init__(self, root: Path, *, clock: Optional[Callable[[], str]] = None) -> None:
        self.root = Path(root)
        self.state_path = self.root / STATE_RELATIVE
        self.audit_path = self.root / AUDIT_RELATIVE
        self.outbox_path = self.root / OUTBOX_RELATIVE
        self.clock = clock or utc_now

    def load(self) -> dict[str, Any]:
        raw = load_yaml(self.state_path)
        return normalize_state(raw)

    def save(self, state: Mapping[str, Any]) -> None:
        atomic_write_yaml(self.state_path, normalize_state(state))

    def append_audit(self, entries: Iterable[Mapping[str, Any]]) -> None:
        raw = load_yaml(self.audit_path) or {"events": []}
        if not isinstance(raw, Mapping):
            raw = {"events": []}
        events = list(raw.get("events") or [])
        events.extend(dict(e) for e in entries)
        events = events[-MAX_AUDIT_EVENTS:]
        atomic_write_yaml(self.audit_path, {"updated_at": self.clock(), "events": events})

    def append_outbox(self, entries: Iterable[Mapping[str, Any]]) -> None:
        raw = load_yaml(self.outbox_path) or {"events": []}
        if not isinstance(raw, Mapping):
            raw = {"events": []}
        events = list(raw.get("events") or [])
        events.extend(dict(e) for e in entries)
        events = events[-MAX_OUTBOX_EVENTS:]
        atomic_write_yaml(self.outbox_path, {"updated_at": self.clock(), "events": events})

    def with_lock(self, fn: Callable[[], Any]) -> Any:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = self.state_path.with_suffix(self.state_path.suffix + ".lock")
        with lock_path.open("a+", encoding="utf-8") as lock_fh:
            if fcntl is not None:
                fcntl.flock(lock_fh.fileno(), fcntl.LOCK_EX)
            try:
                return fn()
            finally:
                if fcntl is not None:
                    fcntl.flock(lock_fh.fileno(), fcntl.LOCK_UN)

    def apply_event(
        self,
        event: Mapping[str, Any],
        *,
        role_configs: Optional[Mapping[str, RoleConfig]] = None,
    ) -> TransitionResult:
        def _apply() -> TransitionResult:
            controller = RoleFailoverController(self.load(), role_configs=role_configs, clock=self.clock)
            result = controller.apply_event(event)
            if not result.rejected:
                self.save(result.state)
                if result.audit:
                    self.append_audit(result.audit)
                if result.outbox:
                    self.append_outbox(result.outbox)
            return result

        return self.with_lock(_apply)


def resolve_active_launch_profile(
    settings: Mapping[str, Any],
    state: Mapping[str, Any],
    role: str,
) -> dict[str, Any]:
    """Resolve Primary or explicit Fallback profile without inventing another CLI."""
    configs = parse_settings_roles(settings)
    cfg = role_config_for(role, configs)
    if cfg is None:
        raise FailoverError(f"role not configured: {role}")
    roles = state.get("roles") if isinstance(state.get("roles"), Mapping) else {}
    rs = roles.get(role) if isinstance(roles, Mapping) else None
    slot = SLOT_PRIMARY
    generation = 1
    status = STATUS_READY
    if isinstance(rs, Mapping):
        slot = rs.get("active_slot") or SLOT_PRIMARY
        generation = int(rs.get("generation") or 1)
        status = rs.get("status") or STATUS_READY
        if status not in VALID_STATUSES:
            raise FailoverError(f"role {role} has invalid status")
        if rs.get("status") in {STATUS_STOPPED, STATUS_SAFE_STOPPED}:
            raise FailoverError(f"role {role} is stopped")
    if slot == SLOT_FALLBACK:
        if cfg.fallback is None:
            raise FailoverError(f"role {role} has no fallback profile")
        profile = cfg.fallback
    else:
        profile = cfg.primary
    return {
        "role": role,
        "slot": slot,
        "generation": generation,
        "status": status,
        "handoff_complete": bool(rs.get("handoff_complete", False)) if isinstance(rs, Mapping) else False,
        "profile": profile.to_dict(),
    }


def validate_managed_write(state: Mapping[str, Any], role: str, expected_generation: int) -> tuple[bool, str]:
    if not is_role_name(role):
        return False, "invalid_role"
    if state.get("army_mode") == "safe_stopped":
        return False, "army_safe_stopped"
    roles = state.get("roles")
    rs = roles.get(role) if isinstance(roles, Mapping) else None
    if not isinstance(rs, Mapping):
        return False, "role_not_initialized"
    if expected_generation != rs.get("generation"):
        return False, "stale_generation"
    if rs.get("status") in {STATUS_STOPPED, STATUS_SAFE_STOPPED, STATUS_AWAITING_HANDOFF}:
        return False, "role_not_ready"
    return True, "authorized"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Role Primary/Fallback failover controller")
    parser.add_argument("--root", type=Path, default=Path("."), help="project root")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init-role", help="initialize role state from settings")
    p_init.add_argument("--role", required=True)
    p_init.add_argument("--settings", type=Path, default=None)
    p_init.add_argument("--event-id", required=True)
    p_init.add_argument("--reset", action="store_true", help="reset generation and active slot")

    p_event = sub.add_parser("apply-event", help="apply a JSON event")
    p_event.add_argument("--event-json", required=True, help="JSON object or @path")
    p_event.add_argument("--format", choices=("yaml", "json"), default="yaml")

    p_show = sub.add_parser("show", help="print current state")
    p_show.add_argument("--role", default=None)

    p_resolve = sub.add_parser("resolve-profile", help="resolve active launch profile")
    p_resolve.add_argument("--role", required=True)
    p_resolve.add_argument("--settings", type=Path, default=None)
    p_resolve.add_argument("--format", choices=("yaml", "json"), default="yaml")

    p_validate = sub.add_parser("validate-write", help="validate a generation-scoped managed write")
    p_validate.add_argument("--role", required=True)
    p_validate.add_argument("--expected-generation", required=True, type=int)

    p_monitor = sub.add_parser("monitor-candidates", help="list roles eligible for a no-progress tick")
    p_monitor.add_argument("--format", choices=("yaml", "json"), default="yaml")
    return parser


def _load_event_json(raw: str, root: Path) -> dict[str, Any]:
    if raw.startswith("@"):
        event_path = Path(raw[1:]).resolve()
        allowed_root = (root / "queue" / "runtime").resolve()
        if allowed_root not in event_path.parents or event_path.suffix != ".json":
            raise SystemExit("event file must be a .json file under queue/runtime")
        text = event_path.read_text(encoding="utf-8")
    else:
        text = raw
    data = json.loads(text)
    if not isinstance(data, dict):
        raise SystemExit("event must be a JSON object")
    return data


def _load_settings(path: Optional[Path], root: Path) -> dict[str, Any]:
    settings_path = path or (root / "config" / "settings.yaml")
    raw = load_yaml(settings_path) or {}
    if not isinstance(raw, dict):
        raise SystemExit("settings must be a mapping")
    return raw


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    store = RoleFailoverStore(args.root)
    if args.command == "show":
        state = store.load()
        if args.role:
            print(yaml.safe_dump(state.get("roles", {}).get(args.role, {}), allow_unicode=True, sort_keys=False))
        else:
            print(yaml.safe_dump(state, allow_unicode=True, sort_keys=False))
        return 0
    if args.command == "resolve-profile":
        settings = _load_settings(args.settings, args.root)
        state = store.load()
        resolved = resolve_active_launch_profile(settings, state, args.role)
        if args.format == "json":
            print(json.dumps(resolved, ensure_ascii=False, separators=(",", ":")))
        else:
            print(yaml.safe_dump(resolved, allow_unicode=True, sort_keys=False))
        return 0
    if args.command == "validate-write":
        allowed, reason = validate_managed_write(store.load(), args.role, args.expected_generation)
        print(json.dumps({"allowed": allowed, "reason": reason}, ensure_ascii=False))
        return 0 if allowed else 2
    if args.command == "monitor-candidates":
        state = store.load()
        candidates = []
        if state.get("army_mode") != "safe_stopped":
            for role, role_state in state.get("roles", {}).items():
                if role_state.get("current_work") and role_state.get("status") in {STATUS_READY, STATUS_WARNING, STATUS_RESTARTING}:
                    candidates.append({"role": role, "generation": role_state["generation"]})
        if args.format == "json":
            print(json.dumps(candidates, ensure_ascii=False, separators=(",", ":")))
        else:
            print(yaml.safe_dump(candidates, allow_unicode=True, sort_keys=False))
        return 0
    if args.command == "init-role":
        settings = _load_settings(args.settings, args.root)
        configs = parse_settings_roles(settings)
        cfg = role_config_for(args.role, configs)
        if cfg is None:
            raise SystemExit(f"role not in settings: {args.role}")
        event = {
            "event_id": args.event_id,
            "type": EVENT_INIT_ROLE,
            "role": args.role,
            "reset": args.reset,
            "primary_profile": cfg.primary.to_dict(),
            "fallback_profile": None if cfg.fallback is None else cfg.fallback.to_dict(),
        }
        result = store.apply_event(event, role_configs=configs)
        print(yaml.safe_dump(result.to_dict(), allow_unicode=True, sort_keys=False))
        return 0
    if args.command == "apply-event":
        event = _load_event_json(args.event_json, args.root)
        result = store.apply_event(event)
        if args.format == "json":
            print(json.dumps(result.to_dict(), ensure_ascii=False, separators=(",", ":")))
        else:
            print(yaml.safe_dump(result.to_dict(), allow_unicode=True, sort_keys=False))
        return 0 if not result.rejected else 2
    raise SystemExit(f"unknown command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
