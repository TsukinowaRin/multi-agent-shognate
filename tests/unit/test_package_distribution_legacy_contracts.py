import ast
import hashlib
import io
import json
import fnmatch
import os
import re
import subprocess
import tempfile
import tarfile
import unittest
import zipfile
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
BOOTSTRAP = ROOT / "shogunate_mod" / "package" / "bootstrap.sh"
_RELEASE_ARCHIVE_FILES_CACHE: set[str] | None = None


def non_comment_body(text: str) -> str:
    return "\n".join(
        line.rstrip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def without_header_comment(text: str) -> str:
    lines = text.replace("\r\n", "\n").splitlines()
    while lines and (not lines[0].strip() or lines[0].lstrip().startswith("#")):
        lines.pop(0)
    return "\n".join(lines)


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
        if not stripped or stripped.startswith("-"):
            continue
        if ":" not in stripped:
            continue
        _, value = stripped.split(":", 1)
        value = value.strip().strip('"')
        if value:
            values.append(value)
    return values


def manifest_mapping_keys(text: str, name: str) -> list[str]:
    keys = []
    for line in manifest_section(text, name):
        stripped = line.strip()
        if not stripped or stripped.startswith("-"):
            continue
        if ":" not in stripped:
            continue
        key, _ = stripped.split(":", 1)
        if key:
            keys.append(key)
    return keys


def manifest_list_values(text: str, name: str) -> list[str]:
    values = []
    for line in manifest_section(text, name):
        stripped = line.strip()
        if stripped.startswith("- "):
            values.append(stripped[2:].strip().strip('"'))
    return values


def manifest_core_touchpoint_paths(text: str) -> list[str]:
    values = []
    for line in manifest_section(text, "current_core_touchpoints"):
        stripped = line.strip()
        if not stripped.startswith("- path:"):
            continue
        _, value = stripped.split(":", 1)
        for chunk in value.strip().strip('"').split(" and "):
            values.extend(part.strip() for part in chunk.split(" / ") if part.strip())
    return values


def manifest_core_touchpoints(text: str) -> list[dict[str, str]]:
    items = []
    current = None
    for line in manifest_section(text, "current_core_touchpoints"):
        stripped = line.strip()
        if stripped.startswith("- path:"):
            if current is not None:
                items.append(current)
            current = {}
            _, value = stripped.split(":", 1)
            current["path"] = value.strip().strip('"')
            continue
        if current is None or ":" not in stripped:
            continue
        key, value = stripped.split(":", 1)
        current[key] = value.strip().strip('"')
    if current is not None:
        items.append(current)
    return items




def release_archive_files() -> set[str]:
    """Build the release archive from the current worktree without changing the real index."""
    global _RELEASE_ARCHIVE_FILES_CACHE
    if _RELEASE_ARCHIVE_FILES_CACHE is not None:
        return set(_RELEASE_ARCHIVE_FILES_CACHE)
    with tempfile.TemporaryDirectory() as temporary:
        index = Path(temporary) / "index"
        env = {**os.environ, "GIT_INDEX_FILE": str(index)}
        for command in (
            ["git", "read-tree", "HEAD"],
            ["git", "add", "-A", "--", "."],
        ):
            result = subprocess.run(
                command,
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
        tree_result = subprocess.run(
            ["git", "write-tree"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        if tree_result.returncode:
            raise AssertionError(tree_result.stdout + tree_result.stderr)
        archive = subprocess.run(
            [
                "git",
                "archive",
                "--worktree-attributes",
                "--format=tar",
                tree_result.stdout.strip(),
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )
        if archive.returncode:
            raise AssertionError(archive.stderr.decode(errors="replace"))
        with tarfile.open(fileobj=io.BytesIO(archive.stdout), mode="r:") as package:
            _RELEASE_ARCHIVE_FILES_CACHE = {
                member.name.rstrip("/") for member in package.getmembers()
            }
    return set(_RELEASE_ARCHIVE_FILES_CACHE)


def release_zip_archive_files() -> set[str]:
    # Both formats are produced from the same git tree; archive boundary is format-independent.
    return release_archive_files()


def packed_files_cover_path(files: set[str], rel_path: str) -> bool:
    normalized = rel_path.rstrip("/")
    return any(path == normalized or path.startswith(normalized + "/") for path in files)




def manifest_canonical_paths_cover_path(canonical_paths: list[str], rel_path: str) -> bool:
    rel_path = rel_path.rstrip("/")
    for canonical_path in canonical_paths:
        normalized = canonical_path.rstrip("/")
        if rel_path == normalized:
            return True
        if (canonical_path.endswith("/") or (ROOT / normalized).is_dir()) and rel_path.startswith(normalized + "/"):
            return True
    return False


def manifest_root_paths_cover_path(root_paths: list[str], rel_path: str) -> bool:
    rel_path = rel_path.rstrip("/")
    for root_path in root_paths:
        normalized = root_path.rstrip("/")
        if rel_path == normalized:
            return True
        if (root_path.endswith("/") or (ROOT / normalized).is_dir()) and rel_path.startswith(normalized + "/"):
            return True
    return False


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


def prepublish_sync_pairs(text: str) -> list[tuple[str, str]]:
    pairs = []
    normalized = text.replace("\\\n", " ")
    commands = {
        "require_same_file",
        "require_same_text_file",
        "require_same_after_header_comment",
        "require_directory_files_synced",
    }
    for line in normalized.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        parts = stripped.split()
        if len(parts) >= 3 and parts[0] in commands:
            pairs.append((parts[1], parts[2]))
    return pairs


def mod_readme_boundary_paths(text: str) -> list[str]:
    paths = []
    for line in text.splitlines():
        if not line.startswith("- ") or not re.search(r"\bowns\b", line):
            continue
        code_paths = re.findall(r"`([^`]+)`", re.split(r"\s+owns\b", line, 1)[0])
        if code_paths:
            paths.append(code_paths[-1].rstrip("/"))
    return sorted(paths)


def markdown_list_section_values(text: str, heading: str) -> list[str]:
    lines = text.splitlines()
    start = lines.index(f"## {heading}") + 1
    values = []
    for line in lines[start:]:
        if line.startswith("## "):
            break
        if line.startswith("- "):
            values.append(line[2:].strip())
    return values


def is_intentionally_unpacked_mod_path(rel_path: str) -> bool:
    excluded_prefixes = (
        "shogunate_mod/mobile/android/",
        "shogunate_mod/tests/",
    )
    excluded_exact = {
        "shogunate_mod/mobile/android",
        "shogunate_mod/tests",
    }
    return rel_path in excluded_exact or any(rel_path.startswith(prefix) for prefix in excluded_prefixes)


def is_intentionally_release_archive_excluded_mod_path(rel_path: str) -> bool:
    excluded_prefixes = (
        "shogunate_mod/mobile/android/",
        "shogunate_mod/tests/",
        "shogunate_mod/package/workflows/",
    )
    excluded_exact = {
        "shogunate_mod/mobile/android",
        "shogunate_mod/tests",
        "shogunate_mod/package/workflows",
        "shogunate_mod/package/package-lock.json",
        "shogunate_mod/package/gitattributes",
        "shogunate_mod/package/gitignore",
        "shogunate_mod/github/FUNDING.yml",
        "shogunate_mod/development/gitmodules",
    }
    return rel_path in excluded_exact or any(rel_path.startswith(prefix) for prefix in excluded_prefixes)


def manifest_canonical_mod_source_files(manifest: str) -> list[str]:
    files = []
    for rel_path in manifest_mapping_values(manifest, "canonical_paths"):
        normalized = rel_path.rstrip("/")
        if not normalized.startswith("shogunate_mod/"):
            continue
        path = ROOT / normalized
        if path.is_file():
            files.append(normalized)
            continue
        if path.is_dir():
            for child in sorted(path.rglob("*")):
                if not child.is_file():
                    continue
                rel = str(child.relative_to(ROOT))
                if allowed_ignored_mod_artifact(rel):
                    continue
                files.append(rel)

    return sorted(set(files))


def root_mod_delegate_candidates() -> list[str]:
    candidates = []
    root_launcher_files = [
        "first_setup.sh",
        "setup.sh",
        "Shogunate-Configure-Roles.bat",
        "Shogunate-Configure-Roles.command",
        "Shogunate-Configure-Roles.sh",
        "Shogunate-Runtime.bat",
        "Shogunate-Runtime.command",
        "Shogunate-Runtime.sh",
        "Shutsujin-Clean.bat",
        "Shutsujin-Resume.bat",
        "Shutsujin.bat",
        "Shutsujin.sh",
        "shutsujin_departure.sh",
    ]

    for rel in root_launcher_files:
        path = ROOT / rel
        if path.exists() and "shogunate_mod" in path.read_text(encoding="utf-8", errors="ignore"):
            candidates.append(rel)

    for directory in ("bin", "lib", "scripts"):
        root_dir = ROOT / directory
        for path in sorted(root_dir.rglob("*")):
            if not path.is_file():
                continue
            rel_parts = path.relative_to(ROOT).parts
            if "__pycache__" in rel_parts:
                continue
            if path.suffix in {".pyc", ".pyo"}:
                continue
            if "shogunate_mod" not in path.read_text(encoding="utf-8", errors="ignore"):
                continue
            candidates.append(str(path.relative_to(ROOT)))

    return sorted(set(candidates))


def tracked_root_wrapper_surface_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr)

    files = []
    for rel in result.stdout.split("\0"):
        if not rel:
            continue
        if "__pycache__" in rel.split("/") or rel.endswith((".pyc", ".pyo")):
            continue
        if rel.startswith(("bin/", "lib/", "scripts/")) or is_top_level_launcher_wrapper(rel):
            files.append(rel)
    return sorted(files)


def root_shogunate_surface_candidates() -> list[str]:
    markers = (
        "shogunate_mod",
        "Shogunate",
        "shogunate",
        "SHOGUNATE_",
        "Gunkan",
        "軍監",
        "multi-agent-shognate",
    )
    surface_dirs = (
        ".claude",
        ".codd",
        ".cursor",
        ".github",
        ".opencode",
        "agents",
        "bin",
        "config",
        "context",
        "docs",
        "instructions",
        "lib",
        "memory",
        "saytask",
        "scripts",
        "skills",
        "templates",
    )
    ignored_suffixes = {
        ".apk",
        ".class",
        ".dex",
        ".jar",
        ".jpg",
        ".jpeg",
        ".keystore",
        ".png",
        ".webp",
    }
    candidates = []
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr)

    for rel in sorted(path for path in result.stdout.split("\0") if path):
        parts = rel.split("/")
        if len(parts) > 1 and parts[0] not in surface_dirs:
            continue
        if (
            rel.startswith("docs/EXECPLAN_")
            or rel.startswith("docs/HANDOFF_")
            or rel in {"docs/INDEX.md", "docs/REQS.md", "docs/WORKLOG.md"}
        ):
            continue
        if "__pycache__" in parts:
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        if path.suffix in ignored_suffixes or path.suffix in {".pyc", ".pyo"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if any(marker in text for marker in markers):
            candidates.append(rel)

    return candidates


def tracked_root_code_like_files() -> list[str]:
    code_like_suffixes = {
        ".bash",
        ".bat",
        ".bats",
        ".cmd",
        ".command",
        ".js",
        ".json",
        ".jsonc",
        ".ps1",
        ".py",
        ".sh",
        ".toml",
        ".ts",
        ".yaml",
        ".yml",
    }
    code_like_exact_names = {
        "Makefile",
        "package-lock.json",
        "requirements.txt",
    }
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(result.stderr)

    files = []
    for rel in sorted(path for path in result.stdout.split("\0") if path):
        if rel.startswith("shogunate_mod/"):
            continue
        parts = rel.split("/")
        if "__pycache__" in parts or rel.endswith((".pyc", ".pyo")):
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        if path.suffix.lower() in code_like_suffixes or path.name in code_like_exact_names:
            files.append(rel)

    return files


def wrapper_mod_delegate_paths(text: str) -> list[str]:
    normalized = text.replace("\\", "/")
    paths = set()

    for match in re.finditer(r"shogunate_mod/[A-Za-z0-9_./-]+", normalized):
        paths.add(match.group(0).rstrip(".,;:)'\""))

    for line in normalized.splitlines():
        if '"shogunate_mod"' not in line:
            continue
        parts = re.findall(r'"([^"]+)"', line)
        if "shogunate_mod" not in parts:
            continue
        index = parts.index("shogunate_mod")
        delegate_parts = []
        for part in parts[index:]:
            if part == "__main__":
                break
            delegate_parts.append(part)
        if len(delegate_parts) > 1:
            paths.add("/".join(delegate_parts))

    return sorted(paths)


def generated_root_touchpoint_files() -> list[str]:
    candidates = [
        "AGENTS.md",
        ".github/copilot-instructions.md",
    ]

    for directory in ("agents/default", ".opencode/agents"):
        for path in sorted((ROOT / directory).glob("*")):
            if path.is_file():
                candidates.append(str(path.relative_to(ROOT)))

    return sorted(candidates)


def ensure_generated_targets(text: str) -> list[str]:
    targets = []
    in_targets = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "targets=(":
            in_targets = True
            continue
        if in_targets and stripped == ")":
            break
        if not in_targets:
            continue
        match = re.search(r'"([^"]+)"', stripped)
        if match:
            targets.append(match.group(1))
    return targets


def root_dot_compatibility_surface_files(files: set[str]) -> list[str]:
    prefixes = (
        ".claude/",
        ".codd/",
        ".github/",
        ".opencode/",
        "agents/default/",
    )
    return sorted(
        rel
        for rel in files
        if rel.startswith(prefixes) and (ROOT / rel).is_file()
    )


def expected_root_dot_compatibility_surface_files() -> list[str]:
    return sorted(
        [
            ".claude/settings.json",
            ".codd/codd.yaml",
            ".opencode/tools/mark-as-read.ts",
            *[
                rel
                for rel in generated_root_touchpoint_files()
                if rel.startswith((".github/", ".opencode/agents/", "agents/default/"))
            ],
        ]
    )


def top_level_runtime_file_surface(files: set[str]) -> list[str]:
    return sorted(rel for rel in files if "/" not in rel and (ROOT / rel).is_file())


def root_runtime_directory_surface(files: set[str]) -> list[str]:
    directories = set()
    for rel in files:
        if "/" in rel:
            directories.add(rel.split("/", 1)[0])
        elif (ROOT / rel).is_dir():
            directories.add(rel)
    return sorted(directories)


def expected_root_runtime_directory_surface() -> list[str]:
    return sorted(
        {
            ".claude",
            ".codd",
            ".cursor",
            ".github",
            ".opencode",
            "agents",
            "config",
            "context",
            "docs",
            "instructions",
            "lib",
            "memory",
            "saytask",
            "scripts",
            "shogunate_mod",
            "skills",
            "templates",
        }
    )


def manifest_declared_root_directories(manifest: str) -> list[str]:
    roots = set()
    for rel in (
        manifest_core_touchpoint_paths(manifest)
        + manifest_list_values(manifest, "compatibility_wrappers")
        + manifest_mapping_values(manifest, "canonical_paths")
    ):
        normalized = rel.rstrip("/")
        if normalized:
            roots.add(normalized.split("/", 1)[0])
    return sorted(roots)


def manifest_current_directory_touchpoint_roots(manifest: str) -> list[str]:
    roots = set()
    for rel in manifest_core_touchpoint_paths(manifest):
        normalized = rel.rstrip("/")
        if not normalized:
            continue
        if "/" in normalized or rel.endswith("/") or (ROOT / normalized).is_dir():
            roots.add(normalized.split("/", 1)[0])
    return sorted(roots)


def manifest_declared_root_files(manifest: str) -> list[str]:
    files = set()
    for rel in (
        manifest_core_touchpoint_paths(manifest)
        + manifest_list_values(manifest, "compatibility_wrappers")
    ):
        normalized = rel.rstrip("/")
        if normalized and "/" not in normalized and (ROOT / normalized).is_file():
            files.add(normalized)
    return sorted(files)


def manifest_current_top_level_file_touchpoints(manifest: str) -> list[str]:
    return sorted(
        normalized
        for rel in manifest_core_touchpoint_paths(manifest)
        if (normalized := rel.rstrip("/")) and "/" not in normalized and (ROOT / normalized).is_file()
    )


def expected_top_level_runtime_file_surface(manifest: str) -> list[str]:
    public_files = {
        ".gitleaks.toml",
        "AGENTS.md",
        "CHANGELOG.md",
        "CLAUDE.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "Makefile",
        "README.md",
        "README_ja.md",
        "SECURITY.md",
        "requirements.txt",
    }
    wrapper_files = {
        rel
        for rel in manifest_list_values(manifest, "compatibility_wrappers")
        if is_top_level_launcher_wrapper(rel)
    }
    return sorted(public_files | wrapper_files)


def is_top_level_launcher_wrapper(rel_path: str) -> bool:
    return "/" not in rel_path and (
        rel_path in {"first_setup.sh", "setup.sh", "shutsujin_departure.sh"}
        or rel_path.startswith(("Shogunate-", "Shutsujin"))
    )


def legacy_installer_surface_files() -> set[str]:
    return {
        "install.bat",
        "install.command",
        "install.sh",
        "Shogunate-Uninstaller.bat",
    }


def representative_wrapper_smoke_cases() -> list[tuple[list[str], str]]:
    return [
        (
            ["python3", "scripts/shogunate_pair_server.py", "--help"],
            "Run the Shogunate Android pairing server.",
        ),
        (
            ["bash", "scripts/shell_aliases.sh"],
            "shogunate_mod/shell/install_aliases.sh",
        ),
        (
            ["bash", "scripts/agent_status.sh", "--help"],
            "Usage: agent_status.sh",
        ),
    ]




class PackageDistributionContractTests(unittest.TestCase):

    def test_curl_bootstrap_installs_command_before_first_setup(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        command_index = text.index('cat > "$BIN_DIR/shogunate"')
        setup_index = text.index('log "run shogunate_mod/package/first_setup.sh"')
        self.assertLess(command_index, setup_index)
        self.assertIn("pair)\n        shift || true", text)
        self.assertIn("exec bash shogunate_mod/runtime/runtime_launcher.sh", text)
        self.assertIn("exec bash shogunate_mod/configure/role_launcher.sh", text)
        self.assertIn('exec bash "\\$SHOGUNATE_INSTALL_DIR/shogunate_mod/package/bootstrap.sh"', text)
        self.assertNotIn("exec ./Shogunate-Runtime.sh", text)
        self.assertNotIn("exec ./Shogunate-Configure-Roles.sh", text)
        self.assertNotIn('exec bash "\\$SHOGUNATE_INSTALL_DIR/scripts/shogunate_package_bootstrap.sh"', text)
        self.assertIn("exec python3 shogunate_mod/pair/server.py", text)
        self.assertNotIn("exec python3 scripts/shogunate_pair_server.py", text)
        self.assertIn("prepare_project_runtime", text)
        self.assertIn('project="\\$(resolve_project_dir)"', text)
        self.assertIn("default_session_name", text)
        self.assertIn("project_registry()", text)
        self.assertIn("resolve_registered_project_ref()", text)
        self.assertIn("projects|project)", text)
        self.assertIn("battlefield|battlefields|app)", text)
        self.assertIn("open|use)", text)
        self.assertIn("SHOGUNATE_PROJECT_DIR", text)
        self.assertIn("--target-project", text)
        self.assertIn("config/settings.yaml", text)
        self.assertIn("queue/runtime/session_name", text)
        self.assertIn("print_project_info", text)
        self.assertIn("rsync -a --checksum --delete", text)
        self.assertIn("--exclude '/.shogunate/'", text)
        self.assertIn("--exclude '/dashboard.md'", text)
        self.assertIn("--exclude='./.shogunate'", text)
        self.assertIn("--exclude='./dashboard.md'", text)

    def test_runtime_state_recreates_missing_dashboard(self):
        text = (ROOT / "shogunate_mod" / "runtime" / "state.sh").read_text(encoding="utf-8")
        self.assertIn('[ "$CLEAN_MODE" = true ] || [ ! -f "./dashboard.md" ]', text)

    def test_package_where_does_not_prepare_project_runtime(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        match = re.search(r"print_project_info\(\) \{\n(?P<body>.*?)\n\}", text, re.DOTALL)
        self.assertIsNotNone(match)
        body = match.group("body")
        self.assertNotIn("prepare_project_runtime", body)
        self.assertIn('runtime_dir="\\$workspace_home/\\${slug}-\\${hash}"', body)

    def test_project_registry_supports_registered_project_selection(self):
        registry_script = ROOT / "shogunate_mod" / "projects" / "registry.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            project = tmp_path / "project one"
            project.mkdir()
            env = {
                **os.environ,
                "SHOGUNATE_PROJECT_REGISTRY": str(tmp_path / "projects.json"),
            }

            def run(*args: str) -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    ["python3", str(registry_script), *args],
                    cwd=ROOT,
                    env=env,
                    text=True,
                    capture_output=True,
                    check=False,
                )

            add = run("add", str(project), "--name", "demo", "--select")
            self.assertEqual(0, add.returncode, add.stdout + add.stderr)
            self.assertIn("registered", add.stdout)

            add_json = run("add", str(project), "--name", "demo", "--select", "--json")
            self.assertEqual(0, add_json.returncode, add_json.stdout + add_json.stderr)
            add_payload = json.loads(add_json.stdout)
            self.assertEqual("demo", add_payload["project"]["name"])
            self.assertEqual(str(project.resolve()), add_payload["project"]["path"])

            listing = run("list")
            self.assertEqual(0, listing.returncode, listing.stdout + listing.stderr)
            self.assertIn("* ", listing.stdout)
            self.assertIn("demo", listing.stdout)

            listing_json = run("list", "--json")
            self.assertEqual(0, listing_json.returncode, listing_json.stdout + listing_json.stderr)
            self.assertEqual("demo", json.loads(listing_json.stdout)["projects"][0]["name"])

            current = run("current", "--path")
            self.assertEqual(0, current.returncode, current.stdout + current.stderr)
            self.assertEqual(str(project.resolve()), current.stdout.strip())

            current_json = run("current", "--json")
            self.assertEqual(0, current_json.returncode, current_json.stdout + current_json.stderr)
            self.assertEqual("demo", json.loads(current_json.stdout)["project"]["name"])

            resolve = run("resolve", "@demo")
            self.assertEqual(0, resolve.returncode, resolve.stdout + resolve.stderr)
            self.assertEqual(str(project.resolve()), resolve.stdout.strip())

            resolve_json = run("resolve", "@demo", "--json")
            self.assertEqual(0, resolve_json.returncode, resolve_json.stdout + resolve_json.stderr)
            self.assertEqual(str(project.resolve()), json.loads(resolve_json.stdout)["path"])

            select_json = run("select", "demo", "--json")
            self.assertEqual(0, select_json.returncode, select_json.stdout + select_json.stderr)
            self.assertEqual("demo", json.loads(select_json.stdout)["project"]["name"])

            remove = run("remove", "demo")
            self.assertEqual(0, remove.returncode, remove.stdout + remove.stderr)
            self.assertIn("removed", remove.stdout)

            add_again = run("add", str(project), "--name", "demo", "--select", "--json")
            self.assertEqual(0, add_again.returncode, add_again.stdout + add_again.stderr)
            remove_json = run("remove", "demo", "--json")
            self.assertEqual(0, remove_json.returncode, remove_json.stdout + remove_json.stderr)
            self.assertEqual("demo", json.loads(remove_json.stdout)["removed"]["name"])

    def test_battlefield_api_lists_projects_and_tracks_app_sessions(self):
        registry_script = ROOT / "shogunate_mod" / "projects" / "registry.py"
        battlefield_script = ROOT / "shogunate_mod" / "battlefield" / "api.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            project = tmp_path / "project one"
            workspace = tmp_path / "workspaces"
            project.mkdir()
            env = {
                **os.environ,
                "SHOGUNATE_PROJECT_REGISTRY": str(tmp_path / "projects.json"),
                "SHOGUNATE_WORKSPACE_HOME": str(workspace),
            }
            add = subprocess.run(
                ["python3", str(registry_script), "add", str(project), "--name", "demo", "--select"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, add.returncode, add.stdout + add.stderr)

            listing = subprocess.run(
                ["python3", str(battlefield_script), "list", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, listing.returncode, listing.stdout + listing.stderr)
            payload = json.loads(listing.stdout)
            self.assertEqual("demo", payload["projects"][0]["name"])
            self.assertEqual("stopped", payload["projects"][0]["runtime"]["status"])

            create = subprocess.run(
                ["python3", str(battlefield_script), "session-create", "demo", "--title", "Mobile chat", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, create.returncode, create.stdout + create.stderr)
            session = json.loads(create.stdout)["session"]
            self.assertEqual("Mobile chat", session["title"])

            transcript = subprocess.run(
                ["python3", str(battlefield_script), "transcript", "demo", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, transcript.returncode, transcript.stdout + transcript.stderr)
            self.assertEqual(session["id"], json.loads(transcript.stdout)["session"])

    def test_battlefield_api_start_delegates_to_registered_project_runtime(self):
        registry_script = ROOT / "shogunate_mod" / "projects" / "registry.py"
        battlefield_script = ROOT / "shogunate_mod" / "battlefield" / "api.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            project = tmp_path / "project one"
            workspace = tmp_path / "workspaces"
            log = tmp_path / "fake-shogunate-args.json"
            fake = tmp_path / "fake-shogunate"
            project.mkdir()
            fake.write_text(
                "#!/usr/bin/env python3\n"
                "import json, pathlib, sys\n"
                f"pathlib.Path({str(log)!r}).write_text(json.dumps(sys.argv[1:]), encoding='utf-8')\n"
                "print('fake runtime started')\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            env = {
                **os.environ,
                "SHOGUNATE_PROJECT_REGISTRY": str(tmp_path / "projects.json"),
                "SHOGUNATE_WORKSPACE_HOME": str(workspace),
                "SHOGUNATE_COMMAND": str(fake),
            }
            add = subprocess.run(
                ["python3", str(registry_script), "add", str(project), "--name", "demo", "--select"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, add.returncode, add.stdout + add.stderr)

            start = subprocess.run(
                ["python3", str(battlefield_script), "start", "demo", "--resume", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, start.returncode, start.stdout + start.stderr)
            payload = json.loads(start.stdout)
            self.assertIn("fake runtime started", payload["stdout"])
            delegated_args = json.loads(log.read_text(encoding="utf-8"))
            self.assertEqual(["--project", f"@{payload['project']['id']}", "resume", "--no-attach"], delegated_args)

    def test_battlefield_api_queues_stopped_messages_and_flushes_on_start(self):
        registry_script = ROOT / "shogunate_mod" / "projects" / "registry.py"
        battlefield_script = ROOT / "shogunate_mod" / "battlefield" / "api.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            project = tmp_path / "project one"
            workspace = tmp_path / "workspaces"
            writer_log = tmp_path / "writer.log"
            project.mkdir()
            project_path = str(project.resolve())
            runtime = workspace / f"project-one-{hashlib.sha1(project_path.encode('utf-8')).hexdigest()[:8]}"
            fake = tmp_path / "fake-shogunate"
            fake.write_text(
                "#!/usr/bin/env python3\n"
                "import pathlib\n"
                f"runtime = pathlib.Path({str(runtime)!r})\n"
                f"writer_log = {str(writer_log)!r}\n"
                "writer = runtime / 'shogunate_mod' / 'inbox' / 'write.sh'\n"
                "writer.parent.mkdir(parents=True, exist_ok=True)\n"
                "writer.write_text(\"#!/usr/bin/env bash\\n\"\n"
                "                  \"printf '%s|%s|%s|%s\\\\n' \\\"$1\\\" \\\"$2\\\" \\\"$3\\\" \\\"$4\\\" >> '\" + writer_log + \"'\\n\",\n"
                "                  encoding='utf-8')\n"
                "writer.chmod(0o755)\n"
                "print('fake runtime started')\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            env = {
                **os.environ,
                "SHOGUNATE_PROJECT_REGISTRY": str(tmp_path / "projects.json"),
                "SHOGUNATE_WORKSPACE_HOME": str(workspace),
                "SHOGUNATE_COMMAND": str(fake),
            }
            add = subprocess.run(
                ["python3", str(registry_script), "add", str(project), "--name", "demo", "--select"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, add.returncode, add.stdout + add.stderr)

            send = subprocess.run(
                [
                    "python3",
                    str(battlefield_script),
                    "send",
                    "demo",
                    "hello from road",
                    "--role",
                    "shogun",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, send.returncode, send.stdout + send.stderr)
            send_payload = json.loads(send.stdout)
            self.assertTrue(send_payload["queued"])
            self.assertEqual(1, send_payload["project"]["sessions"]["pending_messages"])
            session_id = send_payload["session"]["id"]

            outbox = subprocess.run(
                ["python3", str(battlefield_script), "outbox", "demo", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, outbox.returncode, outbox.stdout + outbox.stderr)
            self.assertEqual(1, json.loads(outbox.stdout)["count"])

            start = subprocess.run(
                [
                    "python3",
                    str(battlefield_script),
                    "start",
                    "demo",
                    "--resume",
                    "--deliver-pending-timeout",
                    "0",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, start.returncode, start.stdout + start.stderr)
            start_payload = json.loads(start.stdout)
            self.assertEqual(1, start_payload["pending_delivery"]["delivered"])
            self.assertEqual(0, start_payload["pending_delivery"]["remaining"])
            self.assertIn(
                f"shogun|[session:{session_id}] hello from road|user_message|lord",
                writer_log.read_text(encoding="utf-8"),
            )

            transcript = subprocess.run(
                ["python3", str(battlefield_script), "transcript", "demo", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, transcript.returncode, transcript.stdout + transcript.stderr)
            messages = json.loads(transcript.stdout)["messages"]
            self.assertEqual("pending", messages[0]["delivery"])
            self.assertEqual("delivered", messages[-1]["delivery"])

            send_start = subprocess.run(
                [
                    "python3",
                    str(battlefield_script),
                    "send",
                    "demo",
                    "second message",
                    "--role",
                    "shogun",
                    "--start",
                    "--launch-probe-timeout",
                    "1",
                    "--deliver-pending-timeout",
                    "0",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, send_start.returncode, send_start.stdout + send_start.stderr)
            self.assertFalse(json.loads(send_start.stdout)["queued"])
            self.assertIn(
                f"shogun|[session:{session_id}] second message|user_message|lord",
                writer_log.read_text(encoding="utf-8"),
            )

    def test_package_bootstrap_wrapper_prefers_mod_source(self):
        text = (ROOT / "scripts" / "shogunate_package_bootstrap.sh").read_text(encoding="utf-8")
        local_delegate = 'exec bash "$SCRIPT_DIR/../shogunate_mod/package/bootstrap.sh" "$@"'
        remote_delegate = (
            'MOD_BOOTSTRAP_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/'
            '${REF}/shogunate_mod/package/bootstrap.sh"'
        )
        remote_exec = 'curl -fsSL "$MOD_BOOTSTRAP_URL" | bash -s -- "$@"'

        self.assertIn(local_delegate, text)
        self.assertIn(remote_delegate, text)
        self.assertIn(remote_exec, text)
        self.assertLess(text.index(local_delegate), text.index(remote_exec))
        self.assertNotIn("/scripts/shogunate_package_bootstrap.sh", text)

    def test_runtime_startup_uses_mod_canonical_helpers(self):
        text = (ROOT / "shogunate_mod" / "runtime" / "startup.sh").read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/configure/sync_opencode_config.py", text)
        self.assertIn("shogunate_mod/instructions/ensure_generated.sh", text)
        self.assertNotIn("scripts/sync_opencode_config.py", text)
        self.assertNotIn("scripts/ensure_generated_instructions.sh", text)

    def test_generated_instruction_freshness_tracks_mod_builder(self):
        text = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/instructions/build.sh", text)
        self.assertIn("shogunate_mod/instructions/ensure_generated.sh", text)
        self.assertNotIn("scripts/build_instructions.sh", text)

    def test_runtime_daemon_starts_mod_canonical_helpers(self):
        text = (ROOT / "shogunate_mod" / "runtime" / "daemon.sh").read_text(encoding="utf-8")
        normalized = text.replace('\\"', '"')

        self.assertIn('"$runtime_bash" "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh"', normalized)
        self.assertIn('python3 "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py"', normalized)
        self.assertIn('pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/inbox_watcher.sh "', normalized)
        self.assertNotIn('bash "$SCRIPT_DIR/scripts/watcher_supervisor.sh"', normalized)
        self.assertNotIn('python3 "$SCRIPT_DIR/scripts/gunkan_light_watch.py"', normalized)

    def test_runtime_state_cleanup_handles_mod_and_legacy_daemons(self):
        text = (ROOT / "shogunate_mod" / "runtime" / "state.sh").read_text(encoding="utf-8")

        self.assertIn('pkill -f "$SCRIPT_DIR/scripts/inbox_watcher.sh "', text)
        self.assertIn('pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/inbox_watcher.sh "', text)
        self.assertIn('pkill -f "$SCRIPT_DIR/scripts/gunkan_light_watch.py"', text)
        self.assertIn('pkill -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py"', text)

    def test_watcher_supervisor_starts_mod_canonical_helpers(self):
        text = (ROOT / "shogunate_mod" / "watcher" / "supervisor.sh").read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/cli/adapter.sh", text)
        self.assertIn("shogunate_mod/watcher/inbox_watcher.sh", text)
        self.assertIn("(scripts|shogunate_mod/watcher)/inbox_watcher", text)
        self.assertNotIn('source "$SCRIPT_DIR/lib/cli_adapter.sh"', text)
        self.assertNotIn('"$SCRIPT_DIR/scripts/inbox_watcher.sh" \\', text)

    def test_mod_runtime_helpers_call_mod_canonical_sources(self):
        checks = {
            "shogunate_mod/watcher/inbox_watcher.sh": [
                "shogunate_mod/cli/adapter.sh",
                "shogunate_mod/inbox/write.sh",
                "shogunate_mod/localapi/repl.py",
                "shogunate_mod/gunkan/codd_audit.py",
            ],
            "shogunate_mod/inbox/write.sh": [
                "shogunate_mod/inbox/write.sh",
                "shogunate_mod/gunkan/event_log.py",
            ],
            "shogunate_mod/notify/listener.sh": [
                "shogunate_mod/inbox/write.sh",
            ],
            "shogunate_mod/runtime/blocker.sh": [
                "shogunate_mod/inbox/write.sh",
            ],
            "shogunate_mod/configure/switch_cli.sh": [
                "shogunate_mod/cli/adapter.sh",
            ],
            "shogunate_mod/status/ratelimit_check.sh": [
                "shogunate_mod/status/agent_status.sh",
                "shogunate_mod/cli/adapter.sh",
            ],
            "shogunate_mod/status/command.sh": [
                "shogunate_mod/status/command.sh",
            ],
            "shogunate_mod/status/agent_status.sh": [
                "shogunate_mod/status/agent_status.sh",
            ],
            "shogunate_mod/git/branch_policy.sh": [
                "shogunate_mod/notify/send.sh",
            ],
            "shogunate_mod/configure/role_launcher.sh": [
                "shogunate_mod/configure/runtime_roles.py",
                "shogunate_mod/runtime/entrypoint.sh",
            ],
            "shogunate_mod/package/first_setup.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
                "shogunate_mod/runtime/runtime_launcher.sh",
                "shogunate_mod/runtime/shutsujin_launcher.sh",
                "shogunate_mod/runtime/setup_compat.sh",
                "shogunate_mod/shell/install_aliases.sh",
            ],
            "shogunate_mod/shell/aliases.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
                "shogunate_mod/view/focus_agent_pane.sh",
                "shogunate_mod/view/goza_no_ma.sh",
            ],
            "shogunate_mod/shell/install_aliases.sh": [
                "shogunate_mod/shell/aliases.sh",
            ],
            "shogunate_mod/runtime/summary.sh": [
                "shogunate_mod/view/focus_agent_pane.sh",
                "shogunate_mod/view/goza_no_ma.sh",
                "shogunate_mod/shell/aliases.sh",
                "shogunate_mod/shell/install_aliases.sh",
            ],
            "shogunate_mod/mobile/android/tools/setup_android_ssh.sh": [
                "shogunate_mod/pair/server.py",
            ],
            "shogunate_mod/hooks/stop_hook_inbox.sh": [
                "shogunate_mod/inbox/write.sh",
            ],
            "shogunate_mod/gunkan/emergency_stop.sh": [
                "shogunate_mod/inbox/write.sh",
            ],
            "shogunate_mod/gunkan/codd_check.sh": [
                "shogunate_mod/gunkan/codd_check.sh",
            ],
            "shogunate_mod/update/stop_and_apply_update.sh": [
                "shogunate_mod/update/stop_and_apply_update.sh",
            ],
            "shogunate_mod/runtime/mux_parity_smoke.sh": [
                "shogunate_mod/runtime/mux_parity_smoke.sh",
                "shogunate_mod/runtime/entrypoint.sh",
            ],
            "shogunate_mod/runtime/source_smoke.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
            ],
            "shogunate_mod/cli/adapter.sh": [
                "shogunate_mod/cli/antigravity_keyring.sh",
                "shogunate_mod/localapi/repl.py",
            ],
            "shogunate_mod/runtime/departure.sh": [
                "shogunate_mod/cli/adapter.sh",
                "shogunate_mod/package/first_setup.sh",
            ],
            "shogunate_mod/configure/agents.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
                "shogunate_mod/topology/adapter.sh",
                "shogunate_mod/localapi/repl.py",
            ],
            "shogunate_mod/git/setup_cron.sh": [
                "shogunate_mod/git/branch_drift_check.sh",
                "shogunate_mod/git/auto_merge_short_lived.sh",
            ],
            "shogunate_mod/gunkan/light_watch.py": [
                "shogunate_mod/gunkan/codd_audit.py",
            ],
            "shogunate_mod/runtime/android_compat.sh": [
                "shogunate_mod/runtime/android_tmux_proxy.py",
            ],
            "shogunate_mod/runtime/env.sh": [
                "shogunate_mod/shell/aliases.sh",
            ],
            "shogunate_mod/runtime/launch.sh": [
                "shogunate_mod/shell/aliases.sh",
                "shogunate_mod/package/first_setup.sh",
            ],
            "shogunate_mod/runtime/startup.sh": [
                "shogunate_mod/package/first_setup.sh",
            ],
            "shogunate_mod/runtime/shutsujin_launcher.sh": [
                "shogunate_mod/shell/aliases.sh",
            ],
            "shogunate_mod/runtime/runtime_launcher.sh": [
                "shogunate_mod/runtime/runtime_launcher.sh",
                "shogunate_mod/runtime/entrypoint.sh",
            ],
            "shogunate_mod/runtime/options.sh": [
                "shogunate_mod/configure/agents.sh",
                "shogunate_mod/view/focus_agent_pane.sh",
                "shogunate_mod/view/goza_no_ma.sh",
            ],
            "shogunate_mod/view/goza_no_ma.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
                "shogunate_mod/view/focus_agent_pane.sh",
                "shogunate_mod/view/goza_no_ma.sh",
            ],
            "shogunate_mod/view/focus_agent_pane.sh": [
                "shogunate_mod/runtime/entrypoint.sh",
                "shogunate_mod/view/focus_agent_pane.sh",
            ],
            "shogunate_mod/runtime/mcp_health_check.sh": [
                "shogunate_mod/configure/switch_cli.sh",
            ],
        }

        forbidden = [
            'SCRIPT_DIR}/lib/cli_adapter.sh',
            'PROJECT_ROOT}/lib/cli_adapter.sh',
            'ROOT_DIR}/lib/topology_adapter.sh',
            'SCRIPT_DIR}/scripts/inbox_write.sh',
            'project_root}/scripts/inbox_write.sh',
            'SCRIPT_DIR}/scripts/gunkan_event_log.py',
            'scripts/ensure_antigravity_keyring.sh',
            'scripts/localapi_repl.py',
            'scripts/gunkan_codd_audit.py',
            'scripts/branch_drift_check.sh',
            'scripts/auto_merge_short_lived.sh',
            'scripts/ntfy_send.sh',
            'scripts/ntfy.sh',
            'scripts/configure_runtime_roles.py',
            'scripts/install_shell_aliases.sh',
            'scripts/shogunate_pair_server.py',
            'scripts/focus_agent_pane.sh',
            'scripts/goza_no_ma.sh',
            'scripts/shell_aliases.sh',
            'scripts/install_shell_aliases.sh',
            'SCRIPT_DIR}/scripts/android_tmux_proxy.py',
            'scripts/switch_cli.sh',
            'scripts/configure_agents.sh',
            'scripts/inbox_watcher.sh',
            'scripts/gunkan_emergency_stop.sh',
            'scripts/codd_check.sh',
            'scripts/ratelimit_check.sh',
            'scripts/agent_status.sh',
            'scripts/stop_and_apply_update.sh',
            'scripts/mux_parity_smoke.sh',
            'source lib/agent_status.sh',
            'bash "$ROOT_DIR/shutsujin_departure.sh"',
            'bash shutsujin_departure.sh -c',
            'bash shutsujin_departure.sh -s',
            'bash shutsujin_departure.sh を実行',
            'bash first_setup.sh',
            'Run first_setup.sh first:',
            './shutsujin_departure.sh [オプション]',
            './shutsujin_departure.sh              #',
            '<shutsujin_departure.sh options>',
            '&& ./shutsujin_departure.sh',
        ]

        for rel, required in checks.items():
            with self.subTest(path=rel):
                text = (ROOT / rel).read_text(encoding="utf-8")
                for needle in required:
                    self.assertIn(needle, text)
                for needle in forbidden:
                    self.assertNotIn(needle, text)

        mux_parity_smoke = (ROOT / "shogunate_mod/runtime/mux_parity_smoke.sh").read_text(encoding="utf-8")
        self.assertIn("bash shogunate_mod/runtime/entrypoint.sh", mux_parity_smoke)
        self.assertNotIn("MAS_MULTIPLEXER=${mode} bash shutsujin_departure.sh", mux_parity_smoke)
        source_smoke = (ROOT / "shogunate_mod/runtime/source_smoke.sh").read_text(encoding="utf-8")
        self.assertIn("bash shogunate_mod/runtime/entrypoint.sh -s -c", source_smoke)
        self.assertNotIn("bash shutsujin_departure.sh -s -c", source_smoke)

    def test_representative_wrapper_smoke_cases_are_manifest_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        smoke_paths = [command[1] for command, _ in representative_wrapper_smoke_cases()]

        self.assertEqual(len(smoke_paths), len(set(smoke_paths)))
        for rel in smoke_paths:
            self.assertIn(rel, wrappers)
            self.assertTrue((ROOT / rel).exists(), f"missing representative wrapper smoke path: {rel}")


    def test_representative_wrapper_smoke_cases_have_mod_delegates(self):
        for command, _ in representative_wrapper_smoke_cases():
            rel = command[1]
            text = (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
            delegate_paths = wrapper_mod_delegate_paths(text)

            self.assertEqual(1, len(delegate_paths), f"{rel}: {delegate_paths}")
            self.assertTrue((ROOT / delegate_paths[0]).exists(), f"{rel} delegate missing: {delegate_paths[0]}")

    def test_representative_compatibility_wrappers_execute_mod_sources(self):
        for command, expected in representative_wrapper_smoke_cases():
            with self.subTest(command=command):
                result = subprocess.run(
                    command,
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                output = result.stdout + result.stderr
                self.assertEqual(0, result.returncode, output)
                self.assertIn(expected, output)

    def test_release_archive_representative_wrappers_execute_mod_sources(self):
        result = subprocess.run(
            ["git", "archive", "--worktree-attributes", "--format=tar", "HEAD"],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                "git archive failed:\n"
                f"STDOUT:\n{result.stdout.decode('utf-8', errors='replace')}\n"
                f"STDERR:\n{result.stderr.decode('utf-8', errors='replace')}"
            )
        with tempfile.TemporaryDirectory() as tmp:
            archive_root = Path(tmp)
            extract = subprocess.run(
                ["tar", "-xf", "-", "-C", str(archive_root)],
                input=result.stdout,
                capture_output=True,
                check=False,
            )
            if extract.returncode != 0:
                raise AssertionError(
                    "tar extraction failed:\n"
                    f"STDOUT:\n{extract.stdout.decode('utf-8', errors='replace')}\n"
                    f"STDERR:\n{extract.stderr.decode('utf-8', errors='replace')}"
                )
            for command, expected in representative_wrapper_smoke_cases():
                with self.subTest(command=command):
                    smoke = subprocess.run(
                        command,
                        cwd=archive_root,
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    output = smoke.stdout + smoke.stderr
                    self.assertEqual(0, smoke.returncode, output)
                    self.assertIn(expected, output)





    def test_manifest_paths_use_normalized_relative_forms(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        paths = (
            manifest_mapping_values(manifest, "canonical_paths")
            + manifest_list_values(manifest, "compatibility_wrappers")
            + manifest_core_touchpoint_paths(manifest)
        )
        invalid = []

        for rel in paths:
            normalized = rel.rstrip("/")
            path = ROOT / normalized
            if rel != rel.strip() or rel.startswith(("/", "./")) or "//" in rel:
                invalid.append(rel)
                continue
            if path.is_dir() and not rel.endswith("/"):
                invalid.append(f"{rel} (directory path must end with /)")
            if path.is_file() and rel.endswith("/"):
                invalid.append(f"{rel} (file path must not end with /)")

        self.assertEqual([], invalid)


    def test_manifest_nested_canonical_paths_are_limited_to_test_subsections(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        paths = manifest_mapping_values(manifest, "canonical_paths")
        unexpected_nested = []

        for rel in paths:
            normalized = rel.rstrip("/")
            for parent in paths:
                parent_normalized = parent.rstrip("/")
                if normalized == parent_normalized:
                    continue
                if not normalized.startswith(parent_normalized + "/"):
                    continue
                if normalized.startswith("shogunate_mod/tests/") and parent_normalized.startswith("shogunate_mod/tests"):
                    continue
                unexpected_nested.append(f"{rel} is nested under {parent}")

        self.assertEqual([], sorted(unexpected_nested))





    def test_mod_readme_documents_manifest_target_direction(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")

        self.assertEqual(
            manifest_list_values(manifest, "target_direction"),
            markdown_list_section_values(readme, "Direction"),
        )


    def test_manifest_mod_canonical_sources_are_not_gitignored(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        candidates = set()

        for rel in manifest_mapping_values(manifest, "canonical_paths"):
            if not rel.startswith("shogunate_mod/"):
                continue
            path = ROOT / rel.rstrip("/")
            if path.is_file():
                candidates.add(str(path.relative_to(ROOT)))
            elif path.is_dir():
                for child in path.rglob("*"):
                    if child.is_file():
                        candidates.add(str(child.relative_to(ROOT)))

        checked = sorted(
            rel
            for rel in candidates
            if not allowed_ignored_mod_artifact(rel)
        )
        result = subprocess.run(
            ["git", "check-ignore", "--no-index", "--stdin"],
            cwd=ROOT,
            input="\n".join(checked),
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertIn(result.returncode, (0, 1), result.stderr)
        self.assertEqual([], result.stdout.splitlines())

    def test_mod_readme_documents_source_directories(self):
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")
        missing = []

        for directory in sorted(path for path in (ROOT / "shogunate_mod").iterdir() if path.is_dir()):
            has_source_file = False
            for child in directory.rglob("*"):
                if not child.is_file():
                    continue
                rel_parts = child.relative_to(directory).parts
                if "__pycache__" in rel_parts:
                    continue
                if child.suffix in {".pyc", ".pyo"}:
                    continue
                has_source_file = True
                break
            if has_source_file and f"`{directory.name}/" not in readme:
                missing.append(directory.name)

        self.assertEqual([], missing)

    def test_mod_readme_boundary_directories_match_tracked_mod_sources(self):
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")
        result = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "shogunate_mod"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        tracked_dirs = sorted(
            {
                rel.split("/")[1]
                for rel in result.stdout.split("\0")
                if rel.startswith("shogunate_mod/")
                and len(rel.split("/")) > 2
                and (ROOT / rel).is_file()
            }
        )
        readme_dirs = sorted({path.split("/")[0] for path in mod_readme_boundary_paths(readme)})

        self.assertEqual(tracked_dirs, readme_dirs)

    def test_mod_readme_boundary_paths_are_manifest_canonical(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        missing = []

        for rel in mod_readme_boundary_paths(readme):
            mod_rel = f"shogunate_mod/{rel}"
            if not any(
                canonical_path.rstrip("/") == mod_rel
                or canonical_path.rstrip("/").startswith(mod_rel + "/")
                for canonical_path in canonical_paths
            ):
                missing.append(rel)

        self.assertEqual([], missing)

    def test_manifest_canonical_directories_have_mod_readme_boundaries(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")
        boundary_paths = mod_readme_boundary_paths(readme)
        missing = set()

        for rel in manifest_mapping_values(manifest, "canonical_paths"):
            normalized = rel.rstrip("/")
            prefix = "shogunate_mod/"
            if not normalized.startswith(prefix):
                continue
            mod_rel = normalized.removeprefix(prefix)
            if "/" not in mod_rel:
                continue
            root_dir = mod_rel.split("/", 1)[0]
            if not any(path == root_dir or path.startswith(root_dir + "/") for path in boundary_paths):
                missing.add(root_dir)

        self.assertEqual([], sorted(missing))








    def test_manifest_compatibility_wrappers_have_explicit_delegate_targets(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        missing_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            if not wrapper_mod_delegate_paths(text):
                missing_targets.append(rel)

        self.assertEqual([], missing_targets)

    def test_manifest_compatibility_wrapper_targets_are_in_executable_body(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        comment_only_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            all_targets = wrapper_mod_delegate_paths(text)
            body_targets = wrapper_mod_delegate_paths(non_comment_body(text))
            if all_targets != body_targets:
                comment_only_targets.append(f"{rel}: all={all_targets} body={body_targets}")

        self.assertEqual([], comment_only_targets)

    def test_manifest_compatibility_wrappers_have_single_delegate_target(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        multi_target_wrappers = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            delegate_paths = wrapper_mod_delegate_paths(text)
            if len(delegate_paths) != 1:
                multi_target_wrappers.append(f"{rel}: {delegate_paths}")

        self.assertEqual([], multi_target_wrappers)

    def test_manifest_compatibility_wrapper_targets_are_canonical_paths(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        missing_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            for mod_path in wrapper_mod_delegate_paths(text):
                if not manifest_canonical_paths_cover_path(canonical_paths, mod_path):
                    missing_targets.append(f"{rel} -> {mod_path}")

        self.assertEqual([], sorted(set(missing_targets)))

    def test_manifest_compatibility_wrapper_targets_have_readme_boundaries(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        readme = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")
        boundary_paths = mod_readme_boundary_paths(readme)
        missing_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            for mod_path in wrapper_mod_delegate_paths(text):
                mod_rel = mod_path.removeprefix("shogunate_mod/").rstrip("/")
                if not any(mod_rel == boundary or mod_rel.startswith(boundary.rstrip("/") + "/") for boundary in boundary_paths):
                    missing_targets.append(f"{rel} -> {mod_path}")

        self.assertEqual([], sorted(set(missing_targets)))

    def test_release_archive_includes_manifest_wrapper_delegate_targets(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()
        missing_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            for mod_path in wrapper_mod_delegate_paths(text):
                normalized = mod_path.rstrip("/")
                if not packed_files_cover_path(files, normalized):
                    missing_targets.append(f"{rel} -> {mod_path}")

        self.assertEqual([], sorted(set(missing_targets)))


    def test_root_mod_delegates_are_declared_as_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        missing = [rel for rel in root_mod_delegate_candidates() if rel not in wrappers]

        self.assertEqual([], missing)




    def test_development_branch_keeps_upstream_main_as_ancestor(self):
        upstream = subprocess.run(
            ["git", "rev-parse", "--verify", "upstream/main"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if upstream.returncode != 0:
            self.skipTest("upstream/main is not available in this checkout")

        ancestor = subprocess.run(
            ["git", "merge-base", "--is-ancestor", "upstream/main", "HEAD"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(0, ancestor.returncode, ancestor.stderr)

    def test_upstream_modified_root_code_like_files_are_classified_by_manifest(self):
        upstream = subprocess.run(
            ["git", "rev-parse", "--verify", "upstream/main"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if upstream.returncode != 0:
            self.skipTest("upstream/main is not available in this checkout")

        changed = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=ACMRT", "upstream/main...HEAD"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, changed.returncode, changed.stderr)
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        root_paths = manifest_core_touchpoint_paths(manifest) + manifest_list_values(
            manifest,
            "compatibility_wrappers",
        )
        changed_root_code_like = sorted(set(changed.stdout.splitlines()) & set(tracked_root_code_like_files()))
        missing = [
            rel
            for rel in changed_root_code_like
            if not manifest_root_paths_cover_path(root_paths, rel)
        ]

        self.assertEqual([], missing)

    def test_tracked_root_code_like_touchpoints_have_sync_or_generation_gate(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        ensure_generated = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        sync_pairs = prepublish_sync_pairs(prepublish)
        generated_targets = set(ensure_generated_targets(ensure_generated))
        missing = []

        def covered_by_sync(root_rel: str) -> bool:
            normalized = root_rel.rstrip("/")
            if root_rel.startswith("android/") and "require_android_sources_synced" in prepublish:
                return True
            for pair_root, _ in sync_pairs:
                pair_root_normalized = pair_root.rstrip("/")
                if (
                    normalized == pair_root_normalized
                    or normalized.startswith(pair_root_normalized + "/")
                    or pair_root_normalized.startswith(normalized + "/")
                ):
                    return True
            return False

        for rel in tracked_root_code_like_files():
            if rel in wrappers:
                continue
            if rel in generated_targets or covered_by_sync(rel):
                continue
            missing.append(rel)

        self.assertEqual([], missing)

    def test_root_shogunate_text_surfaces_have_sync_or_generation_gate(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        ensure_generated = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        sync_pairs = prepublish_sync_pairs(prepublish)
        generated_targets = set(ensure_generated_targets(ensure_generated))
        missing = []

        def covered_by_sync(root_rel: str) -> bool:
            normalized = root_rel.rstrip("/")
            if root_rel.startswith("android/") and "require_android_sources_synced" in prepublish:
                return True
            if (
                root_rel.startswith("instructions/")
                and not root_rel.startswith("instructions/generated/")
                and "require_instruction_sources_synced" in prepublish
            ):
                return True
            for pair_root, _ in sync_pairs:
                pair_root_normalized = pair_root.rstrip("/")
                if (
                    normalized == pair_root_normalized
                    or normalized.startswith(pair_root_normalized + "/")
                    or pair_root_normalized.startswith(normalized + "/")
                ):
                    return True
            return False

        for rel in root_shogunate_surface_candidates():
            if rel in wrappers:
                continue
            if rel in generated_targets or covered_by_sync(rel):
                continue
            missing.append(rel)

        self.assertEqual([], missing)

    def test_prepublish_sync_targets_are_tracked_by_manifest(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        root_paths = manifest_core_touchpoint_paths(manifest) + manifest_list_values(manifest, "compatibility_wrappers")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        missing_root_tracking = []
        missing_mod_tracking = []

        for root_rel, mod_rel in prepublish_sync_pairs(prepublish):
            if not manifest_root_paths_cover_path(root_paths, root_rel):
                missing_root_tracking.append(root_rel)
            if not manifest_canonical_paths_cover_path(canonical_paths, mod_rel):
                missing_mod_tracking.append(mod_rel)

        self.assertEqual([], sorted(set(missing_root_tracking)))
        self.assertEqual([], sorted(set(missing_mod_tracking)))

    def test_prepublish_sync_pairs_flow_from_root_compatibility_to_mod_source(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        reversed_or_unscoped = []

        for root_rel, mod_rel in prepublish_sync_pairs(prepublish):
            if root_rel.startswith("shogunate_mod/") or not mod_rel.startswith("shogunate_mod/"):
                reversed_or_unscoped.append(f"{root_rel} -> {mod_rel}")

        self.assertEqual([], sorted(reversed_or_unscoped))

    def test_prepublish_sync_pairs_are_declared_as_synchronized_touchpoints(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        synchronized_root_paths = []
        undeclared = []

        for item in manifest_core_touchpoints(manifest):
            if "synchronized" not in item.get("next_step", ""):
                continue
            synchronized_root_paths.extend(
                manifest_core_touchpoint_paths(f"current_core_touchpoints:\n  - path: {item['path']}")
            )

        for root_rel, mod_rel in prepublish_sync_pairs(prepublish):
            if not manifest_root_paths_cover_path(synchronized_root_paths, root_rel):
                undeclared.append(f"{root_rel} -> {mod_rel}")

        self.assertEqual([], sorted(undeclared))

    def test_prepublish_sync_pairs_do_not_duplicate_nested_roots(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        pairs = prepublish_sync_pairs(prepublish)
        nested = []

        for root_rel, mod_rel in pairs:
            root_norm = root_rel.rstrip("/")
            mod_norm = mod_rel.rstrip("/")
            for parent_root, parent_mod in pairs:
                parent_root_norm = parent_root.rstrip("/")
                parent_mod_norm = parent_mod.rstrip("/")
                if root_norm == parent_root_norm:
                    continue
                if root_norm.startswith(parent_root_norm + "/") and mod_norm.startswith(parent_mod_norm + "/"):
                    nested.append(f"{root_rel} -> {mod_rel} duplicates {parent_root} -> {parent_mod}")

        self.assertEqual([], sorted(nested))

    def test_prepublish_requires_manifest_mod_sources_in_head(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertIn("require_manifest_mod_sources_in_head()", prepublish)
        self.assertIn('"git", "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", "shogunate_mod"', prepublish)
        self.assertIn('manifest_mapping_values(manifest, "canonical_paths")', prepublish)
        self.assertIn("for dirpath, dirnames, filenames in os.walk(path):", prepublish)
        self.assertIn("dirnames[:] = [name for name in dirnames if name not in pruned_dirs]", prepublish)
        self.assertIn("expanded_dirs = set()", prepublish)
        self.assertIn("normalized.startswith(parent + \"/\")", prepublish)
        self.assertIn('".android-sdk"', prepublish)
        self.assertIn("manifest MOD canonical sources must be present in HEAD", prepublish)
        self.assertIn("manifest MOD canonical source files are missing from HEAD", prepublish)
        self.assertIn("Commit the listed shogunate_mod sources before creating a release archive", prepublish)
        self.assertLess(
            prepublish.index("require_manifest_mod_sources_in_head"),
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
        )
        self.assertLess(
            prepublish.index("require_manifest_mod_sources_in_head"),
            prepublish.index('dirty="$(git status --short || true)"'),
        )

    def test_prepublish_requires_upstream_main_in_ci(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertIn("require_upstream_main_in_ci()", prepublish)
        self.assertIn('if [[ "${CI:-}" != "true" ]]; then', prepublish)
        self.assertIn("git rev-parse --verify upstream/main", prepublish)
        self.assertIn("CI prepublish check requires upstream/main", prepublish)
        self.assertLess(
            prepublish.index("require_upstream_main_in_ci"),
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
        )
        self.assertLess(
            prepublish.index("require_upstream_main_in_ci"),
            prepublish.index('dirty="$(git status --short || true)"'),
        )

    def test_runtime_cleanup_uses_exact_tmux_session_targets(self):
        state = (ROOT / "shogunate_mod" / "runtime" / "state.sh").read_text(encoding="utf-8")
        android_compat = (ROOT / "shogunate_mod" / "runtime" / "android_compat.sh").read_text(encoding="utf-8")

        self.assertIn('tmux has-session -t "=$1"', state)
        self.assertIn('tmux kill-session -t "=$1"', state)
        self.assertIn("tmux_has_session_exact shogun", state)
        self.assertIn("tmux_kill_session_exact shogun", state)
        self.assertIn("tmux_kill_session_exact multiagent", state)
        self.assertIn("tmux kill-session -t '=shogun'", android_compat)
        self.assertIn("tmux kill-session -t '=multiagent'", android_compat)
        for unsafe in (
            "tmux kill-session -t shogun",
            "tmux kill-session -t gunkan",
            "tmux kill-session -t gunshi",
            "tmux kill-session -t multiagent",
            "tmux has-session -t shogun",
        ):
            self.assertNotIn(unsafe, state)
            self.assertNotIn(unsafe, android_compat)


    def test_synchronized_core_touchpoints_are_covered_by_prepublish_sync(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        sync_pairs = prepublish_sync_pairs(prepublish)
        missing = []

        special_sync_tokens = {
            "android/": "require_android_sources_synced",
        }

        def root_path_covered(root_path: str) -> bool:
            normalized = root_path.rstrip("/")
            special_token = special_sync_tokens.get(root_path)
            if special_token and special_token in prepublish:
                return True
            for pair_root, _ in sync_pairs:
                pair_root_normalized = pair_root.rstrip("/")
                if (
                    normalized == pair_root_normalized
                    or normalized.startswith(pair_root_normalized + "/")
                    or pair_root_normalized.startswith(normalized + "/")
                ):
                    return True
            return False

        for item in manifest_core_touchpoints(manifest):
            if "synchronized" not in item.get("next_step", ""):
                continue
            for root_path in manifest_core_touchpoint_paths(f"current_core_touchpoints:\n  - path: {item['path']}"):
                if not root_path_covered(root_path):
                    missing.append(root_path)

        self.assertEqual([], sorted(set(missing)))


























    def test_release_archive_includes_all_manifest_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()
        missing = [
            rel
            for rel in manifest_list_values(manifest, "compatibility_wrappers")
            if rel.rstrip("/") not in files
        ]

        self.assertEqual([], missing)


    def test_package_top_level_file_surface_is_declared_by_manifest(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertEqual(
            [],
            sorted(set(expected_top_level_runtime_file_surface(manifest)) - set(manifest_declared_root_files(manifest))),
        )

    def test_manifest_top_level_file_touchpoints_excluded_from_package_surface_are_explicit(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertEqual(
            [".gitattributes", ".gitignore", ".gitmodules"],
            sorted(
                set(manifest_current_top_level_file_touchpoints(manifest))
                - set(expected_top_level_runtime_file_surface(manifest))
            ),
        )


    def test_package_root_directory_surface_is_declared_by_manifest(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertEqual(
            [],
            sorted(set(expected_root_runtime_directory_surface()) - set(manifest_declared_root_directories(manifest))),
        )

    def test_manifest_directory_touchpoints_excluded_from_package_surface_are_explicit(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertEqual(
            ["android", "images", "reports", "tests"],
            sorted(
                set(manifest_current_directory_touchpoint_roots(manifest))
                - set(expected_root_runtime_directory_surface())
            ),
        )




    def test_release_archive_generated_root_files_are_freshness_targets(self):
        files = release_archive_files()
        archived_generated_root_files = sorted(
            rel
            for rel in generated_root_touchpoint_files()
            if rel in files
        )

        self.assertEqual(generated_root_touchpoint_files(), archived_generated_root_files)




    def test_makefile_has_mod_canonical_copy(self):
        root_makefile = (ROOT / "Makefile").read_bytes()
        mod_makefile = (ROOT / "shogunate_mod" / "development" / "Makefile").read_bytes()
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_makefile, mod_makefile)
        text = mod_makefile.decode("utf-8")
        self.assertIn("shogunate_mod/instructions/build.sh", text)
        self.assertIn("shogunate_mod/gunkan/codd_check.sh gunkan", text)
        self.assertIn("Run shellcheck on shogunate_mod/, lib/, and scripts/", text)
        self.assertIn("find shogunate_mod -path shogunate_mod/tests -prune -o -name '*.sh' -type f -exec shellcheck {} \\;", text)
        self.assertNotIn("bash scripts/build_instructions.sh", text)
        self.assertNotIn("bash scripts/codd_check.sh", text)
        self.assertIn("mod-check", text)
        self.assertIn("structure-check", text)
        self.assertIn("mod-check: structure-check upstream-overlay-smoke package-check package-curl-smoke source-smoke android-check", text)
        self.assertIn("upstream-overlay-smoke", text)
        self.assertIn("bash shogunate_mod/runtime/upstream_overlay_smoke.sh", text)
        self.assertIn("test_manifest_compatibility_wrappers_stay_thin", text)
        self.assertIn("test_tracked_root_code_like_files_are_classified_by_manifest", text)
        self.assertIn("package-check", text)
        self.assertIn("bash shogunate_mod/package/prepublish_check.sh", text)
        self.assertIn("package-curl-smoke", text)
        self.assertIn("SHOGUNATE_PACKAGE_CURL_SMOKE_PACKAGE", text)
        self.assertIn("test -f \"$$package\"", text)
        self.assertIn("SHOGUNATE_PACKAGE_URL=\"file://$$package\"", text)
        self.assertIn("curl -fsSL \"file://$$root/shogunate_mod/package/bootstrap.sh\"", text)
        self.assertIn("\"$$bin/shogunate\" --project \"$$project\" where", text)
        self.assertIn("\"$$bin/shogunate\" --project \"$$project\" pair --help", text)
        self.assertIn("source-smoke", text)
        self.assertIn("bash shogunate_mod/runtime/source_smoke.sh", text)
        self.assertIn("android-check", text)
        self.assertIn("cd android && ./gradlew --no-daemon", text)
        self.assertIn("testDebugUnitTest assembleDebug", text)
        self.assertIn("test-int", text)
        self.assertIn(
            "require_same_file Makefile shogunate_mod/development/Makefile",
            prepublish,
        )

    def test_development_and_github_metadata_have_mod_canonical_copy(self):
        root_gitmodules = (ROOT / ".gitmodules").read_text(encoding="utf-8")
        mod_gitmodules = (ROOT / "shogunate_mod" / "development" / "gitmodules").read_text(encoding="utf-8")
        root_funding = (ROOT / ".github" / "FUNDING.yml").read_text(encoding="utf-8")
        mod_funding = (ROOT / "shogunate_mod" / "github" / "FUNDING.yml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_gitmodules, mod_gitmodules)
        self.assertIn("tests/test_helper/bats-assert", mod_gitmodules)
        self.assertIn("tests/test_helper/bats-support", mod_gitmodules)
        self.assertEqual(root_funding, mod_funding)
        self.assertIn("github:", mod_funding)
        self.assertIn(
            "require_same_file .gitmodules shogunate_mod/development/gitmodules",
            prepublish,
        )
        self.assertIn(
            "require_same_file .github/FUNDING.yml shogunate_mod/github/FUNDING.yml",
            prepublish,
        )

    def test_public_readmes_have_mod_canonical_copy(self):
        root_readme = (ROOT / "README.md").read_text(encoding="utf-8")
        root_readme_ja = (ROOT / "README_ja.md").read_text(encoding="utf-8")
        mod_readme = (ROOT / "shogunate_mod" / "docs" / "README.md").read_text(encoding="utf-8")
        mod_readme_ja = (ROOT / "shogunate_mod" / "docs" / "README_ja.md").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        readmes = {
            "README.md": root_readme,
            "README_ja.md": root_readme_ja,
            "shogunate_mod/docs/README.md": mod_readme,
            "shogunate_mod/docs/README_ja.md": mod_readme_ja,
        }
        latest_curl = (
            "curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/"
            "multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash"
        )
        pinned_curl = re.compile(
            r"curl -fsSL https://raw\.githubusercontent\.com/TsukinowaRin/"
            r"multi-agent-shognate/(v[0-9]+(?:\.[0-9]+)+)/"
            r"scripts/shogunate_package_bootstrap\.sh \| bash -s -- --version "
            r"(v[0-9]+(?:\.[0-9]+)+)"
        )

        self.assertEqual(root_readme, mod_readme)
        self.assertEqual(root_readme_ja, mod_readme_ja)
        self.assertIn("curl -fsSL", mod_readme)
        self.assertIn("shogunate pair", mod_readme)
        self.assertIn("cd /path/to/your-project", mod_readme)
        self.assertIn("curl -fsSL", mod_readme_ja)
        self.assertIn("shogunate pair", mod_readme_ja)
        self.assertIn("cd /path/to/your-project", mod_readme_ja)
        for path, text in readmes.items():
            self.assertIn("Shogunate MOD canonical sources", text, path)
            self.assertIn("legacy scripts/*, lib/*", text, path)
            self.assertTrue(
                "delegate into shogunate_mod/" in text or "shogunate_mod/ へ委譲" in text,
                path,
            )
            self.assertIn("shogunate_mod/\n    app/", text, path)
            self.assertIn("    battlefield/", text, path)
            self.assertIn("    gunkan/", text, path)
            self.assertIn("    watcher/", text, path)
            self.assertIn("    view/", text, path)
            self.assertNotIn("scripts/gunkan_*.py", text, path)
            self.assertNotIn("scripts/gunkan_emergency_stop.sh", text, path)
            self.assertIn("shogunate_mod/cli/antigravity_keyring.sh", text, path)
            self.assertIn("shogunate_mod/instructions/ensure_generated.sh", text, path)
            self.assertIn("bash shogunate_mod/package/first_setup.sh", text, path)
            self.assertIn("bash shogunate_mod/runtime/entrypoint.sh", text, path)
            self.assertNotIn("scripts/ensure_antigravity_keyring.sh", text, path)
            self.assertNotIn("scripts/ensure_generated_instructions.sh", text, path)
            self.assertNotIn("bash first_setup.sh", text, path)
            self.assertNotIn("bash shutsujin_departure.sh", text, path)
            self.assertIn("make package-check", text, path)
            self.assertNotIn("bash -n scripts/shogunate_package_bootstrap.sh shutsujin_departure.sh", text, path)
        pinned_tags = set()
        for path, text in readmes.items():
            self.assertIn(latest_curl, text, path)
            matches = pinned_curl.findall(text)
            self.assertGreaterEqual(len(matches), 1, f"missing pinned release cURL in {path}")
            for url_tag, version_arg in matches:
                self.assertEqual(url_tag, version_arg, f"pinned cURL tag/version mismatch in {path}")
                pinned_tags.add(url_tag)
        self.assertEqual(
            len(pinned_tags),
            1,
            f"public README pinned release tags must stay synchronized: {sorted(pinned_tags)}",
        )
        self.assertIn(
            "require_same_file README.md shogunate_mod/docs/README.md",
            prepublish,
        )
        self.assertIn(
            "require_same_file README_ja.md shogunate_mod/docs/README_ja.md",
            prepublish,
        )
        self.assertIn(
            "require_same_file docs/philosophy.md shogunate_mod/docs/philosophy.md",
            prepublish,
        )

    def test_docs_index_uses_mod_canonical_gunkan_helpers(self):
        index = (ROOT / "docs" / "INDEX.md").read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/gunkan/codd_audit.py", index)
        self.assertIn("shogunate_mod/gunkan/light_watch.py", index)
        self.assertNotIn("scripts/gunkan_codd_audit.py 経由", index)
        self.assertNotIn("scripts/gunkan_light_watch.py", index)

    def test_mod_readme_describes_configure_canonical_sources(self):
        text = (ROOT / "shogunate_mod" / "README.md").read_text(encoding="utf-8")

        for required in (
            "shogunate_mod/configure/agents.sh",
            "shogunate_mod/configure/runtime_roles.py",
            "shogunate_mod/configure/sync_opencode_config.py",
            "shogunate_mod/configure/switch_cli.sh",
            "compatibility wrappers only",
        ):
            self.assertIn(required, text)
        for forbidden in (
            "`scripts/configure_agents.sh`",
            "`scripts/configure_runtime_roles.py`",
            "`scripts/sync_opencode_config.py`",
            "`scripts/switch_cli.sh`",
        ):
            self.assertNotIn(forbidden, text)


    def test_codd_config_has_mod_canonical_copy(self):
        root_codd = (ROOT / ".codd" / "codd.yaml").read_text(encoding="utf-8")
        mod_codd = (ROOT / "shogunate_mod" / "gunkan" / "codd.yaml").read_text(encoding="utf-8")
        self.assertEqual(root_codd, mod_codd)
        self.assertIn('- "shogunate_mod/"', mod_codd)
        self.assertIn("find shogunate_mod scripts lib -name '*.sh' -print0 | xargs -0 bash -n", mod_codd)
        self.assertNotIn('typecheck_command: "bash -n shutsujin_departure.sh scripts/*.sh lib/*.sh"', mod_codd)

    def test_codd_docs_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        root_docs = sorted((ROOT / "docs" / "codd").glob("*.md"))

        self.assertGreaterEqual(len(root_docs), 4)
        for root_path in root_docs:
            rel = root_path.relative_to(ROOT / "docs" / "codd")
            mod_path = ROOT / "shogunate_mod" / "gunkan" / "docs" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD CoDD doc: {rel}")
            root_text = root_path.read_text(encoding="utf-8")
            mod_text = mod_path.read_text(encoding="utf-8")
            self.assertEqual(root_text, mod_text, f"CoDD doc differs: {rel}")

        combined = "\n".join(path.read_text(encoding="utf-8") for path in root_docs)
        for forbidden in (
            '"scripts/gunkan_codd_audit.py"',
            '"scripts/gunkan_light_watch.py"',
            '"scripts/watcher_supervisor.sh"',
            "`scripts/gunkan_codd_audit.py`",
            "`scripts/gunkan_light_watch.py`",
        ):
            self.assertNotIn(forbidden, combined)
        for required in (
            '"shogunate_mod/gunkan/codd_audit.py"',
            '"shogunate_mod/gunkan/light_watch.py"',
            '"shogunate_mod/watcher/supervisor.sh"',
            '"shogunate_mod/runtime/entrypoint.sh"',
            "`shogunate_mod/gunkan/codd_audit.py`",
            "`shogunate_mod/gunkan/light_watch.py`",
        ):
            self.assertIn(required, combined)
        self.assertIn("require_directory_files_synced docs/codd shogunate_mod/gunkan/docs", prepublish)

    def test_gunkan_audit_tests_run_mod_light_watch(self):
        for rel in ("tests/unit/test_gunkan_audit.bats", "shogunate_mod/tests/unit/test_gunkan_audit.bats"):
            with self.subTest(path=rel):
                text = (ROOT / rel).read_text(encoding="utf-8")
                self.assertIn("$PROJECT_ROOT/shogunate_mod/gunkan/light_watch.py", text)
                self.assertNotIn("$PROJECT_ROOT/scripts/gunkan_light_watch.py", text)

    def test_gitleaks_config_has_mod_canonical_copy(self):
        root_gitleaks = (ROOT / ".gitleaks.toml").read_text(encoding="utf-8")
        mod_gitleaks = (ROOT / "shogunate_mod" / "security" / "gitleaks.toml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_gitleaks, mod_gitleaks)
        self.assertIn("ntfy-topic-name", mod_gitleaks)
        self.assertIn("openai-api-key", mod_gitleaks)
        self.assertIn(
            "require_same_file .gitleaks.toml shogunate_mod/security/gitleaks.toml",
            prepublish,
        )

    def test_opencode_permissions_have_mod_canonical_copy(self):
        root_permissions = (ROOT / "config" / "opencode-permissions.yaml").read_text(encoding="utf-8")
        mod_permissions = (
            ROOT / "shogunate_mod" / "configure" / "opencode-permissions.yaml"
        ).read_text(encoding="utf-8")
        build_script = (ROOT / "shogunate_mod" / "instructions" / "build.sh").read_text(encoding="utf-8")
        self.assertEqual(without_header_comment(root_permissions), without_header_comment(mod_permissions))
        self.assertNotEqual(root_permissions.splitlines()[:5], mod_permissions.splitlines()[:5])
        self.assertIn("shogunate_mod/configure/opencode-permissions.yaml", build_script)
        self.assertIn("config/opencode-permissions.yaml", build_script)

    def test_opencode_tui_config_has_mod_canonical_copy(self):
        root_tui = json.loads((ROOT / "config" / "opencode-tui.json").read_text(encoding="utf-8"))
        mod_tui = json.loads(
            (ROOT / "shogunate_mod" / "configure" / "opencode-tui.json").read_text(encoding="utf-8")
        )
        adapter = (ROOT / "shogunate_mod" / "cli" / "adapter.sh").read_text(encoding="utf-8")
        self.assertEqual(root_tui, mod_tui)
        self.assertIn("shogunate_mod/configure/opencode-tui.json", adapter)


    def test_android_rate_limit_check_prefers_mod_canonical_status_script(self):
        root_viewmodel = (
            ROOT / "android/app/src/main/java/com/shogun/android/viewmodel/AgentsViewModel.kt"
        ).read_text(encoding="utf-8")
        mod_viewmodel = (
            ROOT
            / "shogunate_mod/mobile/android/app/src/main/java/com/shogun/android/viewmodel/AgentsViewModel.kt"
        ).read_text(encoding="utf-8")

        for text in (root_viewmodel, mod_viewmodel):
            self.assertIn("shogunate_mod/status/ratelimit_check.sh", text)
            self.assertIn("scripts/ratelimit_check.sh", text)
            self.assertLess(
                text.index("shogunate_mod/status/ratelimit_check.sh"),
                text.index("scripts/ratelimit_check.sh"),
            )
            self.assertIn('timeout 12s bash \\"\\$rate_limit_script\\"', text)

    def test_android_readmes_use_mod_runtime_entrypoint(self):
        paths = [
            ROOT / "android/README.md",
            ROOT / "android/README_ja.md",
            ROOT / "shogunate_mod/mobile/android/README.md",
            ROOT / "shogunate_mod/mobile/android/README_ja.md",
        ]

        for path in paths:
            with self.subTest(path=str(path.relative_to(ROOT))):
                text = path.read_text(encoding="utf-8")
                self.assertIn("shogunate_mod/runtime/entrypoint.sh", text)
                self.assertNotIn("via `shutsujin_departure.sh`", text)
                self.assertNotIn("`shutsujin_departure.sh` でtmux", text)

    def test_default_config_templates_are_mod_owned(self):
        first_setup = (ROOT / "shogunate_mod" / "package" / "first_setup.sh").read_text(encoding="utf-8")
        requirements = (
            ROOT / "shogunate_mod" / "package" / "requirements.txt"
        ).read_text(encoding="utf-8")
        settings_template = (
            ROOT / "shogunate_mod" / "configure" / "settings.yaml.sample"
        ).read_text(encoding="utf-8")
        projects_template = (
            ROOT / "shogunate_mod" / "configure" / "projects.yaml.sample"
        ).read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/configure/settings.yaml.sample", first_setup)
        self.assertIn("shogunate_mod/configure/projects.yaml.sample", first_setup)
        self.assertIn("shogunate_mod/package/requirements.txt", first_setup)
        self.assertIn("REQUIREMENTS_FILE=\"$SCRIPT_DIR/requirements.txt\"", first_setup)
        self.assertIn("pyyaml", requirements.lower())
        self.assertIn("create_config_from_template", first_setup)
        self.assertIn("active_ashigaru:", settings_template)
        self.assertIn("shared_auth_file: .shogunate/codex/shared/auth.json", settings_template)
        self.assertIn("current_project: sample_project", projects_template)

    def test_context_readme_has_mod_canonical_copy(self):
        root_context = (ROOT / "context" / "README.md").read_text(encoding="utf-8")
        mod_context = (ROOT / "shogunate_mod" / "context" / "README.md").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_context, mod_context)
        self.assertIn("プロジェクト固有のコンテキスト", mod_context)
        self.assertIn(
            "require_same_file context/README.md shogunate_mod/context/README.md",
            prepublish,
        )


    def test_instruction_sources_have_mod_canonical_copy(self):
        build_script = (ROOT / "shogunate_mod" / "instructions" / "build.sh").read_text(encoding="utf-8")
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )
        source_root = ROOT / "shogunate_mod" / "instructions" / "source"
        root_files = sorted(
            path
            for path in (ROOT / "instructions").rglob("*.md")
            if "generated" not in path.relative_to(ROOT / "instructions").parts
        )

        self.assertIn("DEFAULT_SOURCE_DIR=\"$ROOT_DIR/shogunate_mod/instructions/source\"", build_script)
        self.assertIn("FALLBACK_SOURCE_DIR=\"$ROOT_DIR/instructions\"", build_script)
        self.assertIn("DEFAULT_AUTOLOAD_DIR=\"$ROOT_DIR/shogunate_mod/instructions/autoload\"", build_script)
        self.assertIn("DEFAULT_SOURCE_DIR=\"${ROOT_DIR}/shogunate_mod/instructions/source\"", ensure_script)
        self.assertIn("DEFAULT_AUTOLOAD_DIR=\"${ROOT_DIR}/shogunate_mod/instructions/autoload\"", ensure_script)
        self.assertIn("find \"${SOURCE_DIR}\" -type f", ensure_script)
        self.assertIn("printf '%s\\n' \"${AUTOLOAD_CLAUDE_MD}\"", ensure_script)
        self.assertIn("shogunate_mod/configure/opencode-permissions.yaml", ensure_script)
        self.assertIn('"AGENTS.md"', ensure_script)
        self.assertIn('".github/copilot-instructions.md"', ensure_script)
        self.assertIn('"agents/default/system.md"', ensure_script)
        self.assertIn('".opencode/agents/shogun.md"', ensure_script)
        self.assertIn('".opencode/agents/ashigaru8.md"', ensure_script)

        # Claude Code reads the five top-level role files; build.sh publishes the
        # claude build output there (role + harness + common + claude_tools), so
        # they must match instructions/generated/ instead of the front-matter
        # donor monolith under shogunate_mod/instructions/source/.
        published_claude_roles = {"shogun.md", "karo.md", "ashigaru.md", "gunshi.md", "gunkan.md"}
        for root_path in root_files:
            rel = root_path.relative_to(ROOT / "instructions")
            if str(rel) in published_claude_roles:
                generated_path = ROOT / "instructions" / "generated" / str(rel)
                self.assertTrue(
                    generated_path.exists(), f"missing generated claude instruction: {generated_path}"
                )
                self.assertEqual(
                    root_path.read_text(encoding="utf-8"),
                    generated_path.read_text(encoding="utf-8"),
                    f"published claude instruction differs from generated build: {rel}",
                )
                continue
            mod_path = source_root / rel
            self.assertTrue(mod_path.exists(), f"missing MOD instruction source: {mod_path}")
            self.assertEqual(
                root_path.read_text(encoding="utf-8"),
                mod_path.read_text(encoding="utf-8"),
                f"instruction source compatibility copy differs: {rel}",
            )


    def test_release_archive_root_instructions_are_mod_source_or_freshness_targets(self):
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )
        files = release_archive_files()
        source_files = set()
        for path in (ROOT / "instructions").rglob("*.md"):
            rel = path.relative_to(ROOT / "instructions")
            if "generated" in rel.parts:
                continue
            source_files.add(str(path.relative_to(ROOT)))

        archived_instruction_files = sorted(path for path in files if path.startswith("instructions/"))
        unexpected = []
        missing_freshness_targets = []
        for rel in archived_instruction_files:
            if not rel.endswith(".md"):
                continue
            if rel in source_files:
                continue
            if rel.startswith("instructions/generated/"):
                if f'"{rel}"' not in ensure_script:
                    missing_freshness_targets.append(rel)
                continue
            unexpected.append(rel)

        self.assertEqual([], unexpected)
        self.assertEqual([], missing_freshness_targets)

    def test_generated_root_touchpoints_are_freshness_targets(self):
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertIn("  - path: AGENTS.md", manifest)
        self.assertIn("  - path: .github/copilot-instructions.md", manifest)
        self.assertIn("  - path: agents/default/", manifest)
        self.assertIn("  - path: .opencode/agents/", manifest)
        for rel in generated_root_touchpoint_files():
            self.assertIn(f'"{rel}"', ensure_script, f"missing generated freshness target: {rel}")

    def test_generated_freshness_targets_are_manifest_classified(self):
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        root_paths = manifest_core_touchpoint_paths(manifest)
        missing_manifest_classification = []
        missing_files = []

        for rel in ensure_generated_targets(ensure_script):
            if not (ROOT / rel).is_file():
                missing_files.append(rel)
            if not manifest_root_paths_cover_path(root_paths, rel):
                missing_manifest_classification.append(rel)

        self.assertEqual([], missing_files)
        self.assertEqual([], missing_manifest_classification)

    def test_generated_opencode_agents_identify_mod_instruction_sources(self):
        build_script = (ROOT / "shogunate_mod" / "instructions" / "build.sh").read_text(encoding="utf-8")
        agent_files = sorted((ROOT / ".opencode" / "agents").glob("*.md"))

        self.assertIn(
            "Source: shogunate_mod/instructions/source/roles/${role}_role.md",
            build_script,
        )
        self.assertGreaterEqual(len(agent_files), 15)
        for path in agent_files:
            text = path.read_text(encoding="utf-8")
            self.assertIn(
                "# Source: shogunate_mod/instructions/source/roles/",
                text,
                f"generated OpenCode agent does not point at MOD role source: {path}",
            )
            self.assertIn("shogunate_mod/instructions/source/common/*", text)
            self.assertIn("shogunate_mod/instructions/source/cli_specific/opencode_tools.md", text)
            self.assertNotIn("# Source: instructions/roles/", text)

    def test_cli_skills_have_mod_canonical_copy(self):
        first_setup = (ROOT / "shogunate_mod" / "package" / "first_setup.sh").read_text(encoding="utf-8")
        root_skill_files = sorted(
            path
            for path in (ROOT / "skills").rglob("*")
            if path.is_file() and ".system" not in path.relative_to(ROOT / "skills").parts
        )
        cursor_skill_files = sorted(
            path for path in (ROOT / ".cursor" / "skills").rglob("*") if path.is_file()
        )

        self.assertIn("SKILLS_SOURCE_DIR=\"$SCRIPT_DIR/shogunate_mod/skills/claude\"", first_setup)
        self.assertIn("SKILLS_SOURCE_DIR=\"$SCRIPT_DIR/skills\"", first_setup)
        self.assertGreaterEqual(len(root_skill_files), 8)
        for root_path in root_skill_files:
            rel = root_path.relative_to(ROOT / "skills")
            mod_path = ROOT / "shogunate_mod" / "skills" / "claude" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD Claude skill: {rel}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"Claude skill differs: {rel}")

        self.assertGreaterEqual(len(cursor_skill_files), 1)
        for root_path in cursor_skill_files:
            rel = root_path.relative_to(ROOT / ".cursor" / "skills")
            mod_path = ROOT / "shogunate_mod" / "skills" / "cursor" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD Cursor skill: {rel}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"Cursor skill differs: {rel}")

        skill_texts = {
            str(path.relative_to(ROOT)): path.read_text(encoding="utf-8")
            for path in [*root_skill_files, *cursor_skill_files]
        }
        forbidden_root_skill_commands = [
            "Bash(bash scripts/switch_cli.sh",
            "bash scripts/switch_cli.sh",
            "bash scripts/inbox_write.sh",
            "bash scripts/agent_status.sh",
            "source lib/cli_adapter.sh",
            "`scripts/switch_cli.sh`",
            "`lib/cli_adapter.sh`",
            "`scripts/inbox_watcher.sh`",
        ]
        required_mod_skill_commands = [
            "bash shogunate_mod/configure/switch_cli.sh",
            "bash shogunate_mod/inbox/write.sh",
            "bash shogunate_mod/status/command.sh",
            "source shogunate_mod/cli/adapter.sh",
            "`shogunate_mod/configure/switch_cli.sh`",
            "`shogunate_mod/cli/adapter.sh`",
            "`shogunate_mod/watcher/inbox_watcher.sh`",
        ]
        combined_skill_text = "\n".join(skill_texts.values())
        for forbidden in forbidden_root_skill_commands:
            for path, text in skill_texts.items():
                self.assertNotIn(forbidden, text, path)
        for required in required_mod_skill_commands:
            self.assertIn(required, combined_skill_text)


    def test_test_support_files_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        def is_synced_test_file(path: Path) -> bool:
            rel_parts = path.relative_to(ROOT / "tests").parts
            if "__pycache__" in rel_parts:
                return False
            if path.suffix in {".pyc", ".pyo"}:
                return False
            return not (
                len(rel_parts) >= 2
                and rel_parts[0] == "test_helper"
                and rel_parts[1] in {"bats-assert", "bats-support"}
            )

        root_test_files = sorted(
            path
            for path in (ROOT / "tests").rglob("*")
            if path.is_file() and is_synced_test_file(path)
        )

        self.assertGreaterEqual(len(root_test_files), 1)
        for root_path in root_test_files:
            rel = root_path.relative_to(ROOT / "tests")
            mod_path = ROOT / "shogunate_mod" / "tests" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD test file: {mod_path}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"test file differs: {rel}")

        for root_dir, mod_dir, pattern in (
            (ROOT / "tests" / "specs", ROOT / "shogunate_mod" / "tests" / "specs", "*.md"),
            (ROOT / "tests" / "fixtures", ROOT / "shogunate_mod" / "tests" / "fixtures", "*.yaml"),
            (ROOT / "tests" / "helpers", ROOT / "shogunate_mod" / "tests" / "helpers", "*.bash"),
        ):
            root_files = sorted(root_dir.glob(pattern))
            self.assertGreaterEqual(len(root_files), 1)
            for root_path in root_files:
                rel = root_path.relative_to(root_dir)
                mod_path = mod_dir / rel
                self.assertTrue(mod_path.exists(), f"missing MOD test support file: {mod_path}")
                self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"test support differs: {rel}")

        self.assertIn("require_directory_files_synced tests shogunate_mod/tests", prepublish)

    def test_unit_test_cases_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        root_cases = sorted(
            path
            for pattern in ("*.bats", "*.py")
            for path in (ROOT / "tests" / "unit").glob(pattern)
        )

        self.assertGreaterEqual(len(root_cases), 1)
        for root_path in root_cases:
            rel = root_path.relative_to(ROOT / "tests" / "unit")
            mod_path = ROOT / "shogunate_mod" / "tests" / "unit" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD unit test case: {mod_path}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"unit test case differs: {rel}")

        self.assertIn("require_directory_files_synced tests shogunate_mod/tests", prepublish)

    def test_python_unit_tests_resolve_repo_root_from_mod_copy(self):
        for path in sorted((ROOT / "tests" / "unit").glob("test_*.py")):
            text = path.read_text(encoding="utf-8")
            self.assertIn("def find_repo_root(start: Path) -> Path:", text, path)
            self.assertIn('"shogunate_mod" / "manifest.yaml"', text, path)
            self.assertNotRegex(text, r"(?m)^ROOT\s*=\s*Path\(__file__\)\.resolve\(\)\.parents\[2\]", path)

    def test_unit_tests_import_mod_canonical_runtime_sources(self):
        expected_imports = {
            "tests.unit.test_shogunate_pair_server": 'ROOT / "shogunate_mod" / "pair" / "server.py"',
            "tests.unit.test_runtime_blocker_notice": 'ROOT / "shogunate_mod" / "runtime" / "blocker_notice.py"',
            "tests.unit.test_update_manager": 'ROOT / "shogunate_mod" / "update" / "manager.py"',
        }

        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        behavior_block = prepublish.split("printf '[INFO] MOD behavior unit tests\\n'", 1)[1].split(
            "bash shogunate_mod/instructions/ensure_generated.sh",
            1,
        )[0]
        behavior_modules = re.findall(r"tests\.unit\.test_[A-Za-z0-9_]+", behavior_block)

        self.assertEqual(behavior_modules, list(expected_imports))
        for module_name, expected in expected_imports.items():
            filename = f"{module_name.rsplit('.', 1)[1]}.py"
            text = (ROOT / "tests" / "unit" / filename).read_text(encoding="utf-8")
            self.assertIn("importlib.util.spec_from_file_location", text)
            self.assertIn(expected, text, f"{filename} should import the MOD canonical source")
            self.assertNotIn('ROOT / "scripts"', text, f"{filename} should not import root scripts wrappers")
            self.assertNotIn("scripts/", text, f"{filename} should not import root scripts wrappers")

    def test_e2e_support_files_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        root_cases = sorted((ROOT / "tests" / "e2e").glob("*.bats"))
        self.assertGreaterEqual(len(root_cases), 1)
        for root_path in root_cases:
            rel = root_path.relative_to(ROOT / "tests" / "e2e")
            mod_path = ROOT / "shogunate_mod" / "tests" / "e2e" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD E2E test case: {mod_path}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"E2E test case differs: {rel}")

        for root_dir, mod_dir, pattern in (
            (ROOT / "tests" / "e2e" / "fixtures", ROOT / "shogunate_mod" / "tests" / "e2e" / "fixtures", "*.yaml"),
            (ROOT / "tests" / "e2e" / "helpers", ROOT / "shogunate_mod" / "tests" / "e2e" / "helpers", "*.bash"),
            (
                ROOT / "tests" / "e2e" / "mock_behaviors",
                ROOT / "shogunate_mod" / "tests" / "e2e" / "mock_behaviors",
                "*.sh",
            ),
        ):
            root_files = sorted(root_dir.glob(pattern))
            self.assertGreaterEqual(len(root_files), 1)
            for root_path in root_files:
                rel = root_path.relative_to(root_dir)
                mod_path = mod_dir / rel
                self.assertTrue(mod_path.exists(), f"missing MOD E2E support file: {mod_path}")
                self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"E2E support differs: {rel}")

        root_mock_cli = ROOT / "tests" / "e2e" / "mock_cli.sh"
        mod_mock_cli = ROOT / "shogunate_mod" / "tests" / "e2e" / "mock_cli.sh"
        self.assertEqual(root_mock_cli.read_bytes(), mod_mock_cli.read_bytes())
        self.assertIn("MOCK_CLI_TYPE", mod_mock_cli.read_text(encoding="utf-8"))
        self.assertIn("require_directory_files_synced tests shogunate_mod/tests", prepublish)
        self.assertIn("printf '[INFO] source syntax checks\\n'", prepublish)
        self.assertIn("git ls-files -z -- '*.sh' '*.command' | xargs -0 -r bash -n", prepublish)
        self.assertIn("require_python_syntax_clean", prepublish)
        self.assertIn('subprocess.check_output(["git", "ls-files", "-z", "--", "*.py"])', prepublish)
        self.assertIn('compile(source, str(path), "exec")', prepublish)
        self.assertIn("xargs -0 -r -n1 node --check", prepublish)
        self.assertIn(
            "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution",
            prepublish,
        )
        self.assertIn("printf '[INFO] MOD behavior unit tests\\n'", prepublish)
        self.assertIn("tests.unit.test_shogunate_pair_server", prepublish)
        self.assertIn("tests.unit.test_runtime_blocker_notice", prepublish)
        self.assertIn("tests.unit.test_update_manager", prepublish)
        self.assertLess(
            prepublish.index("printf '[INFO] source syntax checks\\n'"),
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
        )
        self.assertLess(
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
            prepublish.index("printf '[INFO] MOD behavior unit tests\\n'"),
        )
        self.assertLess(
            prepublish.index("printf '[INFO] MOD behavior unit tests\\n'"),
            prepublish.index("bash shogunate_mod/instructions/ensure_generated.sh"),
        )
        self.assertLess(
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
            prepublish.index('dirty="$(git status --short || true)"'),
        )

    def test_autoload_claude_has_mod_canonical_copy(self):
        root_claude = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        mod_claude = (
            ROOT / "shogunate_mod" / "instructions" / "autoload" / "CLAUDE.md"
        ).read_text(encoding="utf-8")
        build_script = (ROOT / "shogunate_mod" / "instructions" / "build.sh").read_text(encoding="utf-8")
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )

        self.assertEqual(root_claude, mod_claude)
        self.assertIn("AUTOLOAD_CLAUDE_MD", build_script)
        self.assertIn("Auto-load source: $AUTOLOAD_CLAUDE_MD", build_script)
        self.assertIn("AUTOLOAD_CLAUDE_MD", ensure_script)

    def test_autoload_mailbox_protocol_uses_mod_canonical_writer(self):
        autoload_surfaces = [
            ROOT / "shogunate_mod" / "instructions" / "autoload" / "CLAUDE.md",
            ROOT / "CLAUDE.md",
            ROOT / "AGENTS.md",
            ROOT / ".github" / "copilot-instructions.md",
            ROOT / "agents" / "default" / "system.md",
        ]
        canonical_command = 'bash shogunate_mod/inbox/write.sh <target_agent> "<message>" <type> <from>'

        for path in autoload_surfaces:
            with self.subTest(path=str(path.relative_to(ROOT))):
                text = path.read_text(encoding="utf-8")
                self.assertIn(canonical_command, text)
                self.assertNotIn("bash scripts/inbox_write.sh <target_agent>", text)
                self.assertNotIn("bash scripts/inbox_write.sh karo", text)
                self.assertNotIn("bash scripts/inbox_write.sh ashigaru3", text)

    def test_instruction_runtime_commands_do_not_point_to_root_wrappers(self):
        instruction_surfaces = [
            ROOT / "shogunate_mod" / "instructions" / "autoload" / "CLAUDE.md",
            ROOT / "CLAUDE.md",
            ROOT / "AGENTS.md",
            ROOT / ".github" / "copilot-instructions.md",
            ROOT / "agents" / "default" / "system.md",
        ]
        for base in [
            ROOT / "shogunate_mod" / "instructions" / "source",
            ROOT / "instructions",
            ROOT / ".opencode" / "agents",
        ]:
            instruction_surfaces.extend(path for path in base.rglob("*.md") if path.is_file())

        forbidden_root_wrappers = [
            "scripts/inbox_write.sh",
            "scripts/ntfy.sh",
            "scripts/karo_done_to_shogun_bridge_daemon.sh",
            "scripts/gunkan_codd_audit.py",
            "scripts/gunkan_emergency_stop.sh",
            "scripts/localapi_repl.py",
            "lib/file_watch.sh",
        ]
        forbidden_legacy_mailbox_labels = [
            "## Mailbox System (inbox_write.sh)",
            "| inbox_write.sh |",
            "No sleep needed. All messages guaranteed delivered by inbox_watcher.sh",
            "**Why no background monitor**: inbox_watcher.sh",
            "- inbox_watcher.sh sends",
        ]
        required_mod_commands = [
            "shogunate_mod/inbox/write.sh",
            "shogunate_mod/notify/ntfy.sh",
            "shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh",
            "shogunate_mod/gunkan/codd_audit.py",
            "shogunate_mod/gunkan/emergency_stop.sh",
            "shogunate_mod/localapi/repl.py",
            "shogunate_mod/watcher/inbox_watcher.sh",
            "shogunate_mod/watcher/file_watch.sh",
        ]
        combined = ""
        for path in sorted(set(instruction_surfaces)):
            with self.subTest(path=str(path.relative_to(ROOT))):
                text = path.read_text(encoding="utf-8")
                combined += text
                for forbidden in forbidden_root_wrappers:
                    self.assertNotIn(forbidden, text)
                for forbidden in forbidden_legacy_mailbox_labels:
                    self.assertNotIn(forbidden, text)
        for required in required_mod_commands:
            self.assertIn(required, combined)
        self.assertIn("## Mailbox System (shogunate_mod/inbox/write.sh)", combined)
        self.assertIn("mailbox write to ashigaru via shogunate_mod/inbox/write.sh", combined)
        self.assertIn("shogunate_mod/watcher/inbox_watcher.sh sends nudge text", combined)

    def test_claude_settings_have_mod_canonical_copy(self):
        root_settings = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))
        mod_settings = json.loads(
            (ROOT / "shogunate_mod" / "hooks" / "claude_settings.json").read_text(encoding="utf-8")
        )
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_settings, mod_settings)
        self.assertIn("SessionStart", mod_settings["hooks"])
        self.assertIn("Stop", mod_settings["hooks"])
        self.assertIn("bash shogunate_mod/hooks/session_start_hook.sh", str(mod_settings))
        self.assertIn("bash shogunate_mod/hooks/stop_hook_inbox.sh", str(mod_settings))
        self.assertNotIn("bash scripts/session_start_hook.sh", str(mod_settings))
        self.assertNotIn("bash scripts/stop_hook_inbox.sh", str(mod_settings))
        self.assertIn(
            "require_same_file .claude/settings.json shogunate_mod/hooks/claude_settings.json",
            prepublish,
        )

    def test_ntfy_auth_sample_has_mod_canonical_copy(self):
        root_sample = (ROOT / "config" / "ntfy_auth.env.sample").read_text(encoding="utf-8")
        mod_sample = (ROOT / "shogunate_mod" / "notify" / "ntfy_auth.env.sample").read_text(encoding="utf-8")
        self.assertEqual(root_sample, mod_sample)
        self.assertIn("NTFY_TOKEN", mod_sample)
        self.assertIn("NTFY_USER", mod_sample)
        self.assertIn("NTFY_PASS", mod_sample)

    def test_release_workflow_builds_packages_not_installers_or_apks(self):
        root_workflow = (ROOT / ".github/workflows/package-release.yml").read_text(encoding="utf-8")
        mod_workflow = (
            ROOT / "shogunate_mod" / "package" / "workflows" / "package-release.yml"
        ).read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        text = mod_workflow
        self.assertEqual(root_workflow, mod_workflow)
        self.assertIn(
            "require_same_file .github/workflows/package-release.yml shogunate_mod/package/workflows/package-release.yml",
            prepublish,
        )
        self.assertIn("v<upstream-version>.<fork-revision>", text)
        self.assertIn("multi-agent-shognate-package.tar.gz", text)
        self.assertIn("multi-agent-shognate-package.zip", text)
        package_asset_paths = [
            "dist/${{ steps.asset.outputs.package_tgz_asset }}",
            "dist/${{ steps.asset.outputs.package_zip_asset }}",
            "dist/${{ steps.asset.outputs.versioned_package_tgz_asset }}",
            "dist/${{ steps.asset.outputs.versioned_package_zip_asset }}",
        ]
        package_asset_block = "\n".join(f"            {path}" for path in package_asset_paths)
        self.assertIn(f"path: |\n{package_asset_block}", text)
        self.assertIn(f"files: |\n{package_asset_block}", text)
        for path in package_asset_paths:
            expected_count = 3 if path == "dist/${{ steps.asset.outputs.package_tgz_asset }}" else 2
            self.assertEqual(expected_count, text.count(path))
        self.assertIn("Install system dependencies", text)
        self.assertIn("sudo apt-get install -y curl python3-venv", text)
        self.assertIn('TAG_COMMIT="$(git rev-list -n 1 "$TAG")"', text)
        self.assertIn('HEAD_COMMIT="$(git rev-parse HEAD)"', text)
        self.assertIn('"Release tag $TAG does not point to the checked prepublish commit."', text)
        self.assertIn("git archive --worktree-attributes --format=tar.gz --prefix=multi-agent-shognate/ HEAD", text)
        self.assertIn("git archive --worktree-attributes --format=zip --prefix=multi-agent-shognate/ HEAD", text)
        self.assertIn('cp "dist/${PACKAGE_TGZ_ASSET}" "dist/${VERSIONED_PACKAGE_TGZ_ASSET}"', text)
        self.assertIn('cp "dist/${PACKAGE_ZIP_ASSET}" "dist/${VERSIONED_PACKAGE_ZIP_ASSET}"', text)
        self.assertLess(
            text.index('git archive --worktree-attributes --format=tar.gz --prefix=multi-agent-shognate/ HEAD'),
            text.index('cp "dist/${PACKAGE_TGZ_ASSET}" "dist/${VERSIONED_PACKAGE_TGZ_ASSET}"'),
        )
        self.assertLess(
            text.index('git archive --worktree-attributes --format=zip --prefix=multi-agent-shognate/ HEAD'),
            text.index('cp "dist/${PACKAGE_ZIP_ASSET}" "dist/${VERSIONED_PACKAGE_ZIP_ASSET}"'),
        )
        self.assertIn("target_commitish: ${{ steps.asset.outputs.tag }}", text)
        self.assertIn("fetch-depth: 0", text)
        self.assertIn("Fetch upstream main", text)
        self.assertIn("git remote add upstream https://github.com/yohey-w/multi-agent-shogun.git", text)
        self.assertIn("git fetch --no-tags upstream main:refs/remotes/upstream/main", text)
        self.assertLess(text.index("Fetch upstream main"), text.index("Run prepublish check"))
        self.assertNotIn("git fetch --force --tags", text)
        self.assertNotIn("target_commitish: ${{ github.sha }}", text)
        self.assertNotIn('git archive --format=tar.gz --prefix=multi-agent-shognate/ "$TAG"', text)
        self.assertNotIn('git archive --format=zip --prefix=multi-agent-shognate/ "$TAG"', text)
        self.assertIn("Setup Python venv with PyYAML", text)
        self.assertIn(".venv/bin/pip install --quiet -r shogunate_mod/package/requirements.txt", text)
        self.assertIn("## Install With cURL", text)
        self.assertIn("Install this exact release:", text)
        self.assertIn("curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/${TAG}/scripts/shogunate_package_bootstrap.sh | bash -s -- --version ${TAG}", text)
        self.assertIn("This pins both the bootstrap script and package resolution to \\`${TAG}\\`.", text)
        self.assertIn("For the latest release channel, use:", text)
        self.assertIn("curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main/scripts/shogunate_package_bootstrap.sh | bash", text)
        self.assertIn("body_path: ${{ steps.asset.outputs.release_notes_path }}", text)
        self.assertIn("Smoke cURL install package", text)
        self.assertIn("SHOGUNATE_PACKAGE_CURL_SMOKE_RUN_ID: package-curl-smoke-release-", text)
        self.assertIn("SHOGUNATE_PACKAGE_CURL_SMOKE_PACKAGE: ${{ github.workspace }}/dist/${{ steps.asset.outputs.package_tgz_asset }}", text)
        self.assertIn("make package-curl-smoke", text)
        self.assertLess(text.index("Setup Python venv with PyYAML"), text.index("Run prepublish check"))
        self.assertLess(text.index("Run prepublish check"), text.index("Validate release tag format"))
        self.assertLess(text.index("Run prepublish check"), text.index("Prepare release packages"))
        self.assertLess(text.index("Prepare release packages"), text.index("Smoke cURL install package"))
        self.assertLess(text.index("Smoke cURL install package"), text.index("Upload workflow artifact"))
        self.assertLess(text.index("Smoke cURL install package"), text.index("Publish GitHub Release"))
        self.assertIn("bash shogunate_mod/package/prepublish_check.sh", text)
        self.assertNotIn("bash scripts/prepublish_check.sh", text)
        self.assertLess(text.index("bash shogunate_mod/package/prepublish_check.sh"), text.index("git archive --worktree-attributes --format=tar.gz"))
        self.assertLess(text.index("bash shogunate_mod/package/prepublish_check.sh"), text.index("git archive --worktree-attributes --format=zip"))
        self.assertNotIn("multi-agent-shognate-installer-", text)
        self.assertNotIn("install.bat", text)
        self.assertNotIn("install.sh", text)
        self.assertNotIn("install.command", text)
        self.assertNotIn("assembleRelease", text)
        self.assertNotIn(".apk", text)

    def test_test_workflow_has_mod_canonical_copy(self):
        root_workflow = (ROOT / ".github/workflows/test.yml").read_text(encoding="utf-8")
        mod_workflow = (
            ROOT / "shogunate_mod" / "package" / "workflows" / "test.yml"
        ).read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        self.assertEqual(root_workflow, mod_workflow)
        self.assertIn(
            "require_same_file .github/workflows/test.yml shogunate_mod/package/workflows/test.yml",
            prepublish,
        )
        self.assertIn("Run unit tests", mod_workflow)
        self.assertIn("bats tests/agent_selfwatch.bats", mod_workflow)
        self.assertIn("python3 -m venv .venv", mod_workflow)
        self.assertIn("MOD Package, Runtime, and Android Check", mod_workflow)
        self.assertIn("actions/setup-java@v4", mod_workflow)
        self.assertIn("sudo apt-get install -y curl tmux python3-venv ripgrep", mod_workflow)
        self.assertIn("Fetch upstream main", mod_workflow)
        self.assertIn("git remote add upstream https://github.com/yohey-w/multi-agent-shogun.git", mod_workflow)
        self.assertIn("git fetch --no-tags upstream main:refs/remotes/upstream/main", mod_workflow)
        self.assertLess(mod_workflow.index("Fetch upstream main"), mod_workflow.index("Run MOD verification"))
        self.assertIn("SHOGUNATE_SOURCE_SMOKE_RUN_ID: source-runtime-smoke-ci-", mod_workflow)
        self.assertIn("make mod-check", mod_workflow)
        self.assertIn("shogunate_mod/instructions/build.sh", mod_workflow)
        self.assertIn("bash shogunate_mod/instructions/build.sh", mod_workflow)
        self.assertIn("Run MOD instruction build", mod_workflow)
        self.assertIn("Run shellcheck on Shogunate MOD", mod_workflow)
        self.assertIn("find shogunate_mod -path shogunate_mod/tests -prune -o -name '*.sh' -type f -exec shellcheck -x -S error {} +", mod_workflow)
        self.assertNotIn("Run build_instructions.sh", mod_workflow)
        self.assertNotIn("bash scripts/build_instructions.sh", mod_workflow)


    def test_release_archive_docs_boundary_is_explicit(self):
        result = subprocess.run(
            ["git", "ls-files", "docs"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        docs = sorted(path for path in result.stdout.splitlines() if path)

        attr_result = subprocess.run(
            ["git", "check-attr", "export-ignore", "--", *docs],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, attr_result.returncode, attr_result.stderr)

        attrs_by_path = {}
        for line in attr_result.stdout.splitlines():
            path, _, value = line.rpartition(": export-ignore: ")
            attrs_by_path[path] = value

        public_docs = {
            rel
            for rel in docs
            if rel == "docs/philosophy.md" or rel.startswith("docs/codd/")
        }
        internal_docs = set(docs) - public_docs
        missing_exclusion = sorted(
            rel
            for rel in internal_docs
            if attrs_by_path.get(rel) != "set"
        )
        unexpected_exclusion = sorted(
            rel
            for rel in public_docs
            if attrs_by_path.get(rel) == "set"
        )

        self.assertEqual([], missing_exclusion)
        self.assertEqual([], unexpected_exclusion)


    def test_release_tar_and_zip_archives_have_same_file_boundary(self):
        self.assertEqual(release_archive_files(), release_zip_archive_files())

    def test_release_archive_root_wrappers_match_manifest(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))

        for root_dir in ("bin/", "lib/", "scripts/"):
            archived_files = sorted(
                rel
                for rel in files
                if rel.startswith(root_dir) and (ROOT / rel).is_file()
            )
            declared_files = sorted(
                rel
                for rel in wrappers
                if rel.startswith(root_dir)
            )
            self.assertEqual(declared_files, archived_files)

    def test_release_archive_root_code_like_files_are_manifest_classified(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()
        root_paths = manifest_core_touchpoint_paths(manifest) + manifest_list_values(
            manifest,
            "compatibility_wrappers",
        )
        archived_root_code_like = sorted(set(files) & set(tracked_root_code_like_files()))
        missing = [
            rel
            for rel in archived_root_code_like
            if not manifest_root_paths_cover_path(root_paths, rel)
        ]

        self.assertEqual([], missing)

    def test_release_archive_top_level_launchers_match_manifest_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()
        top_level_wrappers = sorted(
            rel
            for rel in manifest_list_values(manifest, "compatibility_wrappers")
            if is_top_level_launcher_wrapper(rel)
        )
        archived_top_level_wrappers = sorted(
            rel for rel in files if is_top_level_launcher_wrapper(rel)
        )

        self.assertEqual(top_level_wrappers, archived_top_level_wrappers)

    def test_release_archive_top_level_file_surface_is_explicit(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = release_archive_files()

        self.assertEqual(
            expected_top_level_runtime_file_surface(manifest),
            top_level_runtime_file_surface(files),
        )

    def test_release_archive_excludes_legacy_installer_surface(self):
        files = release_archive_files()

        self.assertEqual([], sorted(files & legacy_installer_surface_files()))
        self.assertFalse(
            any(path.startswith("multi-agent-shognate-installer-") for path in files),
            "cURL release archive must not ship legacy installer assets",
        )

    def test_release_archive_root_directory_surface_is_explicit(self):
        files = release_archive_files()

        self.assertEqual(expected_root_runtime_directory_surface(), root_runtime_directory_surface(files))

    def test_release_archive_root_config_surface_is_runtime_defaults_only(self):
        files = release_archive_files()
        archived_config_files = sorted(path for path in files if path.startswith("config/"))
        expected = [
            "config/ntfy_auth.env.sample",
            "config/opencode-permissions.yaml",
            "config/opencode-tui.json",
        ]

        self.assertEqual(expected, archived_config_files)

    def test_release_archive_root_dot_compatibility_surface_is_explicit(self):
        files = release_archive_files()

        self.assertEqual(
            expected_root_dot_compatibility_surface_files(),
            root_dot_compatibility_surface_files(files),
        )

    def test_release_archive_includes_runtime_mod_canonical_sources(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_files = []
        canonical_paths = [
            rel_path.rstrip("/")
            for rel_path in manifest_mapping_values(manifest, "canonical_paths")
            if rel_path.rstrip("/").startswith("shogunate_mod/")
        ]

        for normalized in canonical_paths:
            path = ROOT / normalized
            if path.is_file():
                canonical_files.append(normalized)
                continue
            if path.is_dir():
                for child in sorted(path.rglob("*")):
                    if not child.is_file():
                        continue
                    rel = str(child.relative_to(ROOT))
                    if allowed_ignored_mod_artifact(rel):
                        continue
                    canonical_files.append(rel)

        attr_result = subprocess.run(
            ["git", "check-attr", "export-ignore", "--", *sorted(set(canonical_files))],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, attr_result.returncode, attr_result.stderr)

        unexpected_excluded = []
        missing_exclusion = []
        archive_files = release_archive_files()
        missing_archive_files = []
        unexpected_archive_files = []
        intentionally_excluded_paths = [
            path for path in canonical_paths if is_intentionally_release_archive_excluded_mod_path(path)
        ]
        for line in attr_result.stdout.splitlines():
            path, _, value = line.rpartition(": export-ignore: ")
            intentionally_excluded = is_intentionally_release_archive_excluded_mod_path(path)
            if intentionally_excluded and value != "set":
                missing_exclusion.append(path)
            if not intentionally_excluded and value == "set":
                unexpected_excluded.append(path)
            if intentionally_excluded and path in archive_files:
                unexpected_archive_files.append(path)
            if not intentionally_excluded and path not in archive_files:
                missing_archive_files.append(path)

        self.assertEqual([], sorted(set(unexpected_excluded)))
        self.assertEqual([], sorted(set(missing_exclusion)))
        self.assertEqual([], sorted(set(missing_archive_files)))
        self.assertEqual([], sorted(set(unexpected_archive_files)))
        self.assertEqual(
            [
                "shogunate_mod/development/gitmodules",
                "shogunate_mod/github/FUNDING.yml",
                "shogunate_mod/mobile/android",
                "shogunate_mod/package/gitattributes",
                "shogunate_mod/package/gitignore",
                "shogunate_mod/package/workflows/package-release.yml",
                "shogunate_mod/package/workflows/test.yml",
                "shogunate_mod/tests",
                "shogunate_mod/tests/e2e",
                "shogunate_mod/tests/e2e/fixtures",
                "shogunate_mod/tests/e2e/helpers",
                "shogunate_mod/tests/e2e/mock_behaviors",
                "shogunate_mod/tests/e2e/mock_cli.sh",
                "shogunate_mod/tests/fixtures",
                "shogunate_mod/tests/helpers",
                "shogunate_mod/tests/specs",
                "shogunate_mod/tests/unit",
            ],
            sorted(set(intentionally_excluded_paths)),
        )

    def test_release_archive_mod_files_are_manifest_canonical(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        files = release_archive_files()
        unclassified = []

        for rel in sorted(path for path in files if path.startswith("shogunate_mod/")):
            if rel.endswith("/") or (ROOT / rel).is_dir():
                continue
            if not manifest_canonical_paths_cover_path(canonical_paths, rel):
                unclassified.append(rel)

        self.assertEqual([], unclassified)

    def test_android_source_has_mod_canonical_copy(self):
        root_android = ROOT / "android"
        mod_android = ROOT / "shogunate_mod" / "mobile" / "android"
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
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

        def source_files(base: Path) -> list[Path]:
            files = []
            for dirpath, dirnames, filenames in os.walk(base):
                dirnames[:] = [name for name in dirnames if name not in excluded_dirs]
                current_dir = Path(dirpath)
                for filename in filenames:
                    path = current_dir / filename
                    rel = path.relative_to(base)
                    if filename in excluded_names:
                        continue
                    if path.suffix in excluded_suffixes:
                        continue
                    files.append(rel)
            return files

        root_files = source_files(root_android)
        mod_files = source_files(mod_android)

        self.assertGreater(len(root_files), 50)
        self.assertIn("require_android_sources_synced", prepublish)
        self.assertIn("def check_tree(source: Path, destination: Path", prepublish)
        self.assertIn('check_tree(root_android, mod_android, "compatibility", "MOD")', prepublish)
        self.assertIn('check_tree(mod_android, root_android, "MOD", "root compatibility")', prepublish)
        self.assertIn("for dirpath, dirnames, filenames in os.walk(source):", prepublish)
        self.assertIn("dirnames[:] = [name for name in dirnames if name not in excluded_dirs]", prepublish)
        self.assertIn('excluded_names = {"local.properties", ".gitignore"}', prepublish)
        mod_gitignore = (mod_android / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("release/*.apk", mod_gitignore)
        for rel in sorted(root_files):
            mod_path = mod_android / rel
            self.assertTrue(mod_path.exists(), f"missing MOD Android source: {rel}")
            self.assertEqual(
                (root_android / rel).read_bytes(),
                mod_path.read_bytes(),
                f"Android compatibility copy differs: {rel}",
            )
        for rel in sorted(mod_files):
            root_path = root_android / rel
            self.assertTrue(root_path.exists(), f"missing root Android compatibility source: {rel}")
            self.assertEqual(
                root_path.read_bytes(),
                (mod_android / rel).read_bytes(),
                f"Android MOD copy differs: {rel}",
            )




    def test_android_gradle_wrapper_uses_lf(self):
        # Acceptance 8: android/gradlew has no CR, the leading shebang is
        # interpretable by a Linux shell, and the executable bit is kept.
        gradlew = ROOT / "android" / "gradlew"
        self.assertTrue(gradlew.is_file())
        data = gradlew.read_bytes()
        self.assertNotIn(b"\r", data, "android/gradlew must not contain CR bytes")
        first_line = data.split(b"\n", 1)[0]
        self.assertTrue(
            first_line.startswith(b"#!"),
            f"android/gradlew shebang must lead the file, got: {first_line!r}",
        )
        # A Linux shell must accept the shebang interpreter path.
        self.assertTrue(
            first_line.decode("utf-8", "replace").startswith("#!/"),
            "android/gradlew shebang must use an absolute interpreter path",
        )
        # Execute bit must be preserved (the wrapper is invoked directly).
        self.assertTrue(gradlew.stat().st_mode & 0o100, "android/gradlew must keep the executable bit")


if __name__ == "__main__":
    unittest.main()
