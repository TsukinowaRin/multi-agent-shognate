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
    else:
        base = f"- [runtime-blocked/{agent}] {issue}"
    normalized = normalize_detail(detail)
    if normalized:
        base += f" 詳細: {normalized}"
    return base


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

    update_last_updated(lines, timestamp_text)
    notice = format_notice(agent, issue, detail)
    start, end = find_section_bounds(lines, (ACTION_REQUIRED_HEADING, ACTION_REQUIRED_HEADING_ALT))
    body = lines[start + 1:end]

    if any(line.strip() == notice for line in body):
        dashboard_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
        return "duplicate"

    filtered_body = [line for line in body if line.strip() and line.strip() != "なし"]
    filtered_body.append(notice)
    lines[start + 1:end] = filtered_body + [""]

    dashboard_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return "updated"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=str(ROOT))
    parser.add_argument("--dashboard")
    parser.add_argument("--agent", required=True)
    parser.add_argument("--issue", required=True)
    parser.add_argument("--detail", default="")
    args = parser.parse_args()

    project_root = Path(args.project_root)
    dashboard_path = Path(args.dashboard) if args.dashboard else project_root / "dashboard.md"
    timestamp_text = datetime.now().strftime("%Y-%m-%d %H:%M")
    status = ensure_notice(dashboard_path, args.agent, args.issue, args.detail, timestamp_text)
    print(status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
