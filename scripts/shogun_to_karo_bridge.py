#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

import yaml


def load_yaml(path: Path):
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as fh:
            return yaml.safe_load(fh)
    except Exception:
        return None


def save_state(path: Path, ids):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        for cmd_id in sorted(set(ids)):
            fh.write(f"{cmd_id}\n")


def load_state(path: Path):
    if not path.exists():
        return set()
    return {
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


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
    return bool(cmd_id and "\t" not in identity and cmd_id in state)


def inbox_already_mentions(inbox_path: Path, cmd: dict) -> bool:
    cmd_id = str(cmd.get("id", "")).strip()
    timestamp = str(cmd.get("timestamp", "")).strip()
    data = load_yaml(inbox_path) or {}
    for msg in data.get("messages", []) or []:
        if msg.get("from") != "shogun":
            continue
        if msg.get("type") != "cmd_new":
            continue
        content = str(msg.get("content", ""))
        if not cmd_id or cmd_id not in content:
            continue
        if not timestamp or timestamp in content:
            return True
    return False


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


def main() -> int:
    root = Path(os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[1]))
    queue_dir = Path(os.environ.get("MAS_QUEUE_DIR", root / "queue"))
    runtime_dir = Path(os.environ.get("MAS_RUNTIME_DIR", queue_dir / "runtime"))
    cmd_file = Path(os.environ.get("MAS_SHOGUN_TO_KARO_FILE", queue_dir / "shogun_to_karo.yaml"))
    inbox_file = Path(os.environ.get("MAS_KARO_INBOX_FILE", queue_dir / "inbox" / "karo.yaml"))
    state_file = Path(
        os.environ.get(
            "MAS_SHOGUN_TO_KARO_BRIDGE_STATE",
            runtime_dir / "shogun_to_karo_bridge.tsv",
        )
    )
    inbox_write = os.environ.get(
        "MAS_INBOX_WRITE_SCRIPT", str(root / "scripts" / "inbox_write.sh")
    )
    target_agent = os.environ.get("MAS_KARO_TARGET_AGENT", "karo")

    cmds = normalize_commands(load_yaml(cmd_file) or [])

    inbox_file.parent.mkdir(parents=True, exist_ok=True)
    if not inbox_file.exists():
        inbox_file.write_text("messages: []\n", encoding="utf-8")

    state = upgrade_legacy_state(load_state(state_file), cmds)
    newly_sent = []
    already_sent = []
    already_notified = []
    skipped_nonpending = []

    for cmd in cmds:
        cmd_id = str(cmd.get("id", "")).strip()
        identity = command_identity(cmd)
        if not cmd_id:
            continue
        status = str(cmd.get("status", "")).strip().lower()
        if status not in {"pending", "assigned"}:
            skipped_nonpending.append(cmd_id)
            continue
        if state_contains(state, cmd):
            already_sent.append(cmd_id)
            continue
        if inbox_already_mentions(inbox_file, cmd):
            if identity:
                state.add(identity)
            already_notified.append(cmd_id)
            continue

        timestamp = str(cmd.get("timestamp", "")).strip()
        content = (
            f"[cmd:{cmd_id}] 殿の新規命令が queue/shogun_to_karo.yaml に追加された。"
            "確認し、ただちに着手せよ。"
        )
        if timestamp:
            content += f" 時刻: {timestamp}"
        subprocess.run(
            [inbox_write, target_agent, content, "cmd_new", "shogun"],
            check=True,
            cwd=str(root),
        )
        if identity:
            state.add(identity)
        newly_sent.append(cmd_id)

    save_state(state_file, state)

    if newly_sent:
        print("sent\t" + ",".join(newly_sent))
    elif already_notified:
        print("noop\talready_notified=" + ",".join(already_notified))
    elif already_sent:
        print("noop\talready_sent=" + ",".join(already_sent))
    elif skipped_nonpending:
        print("noop\tno_pending")
    else:
        print("noop\tempty")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
