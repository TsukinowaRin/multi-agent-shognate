#!/usr/bin/env python3
"""Update manager for git-main and release installs.

Modes:
  - git-main installs: fetch/pull latest `origin/main` on startup when safe
  - release installs: manual updater by default, optional startup auto-apply

Local customizations are preserved. When an incoming tracked file collides with
local edits, the incoming version is written into `.shogunate/merge-candidates/`
and Karo is notified on next startup.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

try:
    import yaml
except ImportError as exc:  # pragma: no cover - handled by caller environment
    print(f"[update_manager] PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(1)


ROOT = Path(__file__).resolve().parents[1]
STATE_DIR = ROOT / ".shogunate"
STATE_PATH = STATE_DIR / "install_state.json"
MANIFEST_PATH = STATE_DIR / "install_manifest.json"
MERGE_ROOT = STATE_DIR / "merge-candidates"
NOTICE_PATH = STATE_DIR / "pending_merge_notice.json"
SETTINGS_PATH = ROOT / "config" / "settings.yaml"

REPO_OWNER = "TsukinowaRin"
REPO_NAME = "multi-agent-shognate"
DEFAULT_BRANCH = "main"

DEFAULT_PRESERVE_PATTERNS = [
    ".codex/**",
    ".claude/**",
    "config/settings.yaml",
    "projects/**",
    "context/local/**",
    "instructions/local/**",
    "skills/local/**",
    "memory/global_context.md",
    "dashboard.md",
    "queue/**",
    "logs/**",
]

@dataclass
class ApplyResult:
    applied: bool
    version_before: str
    version_after: str
    conflicts: List[str]
    deletions_blocked: List[str]
    preserved: List[str]
    updated: List[str]
    added: List[str]
    removed: List[str]
    merge_batch: Optional[str] = None


def utcnow() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def ensure_state_dir() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    MERGE_ROOT.mkdir(parents=True, exist_ok=True)


def shogun_to_karo_path() -> Path:
    return ROOT / "queue" / "shogun_to_karo.yaml"


def read_json(path: Path, default):
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def write_json(path: Path, data) -> None:
    ensure_state_dir()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
    tmp.replace(path)


def read_settings() -> dict:
    if not SETTINGS_PATH.exists():
        return {}
    with SETTINGS_PATH.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def write_settings(data: dict) -> None:
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with SETTINGS_PATH.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)


def ensure_update_settings_block(auto_apply_release: Optional[bool] = None) -> None:
    settings = read_settings()
    update = settings.setdefault("update", {})
    if not isinstance(update, dict):
        update = {}
        settings["update"] = update

    if "startup_check" not in update:
        update["startup_check"] = True
    if "auto_apply_release" not in update:
        update["auto_apply_release"] = False
    if auto_apply_release is not None:
        update["auto_apply_release"] = auto_apply_release
    if "preserve_paths" not in update or not isinstance(update.get("preserve_paths"), list):
        update["preserve_paths"] = [
            ".codex/",
            ".claude/",
            "projects/",
            "context/local/",
            "instructions/local/",
            "skills/local/",
            "memory/global_context.md",
        ]
    write_settings(settings)


def configured_preserve_patterns() -> List[str]:
    settings = read_settings()
    update = settings.get("update") if isinstance(settings, dict) else {}
    extra = update.get("preserve_paths", []) if isinstance(update, dict) else []
    patterns = list(DEFAULT_PRESERVE_PATTERNS)
    if isinstance(extra, list):
        for item in extra:
            if isinstance(item, str) and item.strip():
                value = item.strip()
                if value.endswith("/"):
                    value = f"{value}**"
                patterns.append(value)
    return sorted(set(patterns))


def should_preserve(rel_path: str, patterns: Iterable[str]) -> bool:
    path = rel_path.replace("\\", "/")
    for pattern in patterns:
        normalized = pattern.replace("\\", "/")
        if normalized.endswith("/"):
            normalized = f"{normalized}**"
        if fnmatch.fnmatch(path, normalized):
            return True
        if normalized.endswith("/**"):
            prefix = normalized[:-3]
            if path.startswith(prefix):
                return True
    return False


def sha256_file(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def list_source_files(source_root: Path) -> Dict[str, Path]:
    files: Dict[str, Path] = {}
    for path in source_root.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(source_root).as_posix()
        if rel.startswith(".git/"):
            continue
        files[rel] = path
    return files


def build_manifest_from_source(source_root: Path) -> Dict[str, str]:
    return {rel: sha256_file(path) for rel, path in list_source_files(source_root).items()}


def build_manifest_from_git(root: Path) -> Dict[str, str]:
    completed = subprocess.run(
        ["git", "ls-files"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    manifest: Dict[str, str] = {}
    for rel in completed.stdout.splitlines():
        if not rel:
            continue
        path = root / rel
        if path.is_file():
            manifest[rel] = sha256_file(path)
    return manifest


def current_version_label(state: dict) -> str:
    label = (
        state.get("version_label")
        or state.get("ref")
        or state.get("current_commit")
    )
    if label:
        return label
    if (ROOT / ".git").exists():
        try:
            return git(["rev-parse", "--short", "HEAD"]).stdout.strip()
        except subprocess.CalledProcessError:
            pass
    return "unknown"


def git(args: List[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=check,
        capture_output=True,
        text=True,
    )


def detect_install_mode(state: dict) -> str:
    git_dir = ROOT / ".git"
    if git_dir.exists():
        try:
            branch = git(["branch", "--show-current"]).stdout.strip()
        except subprocess.CalledProcessError:
            branch = ""
        if branch == DEFAULT_BRANCH:
            return "git-main"
        return "git-local"
    return state.get("install_mode", "release")


def latest_release_info() -> dict:
    url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases/latest"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": f"{REPO_NAME}-updater",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def download_and_extract(ref: str, ref_kind: str) -> Tuple[Path, tempfile.TemporaryDirectory[str]]:
    temp_dir = tempfile.TemporaryDirectory(prefix="mas-update-")
    root = Path(temp_dir.name)
    zip_path = root / f"{ref}.zip"
    url = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/archive/refs/{ref_kind}/{ref}.zip"
    req = urllib.request.Request(url, headers={"User-Agent": f"{REPO_NAME}-updater"})
    with urllib.request.urlopen(req, timeout=60) as resp, zip_path.open("wb") as fh:
        shutil.copyfileobj(resp, fh)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(root)
    extracted = root / f"{REPO_NAME}-{ref}"
    if not extracted.exists():
        raise FileNotFoundError(f"archive root not found: {extracted}")
    return extracted, temp_dir


def copy_with_parents(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def extract_git_tree(ref: str) -> Tuple[Path, tempfile.TemporaryDirectory[str]]:
    temp_dir = tempfile.TemporaryDirectory(prefix="mas-git-tree-")
    root = Path(temp_dir.name)
    tar_path = root / "tree.tar"
    archive = subprocess.run(
        ["git", "archive", "--format=tar", ref],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    tar_path.write_bytes(archive.stdout)
    extract_root = root / "tree"
    extract_root.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "-xf", str(tar_path), "-C", str(extract_root)], check=True)
    return extract_root, temp_dir


def write_merge_summary(
    merge_batch: str,
    source_label: str,
    conflicts: List[str],
    deletions_blocked: List[str],
) -> Path:
    batch_root = MERGE_ROOT / merge_batch
    summary = batch_root / "SUMMARY.md"
    lines = [
        f"# Update Merge Candidates",
        "",
        f"- batch: `{merge_batch}`",
        f"- source: `{source_label}`",
        f"- created_at: `{utcnow()}`",
        "",
    ]
    if conflicts:
        lines.append("## Incoming file versions kept aside")
        lines.append("")
        for rel in conflicts:
            lines.append(f"- `{rel}`")
        lines.append("")
    if deletions_blocked:
        lines.append("## Upstream deleted but local copy was kept")
        lines.append("")
        for rel in deletions_blocked:
            lines.append(f"- `{rel}`")
        lines.append("")
    summary.parent.mkdir(parents=True, exist_ok=True)
    summary.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return summary


def append_karo_command_for_merge(
    source_label: str,
    summary_path: Path,
    conflicts: List[str],
    deletions_blocked: List[str],
    purpose_prefix: str,
) -> str:
    queue_path = shogun_to_karo_path()
    queue_path.parent.mkdir(parents=True, exist_ok=True)
    existing = []
    if queue_path.exists():
        with queue_path.open("r", encoding="utf-8") as fh:
            existing = yaml.safe_load(fh) or []
        if not isinstance(existing, list):
            existing = []

    cmd_id = "cmd_upstream_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    criteria = [
        f"`{summary_path.relative_to(ROOT).as_posix()}` の内容が確認されている。",
        "local customization を保持したまま、必要な upstream 差分の採否が整理されている。",
        "採用・保留・却下の判断と理由が dashboard.md に記録されている。",
    ]
    if conflicts:
        criteria.append("衝突ファイルごとに、どの版を採るかが整理されている。")
    if deletions_blocked:
        criteria.append("upstream 削除候補について、残置/削除の判断が整理されている。")

    command_lines = [
        f"{purpose_prefix} の取り込み後、local 変更と衝突した差分が残った。",
        f"summary: {summary_path.relative_to(ROOT).as_posix()}",
        f"source: {source_label}",
        "merge-candidates を確認し、local customization を残しつつ必要な upstream 差分を統合せよ。",
    ]
    if conflicts:
        command_lines.append("衝突ファイル: " + ", ".join(conflicts[:12]))
    if deletions_blocked:
        command_lines.append("upstream 削除候補: " + ", ".join(deletions_blocked[:12]))
    command_lines.append("結果は dashboard.md に記し、必要なら追加 subtasks を発行せよ。")

    entry = {
        "id": cmd_id,
        "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
        "purpose": "家老が upstream 差分の衝突候補を整理し、統合方針を報告できる状態にする。",
        "acceptance_criteria": criteria,
        "command": "\n".join(command_lines),
        "project": REPO_NAME,
        "priority": "high",
        "status": "pending",
    }
    existing.append(entry)
    with queue_path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(existing, fh, allow_unicode=True, sort_keys=False)
    return cmd_id


def register_pending_merge_notice(
    merge_batch: str,
    summary_path: Path,
    source_label: str,
    conflicts: List[str],
    deletions_blocked: List[str],
    reason: str,
    cmd_id: Optional[str] = None,
) -> None:
    notice = {
        "created_at": utcnow(),
        "merge_batch": merge_batch,
        "summary_path": summary_path.relative_to(ROOT).as_posix(),
        "source_label": source_label,
        "conflicts": conflicts,
        "deletions_blocked": deletions_blocked,
        "reason": reason,
        "cmd_id": cmd_id,
        "delivered": False,
    }
    write_json(NOTICE_PATH, notice)


def apply_release_snapshot(
    source_root: Path,
    version_before: str,
    version_after: str,
    old_manifest: Dict[str, str],
    preserve_patterns: List[str],
    emit_merge_command: bool = True,
) -> ApplyResult:
    ensure_state_dir()
    source_files = list_source_files(source_root)
    source_manifest = {rel: sha256_file(path) for rel, path in source_files.items()}
    merge_batch = datetime.now().strftime("%Y%m%d_%H%M%S_release")
    merge_incoming_root = MERGE_ROOT / merge_batch / "incoming"

    conflicts: List[str] = []
    deletions_blocked: List[str] = []
    preserved: List[str] = []
    updated: List[str] = []
    added: List[str] = []
    removed: List[str] = []

    for rel, src in source_files.items():
        dest = ROOT / rel
        src_hash = source_manifest[rel]
        old_hash = old_manifest.get(rel)

        if should_preserve(rel, preserve_patterns) and dest.exists():
            preserved.append(rel)
            continue

        if not dest.exists():
            copy_with_parents(src, dest)
            added.append(rel)
            continue

        current_hash = sha256_file(dest)
        if current_hash == src_hash:
            continue

        if old_hash and current_hash == old_hash:
            copy_with_parents(src, dest)
            updated.append(rel)
            continue

        if old_hash and src_hash == old_hash:
            preserved.append(rel)
            continue

        conflicts.append(rel)
        copy_with_parents(src, merge_incoming_root / rel)

    for rel, old_hash in old_manifest.items():
        if rel in source_manifest:
            continue
        dest = ROOT / rel
        if not dest.exists():
            continue
        if should_preserve(rel, preserve_patterns):
            preserved.append(rel)
            continue
        current_hash = sha256_file(dest)
        if current_hash == old_hash:
            dest.unlink()
            removed.append(rel)
        else:
            deletions_blocked.append(rel)

    applied = bool(added or updated or removed)
    if conflicts or deletions_blocked:
        summary = write_merge_summary(merge_batch, version_after, conflicts, deletions_blocked)
        cmd_id = None
        if emit_merge_command:
            cmd_id = append_karo_command_for_merge(
                source_label=version_after,
                summary_path=summary,
                conflicts=conflicts,
                deletions_blocked=deletions_blocked,
                purpose_prefix="Release update",
            )
        register_pending_merge_notice(
            merge_batch=merge_batch,
            summary_path=summary,
            source_label=version_after,
            conflicts=conflicts,
            deletions_blocked=deletions_blocked,
            reason="release update kept local changes and stored incoming files for merge",
            cmd_id=cmd_id,
        )
    else:
        merge_batch = None

    write_json(MANIFEST_PATH, source_manifest)

    return ApplyResult(
        applied=applied,
        version_before=version_before,
        version_after=version_after,
        conflicts=conflicts,
        deletions_blocked=deletions_blocked,
        preserved=preserved,
        updated=updated,
        added=added,
        removed=removed,
        merge_batch=merge_batch,
    )


def update_release_state(
    state: dict,
    ref: str,
    ref_kind: str,
    version_label: str,
    auto_update: Optional[bool] = None,
) -> None:
    state.update(
        {
            "install_mode": "release",
            "repo_owner": REPO_OWNER,
            "repo_name": REPO_NAME,
            "ref": ref,
            "ref_kind": ref_kind,
            "version_label": version_label,
            "current_commit": state.get("current_commit", ""),
            "last_update_at": utcnow(),
        }
    )
    if auto_update is not None:
        state["auto_update"] = auto_update
    else:
        state.setdefault("auto_update", False)
    write_json(STATE_PATH, state)


def init_install_state(args: argparse.Namespace) -> int:
    ensure_state_dir()
    ensure_update_settings_block()
    state = read_json(STATE_PATH, {})
    install_mode = args.install_mode or detect_install_mode(state)
    state.update(
        {
            "install_mode": install_mode,
            "repo_owner": REPO_OWNER,
            "repo_name": REPO_NAME,
            "ref": args.ref or DEFAULT_BRANCH,
            "ref_kind": args.ref_kind or ("tags" if install_mode == "release" else "heads"),
            "version_label": args.version_label or args.ref or DEFAULT_BRANCH,
            "auto_update": args.auto_update
            if args.auto_update is not None
            else (install_mode == "git-main"),
            "initialized_at": state.get("initialized_at", utcnow()),
            "last_update_at": utcnow(),
        }
    )
    if (ROOT / ".git").exists():
        try:
            state["current_commit"] = git(["rev-parse", "HEAD"]).stdout.strip()
        except subprocess.CalledProcessError:
            pass

    source_root = Path(args.source_root).resolve() if args.source_root else None
    if source_root and source_root.exists():
        manifest = build_manifest_from_source(source_root)
    elif (ROOT / ".git").exists():
        manifest = build_manifest_from_git(ROOT)
    else:
        manifest = {}
    write_json(STATE_PATH, state)
    write_json(MANIFEST_PATH, manifest)
    print(f"[update_manager] initialized install state: mode={install_mode} version={state['version_label']}")
    return 0


def maybe_toggle_auto_release(args: argparse.Namespace) -> None:
    if args.enable_auto:
        ensure_update_settings_block(auto_apply_release=True)
    elif args.disable_auto:
        ensure_update_settings_block(auto_apply_release=False)

    if args.enable_auto or args.disable_auto:
        state = read_json(STATE_PATH, {})
        if detect_install_mode(state) == "release":
            state["auto_update"] = bool(args.enable_auto)
            write_json(STATE_PATH, state)


def startup_enabled() -> bool:
    settings = read_settings()
    update = settings.get("update", {}) if isinstance(settings, dict) else {}
    if isinstance(update, dict):
        return bool(update.get("startup_check", True))
    return True


def release_auto_apply_enabled(state: dict) -> bool:
    settings = read_settings()
    update = settings.get("update", {}) if isinstance(settings, dict) else {}
    auto_apply = update.get("auto_apply_release") if isinstance(update, dict) else None
    if auto_apply is None:
        return bool(state.get("auto_update", False))
    return bool(auto_apply)


def git_manual_or_startup() -> Tuple[bool, str]:
    state = read_json(STATE_PATH, {})
    version_before = current_version_label(state)

    fetch_proc = git(["fetch", "origin", DEFAULT_BRANCH], check=False)
    if fetch_proc.returncode != 0:
        print(fetch_proc.stderr.strip(), file=sys.stderr)
        return False, version_before

    branch = git(["branch", "--show-current"]).stdout.strip()
    if branch != DEFAULT_BRANCH:
        print(f"[update_manager] skip git update: branch is {branch}, not {DEFAULT_BRANCH}")
        return False, version_before

    divergence = git(["rev-list", "--left-right", "--count", f"origin/{DEFAULT_BRANCH}...HEAD"]).stdout.strip()
    behind = ahead = 0
    if divergence:
        left, right = divergence.split()
        behind = int(left)
        ahead = int(right)

    status_proc = git(["status", "--porcelain"], check=False)
    dirty_lines = [line for line in status_proc.stdout.splitlines() if line]

    if ahead > 0:
        merge_batch = datetime.now().strftime("%Y%m%d_%H%M%S_git")
        summary = write_merge_summary(
            merge_batch,
            f"origin/{DEFAULT_BRANCH}",
            conflicts=[],
            deletions_blocked=[],
        )
        register_pending_merge_notice(
            merge_batch=merge_batch,
            summary_path=summary,
            source_label=f"origin/{DEFAULT_BRANCH}",
            conflicts=[],
            deletions_blocked=[],
            reason="git install has local commits; auto fast-forward skipped",
        )
        print("[update_manager] skip git update: local commits exist")
        return False, version_before

    if dirty_lines:
        modified = {
            line[3:]
            for line in dirty_lines
            if len(line) > 3 and not line.startswith("??")
        }
        upstream_changed = set(
            git(["diff", "--name-only", f"HEAD..origin/{DEFAULT_BRANCH}"]).stdout.splitlines()
        )
        conflicts = sorted(modified & upstream_changed)
        merge_batch = datetime.now().strftime("%Y%m%d_%H%M%S_git")
        summary = write_merge_summary(
            merge_batch,
            f"origin/{DEFAULT_BRANCH}",
            conflicts=conflicts,
            deletions_blocked=[],
        )
        if conflicts:
            incoming_root = MERGE_ROOT / merge_batch / "incoming"
            for rel in conflicts:
                show = subprocess.run(
                    ["git", "show", f"origin/{DEFAULT_BRANCH}:{rel}"],
                    cwd=ROOT,
                    check=False,
                    capture_output=True,
                )
                if show.returncode == 0:
                    dest = incoming_root / rel
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(show.stdout)
        register_pending_merge_notice(
            merge_batch=merge_batch,
            summary_path=summary,
            source_label=f"origin/{DEFAULT_BRANCH}",
            conflicts=conflicts,
            deletions_blocked=[],
            reason="git install has local modifications; auto fast-forward skipped",
        )
        print("[update_manager] skip git update: worktree is dirty")
        return False, version_before

    if behind == 0:
        print("[update_manager] git install already up to date")
        return False, version_before

    pull_proc = git(["pull", "--ff-only", "origin", DEFAULT_BRANCH], check=False)
    if pull_proc.returncode != 0:
        print(pull_proc.stderr.strip(), file=sys.stderr)
        return False, version_before

    state["install_mode"] = "git-main"
    state["version_label"] = DEFAULT_BRANCH
    state["current_commit"] = git(["rev-parse", "HEAD"]).stdout.strip()
    state["last_update_at"] = utcnow()
    state["auto_update"] = True
    write_json(STATE_PATH, state)
    write_json(MANIFEST_PATH, build_manifest_from_git(ROOT))
    print(f"[update_manager] updated git install: {version_before} -> {state['current_commit']}")
    return True, state["current_commit"]


def release_manual_or_startup() -> Tuple[bool, str]:
    ensure_state_dir()
    ensure_update_settings_block()
    state = read_json(STATE_PATH, {})
    version_before = current_version_label(state)
    latest = latest_release_info()
    latest_tag = latest["tag_name"]
    if version_before == latest_tag:
        print(f"[update_manager] release install already at latest tag: {latest_tag}")
        return False, version_before

    extracted, temp_dir = download_and_extract(latest_tag, "tags")
    try:
        old_manifest = read_json(MANIFEST_PATH, {})
        preserve = configured_preserve_patterns()
        result = apply_release_snapshot(
            source_root=extracted,
            version_before=version_before,
            version_after=latest_tag,
            old_manifest=old_manifest,
            preserve_patterns=preserve,
        )
    finally:
        temp_dir.cleanup()

    update_release_state(
        state=state,
        ref=latest_tag,
        ref_kind="tags",
        version_label=latest_tag,
    )
    print(
        f"[update_manager] release update applied: {version_before} -> {latest_tag} "
        f"(updated={len(result.updated)}, added={len(result.added)}, conflicts={len(result.conflicts)})"
    )
    return True, latest_tag


def upstream_sync() -> Tuple[bool, str]:
    ensure_state_dir()
    state = read_json(STATE_PATH, {})
    current_upstream = state.get("upstream_ref", "")

    fetch_proc = subprocess.run(
        ["git", "fetch", "upstream", DEFAULT_BRANCH],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if fetch_proc.returncode != 0:
        print(fetch_proc.stderr.strip(), file=sys.stderr)
        return False, current_upstream or "unknown"

    latest_upstream = git(["rev-parse", f"upstream/{DEFAULT_BRANCH}"]).stdout.strip()
    if current_upstream == latest_upstream:
        print(f"[update_manager] upstream snapshot already imported: {latest_upstream}")
        return False, latest_upstream

    extracted, temp_dir = extract_git_tree(f"upstream/{DEFAULT_BRANCH}")
    try:
        old_manifest = read_json(MANIFEST_PATH, {})
        preserve = configured_preserve_patterns()
        result = apply_release_snapshot(
            source_root=extracted,
            version_before=current_upstream or "upstream-unset",
            version_after=f"upstream/{DEFAULT_BRANCH}@{latest_upstream[:12]}",
            old_manifest=old_manifest,
            preserve_patterns=preserve,
            emit_merge_command=False,
        )
    finally:
        temp_dir.cleanup()

    # release-style conflict command text is too vague; append upstream-specific command if needed
    if result.conflicts or result.deletions_blocked:
        summary_path = (MERGE_ROOT / result.merge_batch / "SUMMARY.md") if result.merge_batch else None
        if summary_path and summary_path.exists():
            cmd_id = append_karo_command_for_merge(
                source_label=f"upstream/{DEFAULT_BRANCH}@{latest_upstream[:12]}",
                summary_path=summary_path,
                conflicts=result.conflicts,
                deletions_blocked=result.deletions_blocked,
                purpose_prefix="Original upstream import",
            )
            notice = read_json(NOTICE_PATH, {})
            if notice:
                notice["cmd_id"] = cmd_id
                notice["reason"] = "upstream import kept local changes and stored incoming files for merge"
                write_json(NOTICE_PATH, notice)

    state["upstream_ref"] = latest_upstream
    state["last_upstream_sync_at"] = utcnow()
    write_json(STATE_PATH, state)
    print(
        f"[update_manager] upstream import applied: {current_upstream or 'unset'} -> {latest_upstream} "
        f"(updated={len(result.updated)}, added={len(result.added)}, conflicts={len(result.conflicts)})"
    )
    return True, latest_upstream


def run_update(mode: str) -> Tuple[bool, str]:
    state = read_json(STATE_PATH, {})
    install_mode = detect_install_mode(state)
    if install_mode == "git-main":
        return git_manual_or_startup()
    if install_mode == "release":
        return release_manual_or_startup()
    print(f"[update_manager] no updater configured for install mode: {install_mode}")
    return False, current_version_label(state)


def manual_update(args: argparse.Namespace) -> int:
    maybe_toggle_auto_release(args)
    applied, version_after = run_update("manual")
    return 10 if applied else 0


def manual_upstream_sync(args: argparse.Namespace) -> int:
    applied, _ = upstream_sync()
    return 10 if applied else 0


def startup_update(args: argparse.Namespace) -> int:
    if not startup_enabled():
        print("[update_manager] startup update check disabled")
        return 0
    state = read_json(STATE_PATH, {})
    install_mode = detect_install_mode(state)
    if install_mode == "release" and not release_auto_apply_enabled(state):
        print("[update_manager] release startup auto-update disabled")
        return 0
    applied, _ = run_update("startup")
    return 10 if applied else 0


def notify_karo(args: argparse.Namespace) -> int:
    if not NOTICE_PATH.exists():
        return 0
    notice = read_json(NOTICE_PATH, {})
    if not notice or notice.get("delivered"):
        return 0
    summary_path = notice.get("summary_path", ".shogunate/merge-candidates")
    source_label = notice.get("source_label", "incoming update")
    reason = notice.get("reason", "merge candidates pending")
    conflicts = notice.get("conflicts", [])
    deletions_blocked = notice.get("deletions_blocked", [])
    message_lines = [
        f"更新候補の衝突が出たため、起動後マージ判断を頼む。source={source_label}",
        f"summary={summary_path}",
        f"reason={reason}",
    ]
    if conflicts:
        message_lines.append(f"conflicts={', '.join(conflicts[:8])}")
    if deletions_blocked:
        message_lines.append(f"upstream_deleted_kept={', '.join(deletions_blocked[:8])}")
    message = " / ".join(message_lines)
    subprocess.run(
        ["bash", str(ROOT / "scripts" / "inbox_write.sh"), "karo", message, "merge_required", "update_manager"],
        cwd=ROOT,
        check=True,
    )
    notice["delivered"] = True
    notice["delivered_at"] = utcnow()
    write_json(NOTICE_PATH, notice)
    print(f"[update_manager] notified karo: {summary_path}")
    return 0


def status(args: argparse.Namespace) -> int:
    state = read_json(STATE_PATH, {})
    install_mode = detect_install_mode(state)
    payload = {
        "install_mode": install_mode,
        "version_label": current_version_label(state),
        "auto_update": state.get("auto_update"),
        "startup_check": startup_enabled(),
        "release_auto_apply": release_auto_apply_enabled(state) if install_mode == "release" else None,
        "pending_merge_notice": NOTICE_PATH.exists(),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="multi-agent-shognate update manager")
    sub = parser.add_subparsers(dest="command", required=True)

    init_p = sub.add_parser("init", help="initialize install/update metadata")
    init_p.add_argument("--install-mode", choices=["release", "git-main", "git-local"], default=None)
    init_p.add_argument("--ref", default=None)
    init_p.add_argument("--ref-kind", default=None)
    init_p.add_argument("--version-label", default=None)
    init_p.add_argument("--source-root", default=None)
    init_p.add_argument("--auto-update", type=lambda x: str(x).lower() == "true", default=None)
    init_p.set_defaults(func=init_install_state)

    manual_p = sub.add_parser("manual", help="run manual update")
    manual_p.add_argument("--enable-auto", action="store_true")
    manual_p.add_argument("--disable-auto", action="store_true")
    manual_p.set_defaults(func=manual_update)

    upstream_p = sub.add_parser("upstream-sync", help="import latest upstream/main snapshot and queue merge work")
    upstream_p.set_defaults(func=manual_upstream_sync)

    startup_p = sub.add_parser("startup", help="run startup update check/apply")
    startup_p.set_defaults(func=startup_update)

    notify_p = sub.add_parser("notify-karo", help="send pending merge notice to karo")
    notify_p.set_defaults(func=notify_karo)

    status_p = sub.add_parser("status", help="print update status")
    status_p.set_defaults(func=status)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
