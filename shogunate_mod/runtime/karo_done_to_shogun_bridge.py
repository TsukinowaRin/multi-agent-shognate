#!/usr/bin/env python3
import os
import hashlib
import subprocess
import sys
from pathlib import Path

import yaml

DONE_STATUSES = {"done", "completed", "closed"}
COMPLETION_TIME_FIELDS = ("completed_at", "done_at", "closed_at", "verified_at", "updated_at")
COMPLETION_HASH_PREFIX = "digest:"

# report provenance (acceptance 3): strict marker がある新runtimeでは、cmd完了通知を
# Shogunへ送る前に全 required role の pane-bound receipt と現report digest を検証する。
# 不合格なら cmd_done を送らず、state も更新せず、blocked ledger へ reason を1件だけ
# 記録する。marker がない legacy runtime は従来挙動を保つ (acceptance 4)。
_REPORT_PROVENANCE_REL = Path("shogunate_mod/runtime/report_provenance.py")


def load_yaml(path: Path):
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except Exception:
        return None


def load_state(path: Path):
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def save_state(path: Path, ids):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for cmd_id in sorted(set(ids)):
            fh.write(f"{cmd_id}\n")


def compact(text: str, limit: int = 360) -> str:
    normalized = " ".join(str(text).split())
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 3] + "..."


def command_completion_marker(cmd: dict, dashboard_summary: str = "") -> str:
    for field in COMPLETION_TIME_FIELDS:
        value = str(cmd.get(field, "")).strip()
        if value:
            return value

    payload = {
        "command": {
            key: cmd.get(key)
            for key in sorted(cmd)
            if key not in {"read", "claimed_by", "claimed_at"}
        },
        "dashboard": dashboard_summary,
    }
    dumped = yaml.safe_dump(payload, allow_unicode=True, sort_keys=True)
    return COMPLETION_HASH_PREFIX + hashlib.sha256(dumped.encode("utf-8")).hexdigest()[:16]


def command_identity(cmd: dict, dashboard_summary: str = "") -> str:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    if not cmd_id:
        return ""
    parts = [cmd_id]
    if timestamp:
        parts.append(timestamp)
    marker = command_completion_marker(cmd, dashboard_summary)
    if marker:
        parts.append(marker)
    return "\t".join(parts)


def upgrade_legacy_state(state, cmds, dashboard_path: Path):
    unique_identity_by_id = {}
    duplicates = set()

    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        identity = command_identity(cmd, extract_dashboard_summary(dashboard_path, cmd_id))
        if not identity:
            continue
        if cmd_id in unique_identity_by_id:
            duplicates.add(cmd_id)
            continue
        unique_identity_by_id[cmd_id] = identity

    for cmd_id in duplicates:
        unique_identity_by_id.pop(cmd_id, None)

    upgraded = set()
    for entry in state:
        if "\t" in entry:
            upgraded.add(entry)
            continue
        upgraded.add(unique_identity_by_id.get(entry, entry))
    return upgraded


def state_contains(state, cmd: dict, dashboard_summary: str = "", allow_legacy_base: bool = False) -> bool:
    identity = command_identity(cmd, dashboard_summary)
    if not identity:
        return False
    if identity in state:
        return True
    cmd_id = str(cmd.get("id", "")).strip()
    if cmd_id and cmd_id in state:
        return True
    if allow_legacy_base:
        parts = identity.split("\t")
        if len(parts) >= 2 and "\t".join(parts[:2]) in state:
            return True
    return False


def inbox_mentions_cmd_timestamp(inbox_path: Path, cmd: dict) -> bool:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    data = load_yaml(inbox_path) or {}
    for msg in data.get("messages", []) or []:
        if msg.get("type") != "cmd_done":
            continue
        content = str(msg.get("content", ""))
        if cmd_id and cmd_id in content and (not timestamp or timestamp in content):
            return True
    return False


def inbox_already_mentions(inbox_path: Path, cmd: dict, dashboard_summary: str = "") -> bool:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    marker = command_completion_marker(cmd, dashboard_summary)
    data = load_yaml(inbox_path) or {}
    for msg in data.get("messages", []) or []:
        if msg.get("type") != "cmd_done":
            continue
        content = str(msg.get("content", ""))
        if not cmd_id or cmd_id not in content:
            continue
        if marker and marker in content:
            return True
        if marker.startswith(COMPLETION_HASH_PREFIX) and not dashboard_summary and (not timestamp or timestamp in content):
            return True
        if not marker.startswith(COMPLETION_HASH_PREFIX) and (not timestamp or timestamp in content):
            return True
    return False


