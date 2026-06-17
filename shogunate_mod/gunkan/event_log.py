#!/usr/bin/env python3
"""Append lightweight, non-LLM events for Gunkan audit trails."""

from __future__ import annotations

import argparse
import os
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


MAX_EVENTS = 500
HIGH_SIGNAL_TYPES = {
    "audit_requested",
    "audit_warn",
    "audit_failed",
    "runtime_blocked",
    "emergency_stop_requested",
    "error_report",
    "cmd_done",
    "report_completed",
    "report_received",
}


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def atomic_write_yaml(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
        os.replace(tmp_path, path)
    except Exception:
        try:
            tmp_path.unlink()
        finally:
            raise


def short_content(content: str, limit: int = 500) -> str:
    compact = " ".join(content.split())
    if len(compact) <= limit:
        return compact
    return compact[: limit - 1] + "…"


def update_agent_summary(summary: dict[str, Any], agent: str, msg_type: str) -> None:
    if not agent:
        return
    agents = summary.setdefault("by_agent", {})
    item = agents.setdefault(
        agent,
        {
            "events": 0,
            "reports": 0,
            "failures": 0,
            "audit_requests": 0,
            "last_event_type": "",
            "last_seen": "",
        },
    )
    item["events"] = int(item.get("events") or 0) + 1
    item["last_event_type"] = msg_type
    item["last_seen"] = now_iso()
    if msg_type in {"report_completed", "report_received", "cmd_done"}:
        item["reports"] = int(item.get("reports") or 0) + 1
    if msg_type in {"error_report", "audit_failed", "runtime_blocked"}:
        item["failures"] = int(item.get("failures") or 0) + 1
    if msg_type == "audit_requested":
        item["audit_requests"] = int(item.get("audit_requests") or 0) + 1


def update_type_summary(summary: dict[str, Any], msg_type: str) -> None:
    by_type = summary.setdefault("by_type", {})
    by_type[msg_type] = int(by_type.get(msg_type) or 0) + 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--target", required=True)
    parser.add_argument("--from-agent", dest="from_agent", required=True)
    parser.add_argument("--type", dest="msg_type", required=True)
    parser.add_argument("--content", required=True)
    parser.add_argument("--message-id", default="")
    parser.add_argument("--timestamp", default="")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    output = Path(args.output) if args.output else root / "queue" / "runtime" / "gunkan_events.yaml"
    data = load_yaml(output)
    events = data.setdefault("events", [])
    summary = data.setdefault("summary", {})

    msg_type = args.msg_type.strip() or "unknown"
    event = {
        "id": args.message_id or f"evt_{datetime.now().strftime('%Y%m%d_%H%M%S_%f')}",
        "timestamp": args.timestamp or now_iso(),
        "from": args.from_agent,
        "target": args.target,
        "type": msg_type,
        "high_signal": msg_type in HIGH_SIGNAL_TYPES,
        "content": short_content(args.content),
    }
    events.append(event)
    if len(events) > MAX_EVENTS:
        del events[: len(events) - MAX_EVENTS]

    summary["updated_at"] = now_iso()
    summary["total_events"] = int(summary.get("total_events") or 0) + 1
    update_agent_summary(summary, args.from_agent, msg_type)
    update_type_summary(summary, msg_type)

    atomic_write_yaml(output, data)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
