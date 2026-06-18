#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  exit 1
}

require_same_file() {
  local root_path="$1"
  local mod_path="$2"

  cmp -s "$root_path" "$mod_path" \
    || fail "$root_path must match $mod_path"
}

require_same_text_file() {
  local root_path="$1"
  local mod_path="$2"

  python3 - "$root_path" "$mod_path" <<'PYEOF' \
    || fail "$root_path must match $mod_path after normalizing line endings"
import sys
from pathlib import Path

def body(path: str) -> bytes:
    return Path(path).read_bytes().replace(b"\r\n", b"\n")

if body(sys.argv[1]) != body(sys.argv[2]):
    raise SystemExit(1)
PYEOF
}

require_same_after_header_comment() {
  local root_path="$1"
  local mod_path="$2"

  python3 - "$root_path" "$mod_path" <<'PYEOF' \
    || fail "$root_path must match $mod_path except for the leading comment block"
import sys
from pathlib import Path

def body(path: str) -> str:
    lines = Path(path).read_text(encoding="utf-8").replace("\r\n", "\n").splitlines()
    while lines and (not lines[0].strip() or lines[0].lstrip().startswith("#")):
        lines.pop(0)
    return "\n".join(lines)

if body(sys.argv[1]) != body(sys.argv[2]):
    raise SystemExit(1)
PYEOF
}

require_instruction_sources_synced() {
  local root_path mod_source_path rel mod_path

  while IFS= read -r root_path; do
    rel="${root_path#instructions/}"
    mod_path="shogunate_mod/instructions/source/${rel}"
    [[ -f "$mod_path" ]] || fail "missing MOD instruction source: $mod_path"
    cmp -s "$root_path" "$mod_path" \
      || fail "$root_path must match $mod_path"
  done < <(find instructions -type f -name '*.md' ! -path 'instructions/generated/*' | sort)

  while IFS= read -r mod_source_path; do
    rel="${mod_source_path#shogunate_mod/instructions/source/}"
    root_path="instructions/${rel}"
    [[ -f "$root_path" ]] || fail "missing root instruction compatibility copy: $root_path"
    cmp -s "$root_path" "$mod_source_path" \
      || fail "$root_path must match $mod_source_path"
  done < <(find shogunate_mod/instructions/source -type f -name '*.md' | sort)
}

require_directory_files_synced() {
  local root_dir="$1"
  local mod_dir="$2"
  local root_path rel mod_path mod_source_path

  while IFS= read -r root_path; do
    rel="${root_path#${root_dir}/}"
    mod_path="${mod_dir}/${rel}"
    [[ -f "$mod_path" ]] || fail "missing MOD source: $mod_path"
    cmp -s "$root_path" "$mod_path" \
      || fail "$root_path must match $mod_path"
  done < <(find "$root_dir" -type f \
    ! -path '*/__pycache__/*' \
    ! -path '*/.system/*' \
    ! -name '*.pyc' \
    ! -name '*.pyo' \
    | sort)

  while IFS= read -r mod_source_path; do
    rel="${mod_source_path#${mod_dir}/}"
    root_path="${root_dir}/${rel}"
    [[ -f "$root_path" ]] || fail "missing root compatibility copy: $root_path"
    cmp -s "$root_path" "$mod_source_path" \
      || fail "$root_path must match $mod_source_path"
  done < <(find "$mod_dir" -type f \
    ! -path '*/__pycache__/*' \
    ! -path '*/.system/*' \
    ! -name '*.pyc' \
    ! -name '*.pyo' \
    | sort)
}

require_android_sources_synced() {
  python3 <<'PYEOF' || fail "android sources must match shogunate_mod/mobile/android"
import sys
import os
from pathlib import Path

root_android = Path("android")
mod_android = Path("shogunate_mod/mobile/android")
excluded_dirs = {
    ".android-home",
    ".android-prefs",
    ".android-user-home",
    ".gradle",
    ".gradle-home",
    ".gradle-user-home",
    ".home",
    ".android-sdk",
    ".android-sdk-tmp",
    "build",
}
excluded_names = {"local.properties", ".gitignore"}
excluded_suffixes = {".apk"}
problems = []

def check_tree(source: Path, destination: Path, source_name: str, destination_name: str) -> None:
    for dirpath, dirnames, filenames in os.walk(source):
        dirnames[:] = [name for name in dirnames if name not in excluded_dirs]
        current_dir = Path(dirpath)
        for filename in filenames:
            path = current_dir / filename
            rel = path.relative_to(source)
            if filename in excluded_names:
                continue
            if path.suffix in excluded_suffixes:
                continue
            destination_path = destination / rel
            if not destination_path.exists():
                problems.append(f"missing {destination_name} Android source: {destination_path}")
                continue
            if path.read_bytes() != destination_path.read_bytes():
                problems.append(f"Android {source_name} copy differs: {rel}")

check_tree(root_android, mod_android, "compatibility", "MOD")
check_tree(mod_android, root_android, "MOD", "root compatibility")

if problems:
    print("\n".join(problems), file=sys.stderr)
    raise SystemExit(1)
PYEOF
}

