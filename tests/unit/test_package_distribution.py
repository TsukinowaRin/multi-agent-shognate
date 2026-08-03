"""cURL-only Shogunate distribution and MOD boundary contracts."""

from __future__ import annotations

import io
import os
import re
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
MANIFEST = ROOT / "shogunate_mod/manifest.yaml"
BOOTSTRAP = ROOT / "shogunate_mod/package/bootstrap.sh"
NPM_ASSETS = {
    "package.json",
    "package-lock.json",
    "bin/shogunate.js",
    "shogunate_mod/package/package.json",
    "shogunate_mod/package/package-lock.json",
    "shogunate_mod/package/npm_cli.js",
}
_WORKTREE_ARCHIVE_CACHE: set[str] | None = None


def manifest_section(text: str, name: str) -> list[str]:
    lines = text.splitlines()
    start = lines.index(f"{name}:") + 1
    result: list[str] = []
    for line in lines[start:]:
        if line and not line.startswith((" ", "-")):
            break
        result.append(line)
    return result


def manifest_mapping_values(text: str, name: str) -> list[str]:
    result: list[str] = []
    for line in manifest_section(text, name):
        stripped = line.strip()
        if not stripped or stripped.startswith("-") or ":" not in stripped:
            continue
        value = stripped.split(":", 1)[1].strip().strip('"')
        if value:
            result.append(value)
    return result


def manifest_mapping_keys(text: str, name: str) -> list[str]:
    result: list[str] = []
    for line in manifest_section(text, name):
        stripped = line.strip()
        if not stripped or stripped.startswith("-") or ":" not in stripped:
            continue
        result.append(stripped.split(":", 1)[0])
    return result


def manifest_list_values(text: str, name: str) -> list[str]:
    return [
        line.strip()[2:].strip().strip('"')
        for line in manifest_section(text, name)
        if line.strip().startswith("- ")
    ]


def manifest_core_touchpoints(text: str) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in manifest_section(text, "current_core_touchpoints"):
        stripped = line.strip()
        if stripped.startswith("- path:"):
            if current is not None:
                result.append(current)
            current = {"path": stripped.split(":", 1)[1].strip().strip('"')}
        elif current is not None and ":" in stripped:
            key, value = stripped.split(":", 1)
            current[key] = value.strip().strip('"')
    if current is not None:
        result.append(current)
    return result


def manifest_core_touchpoint_paths(text: str) -> list[str]:
    result: list[str] = []
    for item in manifest_core_touchpoints(text):
        for chunk in item["path"].split(" and "):
            result.extend(part.strip() for part in chunk.split(" / ") if part.strip())
    return result


def path_is_covered(paths: list[str], rel: str) -> bool:
    normalized = rel.rstrip("/")
    return any(
        normalized == candidate.rstrip("/")
        or normalized.startswith(candidate.rstrip("/") + "/")
        for candidate in paths
    )


