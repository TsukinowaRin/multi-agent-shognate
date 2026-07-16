#!/usr/bin/env python3
"""Configure coarse Shogunate runtime roles.

This script intentionally edits only role CLI types and active ashigaru count.
Model / reasoning / thinking preferences are left to each tmux pane's CLI state.
"""

from __future__ import annotations

import argparse
import copy
import os
import re
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SETTINGS = ROOT / "config/settings.yaml"
ALLOWED_CLIS = ("codex", "antigravity", "claude", "opencode", "kilo", "localapi", "kimi", "copilot", "cursor")
LEGACY_CLI_ALIASES = {"gemini": "antigravity", "agy": "antigravity"}
CORE_ROLES = ("shogun", "gunkan", "karo", "gunshi")
MODEL_PREF_KEYS = ("model", "reasoning_effort", "thinking")
ASHIGARU_RE = re.compile(r"^ashigaru([1-9][0-9]*)$")
SECRET_KEY_RE = re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|credential|bearer)")
PROFILE_FIELDS = frozenset(
    {"type", "model", "reasoning_effort", "thinking", "effort", "variant", "endpoint", "recommended_model"}
)


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        try:
            data = yaml.safe_load(fh) or {}
        except yaml.YAMLError as exc:
            raise SystemExit(f"invalid settings YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit("settings root must be a mapping")
    validate_settings_profiles(data)
    return data


def _validate_profile(raw: Any, *, field: str) -> None:
    if not isinstance(raw, dict):
        raise SystemExit(f"{field} must be a mapping")
    for key, value in raw.items():
        if SECRET_KEY_RE.search(str(key)):
            raise SystemExit(f"{field}.{key}: secret-like key is not allowed")
        if key not in PROFILE_FIELDS:
            raise SystemExit(f"{field}.{key}: unknown profile field")
        if isinstance(value, dict):
            raise SystemExit(f"{field}.{key}: nested mapping is not allowed")
    normalize_cli(str(raw.get("type") or ""), field=f"{field}.type")
    for key in ("model", "reasoning_effort", "effort", "variant", "recommended_model"):
        value = raw.get(key)
        if value is not None and (not isinstance(value, str) or len(value.strip()) > 128):
            raise SystemExit(f"{field}.{key}: invalid value")
        if isinstance(value, str) and any(ord(char) < 32 or ord(char) == 127 for char in value.strip()):
            raise SystemExit(f"{field}.{key}: control characters are not allowed")
    if raw.get("thinking") is not None and type(raw.get("thinking")) is not bool:
        raise SystemExit(f"{field}.thinking: must be true, false, or null")
    endpoint = raw.get("endpoint")
    if endpoint is not None:
        if not isinstance(endpoint, str) or len(endpoint) > 512:
            raise SystemExit(f"{field}.endpoint: invalid value")
        parsed = urlsplit(endpoint)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise SystemExit(f"{field}.endpoint: must be an http(s) URL")
        if parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise SystemExit(f"{field}.endpoint: credentials, query, and fragment are not allowed")


def validate_settings_profiles(data: dict[str, Any]) -> None:
    cli = data.get("cli")
    if cli is None:
        return
    if not isinstance(cli, dict):
        raise SystemExit("cli must be a mapping")
    agents = cli.get("agents")
    if agents is None:
        return
    if not isinstance(agents, dict):
        raise SystemExit("cli.agents must be a mapping")
    for role, raw in agents.items():
        if not (role in CORE_ROLES or ASHIGARU_RE.fullmatch(str(role))):
            continue
        if isinstance(raw, str):
            normalize_cli(raw, field=f"cli.agents.{role}")
            continue
        if not isinstance(raw, dict):
            raise SystemExit(f"cli.agents.{role} must be a mapping or CLI string")
        primary = {key: value for key, value in raw.items() if key != "fallback"}
        _validate_profile(primary, field=f"cli.agents.{role}")
        fallback = raw.get("fallback")
        if fallback is not None:
            _validate_profile(fallback, field=f"cli.agents.{role}.fallback")


def _atomic_write_bytes(path: Path, content: bytes, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise


def save_yaml(path: Path, data: dict[str, Any]) -> None:
    validate_settings_profiles(data)
    original = path.read_bytes() if path.exists() else None
    mode = (path.stat().st_mode & 0o777) if path.exists() else 0o600
    snapshot = path.with_name(f"{path.name}.last-known-good")
    candidate = yaml.safe_dump(data, sort_keys=False, allow_unicode=True).encode("utf-8")
    try:
        if original is not None:
            _atomic_write_bytes(snapshot, original, mode)
        _atomic_write_bytes(path, candidate, mode)
        reloaded = load_yaml(path)
        if reloaded != data:
            raise SystemExit("settings read-back validation failed")
    except BaseException:
        if original is None:
            path.unlink(missing_ok=True)
        else:
            _atomic_write_bytes(path, original, mode)
        raise


def normalize_cli(value: str, *, field: str) -> str:
    normalized = (value or "").strip().lower()
    normalized = LEGACY_CLI_ALIASES.get(normalized, normalized)
    if normalized not in ALLOWED_CLIS:
        allowed = ", ".join(ALLOWED_CLIS)
        raise SystemExit(f"{field}: unsupported CLI '{value}'. Allowed: {allowed}")
    return normalized


def normalize_count(value: int) -> int:
    if value < 1:
        raise SystemExit("--ashigaru-count must be 1 or greater")
    return value


def current_cli(cfg: dict[str, Any], role: str, fallback: str) -> str:
    cli = cfg.get("cli") if isinstance(cfg.get("cli"), dict) else {}
    agents = cli.get("agents") if isinstance(cli.get("agents"), dict) else {}
    agent_cfg = agents.get(role) if isinstance(agents, dict) else None
    if isinstance(agent_cfg, dict):
        value = str(agent_cfg.get("type") or "").strip().lower()
        value = LEGACY_CLI_ALIASES.get(value, value)
        if value in ALLOWED_CLIS:
            return value
    if isinstance(agent_cfg, str):
        value = LEGACY_CLI_ALIASES.get(agent_cfg.strip().lower(), agent_cfg.strip().lower())
        if value in ALLOWED_CLIS:
            return value
    default_cli = str(cli.get("default") or "").strip().lower() if isinstance(cli, dict) else ""
    default_cli = LEGACY_CLI_ALIASES.get(default_cli, default_cli)
    if default_cli in ALLOWED_CLIS:
        return default_cli
    return fallback


def current_ashigaru_count(cfg: dict[str, Any]) -> int:
    topology = cfg.get("topology") if isinstance(cfg.get("topology"), dict) else {}
    active = topology.get("active_ashigaru") if isinstance(topology, dict) else []
    if isinstance(active, list):
        count = sum(1 for item in active if isinstance(item, str) and item.startswith("ashigaru"))
        if count >= 1:
            return count
    return 2


def prompt_choice(label: str, default: str) -> str:
    while True:
        print("")
        print(label)
        for idx, option in enumerate(ALLOWED_CLIS, start=1):
            suffix = " [default]" if option == default else ""
            print(f"  {idx}) {option}{suffix}")
        raw = input("> ").strip()
        if not raw:
            return default
        if raw.isdigit():
            idx = int(raw)
            if 1 <= idx <= len(ALLOWED_CLIS):
                return ALLOWED_CLIS[idx - 1]
        raw = raw.lower()
        if raw in ALLOWED_CLIS:
            return raw
        print("入力エラー: CLI 種別を選択してください。")


def prompt_count(default: int) -> int:
    while True:
        print("")
        raw = input(f"足軽人数を入力 (1以上) [default: {default}]: ").strip()
        if not raw:
            return default
        if raw.isdigit() and int(raw) >= 1:
            return int(raw)
        print("入力エラー: 足軽人数は 1以上の整数で指定してください。")


def ensure_cli_sections(cfg: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    cli = cfg.get("cli")
    if not isinstance(cli, dict):
        cli = {}
        cfg["cli"] = cli
    agents = cli.get("agents")
    if not isinstance(agents, dict):
        agents = {}
        cli["agents"] = agents
    return cli, agents


def set_role_cli(agents: dict[str, Any], role: str, cli_type: str, *, prune_model_prefs: bool) -> None:
    existing = agents.get(role)
    if isinstance(existing, dict):
        role_cfg = copy.deepcopy(existing)
    elif isinstance(existing, str):
        role_cfg = {}
    else:
        role_cfg = {}
    role_cfg["type"] = cli_type
    if prune_model_prefs:
        for key in MODEL_PREF_KEYS:
            role_cfg.pop(key, None)
    agents[role] = role_cfg


def set_role_fallback(agents: dict[str, Any], role: str, cli_type: str | None) -> None:
    existing = agents.get(role)
    role_cfg = copy.deepcopy(existing) if isinstance(existing, dict) else {}
    if cli_type is None:
        role_cfg["fallback"] = None
    else:
        fallback = role_cfg.get("fallback")
        fallback_cfg = copy.deepcopy(fallback) if isinstance(fallback, dict) else {}
        fallback_cfg["type"] = cli_type
        role_cfg["fallback"] = fallback_cfg
    agents[role] = role_cfg


def configure(
    cfg: dict[str, Any],
    *,
    default_cli: str,
    ashigaru_count: int,
    role_clis: dict[str, str],
    role_fallbacks: dict[str, str | None],
    prune_model_prefs: bool,
) -> dict[str, Any]:
    topology = cfg.get("topology")
    if not isinstance(topology, dict):
        topology = {}
        cfg["topology"] = topology
    topology["active_ashigaru"] = [f"ashigaru{i}" for i in range(1, ashigaru_count + 1)]
    karo_topology = topology.get("karo")
    if not isinstance(karo_topology, dict):
        karo_topology = {}
        topology["karo"] = karo_topology
    karo_topology.setdefault("mode", "auto")
    karo_topology.setdefault("max_ashigaru_per_karo", 6)

    cli, agents = ensure_cli_sections(cfg)
    cli["default"] = default_cli

    for role in CORE_ROLES:
        set_role_cli(agents, role, role_clis.get(role, default_cli), prune_model_prefs=prune_model_prefs)
    for i in range(1, ashigaru_count + 1):
        role = f"ashigaru{i}"
        set_role_cli(agents, role, role_clis.get(role, default_cli), prune_model_prefs=prune_model_prefs)
    for role, fallback in role_fallbacks.items():
        if role in agents:
            set_role_fallback(agents, role, fallback)
    for role in list(agents.keys()):
        if not isinstance(role, str):
            continue
        match = ASHIGARU_RE.match(role)
        if match and int(match.group(1)) > ashigaru_count:
            agents.pop(role, None)

    return cfg


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure only Shogunate role CLI types and active ashigaru count."
    )
    parser.add_argument("--settings", default=str(DEFAULT_SETTINGS), help="settings.yaml path")
    parser.add_argument("--default", choices=ALLOWED_CLIS, help="cli.default")
    parser.add_argument("--ashigaru-count", type=int, help="number of active ashigaru")
    parser.add_argument("--ashigaru-cli", choices=ALLOWED_CLIS, help="default CLI for unspecified ashigaru")
    parser.add_argument("--preserve-model-prefs", action="store_true", help="do not remove model/reasoning/thinking fields")
    parser.add_argument("--dry-run", action="store_true", help="print updated YAML without writing")
    for role in CORE_ROLES:
        parser.add_argument(f"--{role}", choices=ALLOWED_CLIS, help=f"{role} CLI type")
        parser.add_argument(
            f"--{role}-fallback", choices=(*ALLOWED_CLIS, "none"), help=f"{role} Fallback CLI or none"
        )
    for i in range(1, 33):
        parser.add_argument(f"--ashigaru{i}", choices=ALLOWED_CLIS, help=f"ashigaru{i} CLI type")
        parser.add_argument(
            f"--ashigaru{i}-fallback", choices=(*ALLOWED_CLIS, "none"), help=f"ashigaru{i} Fallback CLI or none"
        )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    settings_path = Path(args.settings)
    cfg = load_yaml(settings_path)

    provided_any = any(
        getattr(args, name) is not None
        for name in ("default", "ashigaru_count", "ashigaru_cli", *CORE_ROLES)
    ) or any(getattr(args, f"ashigaru{i}") is not None for i in range(1, 33))
    provided_any = provided_any or any(
        getattr(args, f"{role}_fallback") is not None
        for role in (*CORE_ROLES, *(f"ashigaru{i}" for i in range(1, 33)))
    )

    if args.default:
        default_cli = normalize_cli(args.default, field="--default")
    elif provided_any:
        default_cli = "codex"
    else:
        default_cli = current_cli(cfg, "shogun", "codex")
    ashigaru_count = normalize_count(args.ashigaru_count) if args.ashigaru_count else current_ashigaru_count(cfg)

    role_clis: dict[str, str] = {}
    role_fallbacks: dict[str, str | None] = {}
    if provided_any:
        for role in CORE_ROLES:
            value = getattr(args, role)
            role_clis[role] = normalize_cli(value, field=f"--{role}") if value else current_cli(cfg, role, default_cli)
            fallback = getattr(args, f"{role}_fallback")
            if fallback is not None:
                role_fallbacks[role] = None if fallback == "none" else normalize_cli(fallback, field=f"--{role}-fallback")
        ashigaru_default = args.ashigaru_cli or default_cli
        for i in range(1, ashigaru_count + 1):
            role = f"ashigaru{i}"
            value = getattr(args, role)
            role_clis[role] = normalize_cli(value, field=f"--{role}") if value else current_cli(cfg, role, ashigaru_default)
            fallback = getattr(args, f"{role}_fallback")
            if fallback is not None:
                role_fallbacks[role] = None if fallback == "none" else normalize_cli(fallback, field=f"--{role}-fallback")
    else:
        print("=== Shogunate runtime role configurator ===")
        print(f"settings: {settings_path}")
        default_cli = prompt_choice("cli.default を選択", default_cli)
        for role in CORE_ROLES:
            role_clis[role] = prompt_choice(f"{role} の CLI を選択", current_cli(cfg, role, default_cli))
        ashigaru_count = prompt_count(ashigaru_count)
        for i in range(1, ashigaru_count + 1):
            role = f"ashigaru{i}"
            role_clis[role] = prompt_choice(f"{role} の CLI を選択", current_cli(cfg, role, default_cli))

    updated = configure(
        cfg,
        default_cli=default_cli,
        ashigaru_count=ashigaru_count,
        role_clis=role_clis,
        role_fallbacks=role_fallbacks,
        prune_model_prefs=not args.preserve_model_prefs,
    )

    if args.dry_run:
        print(yaml.safe_dump(updated, sort_keys=False, allow_unicode=True), end="")
    else:
        save_yaml(settings_path, updated)
        print(f"[OK] updated {settings_path}")
        print("[OK] model/reasoning/thinking fields are left to pane-local CLI state")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
