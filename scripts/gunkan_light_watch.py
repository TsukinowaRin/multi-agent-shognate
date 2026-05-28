#!/usr/bin/env python3
"""Lightweight, non-LLM Gunkan watcher.

This script does cheap consistency checks and wakes the Gunkan LLM only when
there is enough signal to justify a real audit.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


STATUS_DONE = {"done", "completed", "complete", "success", "passed", "完了"}
STATUS_BAD = {"failed", "error", "blocked", "timeout", "失敗", "異常", "停止"}
SENSITIVE_PATH_RE = re.compile(
    r"(^|/)(\.env|id_rsa|id_ed25519|.*\.(pem|key|p12|pfx)|auth\.json|credentials?\.json|token.*|secret.*)$",
    re.IGNORECASE,
)
DANGEROUS_DIFF_RE = re.compile(
    r"(git\s+reset\s+--hard|git\s+clean\s+-f|rm\s+-rf\s+/(?:\s|$)|PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY)",
    re.IGNORECASE,
)
REPORT_VERIFY_KEYS = ("verification", "tests", "checks", "evidence", "validated", "acceptance_criteria")
STATE_VERSION = 1


@dataclass
class Finding:
    severity: str
    kind: str
    signature: str
    summary: str
    evidence: str
    parent_cmd: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "severity": self.severity,
            "kind": self.kind,
            "signature": self.signature,
            "summary": self.summary,
            "evidence": self.evidence,
            "parent_cmd": self.parent_cmd,
        }


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def load_yaml(path: Path) -> Any:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_yaml_safe(path: Path) -> tuple[Any, str | None]:
    try:
        return load_yaml(path), None
    except Exception as exc:  # noqa: BLE001 - surfaced as audit evidence
        return None, str(exc)


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


def compact(value: Any, limit: int = 240) -> str:
    text = " ".join(str(value).split())
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def severity_rank(severity: str) -> int:
    return {"info": 0, "warn": 1, "error": 2, "critical": 3}.get(severity, 0)


def max_severity(findings: list[Finding]) -> str:
    if not findings:
        return "passed"
    return max((f.severity for f in findings), key=severity_rank)


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": STATE_VERSION, "alerts": {}, "git_dirty_baseline": []}
    data, err = load_yaml_safe(path)
    if err or not isinstance(data, dict):
        return {"version": STATE_VERSION, "alerts": {}, "git_dirty_baseline": []}
    data.setdefault("version", STATE_VERSION)
    data.setdefault("alerts", {})
    data.setdefault("git_dirty_baseline", [])
    return data


def run_git(root: Path, args: list[str], timeout: int = 4) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except Exception as exc:  # noqa: BLE001 - watcher must not crash runtime
        return 127, "", str(exc)


def parse_git_status_paths(output: str) -> list[str]:
    paths: list[str] = []
    for line in output.splitlines():
        if len(line) < 4:
            continue
        path = line[3:].strip()
        if " -> " in path:
            path = path.rsplit(" -> ", 1)[-1].strip()
        if path:
            paths.append(path)
    return sorted(set(paths))


def yaml_parse_findings(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    paths: list[Path] = []
    for subdir in ("inbox", "reports", "tasks"):
        base = root / "queue" / subdir
        if base.exists():
            paths.extend(sorted(base.glob("*.yaml")))
    for rel in (
        "queue/shogun_to_karo.yaml",
        "queue/shogun_to_karo_archive.yaml",
        "queue/runtime/gunkan_events.yaml",
        "queue/runtime/gunkan_watch.yaml",
    ):
        path = root / rel
        if path.exists():
            paths.append(path)

    seen: set[Path] = set()
    for path in paths:
        if path in seen:
            continue
        seen.add(path)
        rel = path.relative_to(root).as_posix()
        _, err = load_yaml_safe(path)
        if err:
            findings.append(
                Finding(
                    "error",
                    "yaml_parse",
                    f"yaml_parse:{rel}",
                    f"{rel} が YAML として読めない",
                    compact(err),
                )
            )
    return findings


def report_findings(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    reports_dir = root / "queue" / "reports"
    if not reports_dir.exists():
        return findings

    for path in sorted(reports_dir.glob("*_report.yaml")):
        rel = path.relative_to(root).as_posix()
        if path.name == "gunkan_report.yaml":
            continue
        data, err = load_yaml_safe(path)
        if err or not isinstance(data, dict):
            continue
        status = str(data.get("status") or data.get("result") or "").strip().lower()
        result = data.get("result")
        result_status = ""
        if isinstance(result, dict):
            result_status = str(result.get("status") or result.get("verdict") or "").strip().lower()
        text = compact(data, 2000).lower()
        done_like = status in STATUS_DONE or "完了" in text or "done" in text
        bad_like = status in STATUS_BAD or result_status in STATUS_BAD or bool(data.get("error"))
        if bad_like:
            findings.append(
                Finding(
                    "warn",
                    "agent_failure_report",
                    f"agent_failure_report:{rel}:{status}",
                    f"{rel} が失敗/停止系の報告を含む",
                    compact(data),
                    str(data.get("parent_cmd") or data.get("cmd_id") or ""),
                )
            )
        if not done_like:
            continue
        verification = None
        for key in REPORT_VERIFY_KEYS:
            if key in data:
                verification = data.get(key)
                break
            result = data.get("result")
            if isinstance(result, dict) and key in result:
                verification = result.get(key)
                break
        verification_text = compact(verification or "")
        missing = verification in (None, "", [], {}) or any(
            marker in verification_text for marker in ("未実行", "未確認", "なし", "not run", "missing")
        )
        if missing:
            findings.append(
                Finding(
                    "warn",
                    "done_without_verification",
                    f"done_without_verification:{rel}",
                    f"{rel} は完了扱いだが検証証跡が弱い",
                    f"status={status or 'unknown'} verification={verification_text or 'missing'}",
                    str(data.get("parent_cmd") or data.get("cmd_id") or ""),
                )
            )
    return findings


def dashboard_findings(root: Path) -> list[Finding]:
    path = root / "dashboard.md"
    if not path.exists():
        return []
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return []
    lower = text.lower()
    if ("完了" in text or "done" in lower) and any(
        marker in text for marker in ("検証証跡は未添付", "検証未実行", "未確認", "証跡なし")
    ):
        return [
            Finding(
                "warn",
                "dashboard_done_without_evidence",
                "dashboard_done_without_evidence",
                "dashboard が完了扱いと検証不足を同時に示している",
                compact(text),
            )
        ]
    return []


def codd_setup_findings(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    config = root / ".codd" / "codd.yaml"
    if not config.exists():
        findings.append(
            Finding(
                "warn",
                "codd_config_missing",
                "codd_config_missing",
                ".codd/codd.yaml が無く、CoDD graph を作れない",
                "Create .codd/codd.yaml and frontmatter docs.",
            )
        )
    codd_docs = root / "docs" / "codd"
    if not codd_docs.exists() or not any(codd_docs.glob("*.md")):
        findings.append(
            Finding(
                "warn",
                "codd_frontmatter_missing",
                "codd_frontmatter_missing",
                "docs/codd の CoDD frontmatter docs が無い",
                "CoDD needs YAML frontmatter to build requirement/design graph.",
            )
        )
    return findings


def git_findings(root: Path, state: dict[str, Any], alert_on_first_run: bool) -> list[Finding]:
    findings: list[Finding] = []
    rc, out, err = run_git(root, ["rev-parse", "--is-inside-work-tree"])
    if rc != 0 or out.strip() != "true":
        return findings

    rc, out, err = run_git(root, ["status", "--porcelain=v1", "--untracked-files=all"])
    if rc != 0:
        findings.append(
            Finding("warn", "git_status_unavailable", "git_status_unavailable", "git status を確認できない", compact(err))
        )
        return findings

    dirty = [p for p in parse_git_status_paths(out) if not p.startswith("queue/runtime/")]
    baseline = sorted(str(x) for x in state.get("git_dirty_baseline", []))
    if not baseline and not alert_on_first_run:
        state["git_dirty_baseline"] = dirty
        return findings

    new_dirty = sorted(set(dirty) - set(baseline))
    sensitive = [p for p in new_dirty if SENSITIVE_PATH_RE.search(p)]
    if sensitive:
        findings.append(
            Finding(
                "error",
                "sensitive_path_changed",
                "sensitive_path_changed:" + ",".join(sensitive[:8]),
                "認証情報・秘密鍵っぽいファイルが変更対象に入った",
                ", ".join(sensitive[:12]),
            )
        )

    if new_dirty:
        rc, diff, _ = run_git(root, ["diff", "-U0", "--", *new_dirty[:30]], timeout=6)
        if rc == 0 and DANGEROUS_DIFF_RE.search(diff):
            findings.append(
                Finding(
                    "error",
                    "dangerous_diff_pattern",
                    "dangerous_diff_pattern",
                    "破壊的操作または秘密情報らしき差分を検出",
                    compact(DANGEROUS_DIFF_RE.search(diff).group(0) if DANGEROUS_DIFF_RE.search(diff) else "matched"),
                )
            )

    state["git_dirty_baseline"] = dirty
    return findings


def finding_fingerprint(finding: Finding) -> str:
    return "|".join(
        (
            finding.severity,
            finding.kind,
            finding.summary,
            finding.evidence,
            finding.parent_cmd,
        )
    )


def remember_finding_alert(finding: Finding, state: dict[str, Any], now_ts: int) -> None:
    state.setdefault("alerts", {})[finding.signature] = {
        "last_sent": now_ts,
        "fingerprint": finding_fingerprint(finding),
    }


def should_alert(finding: Finding, state: dict[str, Any], cooldown: int, now_ts: int) -> bool:
    if severity_rank(finding.severity) < severity_rank("warn"):
        return False
    alerts = state.setdefault("alerts", {})
    previous = alerts.get(finding.signature)
    fingerprint = finding_fingerprint(finding)
    if isinstance(previous, dict):
        if previous.get("fingerprint") == fingerprint:
            return False
        last_sent = previous.get("last_sent")
    else:
        last_sent = previous
    if isinstance(last_sent, int) and now_ts - last_sent < cooldown:
        return False
    alerts[finding.signature] = {
        "last_sent": now_ts,
        "fingerprint": fingerprint,
    }
    return True


def write_gunkan_inbox(root: Path, findings: list[Finding]) -> str:
    inbox = root / "queue" / "inbox" / "gunkan.yaml"
    data, err = load_yaml_safe(inbox)
    if err or not isinstance(data, dict):
        data = {"messages": []}
    messages = data.setdefault("messages", [])
    msg_id = f"msg_{datetime.now().strftime('%Y%m%d_%H%M%S')}_gwatch"
    severity = max_severity(findings)
    lines = [
        f"軽量軍監watcherが監査候補を検出。severity={severity}",
        "queue/runtime/gunkan_watch.yaml を読み、必要なら python3 scripts/gunkan_codd_audit.py --scope watch を実行し、queue/reports/gunkan_report.yaml に監査結果を書け。",
        "通常の中間報告取得や進行管理は行うな。",
        "findings:",
    ]
    for finding in findings[:8]:
        lines.append(f"- [{finding.severity}] {finding.summary} ({finding.signature})")
    messages.append(
        {
            "id": msg_id,
            "timestamp": now_iso(),
            "from": "gunkan_light_watch",
            "type": "audit_requested",
            "content": "\n".join(lines),
            "read": False,
        }
    )
    if len(messages) > 50:
        unread = [m for m in messages if not m.get("read", False)]
        read = [m for m in messages if m.get("read", False)]
        data["messages"] = unread + read[-30:]
    atomic_write_yaml(inbox, data)
    return msg_id


def run_once(args: argparse.Namespace) -> int:
    root = Path(args.project_root).resolve()
    state_path = root / "queue" / "runtime" / "gunkan_light_watch_state.yaml"
    output = root / "queue" / "runtime" / "gunkan_watch.yaml"
    first_run = not state_path.exists()
    state = load_state(state_path)

    findings: list[Finding] = []
    findings.extend(yaml_parse_findings(root))
    findings.extend(report_findings(root))
    findings.extend(dashboard_findings(root))
    findings.extend(codd_setup_findings(root))
    findings.extend(git_findings(root, state, args.alert_on_first_run))

    now_ts = int(time.time())
    if first_run and not args.alert_on_first_run:
        for finding in findings:
            if severity_rank(finding.severity) >= severity_rank("warn"):
                remember_finding_alert(finding, state, now_ts)
        alertable = []
    else:
        alertable = [f for f in findings if should_alert(f, state, args.cooldown, now_ts)]
    msg_id = ""
    if alertable and not args.no_inbox:
        msg_id = write_gunkan_inbox(root, alertable)

    report = {
        "worker_id": "gunkan_light_watch",
        "timestamp": now_iso(),
        "status": "passed" if not findings else max_severity(findings),
        "alert_sent": bool(msg_id),
        "alert_message_id": msg_id,
        "cooldown_seconds": args.cooldown,
        "findings": [f.to_dict() for f in findings],
    }
    atomic_write_yaml(output, report)
    state["updated_at"] = now_iso()
    atomic_write_yaml(state_path, state)
    print(output)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--cooldown", type=int, default=int(os.environ.get("MAS_GUNKAN_WATCH_COOLDOWN", "300")))
    parser.add_argument("--interval", type=int, default=int(os.environ.get("MAS_GUNKAN_WATCH_INTERVAL", "20")))
    parser.add_argument("--daemon", action="store_true")
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--alert-on-first-run", action="store_true")
    parser.add_argument("--no-inbox", action="store_true")
    args = parser.parse_args()

    if args.daemon:
        while True:
            try:
                run_once(args)
            except Exception as exc:  # noqa: BLE001 - watcher must stay alive
                print(f"[gunkan_light_watch] ERROR: {exc}", flush=True)
            time.sleep(max(args.interval, 5))
    return run_once(args)


if __name__ == "__main__":
    raise SystemExit(main())
