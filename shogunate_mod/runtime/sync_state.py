#!/usr/bin/env python3
"""Synchronize Shogunate runtime YAML state and wake Gunkan for final audits."""

from __future__ import annotations

import argparse
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


DONE_STATUSES = {"done", "completed", "closed", "passed", "warn"}
BAD_STATUSES = {"failed", "error", "blocked", "rejected"}
COMMAND_OPEN_STATUSES = {"pending", "assigned", "in_progress", "audit_requested", "review"}
STATE_FILE_NAME = "runtime_sync_state.yaml"


def now_iso() -> str:
    return datetime.now().astimezone().replace(microsecond=0).isoformat()


def load_yaml(path: Path, default: Any = None) -> Any:
    if not path.exists():
        return default
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except Exception:
        return default
    return default if data is None else data


def save_yaml(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)


def normalize_records(data: Any, key: str) -> list[dict[str, Any]]:
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict):
        items = data.get(key)
        if items is None:
            items = data.get("queue")
        if isinstance(items, list):
            return [item for item in items if isinstance(item, dict)]
        if any(name in data for name in ("id", "task_id", "parent_cmd", "status")):
            return [data]
    return []


def command_id(command: dict[str, Any]) -> str:
    return str(command.get("id", "")).strip()


def record_status(record: dict[str, Any]) -> str:
    return str(record.get("status", "")).strip().lower()


def task_id(task: dict[str, Any], fallback: str = "") -> str:
    for key in ("task_id", "id"):
        value = str(task.get(key, "")).strip()
        if value:
            return value
    return fallback


def report_task_id(report: dict[str, Any], fallback: str = "") -> str:
    for key in ("task_id", "id", "task"):
        value = str(report.get(key, "")).strip()
        if value:
            return value
    worker = str(report.get("worker_id", "")).strip()
    return worker or fallback


def compact(text: Any, limit: int = 180) -> str:
    normalized = " ".join(str(text or "").split())
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 3] + "..."


def load_commands(path: Path) -> tuple[Any, list[dict[str, Any]]]:
    data = load_yaml(path, [])
    return data, normalize_records(data, "commands")


def save_commands(path: Path, original: Any, commands: list[dict[str, Any]]) -> None:
    if isinstance(original, dict):
        key = "commands" if "commands" in original else "queue"
        original[key] = commands
        save_yaml(path, original)
        return
    save_yaml(path, commands)


def collect_tasks(queue_dir: Path, parent_cmd: str) -> list[tuple[Path, dict[str, Any]]]:
    tasks_dir = queue_dir / "tasks"
    records: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(tasks_dir.glob("*.yaml")):
        data = load_yaml(path, {})
        for task in normalize_records(data, "tasks"):
            if str(task.get("parent_cmd", "")).strip() == parent_cmd:
                records.append((path, task))
    return records


def collect_reports(queue_dir: Path, parent_cmd: str, *, include_gunkan: bool = False) -> list[tuple[Path, dict[str, Any]]]:
    reports_dir = queue_dir / "reports"
    records: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(reports_dir.glob("*.yaml")):
        if not include_gunkan and path.name == "gunkan_report.yaml":
            continue
        data = load_yaml(path, {})
        for report in normalize_records(data, "reports"):
            if str(report.get("parent_cmd", "")).strip() == parent_cmd:
                records.append((path, report))
    return records


def gunkan_audit_report(queue_dir: Path, parent_cmd: str) -> tuple[Path, dict[str, Any]] | None:
    path = queue_dir / "reports" / "gunkan_report.yaml"
    for report in normalize_records(load_yaml(path, {}), "reports"):
        if str(report.get("parent_cmd", "")).strip() == parent_cmd:
            return path, report
    return None


def update_task_file(path: Path, wanted_task_id: str, status: str, completed_at: str) -> bool:
    data = load_yaml(path, {})
    records = normalize_records(data, "tasks")
    changed = False
    for task in records:
        if task_id(task, path.stem) != wanted_task_id:
            continue
        if record_status(task) != status:
            task["status"] = status
            changed = True
        if status in DONE_STATUSES and not task.get("completed_at"):
            task["completed_at"] = completed_at
            changed = True
    if changed:
        save_yaml(path, data)
    return changed


