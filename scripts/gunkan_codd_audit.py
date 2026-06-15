#!/usr/bin/env python3
"""Run Gunkan's on-demand CoDD audit with a local fallback."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


COMMAND_TIMEOUT = 90
INSTALL_TIMEOUT = 300
OUTPUT_LIMIT = 12000
CODD_PACKAGE = os.environ.get("CODD_PACKAGE", "codd-dev")
CODD_VERSION_SPEC = os.environ.get("CODD_VERSION_SPEC", "")
CODD_FALLBACK_VERSION = os.environ.get("CODD_FALLBACK_VERSION", "1.34.0")


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


def run_cmd(cmd: list[str], root: Path, timeout: int = COMMAND_TIMEOUT) -> dict[str, Any]:
    try:
        proc = subprocess.run(
            cmd,
            cwd=root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
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
            "stderr": f"timeout after {timeout}s",
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


def default_auto_install(root: Path) -> bool:
    value = os.environ.get("MAS_GUNKAN_CODD_AUTO_INSTALL")
    if value is not None:
        return value.strip().lower() not in {"0", "false", "no", "off"}
    return (root / ".codd" / "codd.yaml").exists()


def venv_python(venv: Path) -> Path:
    win_python = venv / "Scripts" / "python.exe"
    if win_python.exists():
        return win_python
    return venv / "bin" / "python"


def install_repo_codd(root: Path) -> dict[str, Any]:
    venv = Path(os.environ.get("CODD_VENV", root / ".shogunate" / "codd-venv"))
    package_spec = f"{CODD_PACKAGE}{CODD_VERSION_SPEC}"
    python = shutil.which("python3") or sys.executable
    bootstrap: dict[str, Any] = {
        "attempted": True,
        "venv": str(venv),
        "package": package_spec,
        "fallback_package": f"{CODD_PACKAGE}=={CODD_FALLBACK_VERSION}",
        "status": "failed",
        "commands": [],
    }
    if not python:
        bootstrap["summary"] = "python3 not found; cannot install codd-dev"
        return bootstrap

    venv_python_path = venv_python(venv)
    if not venv_python_path.exists():
        venv.parent.mkdir(parents=True, exist_ok=True)
        result = run_cmd([python, "-m", "venv", str(venv)], root, timeout=INSTALL_TIMEOUT)
        bootstrap["commands"].append(result)
        if int(result.get("returncode") or 0) != 0:
            bootstrap["summary"] = "python3 -m venv failed; falling back to built-in audit"
            return bootstrap

    pip_upgrade = run_cmd([str(venv_python_path), "-m", "pip", "install", "--upgrade", "pip"], root, timeout=INSTALL_TIMEOUT)
    bootstrap["commands"].append(pip_upgrade)
    if int(pip_upgrade.get("returncode") or 0) != 0:
        bootstrap["summary"] = "pip upgrade failed; falling back to built-in audit"
        return bootstrap

    install_latest = run_cmd(
        [str(venv_python_path), "-m", "pip", "install", "--upgrade", package_spec],
        root,
        timeout=INSTALL_TIMEOUT,
    )
    bootstrap["commands"].append(install_latest)
    if int(install_latest.get("returncode") or 0) != 0:
        install_fallback = run_cmd(
            [str(venv_python_path), "-m", "pip", "install", "--upgrade", f"{CODD_PACKAGE}=={CODD_FALLBACK_VERSION}"],
            root,
            timeout=INSTALL_TIMEOUT,
        )
        bootstrap["commands"].append(install_fallback)
        if int(install_fallback.get("returncode") or 0) != 0:
            bootstrap["summary"] = "codd-dev install failed; falling back to built-in audit"
            return bootstrap

    if find_codd(root):
        bootstrap["status"] = "installed"
        bootstrap["summary"] = "repo-local codd-dev is ready"
    else:
        bootstrap["summary"] = "codd-dev install completed but codd executable was not found"
    return bootstrap


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
    bootstrap = {
        "enabled": default_auto_install(root),
        "attempted": False,
        "status": "skipped",
        "summary": "codd CLI already available" if codd_bin else "auto-install disabled",
    }
    if not codd_bin and bootstrap["enabled"]:
        bootstrap = install_repo_codd(root)
        bootstrap["enabled"] = True
        codd_bin = find_codd(root)

    report: dict[str, Any] = {
        "worker_id": "gunkan",
        "timestamp": now_iso(),
        "scope": args.scope,
        "parent_cmd": args.parent_cmd,
        "codd_available": bool(codd_bin),
        "codd_bootstrap": bootstrap,
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
        if bootstrap.get("attempted"):
            report["summary"] = (
                "codd CLI not ready after bootstrap; used built-in Gunkan coherence fallback. "
                + str(bootstrap.get("summary", "")).strip()
            ).strip()
        else:
            report["summary"] = "codd CLI not found; used built-in Gunkan coherence fallback."

    atomic_write_yaml(output, report)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
