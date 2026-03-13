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


def inbox_already_mentions(inbox_path: Path, cmd_id: str) -> bool:
    data = load_yaml(inbox_path) or {}
    for msg in data.get("messages", []) or []:
        if msg.get("from") != "shogun":
            continue
        if msg.get("type") != "cmd_new":
            continue
        if cmd_id in str(msg.get("content", "")):
            return True
    return False


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

    cmds = load_yaml(cmd_file) or []
    if not isinstance(cmds, list):
        cmds = []

    inbox_file.parent.mkdir(parents=True, exist_ok=True)
    if not inbox_file.exists():
        inbox_file.write_text("messages: []\n", encoding="utf-8")

    state = load_state(state_file)
    newly_sent = []

    for cmd in cmds:
        if not isinstance(cmd, dict):
            continue
        cmd_id = str(cmd.get("id", "")).strip()
        if not cmd_id:
            continue
        status = str(cmd.get("status", "")).strip().lower()
        if status not in {"pending", "assigned"}:
            continue
        if cmd_id in state:
            continue
        if inbox_already_mentions(inbox_file, cmd_id):
            state.add(cmd_id)
            continue

        content = (
            f"[cmd:{cmd_id}] 殿の新規命令が queue/shogun_to_karo.yaml に追加された。"
            "確認し、ただちに着手せよ。"
        )
        subprocess.run(
            [inbox_write, target_agent, content, "cmd_new", "shogun"],
            check=True,
            cwd=str(root),
        )
        state.add(cmd_id)
        newly_sent.append(cmd_id)

    save_state(state_file, state)

    if newly_sent:
        print("sent\t" + ",".join(newly_sent))
    else:
        print("noop")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