def read_state(path: Path) -> dict[str, Any]:
    state = load_yaml(path, {}) or {}
    if not isinstance(state, dict):
        state = {}
    state.setdefault("gunkan_audit_requested", [])
    state.setdefault("gunkan_reaudit_requested", [])
    state.setdefault("karo_review_requested", [])
    return state


def save_state(path: Path, state: dict[str, Any]) -> None:
    save_yaml(path, state)


def inbox_contains_audit_request(inbox_path: Path, cmd_id: str) -> bool:
    data = load_yaml(inbox_path, {}) or {}
    for msg in data.get("messages", []) or []:
        content = str(msg.get("content", ""))
        if msg.get("type") == "audit_requested" and f"[cmd:{cmd_id}]" in content:
            return True
    return False


def request_gunkan_audit(
    root: Path,
    queue_dir: Path,
    cmd: dict[str, Any],
    reports: list[tuple[Path, dict[str, Any]]],
    state: dict[str, Any],
    *,
    force: bool = False,
    reason: str = "",
) -> bool:
    cmd_id = command_id(cmd)
    requested = set(state.get("gunkan_audit_requested", []) or [])
    if not force and cmd_id in requested:
        return False
    inbox_path = queue_dir / "inbox" / "gunkan.yaml"
    if not force and inbox_contains_audit_request(inbox_path, cmd_id):
        requested.add(cmd_id)
        state["gunkan_audit_requested"] = sorted(requested)
        return False

    report_names = ", ".join(sorted(path.name for path, _ in reports)) or "no reports"
    target_project = str(cmd.get("project") or cmd.get("target_project") or root)
    prefix = "runtime-syncより再監査を要請。" if force else "runtime-syncより最終監査を要請。"
    reason_text = f" 理由: {reason}" if reason else ""
    content = (
        f"[cmd:{cmd_id}] {prefix}{reason_text}"
        f" 足軽reportが揃いました。成果物・テスト結果・禁止操作違反の有無を確認し、"
        f"queue/reports/gunkan_report.yaml に parent_cmd: {cmd_id} の監査reportを書いてください。"
        f" target_project: {target_project} reports: {report_names}"
    )
    inbox_write = root / "scripts" / "inbox_write.sh"
    subprocess.run(
        ["bash", str(inbox_write), "gunkan", content, "audit_requested", "runtime_sync"],
        cwd=str(root),
        check=True,
    )
    requested.add(cmd_id)
    state["gunkan_audit_requested"] = sorted(requested)
    return True


def request_karo_review(root: Path, queue_dir: Path, cmd: dict[str, Any], audit: dict[str, Any], state: dict[str, Any]) -> bool:
    cmd_id = command_id(cmd)
    requested = set(state.get("karo_review_requested", []) or [])
    audit_key = str(audit.get("audit_id") or audit.get("timestamp") or record_status(audit) or "audit")
    key = f"{cmd_id}:{audit_key}"
    if key in requested:
        return False
    content = (
        f"[cmd:{cmd_id}] 軍監監査が {record_status(audit) or 'failed'} です。"
        f" queue/reports/gunkan_report.yaml を読み、指摘を修正差配してください。"
        f" 修正後は必要な足軽reportを更新し、軍監へ再監査を依頼してください。"
    )
    inbox_write = root / "scripts" / "inbox_write.sh"
    subprocess.run(
        ["bash", str(inbox_write), "karo", content, "audit_failed", "runtime_sync"],
        cwd=str(root),
        check=True,
    )
    requested.add(key)
    state["karo_review_requested"] = sorted(requested)
    return True


def latest_report_mtime(reports: list[tuple[Path, dict[str, Any]]]) -> int:
    mtimes = [path.stat().st_mtime_ns for path, _ in reports if path.exists()]
    return max(mtimes) if mtimes else 0