def worktree_archive_files() -> set[str]:
    """List a release archive for the current worktree without touching its index."""
    global _WORKTREE_ARCHIVE_CACHE
    if _WORKTREE_ARCHIVE_CACHE is not None:
        return set(_WORKTREE_ARCHIVE_CACHE)
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
        tree = subprocess.run(
            ["git", "write-tree"],
            cwd=ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        if tree.returncode:
            raise AssertionError(tree.stdout + tree.stderr)
        archive = subprocess.run(
            [
                "git",
                "archive",
                "--worktree-attributes",
                "--format=tar",
                tree.stdout.strip(),
            ],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )
        if archive.returncode:
            raise AssertionError(archive.stderr.decode(errors="replace"))
        with tarfile.open(fileobj=io.BytesIO(archive.stdout), mode="r:") as package:
            _WORKTREE_ARCHIVE_CACHE = {
                member.name.rstrip("/") for member in package.getmembers()
            }
    return set(_WORKTREE_ARCHIVE_CACHE)


def existing_tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise AssertionError(result.stderr)
    return [rel for rel in result.stdout.split("\0") if rel and (ROOT / rel).is_file()]


def wrapper_delegate_paths(text: str) -> list[str]:
    normalized = text.replace("\\", "/")
    return sorted(
        {
            match.group(0).rstrip(".,;:)'\"")
            for match in re.finditer(r"shogunate_mod/[A-Za-z0-9_./-]+", normalized)
        }
    )


class PackageDistributionContractTests(unittest.TestCase):
    def manifest(self) -> str:
        return MANIFEST.read_text(encoding="utf-8")

    def test_npm_assets_are_removed_from_worktree_and_release_archive(self):
        self.assertEqual([], sorted(rel for rel in NPM_ASSETS if (ROOT / rel).exists()))
        archive = worktree_archive_files()
        self.assertEqual([], sorted(NPM_ASSETS & archive))

    def test_curl_bootstrap_is_release_package_aware(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("releases/latest/download/${REPO_NAME}-package.tar.gz", text)
        self.assertIn("releases/download/${VERSION}/${REPO_NAME}-package.tar.gz", text)
        self.assertIn('PACKAGE_URL="${SHOGUNATE_PACKAGE_URL:-$PACKAGE_URL}"', text)
        self.assertIn("curl is required", text)
        self.assertIn("tar is required", text)
        self.assertNotIn("npm_cli.js", text)
        self.assertNotIn("bin/shogunate.js", text)

    def test_curl_bootstrap_installs_bash_cli_with_moa_and_council(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        for command in ("run", "pair", "council", "moa"):
            self.assertIn(f"    {command})", text)
        self.assertIn("    approval-devices|approval-device)", text)
        self.assertIn("shogunate_mod/gunshi/council.py", text)
        self.assertIn("shogunate_mod/moa/manager.py", text)
        self.assertIn("--exclude '/config/moa.yaml'", text)
        self.assertIn("--exclude='./config/moa.yaml'", text)
        self.assertIn('cat > "$BIN_DIR/shogunate"', text)
        self.assertIn('chmod +x "$BIN_DIR/shogunate"', text)
        syntax = subprocess.run(
            ["bash", "-n", str(BOOTSTRAP)], capture_output=True, text=True, check=False
        )
        self.assertEqual(0, syntax.returncode, syntax.stderr)

    def test_first_setup_does_not_install_or_execute_npm(self):
        text = (ROOT / "shogunate_mod/package/first_setup.sh").read_text(encoding="utf-8")
        executable_markers = (
            "npm install",
            "npm -v",
            "npx -y",
            "nvm install",
        )
        self.assertEqual([], [marker for marker in executable_markers if marker in text])
        self.assertIn("npm/npxによる自動導入は行いません", text)

        adapter = (ROOT / "shogunate_mod/cli/adapter.sh").read_text(encoding="utf-8")
        self.assertNotIn("npm install", adapter)

    def test_release_workflow_builds_git_archives_and_runs_curl_smoke(self):
        root = (ROOT / ".github/workflows/package-release.yml").read_text(encoding="utf-8")
        canonical = (ROOT / "shogunate_mod/package/workflows/package-release.yml").read_text(
            encoding="utf-8"
        )
        self.assertEqual(canonical, root)
        self.assertIn("git archive --worktree-attributes --format=tar.gz", root)
        self.assertIn("make package-curl-smoke", root)
        self.assertNotIn("npm pack", root)
        self.assertNotIn("npm publish", root)

    def test_curl_smoke_checks_moa_council_and_no_npm_assets(self):
        makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
        canonical = (ROOT / "shogunate_mod/development/Makefile").read_text(encoding="utf-8")
        self.assertEqual(canonical, makefile)
        self.assertIn('"$$bin/shogunate" --project "$$project" council --help', makefile)
        self.assertIn('"$$bin/shogunate" --project "$$project" moa --help', makefile)
        self.assertIn('"$$bin/shogunate" --project "$$project" configure', makefile)
        self.assertIn('\\"representative\\": \\"leader\\"', makefile)
        self.assertIn('GIT_INDEX_FILE="$$index" git add -A -- .', makefile)
        self.assertIn('GIT_INDEX_FILE="$$index" git write-tree', makefile)
        self.assertIn("-name npm_cli.js", makefile)
        self.assertNotIn("npm install -g bats", makefile)

    def test_prepublish_enforces_curl_only_distribution(self):
        text = (ROOT / "shogunate_mod/package/prepublish_check.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("require_curl_only_distribution", text)
        for rel in NPM_ASSETS:
            self.assertIn(f'Path("{rel}")', text)
        self.assertNotIn("require_same_file package.json", text)

    def test_release_archive_excludes_runtime_and_development_state(self):
        archive = worktree_archive_files()
        forbidden_prefixes = (
            "queue/",
            "projects/",
            "runtime_sandboxes/",
            "tests/",
            "shogunate_mod/tests/",
            "android/",
            "shogunate_mod/mobile/android/",
            "docs/EXECPLAN_",
            "docs/WORKLOG",
        )
        offenders = sorted(
            rel for rel in archive if rel in {"config/settings.yaml", "config/projects.yaml"} or rel.startswith(forbidden_prefixes)
        )
        self.assertEqual([], offenders)

    def test_release_archive_contains_curl_runtime_and_moa(self):
        archive = worktree_archive_files()
        required = {
            "scripts/shogunate_package_bootstrap.sh",
            "shogunate_mod/package/bootstrap.sh",
            "shogunate_mod/manifest.yaml",
            "shogunate_mod/gunshi/council.py",
            "shogunate_mod/moa/manager.py",
            "shogunate_mod/moa/README.md",
            "shogunate_mod/transport/agmsg_bridge.sh",
        }
        self.assertEqual([], sorted(required - archive))

    def test_manifest_declared_paths_exist(self):
        manifest = self.manifest()
        declared = manifest_mapping_values(manifest, "canonical_paths") + manifest_list_values(
            manifest, "compatibility_wrappers"
        )
        self.assertEqual([], sorted(rel for rel in declared if not (ROOT / rel.rstrip("/")).exists()))

    def test_manifest_sections_do_not_repeat_entries(self):
        manifest = self.manifest()
        sections = {
            "canonical keys": manifest_mapping_keys(manifest, "canonical_paths"),
            "canonical values": manifest_mapping_values(manifest, "canonical_paths"),
            "wrappers": manifest_list_values(manifest, "compatibility_wrappers"),
            "touchpoints": manifest_core_touchpoint_paths(manifest),
        }
        duplicates = [
            f"{name}: {value}"
            for name, values in sections.items()
            for value in sorted(set(values))
            if values.count(value) > 1
        ]
        self.assertEqual([], duplicates)

    def test_manifest_canonical_paths_are_mod_scoped(self):
        paths = manifest_mapping_values(self.manifest(), "canonical_paths")
        self.assertEqual([], sorted(path for path in paths if not path.startswith("shogunate_mod/")))

    def test_manifest_covers_all_mod_source_files(self):
        paths = manifest_mapping_values(self.manifest(), "canonical_paths")
        missing: list[str] = []
        for path in (ROOT / "shogunate_mod").rglob("*"):
            if not path.is_file() or "__pycache__" in path.parts or path.suffix in {".pyc", ".pyo"}:
                continue
            rel = path.relative_to(ROOT).as_posix()
            if not path_is_covered(paths, rel):
                missing.append(rel)
        self.assertEqual([], sorted(missing))

    def test_manifest_current_core_touchpoints_stay_on_root_surface(self):
        paths = manifest_core_touchpoint_paths(self.manifest())
        self.assertEqual([], sorted(path for path in paths if path.startswith("shogunate_mod/")))

    def test_manifest_core_touchpoints_are_actionable_and_not_wrappers(self):
        items = manifest_core_touchpoints(self.manifest())
        wrappers = set(manifest_list_values(self.manifest(), "compatibility_wrappers"))
        classified = wrappers | set(manifest_core_touchpoint_paths(self.manifest()))
        self.assertTrue(items)
        self.assertEqual([], [item.get("path", "") for item in items if not item.get("reason") or not item.get("next_step")])
        for path in manifest_core_touchpoint_paths(self.manifest()):
            self.assertNotIn(path, wrappers)

    def test_manifest_core_touchpoint_next_steps_use_operational_classes(self):
        allowed = (
            "synchronized",
            "generated output",
            "generated outputs",
            "generated/compatibility outputs",
            "root public metadata",
            "out of release archives",
            "local/runtime",
            "compatibility copy",
        )
        failures = [
            f"{item['path']}: {item.get('next_step', '')}"
            for item in manifest_core_touchpoints(self.manifest())
            if not any(marker in item.get("next_step", "") for marker in allowed)
        ]
        self.assertEqual([], failures)

    def test_manifest_target_direction_keeps_core_mod_boundary(self):
        self.assertEqual(
            [
                "Keep upstream-like runtime entrypoints thin.",
                "Move Shogunate-only behavior into shogunate_mod/ first.",
                "Leave compatibility wrappers at historical paths.",
            ],
            manifest_list_values(self.manifest(), "target_direction"),
        )

    def test_tracked_root_wrapper_surface_matches_manifest(self):
        wrappers = set(manifest_list_values(self.manifest(), "compatibility_wrappers"))
        classified = wrappers | set(manifest_core_touchpoint_paths(self.manifest()))
        candidates: set[str] = set()
        for rel in existing_tracked_files():
            if rel.startswith("shogunate_mod/") or rel.startswith(("tests/", "docs/", "instructions/")):
                continue
            path = ROOT / rel
            if path.suffix.lower() not in {".sh", ".py", ".bat", ".command", ".js"}:
                continue
            if "shogunate_mod/" in path.read_text(encoding="utf-8", errors="ignore").replace("\\", "/"):
                candidates.add(rel)
        self.assertEqual([], sorted(rel for rel in candidates if not path_is_covered(list(classified), rel)))

    def test_root_shogunate_surfaces_are_classified_by_manifest(self):
        manifest = self.manifest()
        classified = manifest_core_touchpoint_paths(manifest) + manifest_list_values(
            manifest, "compatibility_wrappers"
        )
        missing = []
        for rel in existing_tracked_files():
            if rel.startswith("shogunate_mod/"):
                continue
            if rel.startswith("docs/EXECPLAN_") or rel == "docs/INDEX.md":
                continue
            text = (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
            if "shogunate_mod/" in text.replace("\\", "/") and not path_is_covered(classified, rel):
                missing.append(rel)
        self.assertEqual([], sorted(missing))

    def test_tracked_root_code_like_files_are_classified_by_manifest(self):
        manifest = self.manifest()
        classified = manifest_core_touchpoint_paths(manifest) + manifest_list_values(
            manifest, "compatibility_wrappers"
        )
        suffixes = {".bash", ".bat", ".bats", ".command", ".json", ".py", ".sh", ".toml", ".ts", ".yaml", ".yml"}
        exact = {"Makefile", "requirements.txt"}
        missing = []
        for rel in existing_tracked_files():
            if rel.startswith("shogunate_mod/"):
                continue
            path = ROOT / rel
            if path.suffix.lower() not in suffixes and path.name not in exact:
                continue
            if not path_is_covered(classified, rel):
                missing.append(rel)
        self.assertEqual([], sorted(missing))

    def test_non_synchronized_core_touchpoints_are_explicitly_classified(self):
        items = manifest_core_touchpoints(self.manifest())
        self.assertEqual([], [item.get("path", "") for item in items if not item.get("reason") or not item.get("next_step")])

    def test_manifest_compatibility_wrappers_stay_thin(self):
        failures = []
        for rel in manifest_list_values(self.manifest(), "compatibility_wrappers"):
            path = ROOT / rel
            text = path.read_text(encoding="utf-8", errors="ignore")
            body = [line for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
            if len(body) > 120 or "shogunate_mod" not in text.replace("\\", "/"):
                failures.append(f"{rel}: {len(body)} body lines")
        self.assertEqual([], failures)

    def test_shell_compatibility_wrappers_exec_unless_sourced(self):
        failures = []
        for rel in manifest_list_values(self.manifest(), "compatibility_wrappers"):
            if not rel.endswith((".sh", ".command")):
                continue
            text = (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
            syntax = subprocess.run(
                ["bash", "-n", str(ROOT / rel)], text=True, capture_output=True, check=False
            )
            if syntax.returncode or not any(marker in text for marker in ("exec ", "source ", "BASH_SOURCE")):
                failures.append(rel)
        self.assertEqual([], failures)

    def test_only_package_bootstrap_wrapper_has_remote_fallback(self):
        offenders = []
        allowed = "scripts/shogunate_package_bootstrap.sh"
        for rel in manifest_list_values(self.manifest(), "compatibility_wrappers"):
            text = (ROOT / rel).read_text(encoding="utf-8", errors="ignore")
            if rel != allowed and ("raw.githubusercontent.com" in text or re.search(r"\bcurl\s+-", text)):
                offenders.append(rel)
        self.assertEqual([], offenders)

    def test_public_docs_and_package_policy_files_are_synced(self):
        pairs = (
            ("README.md", "shogunate_mod/docs/README.md"),
            ("README_ja.md", "shogunate_mod/docs/README_ja.md"),
            (".gitignore", "shogunate_mod/package/gitignore"),
            (".gitattributes", "shogunate_mod/package/gitattributes"),
            ("Makefile", "shogunate_mod/development/Makefile"),
        )
        self.assertEqual(
            [],
            [left for left, right in pairs if (ROOT / left).read_bytes() != (ROOT / right).read_bytes()],
        )


if __name__ == "__main__":
    unittest.main()