require_manifest_mod_sources_in_head() {
  python3 <<'PYEOF' || fail "manifest MOD canonical sources must be present in HEAD"
import subprocess
import os
from pathlib import Path

ROOT = Path(".")


def manifest_section(text: str, name: str) -> list[str]:
    lines = text.splitlines()
    start = lines.index(f"{name}:") + 1
    section_lines = []
    for line in lines[start:]:
        if line and not line.startswith(" ") and not line.startswith("-"):
            break
        section_lines.append(line)
    return section_lines


def manifest_mapping_values(text: str, name: str) -> list[str]:
    values = []
    for line in manifest_section(text, name):
        stripped = line.strip()
        if not stripped or stripped.startswith("-") or ":" not in stripped:
            continue
        _, value = stripped.split(":", 1)
        value = value.strip().strip('"')
        if value:
            values.append(value)
    return values


def allowed_ignored_mod_artifact(rel_path: str) -> bool:
    parts = rel_path.split("/")
    if "__pycache__" in parts or rel_path.endswith((".pyc", ".pyo")):
        return True
    if not rel_path.startswith("shogunate_mod/mobile/android/"):
        return False

    android_rel = rel_path.removeprefix("shogunate_mod/mobile/android/")
    ignored_prefixes = (
        ".android-home/",
        ".android-prefs/",
        ".android-user-home/",
        ".gradle/",
        ".gradle-home/",
        ".gradle-user-home/",
        ".home/",
        ".android-sdk/",
        ".android-sdk-tmp/",
        "build/",
        "app/build/",
        "release/",
    )
    return android_rel == "local.properties" or android_rel.startswith(ignored_prefixes)


def iter_source_files(path: Path) -> list[Path]:
    pruned_dirs = {
        "__pycache__",
        ".android-home",
        ".android-prefs",
        ".android-user-home",
        ".android-sdk",
        ".android-sdk-tmp",
        ".gradle",
        ".gradle-home",
        ".gradle-user-home",
        ".home",
        "build",
        "release",
    }
    files = []
    for dirpath, dirnames, filenames in os.walk(path):
        dirnames[:] = [name for name in dirnames if name not in pruned_dirs]
        current = Path(dirpath)
        for filename in filenames:
            files.append(current / filename)
    return sorted(files)


manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
result = subprocess.run(
    ["git", "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", "shogunate_mod"],
    text=True,
    capture_output=True,
    check=False,
)
if result.returncode != 0:
    raise SystemExit(result.stderr)
head_files = {path for path in result.stdout.split("\0") if path}
missing = []
expanded_dirs = set()

for rel_path in manifest_mapping_values(manifest, "canonical_paths"):
    normalized = rel_path.rstrip("/")
    if not normalized.startswith("shogunate_mod/"):
        continue
    path = ROOT / normalized
    if path.is_file():
        if normalized not in head_files and not allowed_ignored_mod_artifact(normalized):
            missing.append(normalized)
        continue
    if path.is_dir():
        if any(normalized == parent or normalized.startswith(parent + "/") for parent in expanded_dirs):
            continue
        expanded_dirs.add(normalized)
        for child in iter_source_files(path):
            if not child.is_file():
                continue
            rel = str(child.relative_to(ROOT))
            if rel not in head_files and not allowed_ignored_mod_artifact(rel):
                missing.append(rel)

if missing:
    missing = sorted(set(missing))
    print(f"{len(missing)} manifest MOD canonical source files are missing from HEAD.")
    print("Commit the listed shogunate_mod sources before creating a release archive:")
    print("\n".join(missing))
    raise SystemExit(1)
PYEOF
}

require_python_syntax_clean() {
  python3 <<'PYEOF' || fail "tracked Python source syntax check failed"
import pathlib
import subprocess

files = subprocess.check_output(["git", "ls-files", "-z", "--", "*.py"]).split(b"\0")
for raw in files:
    if not raw:
        continue
    path = pathlib.Path(raw.decode())
    source = path.read_text(encoding="utf-8")
    compile(source, str(path), "exec")
PYEOF
}

printf '[INFO] prepublish check start\n'

