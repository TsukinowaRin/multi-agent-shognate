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
MAIN_HEADING = "# 📊 戦況報告"
MAIN_HEADING_ALT = "# 📊 戦況報告 (Battle Status Report)"
IN_PROGRESS_HEADING = "## 🔄 進行中 - 只今、戦闘中でござる"
IN_PROGRESS_HEADING_ALT = "## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)"
TODAY_RESULTS_HEADING = "## ✅ 本日の戦果"
SKILL_CANDIDATES_HEADING = "## 🎯 スキル化候補 - 承認待ち"
GENERATED_SKILLS_HEADING = "## 🛠️ 生成されたスキル"
WAITING_HEADING = "## ⏸️ 待機中"
QUESTIONS_HEADING = "## ❓ 伺い事項"
RUNTIME_BLOCKED_PATTERN = re.compile(r"^- \[runtime-blocked/(?P<agent>[^\]]+)\] (?P<message>.+)$")


def dashboard_template(timestamp_text: str, *, bilingual: bool = False) -> list[str]:
    main_heading = MAIN_HEADING_ALT if bilingual else MAIN_HEADING
    last_updated = (
        f"最終更新 (Last Updated): {timestamp_text}" if bilingual else f"最終更新: {timestamp_text}"
    )
    action_required_heading = ACTION_REQUIRED_HEADING_ALT if bilingual else ACTION_REQUIRED_HEADING
    in_progress_heading = IN_PROGRESS_HEADING_ALT if bilingual else IN_PROGRESS_HEADING
    none_text = "なし (None)" if bilingual else "なし"
    return [
        main_heading,
        last_updated,
        "",
        action_required_heading,
        none_text,
        "",
        in_progress_heading,
        none_text,
        "",
        TODAY_RESULTS_HEADING,
        "| 時刻 | 戦場 | 任務 | 結果 |",
        "|------|------|------|------|",
        "",
        SKILL_CANDIDATES_HEADING,
        "なし",
        "",
        GENERATED_SKILLS_HEADING,
        "なし",
        "",
        WAITING_HEADING,
        "なし",
        "",
        QUESTIONS_HEADING,
        "なし",
        "",
    ]


def normalize_detail(detail: str) -> str:
    compact = re.sub(r"\s+", " ", detail or "").strip()
    return compact[:180]


def normalize_issue_detail(issue: str, detail: str) -> str:
    compact = normalize_detail(detail)
    if not compact:
        return ""

    lower = compact.lower()
    if issue == "codex-auth-required":
        if (
            "login server error" in lower
            or "account/login/start failed" in lower
            or "failed to start login server" in lower
        ):
            return "Login server error / failed to start login server"
        if (
            "finish signing in via your browser" in lower
            or "open the following link to authenticate" in lower
            or "auth.openai.com/oauth/authorize" in lower
        ):
            return "Finish signing in via your browser"
        if (
            "sign in with chatgpt" in lower
            or "sign in with device code" in lower
            or "provide your own api key" in lower
            or "press enter to continue" in lower
        ):
            return "Sign in with ChatGPT / Device Code / API key menu"
        return "Codex authentication prompt detected"

    if issue == "codex-hard-usage-limit":
        match = re.search(r"try again at [^.]+(?:\.)?", compact, flags=re.IGNORECASE)
        if match:
            return match.group(0)
        if "you've hit your usage limit" in lower:
            return "You've hit your usage limit"
        return "You've hit your usage limit"

    return compact


def format_notice(agent: str, issue: str, detail: str) -> str:
    if issue == "codex-hard-usage-limit":
        base = f"- [runtime-blocked/{agent}] Codex hard usage-limit prompt を検知。人手で再開判断が必要。"
    elif issue == "codex-auth-required":
        base = f"- [runtime-blocked/{agent}] Codex auth prompt を検知。ログイン完了待ち。"
    else:
        base = f"- [runtime-blocked/{agent}] {issue}"
    normalized = normalize_issue_detail(issue, detail)
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
    return [line for line in body if line.strip() and line.strip() not in ("なし", "なし (None)")]


def compact_generic_body(body: list[str]) -> list[str]:
    return [line for line in body if line.strip()]


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


def extract_action_required_body(lines: list[str]) -> list[str]:
    try:
        start, end = find_section_bounds(lines[:], (ACTION_REQUIRED_HEADING, ACTION_REQUIRED_HEADING_ALT))
    except Exception:
        return []
    if start == -1:
        return []
    return normalize_action_required_body(lines[start + 1:end])


def extract_section_body(lines: list[str], headings: tuple[str, ...], *, compact_fn=compact_generic_body) -> list[str]:
    start = -1
    end = len(lines)
    for idx, line in enumerate(lines):
        if line.strip() in headings:
            start = idx
            break
    if start == -1:
        return []

    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return compact_fn(lines[start + 1:end])


