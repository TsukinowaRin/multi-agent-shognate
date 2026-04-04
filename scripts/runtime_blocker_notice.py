#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
ACTION_REQUIRED_HEADING = "## 🚨 要対応 - 殿のご判断をお待ちしております"
ACTION_REQUIRED_HEADING_ALT = "## 🚨 要対応 - 殿のご判断をお待ちしております (Action Required - Awaiting Lord's Decision)"
RUNTIME_BLOCKED_PATTERN = re.compile(r"^- \[runtime-blocked/(?P<agent>[^\]]+)\] (?P<message>.+)$")


def dashboard_template(timestamp_text: str) -> list[str]:
    return [
        "# 📊 戦況報告",
        f"最終更新: {timestamp_text}",
        "",
        ACTION_REQUIRED_HEADING,
        "なし",
        "",
        "## 🔄 進行中 - 只今、戦闘中でござる",
        "なし",
        "",
        "## ✅ 本日の戦果",
        "| 時刻 | 戦場 | 任務 | 結果 |",
        "|------|------|------|------|",
        "",
        "## 🎯 スキル化候補 - 承認待ち",
        "なし",
        "",
        "## 🛠️ 生成されたスキル",
        "なし",
        "",
        "## ⏸️ 待機中",
        "なし",
        "",
        "## ❓ 伺い事項",
        "なし",
        "",
    ]


def normalize_detail(detail: str) -> str:
    compact = re.sub(r"\s+", " ", detail or "").strip()
    return compact[:180]


def format_notice(agent: str, issue: str, detail: str) -> str:
    if issue == "codex-hard-usage-limit":
        base = f"- [runtime-blocked/{agent}] Codex hard usage-limit prompt を検知。人手で再開判断が必要。"
    elif issue == "codex-auth-required":
        base = f"- [runtime-blocked/{agent}] Codex auth prompt を検知。ログイン完了待ち。"
    else:
        base = f"- [runtime-blocked/{agent}] {issue}"
    normalized = normalize_detail(detail)
    if normalized:
        base += f" 詳細: {normalized}"
    return base


def matches_notice(line: str, agent: str, issue: str) -> bool:
    stripped = line.strip()
    prefix = f"- [runtime-blocked/{agent}] "
    if not stripped.startswith(prefix):
        return False
    if issue == "codex-hard-usage-limit":
        return "Codex hard usage-limit prompt" in stripped
    if issue == "codex-auth-required":
        return "Codex auth prompt" in stripped
    return stripped == f"{prefix}{issue}"


def notice_identity(line: str) -> tuple[str, str] | None:
    match = RUNTIME_BLOCKED_PATTERN.match(line.strip())
    if not match:
        return None
    agent = match.group("agent")
    message = match.group("message")
    if message.startswith("Codex hard usage-limit prompt"):
        return agent, "codex-hard-usage-limit"
    if message.startswith("Codex auth prompt"):
        return agent, "codex-auth-required"
    return agent, message.split(" 詳細:", 1)[0].strip()


def compact_body(body: list[str]) -> list[str]:
    return [line for line in body if line.strip() and line.strip() != "なし"]


def normalize_action_required_body(body: list[str]) -> list[str]:
    compact = compact_body(body)
    last_index_by_identity: dict[tuple[str, str], int] = {}
    for idx, line in enumerate(compact):
        identity = notice_identity(line)
        if identity is not None:
            last_index_by_identity[identity] = idx

    normalized: list[str] = []
    for idx, line in enumerate(compact):
        identity = notice_identity(line)
        if identity is not None and last_index_by_identity.get(identity) != idx:
            continue
        normalized.append(line)
    return normalized


def find_section_bounds(lines: list[str], headings: tuple[str, ...]) -> tuple[int, int]:
    start = -1
    end = len(lines)
    for idx, line in enumerate(lines):
        if line.strip() in headings:
            start = idx
            break
    if start == -1:
        lines.extend(["", headings[0], "なし", ""])
        start = len(lines) - 3
        end = len(lines) - 1
        return start, end

    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return start, end


def update_last_updated(lines: list[str], timestamp_text: str) -> None:
    for idx, line in enumerate(lines):
        if line.startswith("最終更新: "):
            lines[idx] = f"最終更新: {timestamp_text}"
            return
        if line.startswith("最終更新 (Last Updated): "):
            lines[idx] = f"最終更新 (Last Updated): {timestamp_text}"
            return
    if lines and lines[0].startswith("# "):
        lines.insert(1, f"最終更新: {timestamp_text}")
        lines.insert(2, "")


def ensure_notice(dashboard_path: Path, agent: str, issue: str, detail: str, timestamp_text: str) -> str:
    if dashboard_path.exists():
        lines = dashboard_path.read_text(encoding="utf-8").splitlines()
    else:
        dashboard_path.parent.mkdir(parents=True, exist_ok=True)
        lines = dashboard_template(timestamp_text)

    notice = format_notice(agent, issue, detail)
    start, end = find_section_bounds(lines, (ACTION_REQUIRED_HEADING, ACTION_REQUIRED_HEADING_ALT))
    body = lines[start + 1:end]
    compact_existing = compact_body(body)
    normalized_body = normalize_action_required_body(body)
    had_exact_notice = any(line.strip() == notice for line in normalized_body)
    matched_existing = False

    filtered_body = []
    for line in normalized_body:
        if matches_notice(line, agent, issue):
            if not matched_existing:
                filtered_body.append(notice)
                matched_existing = True
            continue
        filtered_body.append(line)
    if not matched_existing:
        filtered_body.append(notice)

    if had_exact_notice and filtered_body == normalized_body and normalized_body == compact_existing:
        return "duplicate"

    update_last_updated(lines, timestamp_text)
    lines[start + 1:end] = filtered_body + [""]

    dashboard_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return "updated"


def clear_notice(dashboard_path: Path, agent: str, issue: str, timestamp_text: str) -> str:
    if dashboard_path.exists():
        lines = dashboard_path.read_text(encoding="utf-8").splitlines()
    else:
        return "not_found"

    start, end = find_section_bounds(lines, (ACTION_REQUIRED_HEADING, ACTION_REQUIRED_HEADING_ALT))
    body = lines[start + 1:end]
    normalized_body = normalize_action_required_body(body)
    existing_body = compact_body(body)
    filtered_body = [
        line for line in normalized_body if not matches_notice(line, agent, issue)
    ]

    if len(filtered_body) == len(normalized_body) and normalized_body == existing_body:
        return "not_found"

    update_last_updated(lines, timestamp_text)
    replacement_body = filtered_body if filtered_body else ["なし"]
    lines[start + 1:end] = replacement_body + [""]
    dashboard_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return "cleared"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(ROOT))
    parser.add_argument("--dashboard")
    parser.add_argument("--action", choices=("record", "clear"), default="record")
    parser.add_argument("--agent", required=True)
    parser.add_argument("--issue", required=True)
    parser.add_argument("--detail", default="")
    args = parser.parse_args()

    project_root = Path(args.project_root)
    dashboard_path = Path(args.dashboard) if args.dashboard else project_root / "dashboard.md"
    timestamp_text = datetime.now().strftime("%Y-%m-%d %H:%M")
    if args.action == "clear":
        status = clear_notice(dashboard_path, args.agent, args.issue, timestamp_text)
    else:
        status = ensure_notice(dashboard_path, args.agent, args.issue, args.detail, timestamp_text)
    print(status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
