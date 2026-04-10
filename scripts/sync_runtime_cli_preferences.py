#!/usr/bin/env python3
import csv
import os
import re
import subprocess
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SETTINGS_PATH = Path(os.environ.get("MAS_SETTINGS_PATH", ROOT / "config/settings.yaml"))
SUMMARY_PATH = Path(os.environ.get("MAS_RUNTIME_PREFS_SUMMARY_PATH", ROOT / "queue/runtime/runtime_cli_prefs.tsv"))
GEMINI_ALIAS_PATH = Path(os.environ.get("MAS_GEMINI_SUMMARY_PATH", ROOT / "queue/runtime/gemini_aliases.tsv"))
TMUX_BIN = os.environ.get("TMUX_BIN", "tmux")
VERBOSE_NOOP = os.environ.get("MAS_RUNTIME_PREF_VERBOSE_NOOP", "0") == "1"

CODEX_STATUS_RE = re.compile(
    r"^\s*([A-Za-z0-9][A-Za-z0-9._/-]*)"
    r"(?:\s+(none|low|medium|high))?"
    r"\s+[·•]\s+\d+%\s+left\b",
    re.IGNORECASE,
)
MODEL_TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$")
INVALID_CODEX_MODEL_TOKENS = {
    "left",
    "context",
    "working",
    "run",
    "use",
    "model",
    "shortcuts",
    "press",
}


def run_tmux(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([TMUX_BIN, *args], text=True, capture_output=True)


def tmux_ok(*args: str) -> bool:
    return run_tmux(*args).returncode == 0


def tmux_output(*args: str) -> str:
    proc = run_tmux(*args)
    if proc.returncode != 0:
        return ""
    return proc.stdout


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    return data if isinstance(data, dict) else {}


def save_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, sort_keys=False, allow_unicode=True)


