#!/usr/bin/env bash
# 人間向け「歴史書」生成スクリプト
# queue/ の一次情報から、直近の司令・タスク・報告を要約する。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/queue/history"
OUT_FILE="$OUT_DIR/rekishi_book.md"

mkdir -p "$OUT_DIR"

ROOT_DIR="$ROOT_DIR" OUT_FILE="$OUT_FILE" python3 - << 'PY'
from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml

root = Path(os.environ["ROOT_DIR"])
out_file = Path(os.environ["OUT_FILE"])


def load_yaml(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception:
        return default
    return default if data is None else data


def now_text() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def read_language() -> str:
    cfg = load_yaml(root / "config/settings.yaml", {})
    lang = str((cfg or {}).get("language", "ja")).strip().lower()
    return lang or "ja"


def sort_key_timestamp(item: dict[str, Any]) -> str:
    return str(item.get("timestamp") or "")


lang = read_language()

cmd_path = root / "queue/shogun_to_karo.yaml"
cmd_data = load_yaml(cmd_path, [])
if isinstance(cmd_data, dict):
    commands = cmd_data.get("commands", [])
elif isinstance(cmd_data, list):
    commands = cmd_data
else:
    commands = []
commands = [c for c in commands if isinstance(c, dict)]
commands_sorted = sorted(commands, key=sort_key_timestamp, reverse=True)

tasks: list[dict[str, Any]] = []
for task_file in sorted((root / "queue/tasks").glob("ashigaru*.yaml")):
    t = load_yaml(task_file, {})
    task = t.get("task", {}) if isinstance(t, dict) else {}
    if isinstance(task, dict):
        task = dict(task)
        task["agent"] = task_file.stem
        tasks.append(task)

reports: list[dict[str, Any]] = []
for rep_file in sorted((root / "queue/reports").glob("ashigaru*_report.yaml")):
    rep = load_yaml(rep_file, {})
    if isinstance(rep, dict):
        rep = dict(rep)
        rep["worker_id"] = rep.get("worker_id") or rep_file.stem.replace("_report", "")
        reports.append(rep)
reports_sorted = sorted(reports, key=sort_key_timestamp, reverse=True)

inbox_unread: dict[str, int] = {}
for agent in ("shogun", "karo"):
    inbox = load_yaml(root / f"queue/inbox/{agent}.yaml", {})
    msgs = inbox.get("messages", []) if isinstance(inbox, dict) else []
    if not isinstance(msgs, list):
        msgs = []
    unread = 0
    for m in msgs:
        if isinstance(m, dict) and not bool(m.get("read", False)):
            unread += 1
    inbox_unread[agent] = unread

pending_cmds = [
    c for c in commands_sorted
    if str(c.get("status", "")).strip().lower() not in ("done", "completed", "closed")
]

if lang == "ja":
    lines: list[str] = [
        "# 歴史書（会話履歴要約）",
        f"最終更新: {now_text()}",
        "",
        "## 指揮系統",
        "- 殿 → 将軍 → 家老 → 足軽",
        "- 家老完了報告は将軍経由で殿へ上申",
        "",
        "## 未完了の司令",
    ]
    if pending_cmds:
        for c in pending_cmds[:5]:
            cid = c.get("id", "-")
            purpose = c.get("purpose", "")
            status = c.get("status", "")
            lines.append(f"- `{cid}` ({status}): {purpose}")
    else:
        lines.append("- なし")

    lines.extend(["", "## 直近の司令（最新3件）"])
    if commands_sorted:
        for c in commands_sorted[:3]:
            cid = c.get("id", "-")
            ts = c.get("timestamp", "")
            st = c.get("status", "")
            lines.append(f"- `{cid}` [{st}] {ts}")
    else:
        lines.append("- 記録なし")

    lines.extend(["", "## 足軽の最新任務状態"])
    if tasks:
        for t in sorted(tasks, key=lambda x: str(x.get("agent", ""))):
            agent = t.get("agent", "-")
            tid = t.get("task_id", "-")
            status = t.get("status", "-")
            parent = t.get("parent_cmd", "-")
            lines.append(f"- `{agent}`: `{tid}` ({status}) / parent: `{parent}`")
    else:
        lines.append("- 記録なし")

    lines.extend(["", "## 直近の戦果報告（最新5件）"])
    if reports_sorted:
        for r in reports_sorted[:5]:
            wid = r.get("worker_id", "-")
            tid = r.get("task_id", "-")
            status = r.get("status", "-")
            ts = r.get("timestamp", "")
            result = r.get("result", {}) if isinstance(r.get("result"), dict) else {}
            summary = result.get("summary", "")
            lines.append(f"- `{wid}` `{tid}` [{status}] {ts}: {summary}")
    else:
        lines.append("- 記録なし")

    lines.extend([
        "",
        "## 伝令（inbox）未読",
        f"- shogun: {inbox_unread.get('shogun', 0)}",
        f"- karo: {inbox_unread.get('karo', 0)}",
        "",
    ])
else:
    lines = [
        "# Chronicle (Conversation Summary)",
        f"Last updated: {now_text()}",
        "",
        "## Chain of Command",
        "- Lord -> Shogun -> Karo -> Ashigaru",
        "- Completion reports should flow Karo -> Shogun -> Lord",
        "",
        "## Pending Commands",
    ]
    if pending_cmds:
        for c in pending_cmds[:5]:
            cid = c.get("id", "-")
            purpose = c.get("purpose", "")
            status = c.get("status", "")
            lines.append(f"- `{cid}` ({status}): {purpose}")
    else:
        lines.append("- none")

    lines.extend(["", "## Recent Commands (latest 3)"])
    if commands_sorted:
        for c in commands_sorted[:3]:
            cid = c.get("id", "-")
            ts = c.get("timestamp", "")
            st = c.get("status", "")
            lines.append(f"- `{cid}` [{st}] {ts}")
    else:
        lines.append("- no records")

    lines.extend(["", "## Ashigaru Task Snapshot"])
    if tasks:
        for t in sorted(tasks, key=lambda x: str(x.get("agent", ""))):
            agent = t.get("agent", "-")
            tid = t.get("task_id", "-")
            status = t.get("status", "-")
            parent = t.get("parent_cmd", "-")
            lines.append(f"- `{agent}`: `{tid}` ({status}) / parent: `{parent}`")
    else:
        lines.append("- no records")

    lines.extend(["", "## Recent Reports (latest 5)"])
    if reports_sorted:
        for r in reports_sorted[:5]:
            wid = r.get("worker_id", "-")
            tid = r.get("task_id", "-")
            status = r.get("status", "-")
            ts = r.get("timestamp", "")
            result = r.get("result", {}) if isinstance(r.get("result"), dict) else {}
            summary = result.get("summary", "")
            lines.append(f"- `{wid}` `{tid}` [{status}] {ts}: {summary}")
    else:
        lines.append("- no records")

    lines.extend([
        "",
        "## Unread Inbox",
        f"- shogun: {inbox_unread.get('shogun', 0)}",
        f"- karo: {inbox_unread.get('karo', 0)}",
        "",
    ])

tmp = out_file.with_suffix(".tmp")
tmp.write_text("\n".join(lines), encoding="utf-8")
tmp.replace(out_file)
print(out_file)
PY
