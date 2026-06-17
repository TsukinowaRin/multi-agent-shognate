#!/usr/bin/env python3
import os
import hashlib
import subprocess
from pathlib import Path

import yaml

DONE_STATUSES = {"done", "completed", "closed"}
COMPLETION_TIME_FIELDS = ("completed_at", "done_at", "closed_at", "verified_at", "updated_at")
COMPLETION_HASH_PREFIX = "digest:"


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

    cmds = collect_commands(dashboard, cmd_file, archive_file)
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
        )
        state.add(identity)
        newly_sent.append(cmd)

    save_state(state_file, state)

    if newly_sent:
        print("sent\t" + ",".join(format_status_entries(newly_sent)))
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