def dashboard_is_structurally_valid(lines: list[str]) -> bool:
    def count_headings(candidates: tuple[str, ...]) -> int:
        return sum(1 for line in lines if line.strip() in candidates)

    has_main_heading = count_headings((MAIN_HEADING, MAIN_HEADING_ALT)) == 1
    has_last_updated = any(
        line.startswith("最終更新: ") or line.startswith("最終更新 (Last Updated): ")
        for line in lines
    )
    has_action_required = count_headings((ACTION_REQUIRED_HEADING, ACTION_REQUIRED_HEADING_ALT)) == 1
    has_in_progress = count_headings((IN_PROGRESS_HEADING, IN_PROGRESS_HEADING_ALT)) == 1
    has_today_results = count_headings((TODAY_RESULTS_HEADING,)) == 1
    has_skill_candidates = count_headings((SKILL_CANDIDATES_HEADING,)) == 1
    has_generated_skills = count_headings((GENERATED_SKILLS_HEADING,)) == 1
    has_waiting = count_headings((WAITING_HEADING,)) == 1
    has_questions = count_headings((QUESTIONS_HEADING,)) == 1
    return (
        has_main_heading
        and has_last_updated
        and has_action_required
        and has_in_progress
        and has_today_results
        and has_skill_candidates
        and has_generated_skills
        and has_waiting
        and has_questions
    )


def repair_dashboard_lines(lines: list[str], timestamp_text: str) -> list[str]:
    bilingual = any(line.strip() == MAIN_HEADING_ALT for line in lines) or any(
        line.strip() == ACTION_REQUIRED_HEADING_ALT for line in lines
    )
    section_defaults = {
        ACTION_REQUIRED_HEADING: ["なし (None)" if bilingual else "なし"],
        IN_PROGRESS_HEADING: ["なし (None)" if bilingual else "なし"],
        TODAY_RESULTS_HEADING: ["| 時刻 | 戦場 | 任務 | 結果 |", "|------|------|------|------|"],
        SKILL_CANDIDATES_HEADING: ["なし"],
        GENERATED_SKILLS_HEADING: ["なし"],
        WAITING_HEADING: ["なし"],
        QUESTIONS_HEADING: ["なし"],
    }
    section_bodies = {
        ACTION_REQUIRED_HEADING: extract_action_required_body(lines) or section_defaults[ACTION_REQUIRED_HEADING],
        IN_PROGRESS_HEADING: extract_section_body(lines, (IN_PROGRESS_HEADING, IN_PROGRESS_HEADING_ALT)) or section_defaults[IN_PROGRESS_HEADING],
        TODAY_RESULTS_HEADING: extract_section_body(lines, (TODAY_RESULTS_HEADING,)) or section_defaults[TODAY_RESULTS_HEADING],
        SKILL_CANDIDATES_HEADING: extract_section_body(lines, (SKILL_CANDIDATES_HEADING,)) or section_defaults[SKILL_CANDIDATES_HEADING],
        GENERATED_SKILLS_HEADING: extract_section_body(lines, (GENERATED_SKILLS_HEADING,)) or section_defaults[GENERATED_SKILLS_HEADING],
        WAITING_HEADING: extract_section_body(lines, (WAITING_HEADING,)) or section_defaults[WAITING_HEADING],
        QUESTIONS_HEADING: extract_section_body(lines, (QUESTIONS_HEADING,)) or section_defaults[QUESTIONS_HEADING],
    }

    rebuilt = dashboard_template(timestamp_text, bilingual=bilingual)[:3]
    ordered_headings = [
        ACTION_REQUIRED_HEADING,
        IN_PROGRESS_HEADING,
        TODAY_RESULTS_HEADING,
        SKILL_CANDIDATES_HEADING,
        GENERATED_SKILLS_HEADING,
        WAITING_HEADING,
        QUESTIONS_HEADING,
    ]
    heading_labels = {
        ACTION_REQUIRED_HEADING: ACTION_REQUIRED_HEADING_ALT if bilingual else ACTION_REQUIRED_HEADING,
        IN_PROGRESS_HEADING: IN_PROGRESS_HEADING_ALT if bilingual else IN_PROGRESS_HEADING,
        TODAY_RESULTS_HEADING: TODAY_RESULTS_HEADING,
        SKILL_CANDIDATES_HEADING: SKILL_CANDIDATES_HEADING,
        GENERATED_SKILLS_HEADING: GENERATED_SKILLS_HEADING,
        WAITING_HEADING: WAITING_HEADING,
        QUESTIONS_HEADING: QUESTIONS_HEADING,
    }
    for heading in ordered_headings:
        rebuilt.append(heading_labels[heading])
        rebuilt.extend(section_bodies[heading])
        rebuilt.append("")
    return rebuilt


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
        if not dashboard_is_structurally_valid(lines):
            lines = repair_dashboard_lines(lines, timestamp_text)
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
        if not dashboard_is_structurally_valid(lines):
            lines = repair_dashboard_lines(lines, timestamp_text)
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