def dashboard_template() -> str:
    return "\n".join(
        [
            "# Shogunate Dashboard",
            "",
            "最終更新: -",
            "",
            "## 🔄 進行中",
            "",
            "なし",
            "",
            "## ✅ 本日の戦果",
            "",
            "| 時刻 | command | 状態 | 要約 |",
            "|---|---|---|---|",
            "",
        ]
    )


def replace_section(text: str, heading: str, body: list[str]) -> str:
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == heading)
    except StopIteration:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([heading, ""])
        start = len(lines) - 2
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    return "\n".join(lines[: start + 1] + [""] + body + [""] + lines[end:]).rstrip() + "\n"


def section_body(text: str, heading: str) -> list[str]:
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == heading)
    except StopIteration:
        return []
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    return [line for line in lines[start + 1 : end] if line.strip()]


def update_dashboard(root: Path, cmd: dict[str, Any], status: str, summary: str) -> bool:
    path = root / "dashboard.md"
    before = path.read_text(encoding="utf-8") if path.exists() else dashboard_template()
    cmd_id = command_id(cmd)
    now = now_iso()
    text = before
    if "最終更新:" in text:
        text = "\n".join("最終更新: " + now if line.startswith("最終更新:") else line for line in text.splitlines()) + "\n"

    progress_line = f"- `{cmd_id}`: {status} - {summary}"
    progress_body = [
        line
        for line in section_body(text, "## 🔄 進行中")
        if cmd_id not in line and line.strip() != "なし"
    ]
    if status not in {"done", "completed"}:
        progress_body.append(progress_line)
    if not progress_body:
        progress_body = ["なし"]
    text = replace_section(text, "## 🔄 進行中", progress_body)

    if status in {"done", "completed", "audit_requested", "review"}:
        result_line = f"| {now} | `{cmd_id}` | {status} | {summary} |"
        result_body = ["| 時刻 | command | 状態 | 要約 |", "|---|---|---|---|"]
        for line in section_body(text, "## ✅ 本日の戦果"):
            stripped = line.strip()
            if stripped in {"なし", "| 時刻 | command | 状態 | 要約 |", "|---|---|---|---|"}:
                continue
            if cmd_id in stripped:
                continue
            result_body.append(line)
        result_body.append(result_line)
        text = replace_section(text, "## ✅ 本日の戦果", result_body)

    if text != before:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def summarize_reports(reports: list[tuple[Path, dict[str, Any]]]) -> str:
    parts = []
    for path, report in reports:
        status = record_status(report) or "unknown"
        summary = report.get("summary") or report.get("result") or report.get("message") or path.name
        parts.append(f"{path.stem}:{status}:{compact(summary, 80)}")
    return compact("; ".join(parts), 220)