def extract_dashboard_summary(dashboard_path: Path, cmd_id: str) -> str:
    if not dashboard_path.exists():
        return ""
    matches = []
    for raw in dashboard_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if cmd_id in line and line:
            matches.append(line)
    return compact(" / ".join(matches[-4:]), 320)


def normalize_commands(data):
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    if isinstance(data, dict):
        queue = data.get("queue")
        if queue is None:
            queue = data.get("commands", [])
        if isinstance(queue, list):
            return [x for x in queue if isinstance(x, dict)]
    return []


def collect_commands(dashboard_path: Path, *paths: Path):
    commands = []
    seen = set()
    for path in paths:
        for cmd in normalize_commands(load_yaml(path) or []):
            cmd_id = str(cmd.get("id", "")).strip()
            identity = command_identity(cmd, extract_dashboard_summary(dashboard_path, cmd_id))
            if not identity or identity in seen:
                continue
            seen.add(identity)
            commands.append(cmd)
    return commands


def format_status_entries(cmds):
    counts = {}
    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        if not cmd_id:
            continue
        counts[cmd_id] = counts.get(cmd_id, 0) + 1

    labels = []
    seen = set()
    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        if not cmd_id:
            continue
        timestamp = str(cmd.get("timestamp", "")).strip()
        label = cmd_id
        if counts.get(cmd_id, 0) > 1 and timestamp:
            label = f"{cmd_id}@{timestamp}"
        if label in seen:
            continue
        seen.add(label)
        labels.append(label)
    return labels


def read_lead_karo(runtime_dir: Path) -> str:
    path = runtime_dir / "lead_karo"
    if not path.exists():
        return ""
    value = path.read_text(encoding="utf-8").strip().splitlines()
    return value[0].strip() if value and value[0].strip() else ""


def _load_provenance(root: Path):
    if str(root) not in _load_provenance._cache:
        sys.path.insert(0, str(root))
        import importlib
        mod = importlib.import_module("shogunate_mod.runtime.report_provenance")
        _load_provenance._cache[str(root)] = mod
    return _load_provenance._cache[str(root)]
_load_provenance._cache = {}


def _strict_marker_present(runtime_dir: Path) -> bool:
    return (runtime_dir / "report_provenance_required").exists()


def _load_failover_roles(runtime_dir: Path) -> dict:
    state_path = runtime_dir / "role_failover.yaml"
    if not state_path.exists():
        return {}
    data = load_yaml(state_path) or {}
    roles = data.get("roles") if isinstance(data, dict) else {}
    return roles if isinstance(roles, dict) else {}


def _collect_cmd_task_roles(cmd: dict) -> list:
    """cmd に紐付く task 提出 role を収集する (acceptance 3)。

    audit_gate は report_provenance.required_receipt_roles 側で拾うので、ここでは
    実作業 role (ashigaru 等) だけを cmd の task/assignee 系 field から抽出する。
    構造は幅広く受け入れ、role 名として妥当なものだけ残す。
    """
    roles: list = []

    def add(value):
        if isinstance(value, str) and value:
            roles.append(value)

    for key in ("ashigaru", "assignees", "owners", "roles"):
        v = cmd.get(key)
        if isinstance(v, list):
            for item in v:
                add(item if isinstance(item, str) else (item.get("role") if isinstance(item, dict) else None))
        elif isinstance(v, str):
            add(v)

    tasks = cmd.get("tasks")
    if isinstance(tasks, list):
        for task in tasks:
            if not isinstance(task, dict):
                continue
            for key in ("assigned_to", "assignee", "owner", "role", "agent"):
                add(task.get(key))

    rp = _load_provenance(Path(os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[2])))
    return [r for r in dict.fromkeys(roles) if rp.is_role_name(r)]


def _collect_cmd_task_contexts(queue_dir: Path, cmd: dict) -> dict[str, dict[str, str]]:
    """queue/tasks の実taskをcmdへ結び、roleごとの期待contextを返す。

    cmd inline fieldだけを見ると、通常運用の別file taskを見落としてrequired roleが
    空になり得る。task fileのparent_cmdを必須にし、roleは明示fieldを優先しつつ
    role名file（ashigaru1.yaml等）を正規fallbackとして使う。
    """
    cmd_id = str(cmd.get("id") or "").strip()
    if not cmd_id:
        return {}
    rp = _load_provenance(Path(os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[2])))
    contexts: dict[str, dict[str, str]] = {}
    tasks_dir = Path(queue_dir) / "tasks"
    if not tasks_dir.is_dir():
        return contexts
    for path in sorted(tasks_dir.glob("*.yaml")):
        raw = load_yaml(path)
        if not isinstance(raw, dict):
            continue
        task = raw.get("task") if isinstance(raw.get("task"), dict) else raw
        parent_cmd = str(task.get("parent_cmd") or task.get("cmd_id") or "").strip()
        if parent_cmd != cmd_id:
            continue
        role = ""
        for key in ("assigned_to", "assignee", "owner", "role", "agent", "worker_id"):
            value = str(task.get(key) or "").strip()
            if rp.is_role_name(value):
                role = value
                break
        if not role and rp.is_role_name(path.stem):
            role = path.stem
        if not role:
            continue
        task_id = str(task.get("task_id") or task.get("id") or "").strip()
        contexts[role] = {"task_id": task_id, "parent_cmd": parent_cmd}
    return contexts


