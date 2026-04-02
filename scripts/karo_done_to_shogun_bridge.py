#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path

import yaml

DONE_STATUSES = {"done", "completed", "closed"}


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


def command_identity(cmd: dict) -> str:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    if not cmd_id:
        return ""
    return f"{cmd_id}\t{timestamp}" if timestamp else cmd_id


def upgrade_legacy_state(state, cmds):
    unique_identity_by_id = {}
    duplicates = set()

    for cmd in cmds:
        identity = command_identity(cmd)
        if not identity:
            continue
        cmd_id = str(cmd.get("id", "")).strip()
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


def state_contains(state, cmd: dict) -> bool:
    identity = command_identity(cmd)
    if not identity:
        return False
    if identity in state:
        return True
    cmd_id = str(cmd.get("id", "")).strip()
    # Backward compatibility for older state files that stored only cmd_id.
    return bool(cmd_id and "\t" not in identity and cmd_id in state)


def inbox_already_mentions(inbox_path: Path, cmd: dict) -> bool:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    data = load_yaml(inbox_path) or {}
    for msg in data.get("messages", []) or []:
        if msg.get("type") != "cmd_done":
            continue
        content = str(msg.get("content", ""))
        if not cmd_id or cmd_id not in content:
            continue
        if not timestamp or timestamp in content:
            return True
    return False


def extract_dashboard_summary(dashboard_path: Path, cmd_id: str) -> str:
    if not dashboard_path.exists():
        return ""
    for raw in dashboard_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if cmd_id in line and line:
            return line[:240]
    return ""


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


def collect_commands(*paths: Path):
    commands = []
    seen = set()
    for path in paths:
        for cmd in normalize_commands(load_yaml(path) or []):
            identity = command_identity(cmd)
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


def main() -> int:
    root = Path(os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[1]))
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

    cmds = collect_commands(cmd_file, archive_file)
    shogun_inbox.parent.mkdir(parents=True, exist_ok=True)
    if not shogun_inbox.exists():
        shogun_inbox.write_text("messages: []\n", encoding="utf-8")

    if not state_file.exists():
        existing_done = {
            command_identity(cmd)
            for cmd in cmds
            if str(cmd.get("status", "")).strip().lower() in DONE_STATUSES and command_identity(cmd)
        }
        save_state(state_file, existing_done)
        if existing_done:
            print("primed\t" + ",".join(sorted(existing_done)))
        else:
            print("noop\tempty")
        return 0

    state = upgrade_legacy_state(load_state(state_file), cmds)
    newly_sent = []
    already_sent = []
    already_notified = []
    skipped_not_done = []

    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        identity = command_identity(cmd)
        if not cmd_id:
            continue
        status = str(cmd.get("status", "")).strip().lower()
        if status not in DONE_STATUSES:
            skipped_not_done.append(cmd_id)
            continue
        if state_contains(state, cmd):
            already_sent.append(cmd)
            continue
        if inbox_already_mentions(shogun_inbox, cmd):
            state.add(identity)
            already_notified.append(cmd)
            continue

        purpose = str(cmd.get("purpose", "")).strip()
        timestamp = str(cmd.get("timestamp", "")).strip()
        summary = extract_dashboard_summary(dashboard, cmd_id)
        content = f"[cmd:{cmd_id}] 家老より完了報告。dashboard.md を確認し、殿へ結果を上申せよ。"
        if timestamp:
            content += f" 時刻: {timestamp}"
        if purpose:
            content += f" 目的: {purpose}。"
        if summary:
            content += f" 要約: {summary}"
        subprocess.run(
            [inbox_write, target_agent, content, "cmd_done", "karo"],
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