def sync_once(root: Path) -> list[str]:
    queue_dir = Path(os.environ.get("MAS_QUEUE_DIR", root / "queue"))
    cmd_file = Path(os.environ.get("MAS_SHOGUN_TO_KARO_FILE", queue_dir / "shogun_to_karo.yaml"))
    runtime_dir = Path(os.environ.get("MAS_RUNTIME_DIR", queue_dir / "runtime"))
    state_file = Path(os.environ.get("MAS_RUNTIME_SYNC_STATE", runtime_dir / STATE_FILE_NAME))

    original_commands, commands = load_commands(cmd_file)
    if not commands:
        return ["noop\tempty"]

    state = read_state(state_file)
    changed_commands = False
    events: list[str] = []

    for command in commands:
        cid = command_id(command)
        if not cid:
            continue
        status = record_status(command)
        if status not in COMMAND_OPEN_STATUSES:
            continue

        tasks = collect_tasks(queue_dir, cid)
        reports = collect_reports(queue_dir, cid)
        report_by_task = {report_task_id(report, path.stem): (path, report) for path, report in reports}
        report_statuses = [record_status(report) for _, report in reports]
        bad_reports = [item for item in reports if record_status(item[1]) in BAD_STATUSES]

        for task_path, task in tasks:
            tid = task_id(task, task_path.stem)
            report_pair = report_by_task.get(tid)
            if report_pair and record_status(report_pair[1]) in DONE_STATUSES:
                if update_task_file(task_path, tid, "done", now_iso()):
                    events.append(f"task_done\t{cid}:{tid}")

        required_task_ids = [task_id(task, path.stem) for path, task in tasks]
        done_task_ids = {
            tid
            for tid in required_task_ids
            if tid in report_by_task and record_status(report_by_task[tid][1]) in DONE_STATUSES
        }
        all_worker_done = bool(required_task_ids) and set(required_task_ids) <= done_task_ids
        if not required_task_ids and reports:
            all_worker_done = bool(report_statuses) and all(status in DONE_STATUSES for status in report_statuses)

        if bad_reports:
            summary = "failed report detected: " + summarize_reports(bad_reports)
            command["status"] = "review"
            command["updated_at"] = now_iso()
            changed_commands = True
            update_dashboard(root, command, "review", summary)
            if request_gunkan_audit(root, queue_dir, command, reports, state):
                events.append(f"audit_requested\t{cid}")
            events.append(f"review\t{cid}")
            continue

        if all_worker_done:
            audit = gunkan_audit_report(queue_dir, cid)
            summary = summarize_reports(reports)
            if audit and record_status(audit[1]) in DONE_STATUSES:
                command["status"] = "done"
                command.setdefault("completed_at", now_iso())
                command["completion_summary"] = summary
                changed_commands = True
                update_dashboard(root, command, "done", summary)
                events.append(f"done\t{cid}")
                continue
            if audit and record_status(audit[1]) in BAD_STATUSES:
                audit_path, audit_report = audit
                latest_worker_report = latest_report_mtime(reports)
                audit_mtime = audit_path.stat().st_mtime_ns if audit_path.exists() else 0
                reaudit_key = f"{cid}:{latest_worker_report}"
                reaudit_requested = set(state.get("gunkan_reaudit_requested", []) or [])
                if latest_worker_report > audit_mtime and reaudit_key not in reaudit_requested:
                    if request_gunkan_audit(
                        root,
                        queue_dir,
                        command,
                        reports,
                        state,
                        force=True,
                        reason="軍監失敗後に足軽reportが更新されました。",
                    ):
                        reaudit_requested.add(reaudit_key)
                        state["gunkan_reaudit_requested"] = sorted(reaudit_requested)
                        command["status"] = "audit_requested"
                        command["updated_at"] = now_iso()
                        changed_commands = True
                        update_dashboard(root, command, "audit_requested", summary or "waiting for Gunkan re-audit")
                        events.append(f"reaudit_requested\t{cid}")
                        continue

                command["status"] = "review"
                command["updated_at"] = now_iso()
                changed_commands = True
                update_dashboard(root, command, "review", "Gunkan audit failed: " + compact(audit_report.get("summary") or audit_report.get("result") or "see gunkan_report"))
                if request_karo_review(root, queue_dir, command, audit_report, state):
                    events.append(f"review_requested\t{cid}")
                else:
                    events.append(f"review_pending\t{cid}")
                continue

            command["status"] = "audit_requested"
            command["updated_at"] = now_iso()
            changed_commands = True
            update_dashboard(root, command, "audit_requested", summary or "waiting for Gunkan audit")
            if request_gunkan_audit(root, queue_dir, command, reports, state):
                events.append(f"audit_requested\t{cid}")
            else:
                events.append(f"audit_pending\t{cid}")

    if changed_commands:
        save_commands(cmd_file, original_commands, commands)
    save_state(state_file, state)
    return events or ["noop\tno_changes"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Synchronize Shogunate runtime queue/dashboard/Gunkan audit state.")
    parser.add_argument("--project-root", default=os.environ.get("MAS_PROJECT_ROOT", Path(__file__).resolve().parents[2]))
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--interval", type=float, default=float(os.environ.get("MAS_RUNTIME_SYNC_INTERVAL", "5")))
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    if args.daemon:
        while True:
            try:
                events = sync_once(root)
                if events and not all(event.startswith("noop") for event in events):
                    print("\n".join(events), flush=True)
            except Exception as exc:
                print(f"error\t{exc}", flush=True)
            time.sleep(max(args.interval, 1.0))
    else:
        print("\n".join(sync_once(root)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