def _command_completion_blocked_by_provenance(root: Path, runtime_dir: Path, cmd: dict) -> str | None:
    """strict marker がある時、provenance gate が cmd 完了を止めるなら reason を返す。

    合格 (または legacy/marker なし) なら None を返し、呼び出し側は従来どおり通知する。
    """
    if not _strict_marker_present(runtime_dir):
        return None
    rp = _load_provenance(root)
    role_states_raw = _load_failover_roles(runtime_dir)
    task_contexts = _collect_cmd_task_contexts(root / "queue", cmd)
    cmd_id = str(cmd.get("id") or "").strip()
    for role in _collect_cmd_task_roles(cmd):
        task_contexts.setdefault(role, {"task_id": "", "parent_cmd": cmd_id})
    task_roles = list(task_contexts)
    required = rp.required_receipt_roles(cmd, task_roles)
    expected_contexts = {
        role: task_contexts.get(role, {"task_id": "", "parent_cmd": cmd_id})
        for role in required
    }
    receipt_dir = runtime_dir / "report_receipts"
    receipts: dict = {}
    role_states: dict = {}
    report_bytes_by_role: dict = {}
    for role in required:
        receipts[role] = rp.load_receipt(receipt_dir, role)
        rs = role_states_raw.get(role)
        role_states[role] = rs if isinstance(rs, dict) else None
        report_path = root / rp.expected_report_rel(role)
        if report_path.is_file():
            try:
                report_bytes_by_role[role] = report_path.read_bytes()
            except OSError:
                report_bytes_by_role[role] = b""
        else:
            report_bytes_by_role[role] = b""
    result = rp.validate_completion(
        cmd=cmd,
        task_roles=task_roles,
        receipts=receipts,
        role_states=role_states,
        report_bytes_by_role=report_bytes_by_role,
        expected_context_by_role=expected_contexts,
    )
    if result.ok:
        return None
    # 不合格: cmd YAML を自動書き戻さず、blocked ledger へ reason を1件だけ記録する
    # (acceptance 3, plan判断: Karo編集中YAMLとの競合回避)。
    ledger = runtime_dir / "report_provenance_blocked.yaml"
    entry = rp.blocked_ledger_entry(
        cmd_id=str(cmd.get("id", "")),
        reason=result.reason,
        missing_roles=result.missing_roles,
        invalid_roles=result.invalid_roles,
    )
    try:
        rp.append_blocked_ledger(ledger, entry)
    except Exception:
        pass
    return result.reason


def sender_generation_env(runtime_dir: Path, sender: str) -> dict[str, str]:
    env = os.environ.copy()
    state_path = runtime_dir / "role_failover.yaml"
    if not state_path.exists():
        return env
    state = load_yaml(state_path) or {}
    roles = state.get("roles") if isinstance(state, dict) else {}
    role_state = roles.get(sender) if isinstance(roles, dict) else None
    generation = role_state.get("generation") if isinstance(role_state, dict) else None
    if isinstance(generation, int) and not isinstance(generation, bool) and generation > 0:
        env["MAS_ROLE_GENERATION"] = str(generation)
    return env