def load_gemini_aliases() -> dict[str, dict[str, str]]:
    if not GEMINI_ALIAS_PATH.exists():
        return {}
    rows: dict[str, dict[str, str]] = {}
    with GEMINI_ALIAS_PATH.open("r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh, delimiter='\t')
        for row in reader:
            alias = (row.get("alias") or "").strip()
            if alias:
                rows[alias] = {k: (v or "") for k, v in row.items()}
    return rows


def ensure_agent_cfg(cfg: dict, agent_id: str) -> dict:
    cli = cfg.setdefault("cli", {})
    if not isinstance(cli, dict):
        cfg["cli"] = {}
        cli = cfg["cli"]
    agents = cli.setdefault("agents", {})
    if not isinstance(agents, dict):
        cli["agents"] = {}
        agents = cli["agents"]
    current = agents.get(agent_id)
    if isinstance(current, dict):
        return current
    new_cfg: dict = {}
    if isinstance(current, str) and current.strip():
        new_cfg["type"] = current.strip()
    agents[agent_id] = new_cfg
    return new_cfg


def configured_agent_ids(cfg: dict) -> set[str]:
    result: set[str] = {"shogun", "gunshi", "karo"}
    topology = cfg.get("topology")
    if isinstance(topology, dict):
        active = topology.get("active_ashigaru")
        if isinstance(active, list):
            for item in active:
                if isinstance(item, str) and item.strip():
                    result.add(item.strip())

    cli = cfg.get("cli")
    if isinstance(cli, dict):
        agents = cli.get("agents")
        if isinstance(agents, dict):
            for agent_id in agents.keys():
                if isinstance(agent_id, str) and agent_id.strip() and not agent_id.startswith("ashigaru"):
                    result.add(agent_id.strip())
    return result


def list_backend_targets() -> list[tuple[str, str, str]]:
    out = tmux_output("list-panes", "-t", "multiagent:agents", "-F", "#{session_name}:#{window_name}.#{pane_index}\t#{@agent_id}\t#{@agent_cli}")
    targets: list[tuple[str, str, str]] = []
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        target, agent_id, cli_type = parts[0].strip(), parts[1].strip(), parts[2].strip().lower()
        if agent_id:
            targets.append((target, agent_id, cli_type))
    return targets


def gather_targets() -> list[tuple[str, str, str]]:
    if tmux_ok("has-session", "-t", "goza-no-ma"):
        out = tmux_output("list-panes", "-s", "-t", "goza-no-ma", "-F", "#{pane_id}")
        targets: list[tuple[str, str, str]] = []
        for pane_id in out.splitlines():
            pane_id = pane_id.strip()
            if not pane_id:
                continue
            agent_id = tmux_output("show-options", "-p", "-t", pane_id, "-v", "@agent_id").strip()
            cli_type = tmux_output("show-options", "-p", "-t", pane_id, "-v", "@agent_cli").strip().lower()
            if agent_id:
                targets.append((pane_id, agent_id, cli_type))
        if targets:
            return targets

    targets: list[tuple[str, str, str]] = []
    if tmux_ok("has-session", "-t", "shogun"):
        cli_type = tmux_output("show-options", "-p", "-t", "shogun:main", "-v", "@agent_cli").strip().lower() or "claude"
        targets.append(("shogun:main", "shogun", cli_type))
    if tmux_ok("has-session", "-t", "gunshi"):
        cli_type = tmux_output("show-options", "-p", "-t", "gunshi:main", "-v", "@agent_cli").strip().lower() or "claude"
        targets.append(("gunshi:main", "gunshi", cli_type))
    if tmux_ok("has-session", "-t", "multiagent"):
        out = tmux_output("list-panes", "-t", "multiagent:agents", "-F", "#{session_name}:#{window_name}.#{pane_index}")
        for target in out.splitlines():
            target = target.strip()
            if not target:
                continue
            agent_id = tmux_output("show-options", "-p", "-t", target, "-v", "@agent_id").strip()
            cli_type = tmux_output("show-options", "-p", "-t", target, "-v", "@agent_cli").strip().lower()
            if agent_id:
                targets.append((target, agent_id, cli_type))
    if targets:
        return targets
    return targets


def capture_joined(target: str) -> str:
    return tmux_output("capture-pane", "-J", "-p", "-t", target, "-S", "-200")


def normalize_gemini_label(label: str) -> str:
    value = label.strip()
    if not value:
        return ""
    if value.lower().startswith("auto"):
        return "auto"
    if MODEL_TOKEN_RE.match(value):
        return value
    m = re.search(r"(gemini-[A-Za-z0-9._-]+)", value, re.IGNORECASE)
    if m:
        return m.group(1)
    return ""


def is_valid_gemini_model(model: str) -> bool:
    value = (model or "").strip().lower()
    return value in {"", "auto", "default"} or value.startswith("gemini") or value.startswith("mas-")


def parse_codex_state(text: str) -> dict[str, str]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in reversed(lines[-40:]):
        match = CODEX_STATUS_RE.search(line)
        if not match:
            continue
        model = match.group(1).strip()
        effort = (match.group(2) or "auto").strip().lower()
        if model.startswith("/") or model.lower() in INVALID_CODEX_MODEL_TOKENS:
            continue
        return {"model": model, "reasoning_effort": effort}
    return {}


def is_valid_codex_model(model: str) -> bool:
    value = (model or "").strip()
    if not value:
        return True
    lower = value.lower()
    if lower in {"auto", "default"}:
        return True
    if "codux" in lower:
        return False
    if lower in INVALID_CODEX_MODEL_TOKENS:
        return False
    if value.startswith("/"):
        return False
    return bool(MODEL_TOKEN_RE.match(value))


def parse_gemini_state(text: str) -> dict[str, str]:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in reversed(lines[-60:]):
        if "/model" not in line:
            continue
        idx = line.rfind("/model")
        label = line[idx + len("/model"):].strip()
        normalized = normalize_gemini_label(label)
        if normalized:
            return {"model": normalized, "display": label}
    return {}


def apply_codex(agent_cfg: dict, state: dict[str, str]) -> bool:
    changed = False
    model = state.get("model", "")
    effort = state.get("reasoning_effort", "")
    if model and agent_cfg.get("model") != model:
        agent_cfg["model"] = model
        changed = True
    if effort and agent_cfg.get("reasoning_effort") != effort:
        agent_cfg["reasoning_effort"] = effort
        changed = True
    return changed


def apply_gemini(agent_cfg: dict, state: dict[str, str], alias_map: dict[str, dict[str, str]]) -> tuple[bool, str]:
    changed = False
    warning = ""
    model = state.get("model", "")
    if not model:
        return False, warning
    if model == "auto":
        warning = "Gemini footer が Auto 表示のため thinking 設定は据え置き"
    elif model in alias_map:
        row = alias_map[model]
        base_model = (row.get("base_model") or "").strip()
        desired_model = base_model or model
        if agent_cfg.get("model") != desired_model:
            agent_cfg["model"] = desired_model
            changed = True
        level = (row.get("thinking_level") or "").strip().lower()
        budget = (row.get("thinking_budget") or "").strip()
        if level:
            level = level.lower()
            if agent_cfg.get("thinking_level") != level:
                agent_cfg["thinking_level"] = level
                changed = True
        if budget:
            try:
                parsed_budget = int(budget)
            except ValueError:
                parsed_budget = budget
            if agent_cfg.get("thinking_budget") != parsed_budget:
                agent_cfg["thinking_budget"] = parsed_budget
                changed = True
    else:
        if agent_cfg.get("model") != model:
            agent_cfg["model"] = model
            changed = True
    return changed, warning


def main() -> int:
    cfg = load_yaml(SETTINGS_PATH)
    alias_map = load_gemini_aliases()
    targets = gather_targets()
    allowed_agents = configured_agent_ids(cfg)

    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)
    if not targets:
        SUMMARY_PATH.write_text("status\tskipped\treason\tno-running-tmux-agents\n", encoding="utf-8")
        if VERBOSE_NOOP:
            print("[INFO] no running tmux agent panes; runtime preference sync skipped")
        return 0

    changed_any = False
    rows = ["agent_id\tcli_type\tmodel\treasoning_effort\tthinking_level\tthinking_budget\twarning"]

    for target, agent_id, cli_type in targets:
        if agent_id not in allowed_agents:
            rows.append("\t".join([agent_id, cli_type, "", "", "", "", "not-configured-skip"]))
            continue

        text = capture_joined(target)
        agent_cfg = ensure_agent_cfg(cfg, agent_id)

        model = ""
        effort = ""
        level = ""
        budget = ""
        warning = ""
        configured_type = str(agent_cfg.get("type", "") or "").strip().lower()
        if configured_type and cli_type and configured_type != cli_type:
            warning = f"configured-type={configured_type}, running-cli={cli_type}"
            rows.append("\t".join([agent_id, cli_type, "", "", "", "", warning]))
            continue

        if cli_type == "codex":
            current_model = str(agent_cfg.get("model", "") or "")
            if current_model and not is_valid_codex_model(current_model):
                agent_cfg["model"] = "default"
                changed_any = True
                warning = f"{warning}; invalid-codex-model-reset={current_model}".strip("; ")
            state = parse_codex_state(text)
            if apply_codex(agent_cfg, state):
                changed_any = True
            model = state.get("model", "")
            effort = state.get("reasoning_effort", "")
        elif cli_type == "gemini":
            current_model = str(agent_cfg.get("model", "") or "")
            if current_model and not is_valid_gemini_model(current_model):
                agent_cfg["model"] = "auto"
                changed_any = True
                warning = f"{warning}; invalid-gemini-model-reset={current_model}".strip("; ")
            state = parse_gemini_state(text)
            changed, gemini_warning = apply_gemini(agent_cfg, state, alias_map)
            if changed:
                changed_any = True
            model = state.get("model", "")
            level = str(agent_cfg.get("thinking_level", "") or "")
            budget = str(agent_cfg.get("thinking_budget", "") or "")
            if gemini_warning:
                warning = f"{warning}; {gemini_warning}".strip("; ")
        else:
            warning = f"{warning}; unsupported-cli-runtime-sync".strip("; ")

        rows.append("\t".join([agent_id, cli_type, model, effort, level, budget, warning]))

    if changed_any:
        save_yaml(SETTINGS_PATH, cfg)
        print(f"[INFO] runtime CLI preferences synced: {SETTINGS_PATH}")
    elif VERBOSE_NOOP:
        print("[INFO] runtime CLI preferences unchanged")

    SUMMARY_PATH.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
