#!/usr/bin/env python3
"""Run Gunkan's on-demand CoDD audit with a local fallback."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


COMMAND_TIMEOUT = 90
OUTPUT_LIMIT = 12000


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


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


def trim(text: str) -> str:
    if len(text) <= OUTPUT_LIMIT:
        return text
    return text[:OUTPUT_LIMIT] + "\n...[truncated]"


def run_cmd(cmd: list[str], root: Path) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=COMMAND_TIMEOUT,
            check=False,
        )
        return {
            "command": cmd,
            "returncode": proc.returncode,
            "stdout": trim(proc.stdout),
            "stderr": trim(proc.stderr),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "command": cmd,
            "returncode": 124,
            "stdout": trim(exc.stdout or ""),
            "stderr": f"timeout after {COMMAND_TIMEOUT}s",
        }


def run_codd(root: Path, codd_bin: str) -> list[dict[str, Any]]:
    commands: list[list[str]] = [
        [codd_bin, "scan", "--path", "."],
        [codd_bin, "impact"],
        [codd_bin, "validate"],
    ]
    results: list[dict[str, Any]] = []
    for cmd in commands:
        result = run_cmd(cmd, root)
        if result["returncode"] != 0 and cmd[1] == "scan" and "--path" in cmd:
            result = run_cmd([codd_bin, "scan"], root)
        results.append(result)
    return results


def find_codd(root: Path) -> str | None:
    found = shutil.which("codd")
    if found:
        return found
    candidates = [
        root / ".shogunate" / "codd-venv" / "bin" / "codd",
        root / ".shogunate" / "codd-venv" / "Scripts" / "codd.exe",
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def load_yaml(path: Path) -> Any:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def fallback_checks(root: Path) -> tuple[str, list[dict[str, Any]]]:
    checks: list[dict[str, Any]] = []
    required_files = [
        "docs/REQS.md",
        "docs/INDEX.md",
        "dashboard.md",
        "queue/shogun_to_karo.yaml",
        "queue/reports/gunkan_report.yaml",
    ]

    for rel in required_files:
        path = root / rel
        checks.append(
            {
                "name": f"exists:{rel}",
                "status": "passed" if path.exists() else "warn",
                "detail": "present" if path.exists() else "missing",
            }
        )

    yaml_paths = [
        root / "queue" / "shogun_to_karo.yaml",
        root / "queue" / "runtime" / "gunkan_events.yaml",
        root / "queue" / "reports" / "gunkan_report.yaml",
    ]
    for path in yaml_paths:
        if not path.exists():
            continue
        try:
            load_yaml(path)
            status = "passed"
            detail = "valid YAML"
        except Exception as exc:  # noqa: BLE001 - report exact parse failure
            status = "failed"
            detail = str(exc)
        checks.append({"name": f"yaml:{path.relative_to(root)}", "status": status, "detail": detail})

    if any(c["status"] == "failed" for c in checks):
        return "failed", checks
    if any(c["status"] == "warn" for c in checks):
        return "warn", checks
    return "passed", checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--scope", default="runtime")
    parser.add_argument("--parent-cmd", default="")
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    output = Path(args.output) if args.output else root / "queue" / "runtime" / "codd" / "gunkan_audit.yaml"
    codd_bin = find_codd(root)

    report: dict[str, Any] = {
        "worker_id": "gunkan",
        "timestamp": now_iso(),
        "scope": args.scope,
        "parent_cmd": args.parent_cmd,
        "codd_available": bool(codd_bin),
        "status": "blocked",
        "commands": [],
        "fallback_checks": [],
        "summary": "",
    }

    if codd_bin:
        commands = run_codd(root, codd_bin)
        report["commands"] = commands
        failed = [c for c in commands if int(c.get("returncode") or 0) != 0]
        if failed:
            report["status"] = "warn"
            report["summary"] = "CoDD command completed with warnings. Review command stderr/stdout."
        else:
            report["status"] = "passed"
            report["summary"] = "CoDD scan / impact / validate completed successfully."
    else:
        status, checks = fallback_checks(root)
        report["status"] = status
        report["fallback_checks"] = checks
        report["summary"] = "codd CLI not found; used built-in Gunkan coherence fallback."

    atomic_write_yaml(output, report)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