def main() -> int:
    root = Path(os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[2]))
    queue_dir = Path(os.environ.get("MAS_QUEUE_DIR", root / "queue"))
    runtime_dir = Path(os.environ.get("MAS_RUNTIME_DIR", queue_dir / "runtime"))
    cmd_file = Path(os.environ.get("MAS_SHOGUN_TO_KARO_FILE", queue_dir / "shogun_to_karo.yaml"))
    archive_file = Path(
        os.environ.get("MAS_SHOGUN_TO_KARO_ARCHIVE_FILE", queue_dir / "shogun_to_karo_archive.yaml")
    )
    shogun_inbox = Path(os.environ.get("MAS_SHOGUN_INBOX_FILE", queue_dir / "inbox" / "shogun.yaml"))
    dashboard = Path(os.environ.get("MAS_DASHBOARD_FILE", root / "dashboard.md"))
    state_file = Path(os.environ.get("MAS_KARO_DONE_TO_SHOGUN_STATE", runtime_dir / "karo_done_to_shogun.tsv"))
    inbox_write = os.environ.get("MAS_INBOX_WRITE_SCRIPT", str(root / "scripts" / "inbox_write.sh"))
    target_agent = os.environ.get("MAS_SHOGUN_TARGET_AGENT", "shogun")
    source_agent = os.environ.get("MAS_KARO_DONE_FROM_AGENT") or read_lead_karo(runtime_dir) or "karo"

    command_sources = [cmd_file]
    include_archive = os.environ.get("MAS_KARO_DONE_INCLUDE_ARCHIVE", "").strip().lower()
    if include_archive in {"1", "true", "yes", "on"}:
        command_sources.append(archive_file)
    cmds = collect_commands(dashboard, *command_sources)
    shogun_inbox.parent.mkdir(parents=True, exist_ok=True)
    if not shogun_inbox.exists():
        shogun_inbox.write_text("messages: []\n", encoding="utf-8")

    if not state_file.exists():
        existing_done = set()
        for cmd in cmds:
            cmd_id = str(cmd.get("id", "")).strip()
            summary = extract_dashboard_summary(dashboard, cmd_id)
            identity = command_identity(cmd, summary)
            if str(cmd.get("status", "")).strip().lower() in DONE_STATUSES and identity:
                existing_done.add(identity)
        save_state(state_file, existing_done)
        if existing_done:
            print("primed\t" + ",".join(sorted(existing_done)))
        else:
            print("noop\tempty")
        return 0

    state = upgrade_legacy_state(load_state(state_file), cmds, dashboard)
    newly_sent = []
    already_sent = []
    already_notified = []
    already_blocked = []
    skipped_not_done = []

    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        summary = extract_dashboard_summary(dashboard, cmd_id)
        identity = command_identity(cmd, summary)
        marker = command_completion_marker(cmd, summary)
        if not cmd_id:
            continue
        status = str(cmd.get("status", "")).strip().lower()
        if status not in DONE_STATUSES:
            skipped_not_done.append(cmd_id)
            continue
        allow_legacy_base = not inbox_mentions_cmd_timestamp(shogun_inbox, cmd)
        if state_contains(state, cmd, summary, allow_legacy_base=allow_legacy_base):
            already_sent.append(cmd)
            continue
        if inbox_already_mentions(shogun_inbox, cmd, summary):
            state.add(identity)
            already_notified.append(cmd)
            continue

        # report provenance strict gate (acceptance 3, 4): marker がある新runtimeで
        # receipt/digest 検証が不合格なら cmd_done を送らず、state も更新しない。
        blocked_reason = _command_completion_blocked_by_provenance(root, runtime_dir, cmd)
        if blocked_reason is not None:
            # 送信も state 更新もしない (Karo/Gunkan が blocked ledger と summary で
            # 再差配するのを待つ)。理由を次出力へ明示する。
            already_blocked.append((cmd_id, blocked_reason))
            continue

        purpose = str(cmd.get("purpose", "")).strip()
        timestamp = str(cmd.get("timestamp", "")).strip()
        completed_at = str(cmd.get("completed_at", "")).strip()
        content = f"[cmd:{cmd_id}] 家老より完了報告。dashboard.md を確認し、殿へ結果を上申せよ。"
        if timestamp:
            content += f" 時刻: {timestamp}"
        if completed_at:
            content += f" 完了: {completed_at}"
        elif marker.startswith(COMPLETION_HASH_PREFIX):
            content += f" 完了ID: {marker}"
        elif marker:
            content += f" 完了: {marker}"
        if purpose:
            content += f" 目的: {purpose}。"
        if summary:
            content += f" 要約: {summary}"
        subprocess.run(
            [inbox_write, target_agent, content, "cmd_done", source_agent],
            check=True,
            cwd=str(root),
            env=sender_generation_env(runtime_dir, source_agent),
        )
        state.add(identity)
        newly_sent.append(cmd)

    save_state(state_file, state)

    if newly_sent:
        print("sent\t" + ",".join(format_status_entries(newly_sent)))
    elif already_blocked:
        # strict gate で完了通知を止めた。false completion させず、reason を明示する。
        print("blocked\t" + ",".join(f"{cid}:{rsn}" for cid, rsn in already_blocked))
    elif already_notified:
        print("noop\talready_notified=" + ",".join(format_status_entries(already_notified)))
    elif already_sent:
        print("noop\talready_sent=" + ",".join(format_status_entries(already_sent)))
    elif skipped_not_done:
        print("noop\tno_completed")
    else:
        print("noop\tempty")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