tracked_forbidden="$(git ls-files | rg '^(Waste/|_trash/|_upstream_reference/|\\.shogunate/|docs/(WORKLOG|HANDOVER|UPSTREAM_SYNC)|config/(settings|projects)\.yaml|dashboard.md|queue/)' || true)"
if [[ -n "$tracked_forbidden" ]]; then
  printf '[FAIL] forbidden tracked paths detected:\n%s\n' "$tracked_forbidden" >&2
  exit 1
fi

if ! git check-ignore -q config/settings.yaml; then
  fail "config/settings.yaml must remain ignored (local values such as ntfy_topic must not be published)"
fi

if ! git check-ignore -q config/projects.yaml; then
  fail "config/projects.yaml must remain ignored (local project mappings must not be published)"
fi

require_same_file package.json shogunate_mod/package/package.json
require_same_file package-lock.json shogunate_mod/package/package-lock.json
require_same_file requirements.txt shogunate_mod/package/requirements.txt
require_same_file Makefile shogunate_mod/development/Makefile
require_same_file .gitmodules shogunate_mod/development/gitmodules
require_same_file .gitattributes shogunate_mod/package/gitattributes
require_same_file .gitignore shogunate_mod/package/gitignore
require_same_file .github/workflows/package-release.yml shogunate_mod/package/workflows/package-release.yml
require_same_file .github/workflows/test.yml shogunate_mod/package/workflows/test.yml
require_same_file .github/FUNDING.yml shogunate_mod/github/FUNDING.yml
require_same_file README.md shogunate_mod/docs/README.md
require_same_file README_ja.md shogunate_mod/docs/README_ja.md
require_same_file CHANGELOG.md shogunate_mod/docs/CHANGELOG.md
require_same_file CONTRIBUTING.md shogunate_mod/docs/CONTRIBUTING.md
require_same_file SECURITY.md shogunate_mod/docs/SECURITY.md
require_same_file docs/philosophy.md shogunate_mod/docs/philosophy.md
require_same_file .gitleaks.toml shogunate_mod/security/gitleaks.toml
require_same_file .claude/settings.json shogunate_mod/hooks/claude_settings.json
require_same_file context/README.md shogunate_mod/context/README.md
require_same_file .opencode/tools/mark-as-read.ts shogunate_mod/opencode/tools/mark-as-read.ts
require_same_text_file memory/MEMORY.md.sample shogunate_mod/package/templates/memory/MEMORY.md.sample
require_same_text_file saytask/streaks.yaml.sample shogunate_mod/package/templates/saytask/streaks.yaml.sample
require_same_file CLAUDE.md shogunate_mod/instructions/autoload/CLAUDE.md
require_same_file .codd/codd.yaml shogunate_mod/gunkan/codd.yaml
require_same_file config/opencode-tui.json shogunate_mod/configure/opencode-tui.json
require_same_file config/ntfy_auth.env.sample shogunate_mod/notify/ntfy_auth.env.sample
require_same_after_header_comment \
  config/opencode-permissions.yaml \
  shogunate_mod/configure/opencode-permissions.yaml
require_instruction_sources_synced
require_directory_files_synced skills shogunate_mod/skills/claude
require_directory_files_synced .cursor/skills shogunate_mod/skills/cursor
require_directory_files_synced templates shogunate_mod/templates
require_directory_files_synced docs/codd shogunate_mod/gunkan/docs
require_android_sources_synced
require_directory_files_synced tests shogunate_mod/tests
require_manifest_mod_sources_in_head
printf '[INFO] source syntax checks\n'
git ls-files -z -- '*.sh' '*.command' | xargs -0 -r bash -n
require_python_syntax_clean
git ls-files -z -- '*.js' | xargs -0 -r -n1 node --check
printf '[INFO] package distribution contract tests\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution
printf '[INFO] MOD behavior unit tests\n'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  tests.unit.test_shogunate_pair_server \
  tests.unit.test_runtime_blocker_notice \
  tests.unit.test_update_manager
bash shogunate_mod/instructions/ensure_generated.sh

private_hits="$(
  git grep -n -I -E \
    '/mnt/d/Git_WorkSpace|D:\\\\Git_WorkSpace|/mnt/c/Users/muro|100\\.71\\.16\\.5|172\\.31\\.8\\.112|192\\.168\\.1\\.2|muro@MURO' \
    -- . ':(exclude)docs/PUBLISHING.md' ':(exclude)scripts/prepublish_check.sh' ':(exclude)shogunate_mod/package/prepublish_check.sh' || true
)"
if [[ -n "$private_hits" ]]; then
  printf '[FAIL] possible local/private values detected:\n%s\n' "$private_hits" >&2
  exit 1
fi

dirty="$(git status --short || true)"
if [[ -n "$dirty" ]]; then
  printf '[FAIL] worktree is dirty:\n%s\n' "$dirty" >&2
  exit 1
fi

printf '[PASS] prepublish check passed\n'
