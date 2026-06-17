import json
import fnmatch
import os
import re
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / "shogunate_mod" / "package" / "bootstrap.sh"
_NPM_PACK_FILES_CACHE: set[str] | None = None


def non_comment_body(text: str) -> str:
    return "\n".join(
        line.rstrip()
        for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


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


def npm_pack_files() -> set[str]:
    global _NPM_PACK_FILES_CACHE
    if _NPM_PACK_FILES_CACHE is None:
        result = subprocess.run(
            ["npm", "pack", "--dry-run", "--json"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(f"npm pack failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
        package_info = json.loads(result.stdout)[0]
        _NPM_PACK_FILES_CACHE = {entry["path"] for entry in package_info["files"]}
    return set(_NPM_PACK_FILES_CACHE)


def release_archive_files() -> set[str]:
    result = subprocess.run(
        ["bash", "-lc", "git archive --worktree-attributes --format=tar HEAD | tar -tf -"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"git archive listing failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}")
    return {line.rstrip("/") for line in result.stdout.splitlines() if line.strip()}


def packed_files_cover_path(files: set[str], rel_path: str) -> bool:
    normalized = rel_path.rstrip("/")
    return any(path == normalized or path.startswith(normalized + "/") for path in files)


def package_file_entry_has_packed_match(files: set[str], entry: str) -> bool:
    if entry.startswith("!"):
        return True
    normalized = entry.rstrip("/")
    return any(
        path == normalized
        or path.startswith(normalized + "/")
        or fnmatch.fnmatchcase(path, normalized)
        for path in files
    )


def manifest_canonical_paths_cover_path(canonical_paths: list[str], rel_path: str) -> bool:
    rel_path = rel_path.rstrip("/")
    for canonical_path in canonical_paths:
        normalized = canonical_path.rstrip("/")
        if rel_path == normalized or rel_path.startswith(normalized + "/"):
            return True
    return False


def manifest_root_paths_cover_path(root_paths: list[str], rel_path: str) -> bool:
    rel_path = rel_path.rstrip("/")
    for root_path in root_paths:
        normalized = root_path.rstrip("/")
        if rel_path == normalized or rel_path.startswith(normalized + "/"):
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
        "require_same_non_comment_body",
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


def is_intentionally_unpacked_mod_path(rel_path: str) -> bool:
    return rel_path == "shogunate_mod/tests" or rel_path.startswith("shogunate_mod/tests/")


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
        if "__pycache__" in parts:
            continue
        path = ROOT / rel
        if path.suffix in ignored_suffixes or path.suffix in {".pyc", ".pyo"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if any(marker in text for marker in markers):
            candidates.append(rel)

    return candidates


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
        delegate_parts = parts[index:]
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


class PackageDistributionContractTests(unittest.TestCase):
    def test_curl_bootstrap_is_release_package_aware(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        self.assertIn("releases/latest/download/${REPO_NAME}-package.tar.gz", text)
        self.assertIn("releases/download/${VERSION}/${REPO_NAME}-package.tar.gz", text)
        self.assertIn('PACKAGE_URL="${SHOGUNATE_PACKAGE_URL:-$PACKAGE_URL}"', text)
        self.assertIn("SHOGUNATE_PACKAGE_URL  Override package URL", text)
        self.assertIn("--strip-components=1", text)
        self.assertIn("first_setup.sh", text)
        self.assertIn("shogunate_mod/package/first_setup.sh", text)
        self.assertIn("install.bat", text)
        self.assertIn("Shogunate-Uninstaller.bat", text)
        self.assertIn("shogunate pair", text)
        self.assertIn("shogunate_pair_server.py", text)
        self.assertIn("SHOGUNATE_PAIR_PASSWORD", text)
        self.assertIn("cd <project> && shogunate", text)
        self.assertIn("SHOGUNATE_WORKSPACE_HOME", text)
        self.assertIn("shogunate where", text)

    def test_curl_bootstrap_installs_command_before_first_setup(self):
        text = BOOTSTRAP.read_text(encoding="utf-8")
        command_index = text.index('cat > "$BIN_DIR/shogunate"')
        setup_index = text.index('log "run first_setup.sh"')
        self.assertLess(command_index, setup_index)
        self.assertIn("pair)\n        shift || true", text)
        self.assertIn("exec python3 scripts/shogunate_pair_server.py", text)
        self.assertIn("prepare_project_runtime", text)
        self.assertIn("default_session_name", text)
        self.assertIn("SHOGUNATE_PROJECT_DIR", text)
        self.assertIn("--target-project", text)
        self.assertIn("config/settings.yaml", text)
        self.assertIn("queue/runtime/session_name", text)
        self.assertIn("print_project_info", text)

    def test_compatibility_wrappers_delegate_to_shogunate_mod(self):
        bootstrap_wrapper = (ROOT / "scripts" / "shogunate_package_bootstrap.sh").read_text(encoding="utf-8")
        first_setup_wrapper = (ROOT / "first_setup.sh").read_text(encoding="utf-8")
        setup_wrapper = (ROOT / "setup.sh").read_text(encoding="utf-8")
        setup_compat = (ROOT / "shogunate_mod" / "runtime" / "setup_compat.sh").read_text(encoding="utf-8")
        configure_roles_bat_wrapper = (ROOT / "Shogunate-Configure-Roles.bat").read_text(encoding="utf-8")
        runtime_sh_wrapper = (ROOT / "Shogunate-Runtime.sh").read_text(encoding="utf-8")
        shutsujin_sh_wrapper = (ROOT / "Shutsujin.sh").read_text(encoding="utf-8")
        runtime_bat_wrapper = (ROOT / "Shogunate-Runtime.bat").read_text(encoding="utf-8")
        runtime_command_wrapper = (ROOT / "Shogunate-Runtime.command").read_text(encoding="utf-8")
        shutsujin_bat_wrapper = (ROOT / "Shutsujin.bat").read_text(encoding="utf-8")
        shutsujin_clean_wrapper = (ROOT / "Shutsujin-Clean.bat").read_text(encoding="utf-8")
        shutsujin_resume_wrapper = (ROOT / "Shutsujin-Resume.bat").read_text(encoding="utf-8")
        npm_wrapper = (ROOT / "bin" / "shogunate.js").read_text(encoding="utf-8")
        pair_wrapper = (ROOT / "scripts" / "shogunate_pair_server.py").read_text(encoding="utf-8")
        antigravity_keyring_wrapper = (ROOT / "scripts" / "ensure_antigravity_keyring.sh").read_text(encoding="utf-8")
        aliases_wrapper = (ROOT / "scripts" / "shell_aliases.sh").read_text(encoding="utf-8")
        install_aliases_wrapper = (ROOT / "scripts" / "install_shell_aliases.sh").read_text(encoding="utf-8")
        agent_status_command_wrapper = (ROOT / "scripts" / "agent_status.sh").read_text(encoding="utf-8")
        ratelimit_wrapper = (ROOT / "scripts" / "ratelimit_check.sh").read_text(encoding="utf-8")
        focus_agent_wrapper = (ROOT / "scripts" / "focus_agent_pane.sh").read_text(encoding="utf-8")
        goza_autosave_wrapper = (ROOT / "scripts" / "goza_layout_autosave.sh").read_text(encoding="utf-8")
        goza_view_wrapper = (ROOT / "scripts" / "goza_no_ma.sh").read_text(encoding="utf-8")
        dashboard_viewer_wrapper = (ROOT / "scripts" / "dashboard-viewer.py").read_text(encoding="utf-8")
        agent_status_wrapper = (ROOT / "lib" / "agent_status.sh").read_text(encoding="utf-8")
        agent_registry_wrapper = (ROOT / "lib" / "agent_registry.sh").read_text(encoding="utf-8")
        branch_policy_wrapper = (ROOT / "lib" / "branch_policy.sh").read_text(encoding="utf-8")
        setup_cron_wrapper = (ROOT / "scripts" / "setup_cron.sh").read_text(encoding="utf-8")
        branch_drift_wrapper = (ROOT / "scripts" / "branch_drift_check.sh").read_text(encoding="utf-8")
        auto_merge_wrapper = (ROOT / "scripts" / "auto_merge_short_lived.sh").read_text(encoding="utf-8")
        pre_deploy_wrapper = (ROOT / "scripts" / "pre_deploy_verify.sh").read_text(encoding="utf-8")
        prepublish_wrapper = (ROOT / "scripts" / "prepublish_check.sh").read_text(encoding="utf-8")
        prepublish_mod = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        cli_adapter_wrapper = (ROOT / "lib" / "cli_adapter.sh").read_text(encoding="utf-8")
        update_manager_wrapper = (ROOT / "scripts" / "update_manager.py").read_text(encoding="utf-8")
        upstream_sync_wrapper = (ROOT / "scripts" / "upstream_sync.sh").read_text(encoding="utf-8")
        stop_apply_wrapper = (ROOT / "scripts" / "stop_and_apply_update.sh").read_text(encoding="utf-8")
        configure_agents_wrapper = (ROOT / "scripts" / "configure_agents.sh").read_text(encoding="utf-8")
        configure_runtime_roles_wrapper = (ROOT / "scripts" / "configure_runtime_roles.py").read_text(encoding="utf-8")
        sync_opencode_config_wrapper = (ROOT / "scripts" / "sync_opencode_config.py").read_text(encoding="utf-8")
        switch_cli_wrapper = (ROOT / "scripts" / "switch_cli.sh").read_text(encoding="utf-8")
        codd_check_wrapper = (ROOT / "scripts" / "codd_check.sh").read_text(encoding="utf-8")
        build_instructions_wrapper = (ROOT / "scripts" / "build_instructions.sh").read_text(encoding="utf-8")
        ensure_generated_wrapper = (ROOT / "scripts" / "ensure_generated_instructions.sh").read_text(encoding="utf-8")
        localapi_repl_wrapper = (ROOT / "scripts" / "localapi_repl.py").read_text(encoding="utf-8")
        history_book_wrapper = (ROOT / "scripts" / "history_book.sh").read_text(encoding="utf-8")
        mcp_health_wrapper = (ROOT / "scripts" / "mcp_health_check.sh").read_text(encoding="utf-8")
        mux_parity_smoke_wrapper = (ROOT / "scripts" / "mux_parity_smoke.sh").read_text(encoding="utf-8")
        slim_yaml_py_wrapper = (ROOT / "scripts" / "slim_yaml.py").read_text(encoding="utf-8")
        slim_yaml_sh_wrapper = (ROOT / "scripts" / "slim_yaml.sh").read_text(encoding="utf-8")
        session_start_wrapper = (ROOT / "scripts" / "session_start_hook.sh").read_text(encoding="utf-8")
        stop_hook_wrapper = (ROOT / "scripts" / "stop_hook_inbox.sh").read_text(encoding="utf-8")
        file_watch_wrapper = (ROOT / "lib" / "file_watch.sh").read_text(encoding="utf-8")
        inbox_path_wrapper = (ROOT / "lib" / "inbox_path.sh").read_text(encoding="utf-8")
        ntfy_auth_wrapper = (ROOT / "lib" / "ntfy_auth.sh").read_text(encoding="utf-8")
        topology_adapter_wrapper = (ROOT / "lib" / "topology_adapter.sh").read_text(encoding="utf-8")
        inbox_watcher_wrapper = (ROOT / "scripts" / "inbox_watcher.sh").read_text(encoding="utf-8")
        inbox_wrapper = (ROOT / "scripts" / "inbox_write.sh").read_text(encoding="utf-8")
        ntfy_send_wrapper = (ROOT / "scripts" / "ntfy.sh").read_text(encoding="utf-8")
        ntfy_listener_wrapper = (ROOT / "scripts" / "ntfy_listener.sh").read_text(encoding="utf-8")
        karo_done_bridge_wrapper = (ROOT / "scripts" / "karo_done_to_shogun_bridge.py").read_text(encoding="utf-8")
        karo_done_bridge_daemon_wrapper = (ROOT / "scripts" / "karo_done_to_shogun_bridge_daemon.sh").read_text(encoding="utf-8")
        runtime_blocker_notice_wrapper = (ROOT / "scripts" / "runtime_blocker_notice.py").read_text(encoding="utf-8")
        runtime_cli_pref_daemon_wrapper = (ROOT / "scripts" / "runtime_cli_pref_daemon.sh").read_text(encoding="utf-8")
        runtime_cli_pref_sync_wrapper = (ROOT / "scripts" / "sync_runtime_cli_preferences.py").read_text(encoding="utf-8")
        shogun_bridge_wrapper = (ROOT / "scripts" / "shogun_to_karo_bridge.py").read_text(encoding="utf-8")
        shogun_bridge_daemon_wrapper = (ROOT / "scripts" / "shogun_to_karo_bridge_daemon.sh").read_text(encoding="utf-8")
        watcher_supervisor_wrapper = (ROOT / "scripts" / "watcher_supervisor.sh").read_text(encoding="utf-8")
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertIn("shogunate_mod/package/bootstrap.sh", bootstrap_wrapper)
        self.assertIn("shogunate_mod/package/first_setup.sh", first_setup_wrapper)
        self.assertIn("shogunate_mod/runtime/setup_compat.sh", setup_wrapper)
        self.assertIn("shutsujin_departure.sh", setup_compat)
        self.assertIn("shogunate_mod/package/first_setup.sh", manifest)
        self.assertIn("shogunate_mod/runtime/setup_compat.sh", manifest)
        self.assertIn("shogunate_mod/package/package.json", manifest)
        self.assertIn("shogunate_mod/package/package-lock.json", manifest)
        self.assertIn("shogunate_mod/package/requirements.txt", manifest)
        self.assertIn("shogunate_mod/package/gitattributes", manifest)
        self.assertIn("shogunate_mod/package/gitignore", manifest)
        self.assertIn("shogunate_mod/development/gitmodules", manifest)
        self.assertIn("shogunate_mod/docs/CHANGELOG.md", manifest)
        self.assertIn("shogunate_mod/docs/CONTRIBUTING.md", manifest)
        self.assertIn("shogunate_mod/docs/README.md", manifest)
        self.assertIn("shogunate_mod/docs/README_ja.md", manifest)
        self.assertIn("shogunate_mod/docs/SECURITY.md", manifest)
        self.assertIn("shogunate_mod/github/FUNDING.yml", manifest)
        self.assertIn("shogunate_mod/package/workflows/package-release.yml", manifest)
        self.assertIn("shogunate_mod/package/workflows/test.yml", manifest)
        self.assertIn("shogunate_mod/development/Makefile", manifest)
        self.assertIn("compatibility_wrappers:\n  - first_setup.sh", manifest)
        self.assertIn("  - setup.sh", manifest)
        self.assertIn("  - bin/shogunate.js", manifest)
        self.assertIn("shogunate_mod/runtime/runtime_launcher.sh", runtime_sh_wrapper)
        self.assertIn("shogunate_mod/runtime/shutsujin_launcher.sh", shutsujin_sh_wrapper)
        self.assertIn("shogunate_mod\\windows\\configure_roles.bat", configure_roles_bat_wrapper)
        self.assertIn("shogunate_mod/runtime/runtime_launcher.sh", manifest)
        self.assertIn("shogunate_mod/runtime/shutsujin_launcher.sh", manifest)
        self.assertIn("  - Shogunate-Runtime.sh", manifest)
        self.assertIn("  - shutsujin_departure.sh", manifest)
        self.assertIn("  - Shutsujin.sh", manifest)
        self.assertNotIn("current_core_touchpoints:\n  - first_setup.sh", manifest)
        self.assertNotIn("current_core_touchpoints:\n  - Shogunate-Runtime.sh", manifest)
        self.assertNotIn("current_core_touchpoints:\n  - Shutsujin.sh", manifest)
        self.assertIn("current_core_touchpoints:\n  - path: instructions/", manifest)
        self.assertIn("  - path: .opencode/agents/", manifest)
        self.assertIn("  - path: .opencode/tools/", manifest)
        self.assertIn("  - path: agents/default/", manifest)
        self.assertIn("  - path: android/", manifest)
        self.assertIn("  - path: .codd/codd.yaml", manifest)
        self.assertIn("Generated prompt outputs and root compatibility copies", manifest)
        self.assertIn("Shogunate prompt source ownership in shogunate_mod/instructions/source", manifest)
        self.assertIn("shogunate_mod\\windows\\runtime_launcher.bat", runtime_bat_wrapper)
        self.assertIn("shogunate_mod/macos/runtime_launcher.command", runtime_command_wrapper)
        self.assertIn("shogunate_mod\\windows\\shutsujin_launcher.bat", shutsujin_bat_wrapper)
        self.assertIn("shogunate_mod\\windows\\shutsujin_clean.bat", shutsujin_clean_wrapper)
        self.assertIn("shogunate_mod\\windows\\shutsujin_resume.bat", shutsujin_resume_wrapper)
        self.assertIn("shogunate_mod/mobile/android/", manifest)
        self.assertIn("shogunate_mod/macos/runtime_launcher.command", manifest)
        self.assertIn("shogunate_mod/windows/configure_roles.bat", manifest)
        self.assertIn("shogunate_mod/windows/runtime_launcher.bat", manifest)
        self.assertIn("shogunate_mod/windows/shutsujin_launcher.bat", manifest)
        self.assertIn("shogunate_mod/windows/shutsujin_clean.bat", manifest)
        self.assertIn("shogunate_mod/windows/shutsujin_resume.bat", manifest)
        self.assertIn("shogunate_mod/package/npm_cli.js", npm_wrapper)
        self.assertIn("shogunate_mod", pair_wrapper)
        self.assertIn('"pair" / "server.py"', pair_wrapper)
        self.assertIn("shogunate_mod/cli/antigravity_keyring.sh", antigravity_keyring_wrapper)
        self.assertIn("shogunate_mod/cli/antigravity_keyring.sh", manifest)
        self.assertIn("shogunate_mod/shell/aliases.sh", aliases_wrapper)
        self.assertIn("shogunate_mod/shell/install_aliases.sh", install_aliases_wrapper)
        self.assertIn("shogunate_mod/shell/install_aliases.sh", manifest)
        self.assertIn("shogunate_mod/skills/claude/", manifest)
        self.assertIn("shogunate_mod/skills/cursor/", manifest)
        self.assertIn("  - path: skills/ and .cursor/skills/", manifest)
        self.assertIn("shogunate_mod/templates/", manifest)
        self.assertIn("  - path: templates/", manifest)
        self.assertIn("  - path: tests/", manifest)
        self.assertNotIn("  - path: tests/unit/", manifest)
        self.assertNotIn("  - path: tests/e2e/", manifest)
        self.assertIn("shogunate_mod/status/command.sh", agent_status_command_wrapper)
        self.assertIn("shogunate_mod/status/command.sh", manifest)
        self.assertIn("shogunate_mod/status/ratelimit_check.sh", ratelimit_wrapper)
        self.assertIn("shogunate_mod/status/ratelimit_check.sh", manifest)
        self.assertIn("shogunate_mod/view/focus_agent_pane.sh", focus_agent_wrapper)
        self.assertIn("shogunate_mod/view/focus_agent_pane.sh", manifest)
        self.assertIn("shogunate_mod/view/goza_layout_autosave.sh", goza_autosave_wrapper)
        self.assertIn("shogunate_mod/view/goza_layout_autosave.sh", manifest)
        self.assertIn("shogunate_mod/view/goza_no_ma.sh", goza_view_wrapper)
        self.assertIn("shogunate_mod/view/goza_no_ma.sh", manifest)
        self.assertIn("shogunate_mod", dashboard_viewer_wrapper)
        self.assertIn("dashboard_viewer.py", dashboard_viewer_wrapper)
        self.assertIn("shogunate_mod/view/dashboard_viewer.py", manifest)
        self.assertIn("shogunate_mod/status/agent_status.sh", agent_status_wrapper)
        self.assertIn("shogunate_mod/status/agent_status.sh", manifest)
        self.assertIn("shogunate_mod/topology/agent_registry.sh", agent_registry_wrapper)
        self.assertIn("shogunate_mod/topology/agent_registry.sh", manifest)
        self.assertIn("shogunate_mod/git/branch_policy.sh", branch_policy_wrapper)
        self.assertIn("shogunate_mod/git/branch_policy.sh", manifest)
        self.assertIn("shogunate_mod/git/setup_cron.sh", setup_cron_wrapper)
        self.assertIn("shogunate_mod/git/setup_cron.sh", manifest)
        self.assertIn("shogunate_mod/git/branch_drift_check.sh", branch_drift_wrapper)
        self.assertIn("shogunate_mod/git/branch_drift_check.sh", manifest)
        self.assertIn("shogunate_mod/git/auto_merge_short_lived.sh", auto_merge_wrapper)
        self.assertIn("shogunate_mod/git/auto_merge_short_lived.sh", manifest)
        self.assertIn("shogunate_mod/git/pre_deploy_verify.sh", pre_deploy_wrapper)
        self.assertIn("shogunate_mod/git/pre_deploy_verify.sh", manifest)
        self.assertIn("shogunate_mod/package/prepublish_check.sh", prepublish_wrapper)
        self.assertIn("shogunate_mod/package/prepublish_check.sh", manifest)
        self.assertIn("require_same_file package.json shogunate_mod/package/package.json", prepublish_mod)
        self.assertIn("require_same_file package-lock.json shogunate_mod/package/package-lock.json", prepublish_mod)
        self.assertIn("require_same_file requirements.txt shogunate_mod/package/requirements.txt", prepublish_mod)
        self.assertIn("config/(settings|projects)\\.yaml", prepublish_mod)
        self.assertIn("git check-ignore -q config/settings.yaml", prepublish_mod)
        self.assertIn("git check-ignore -q config/projects.yaml", prepublish_mod)
        self.assertIn("require_same_file CLAUDE.md shogunate_mod/instructions/autoload/CLAUDE.md", prepublish_mod)
        self.assertIn("require_same_file .codd/codd.yaml shogunate_mod/gunkan/codd.yaml", prepublish_mod)
        self.assertIn(
            "require_same_file config/opencode-tui.json shogunate_mod/configure/opencode-tui.json",
            prepublish_mod,
        )
        self.assertIn(
            "require_same_file config/ntfy_auth.env.sample shogunate_mod/notify/ntfy_auth.env.sample",
            prepublish_mod,
        )
        self.assertIn("require_same_non_comment_body", prepublish_mod)
        self.assertIn("config/opencode-permissions.yaml", prepublish_mod)
        self.assertIn("shogunate_mod/configure/opencode-permissions.yaml", prepublish_mod)
        self.assertIn("require_instruction_sources_synced", prepublish_mod)
        self.assertIn("shogunate_mod/instructions/source/${rel}", prepublish_mod)
        self.assertIn("require_directory_files_synced skills shogunate_mod/skills/claude", prepublish_mod)
        self.assertIn("! -path '*/.system/*'", prepublish_mod)
        self.assertIn("require_directory_files_synced .cursor/skills shogunate_mod/skills/cursor", prepublish_mod)
        self.assertIn("require_directory_files_synced templates shogunate_mod/templates", prepublish_mod)
        self.assertIn("bash shogunate_mod/instructions/ensure_generated.sh", prepublish_mod)
        self.assertIn("shogunate_mod", update_manager_wrapper)
        self.assertIn("update", update_manager_wrapper)
        self.assertIn("manager.py", update_manager_wrapper)
        self.assertIn("shogunate_mod/update/manager.py", manifest)
        self.assertIn("shogunate_mod/update/upstream_sync.sh", upstream_sync_wrapper)
        self.assertIn("shogunate_mod/update/upstream_sync.sh", manifest)
        self.assertIn("shogunate_mod/update/stop_and_apply_update.sh", stop_apply_wrapper)
        self.assertIn("shogunate_mod/update/stop_and_apply_update.sh", manifest)
        self.assertIn("shogunate_mod/cli/adapter.sh", cli_adapter_wrapper)
        self.assertIn("shogunate_mod/cli/adapter.sh", manifest)
        self.assertIn("shogunate_mod/configure/agents.sh", configure_agents_wrapper)
        self.assertIn("shogunate_mod/configure/agents.sh", manifest)
        self.assertIn("shogunate_mod/configure/opencode-permissions.yaml", manifest)
        self.assertIn("shogunate_mod/configure/opencode-tui.json", manifest)
        self.assertIn("shogunate_mod/configure/projects.yaml.sample", manifest)
        self.assertIn("shogunate_mod/configure/settings.yaml.sample", manifest)
        self.assertIn("shogunate_mod/context/README.md", manifest)
        self.assertIn("shogunate_mod/configure/runtime_roles.py", configure_runtime_roles_wrapper)
        self.assertIn("shogunate_mod/configure/runtime_roles.py", manifest)
        self.assertIn("shogunate_mod/configure/sync_opencode_config.py", sync_opencode_config_wrapper)
        self.assertIn("shogunate_mod/configure/sync_opencode_config.py", manifest)
        self.assertIn("shogunate_mod/opencode/tools/mark-as-read.ts", manifest)
        self.assertIn("shogunate_mod/configure/switch_cli.sh", switch_cli_wrapper)
        self.assertIn("shogunate_mod/configure/switch_cli.sh", manifest)
        self.assertIn("shogunate_mod/gunkan/codd_check.sh", codd_check_wrapper)
        self.assertIn("shogunate_mod/gunkan/codd_check.sh", manifest)
        self.assertIn("shogunate_mod/gunkan/codd.yaml", manifest)
        self.assertIn("shogunate_mod/gunkan/docs/", manifest)
        self.assertIn("shogunate_mod/instructions/build.sh", build_instructions_wrapper)
        self.assertIn("shogunate_mod/instructions/autoload/CLAUDE.md", manifest)
        self.assertIn("shogunate_mod/instructions/build.sh", manifest)
        self.assertIn("shogunate_mod/instructions/ensure_generated.sh", ensure_generated_wrapper)
        self.assertIn("shogunate_mod/instructions/ensure_generated.sh", manifest)
        self.assertIn("shogunate_mod/instructions/source", manifest)
        self.assertIn("shogunate_mod", localapi_repl_wrapper)
        self.assertIn("localapi", localapi_repl_wrapper)
        self.assertIn("repl.py", localapi_repl_wrapper)
        self.assertIn("shogunate_mod/localapi/repl.py", manifest)
        self.assertIn("shogunate_mod/queue/history_book.sh", history_book_wrapper)
        self.assertIn("shogunate_mod/queue/history_book.sh", manifest)
        self.assertIn("shogunate_mod/runtime/mcp_health_check.sh", mcp_health_wrapper)
        self.assertIn("shogunate_mod/runtime/mcp_health_check.sh", manifest)
        self.assertIn("shogunate_mod/runtime/mux_parity_smoke.sh", mux_parity_smoke_wrapper)
        self.assertIn("shogunate_mod/runtime/mux_parity_smoke.sh", manifest)
        self.assertIn("shogunate_mod/queue/slim_yaml.py", slim_yaml_py_wrapper)
        self.assertIn("shogunate_mod/queue/slim_yaml.py", manifest)
        self.assertIn("shogunate_mod/queue/slim_yaml.sh", slim_yaml_sh_wrapper)
        self.assertIn("shogunate_mod/queue/slim_yaml.sh", manifest)
        self.assertIn("shogunate_mod/hooks/session_start_hook.sh", session_start_wrapper)
        self.assertIn("shogunate_mod/hooks/session_start_hook.sh", manifest)
        self.assertIn("shogunate_mod/hooks/stop_hook_inbox.sh", stop_hook_wrapper)
        self.assertIn("shogunate_mod/hooks/stop_hook_inbox.sh", manifest)
        self.assertIn("shogunate_mod/watcher/file_watch.sh", file_watch_wrapper)
        self.assertIn("shogunate_mod/watcher/file_watch.sh", manifest)
        self.assertIn("shogunate_mod/inbox/path.sh", inbox_path_wrapper)
        self.assertIn("shogunate_mod/inbox/path.sh", manifest)
        self.assertIn("shogunate_mod/notify/ntfy_auth.sh", ntfy_auth_wrapper)
        self.assertIn("shogunate_mod/notify/ntfy_auth.sh", manifest)
        self.assertIn("shogunate_mod/notify/ntfy_auth.env.sample", manifest)
        self.assertIn("shogunate_mod/topology/adapter.sh", topology_adapter_wrapper)
        self.assertIn("shogunate_mod/topology/adapter.sh", manifest)
        self.assertIn("shogunate_mod/watcher/inbox_watcher.sh", inbox_watcher_wrapper)
        self.assertIn("shogunate_mod/watcher/inbox_watcher.sh", manifest)
        self.assertIn("shogunate_mod/inbox/write.sh", inbox_wrapper)
        self.assertIn("shogunate_mod/inbox/write.sh", manifest)
        self.assertIn("shogunate_mod/notify/send.sh", ntfy_send_wrapper)
        self.assertIn("shogunate_mod/notify/send.sh", manifest)
        self.assertIn("shogunate_mod/notify/listener.sh", ntfy_listener_wrapper)
        self.assertIn("shogunate_mod/notify/listener.sh", manifest)
        self.assertIn("shogunate_mod", karo_done_bridge_wrapper)
        self.assertIn("karo_done_to_shogun_bridge.py", karo_done_bridge_wrapper)
        self.assertIn("shogunate_mod/runtime/karo_done_to_shogun_bridge.py", manifest)
        self.assertIn("shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh", karo_done_bridge_daemon_wrapper)
        self.assertIn("shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh", manifest)
        self.assertIn("shogunate_mod/runtime/cli_pref_daemon.sh", runtime_cli_pref_daemon_wrapper)
        self.assertIn("shogunate_mod/runtime/cli_pref_daemon.sh", manifest)
        self.assertIn("shogunate_mod", runtime_cli_pref_sync_wrapper)
        self.assertIn("sync_cli_preferences.py", runtime_cli_pref_sync_wrapper)
        self.assertIn("shogunate_mod/runtime/sync_cli_preferences.py", manifest)
        self.assertIn("shogunate_mod", shogun_bridge_wrapper)
        self.assertIn("shogun_to_karo_bridge.py", shogun_bridge_wrapper)
        self.assertIn("shogunate_mod/runtime/shogun_to_karo_bridge.py", manifest)
        self.assertIn("shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh", shogun_bridge_daemon_wrapper)
        self.assertIn("shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh", manifest)
        self.assertIn("shogunate_mod/watcher/supervisor.sh", watcher_supervisor_wrapper)
        self.assertIn("shogunate_mod/watcher/supervisor.sh", manifest)
        self.assertIn("shogunate_mod/package/npm_cli.js", manifest)
        self.assertIn("shogunate_mod/runtime/android_compat.sh", manifest)
        self.assertIn("shogunate_mod/runtime/agent_cli.sh", manifest)
        self.assertIn("shogunate_mod/runtime/banner.sh", manifest)
        self.assertIn("shogunate_mod/runtime/bootstrap.sh", manifest)
        self.assertIn("shogunate_mod/runtime/blocker.sh", manifest)
        self.assertIn("shogunate_mod", runtime_blocker_notice_wrapper)
        self.assertIn("blocker_notice.py", runtime_blocker_notice_wrapper)
        self.assertIn("shogunate_mod/runtime/blocker_notice.py", manifest)
        self.assertIn("shogunate_mod/runtime/cli_pref_daemon.sh", manifest)
        self.assertIn("shogunate_mod/runtime/daemon.sh", manifest)
        self.assertIn("shogunate_mod/runtime/departure.sh", manifest)
        self.assertIn("shogunate_mod/runtime/directives.sh", manifest)
        self.assertIn("shogunate_mod/runtime/env.sh", manifest)
        self.assertIn("shogunate_mod/runtime/goza.sh", manifest)
        self.assertIn("shogunate_mod/runtime/launch.sh", manifest)
        self.assertIn("shogunate_mod/runtime/launcher.sh", manifest)
        self.assertIn("shogunate_mod/runtime/lifecycle.sh", manifest)
        self.assertIn("shogunate_mod/runtime/load.sh", manifest)
        self.assertIn("shogunate_mod/runtime/karo_done_to_shogun_bridge.py", manifest)
        self.assertIn("shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh", manifest)
        self.assertIn("shogunate_mod/runtime/options.sh", manifest)
        self.assertIn("shogunate_mod/runtime/prompts.sh", manifest)
        self.assertIn("shogunate_mod/runtime/shogun_to_karo_bridge.py", manifest)
        self.assertIn("shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh", manifest)
        self.assertIn("shogunate_mod/runtime/startup.sh", manifest)
        self.assertIn("shogunate_mod/runtime/state.sh", manifest)
        self.assertIn("shogunate_mod/runtime/summary.sh", manifest)
        self.assertIn("shogunate_mod/runtime/sync_cli_preferences.py", manifest)
        self.assertIn("shogunate_mod/runtime/topology.sh", manifest)
        self.assertIn("shogunate_mod/view/focus_agent_pane.sh", manifest)
        self.assertIn("shogunate_mod/view/goza_layout_autosave.sh", manifest)
        self.assertIn("shogunate_mod/view/goza_no_ma.sh", manifest)
        self.assertIn("shogunate_mod/gunkan/codd_audit.py", manifest)
        self.assertIn("shogunate_mod/gunkan/light_watch.py", manifest)
        self.assertIn("shogunate_mod/security/gitleaks.toml", manifest)
        self.assertIn("shogunate_mod/hooks/claude_settings.json", manifest)

    def test_manifest_declared_paths_exist(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        for rel in manifest_mapping_values(manifest, "canonical_paths"):
            path = ROOT / rel.rstrip("/")
            self.assertTrue(path.exists(), f"missing canonical path declared in manifest: {rel}")

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            self.assertTrue(path.exists(), f"missing compatibility wrapper declared in manifest: {rel}")

        for rel in manifest_core_touchpoint_paths(manifest):
            path = ROOT / rel.rstrip("/")
            self.assertTrue(path.exists(), f"missing current core touchpoint declared in manifest: {rel}")

    def test_manifest_core_touchpoints_are_actionable_and_not_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        missing_metadata = []
        wrapper_overlap = []

        for item in manifest_core_touchpoints(manifest):
            path = item.get("path", "")
            if not item.get("reason") or not item.get("next_step"):
                missing_metadata.append(path)
            for rel in manifest_core_touchpoint_paths(f"current_core_touchpoints:\n  - path: {path}"):
                if rel in wrappers:
                    wrapper_overlap.append(rel)

        self.assertEqual([], missing_metadata)
        self.assertEqual([], sorted(set(wrapper_overlap)))

    def test_manifest_covers_all_mod_source_files(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        missing = []

        for path in (ROOT / "shogunate_mod").rglob("*"):
            if not path.is_file():
                continue
            rel_parts = path.relative_to(ROOT / "shogunate_mod").parts
            if "__pycache__" in rel_parts:
                continue
            if path.suffix in {".pyc", ".pyo"}:
                continue
            rel = str(path.relative_to(ROOT))
            if not manifest_canonical_paths_cover_path(canonical_paths, rel):
                missing.append(rel)

        self.assertEqual([], sorted(missing))

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

    def test_manifest_compatibility_wrappers_are_mod_delegates_and_packaged(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = npm_pack_files()

        missing_delegation = []
        missing_package_entry = []
        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            if "shogunate_mod" not in text:
                missing_delegation.append(rel)
            if not packed_files_cover_path(files, rel):
                missing_package_entry.append(rel)

        self.assertEqual([], missing_delegation)
        self.assertEqual([], missing_package_entry)

    def test_manifest_compatibility_wrappers_have_explicit_delegate_targets(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        missing_targets = []

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            if not wrapper_mod_delegate_paths(text):
                missing_targets.append(rel)

        self.assertEqual([], missing_targets)

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

    def test_root_mod_delegates_are_declared_as_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        wrappers = set(manifest_list_values(manifest, "compatibility_wrappers"))
        missing = [rel for rel in root_mod_delegate_candidates() if rel not in wrappers]

        self.assertEqual([], missing)

    def test_root_shogunate_surfaces_are_classified_by_manifest(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        root_paths = manifest_core_touchpoint_paths(manifest) + manifest_list_values(
            manifest,
            "compatibility_wrappers",
        )
        missing = [
            rel
            for rel in root_shogunate_surface_candidates()
            if not manifest_root_paths_cover_path(root_paths, rel)
        ]

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

    def test_synchronized_core_touchpoints_have_prepublish_gates(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        synchronized_paths = {
            item["path"]
            for item in manifest_core_touchpoints(manifest)
            if "synchronized" in item.get("next_step", "")
        }
        expected_gates = {
            ".opencode/tools/": [".opencode/tools/mark-as-read.ts", "shogunate_mod/opencode/tools/mark-as-read.ts"],
            "README.md / README_ja.md": ["README.md", "README_ja.md", "shogunate_mod/docs/README.md", "shogunate_mod/docs/README_ja.md"],
            "CHANGELOG.md / CONTRIBUTING.md / SECURITY.md": [
                "CHANGELOG.md",
                "CONTRIBUTING.md",
                "SECURITY.md",
                "shogunate_mod/docs/CHANGELOG.md",
                "shogunate_mod/docs/CONTRIBUTING.md",
                "shogunate_mod/docs/SECURITY.md",
            ],
            "docs/philosophy.md": ["docs/philosophy.md", "shogunate_mod/docs/philosophy.md"],
            "CLAUDE.md": ["CLAUDE.md", "shogunate_mod/instructions/autoload/CLAUDE.md"],
            ".claude/settings.json": [".claude/settings.json", "shogunate_mod/hooks/claude_settings.json"],
            "android/": ["require_android_sources_synced"],
            ".github/workflows/": [
                ".github/workflows/package-release.yml",
                ".github/workflows/test.yml",
                "shogunate_mod/package/workflows/package-release.yml",
                "shogunate_mod/package/workflows/test.yml",
            ],
            ".github/FUNDING.yml": [".github/FUNDING.yml", "shogunate_mod/github/FUNDING.yml"],
            ".gitmodules": [".gitmodules", "shogunate_mod/development/gitmodules"],
            ".gitattributes": [".gitattributes", "shogunate_mod/package/gitattributes"],
            ".gitignore": [".gitignore", "shogunate_mod/package/gitignore"],
            ".gitleaks.toml": [".gitleaks.toml", "shogunate_mod/security/gitleaks.toml"],
            "package.json / package-lock.json / requirements.txt": [
                "package.json",
                "package-lock.json",
                "requirements.txt",
                "shogunate_mod/package/package.json",
                "shogunate_mod/package/package-lock.json",
                "shogunate_mod/package/requirements.txt",
            ],
            "memory/ and saytask/": [
                "memory/MEMORY.md.sample",
                "saytask/streaks.yaml.sample",
                "shogunate_mod/package/templates/memory/MEMORY.md.sample",
                "shogunate_mod/package/templates/saytask/streaks.yaml.sample",
            ],
            "config/": [
                "config/opencode-permissions.yaml",
                "config/opencode-tui.json",
                "config/ntfy_auth.env.sample",
                "shogunate_mod/configure/opencode-permissions.yaml",
                "shogunate_mod/configure/opencode-tui.json",
                "shogunate_mod/notify/ntfy_auth.env.sample",
            ],
            "context/": ["context/README.md", "shogunate_mod/context/README.md"],
            "Makefile": ["Makefile", "shogunate_mod/development/Makefile"],
            ".codd/codd.yaml": [".codd/codd.yaml", "shogunate_mod/gunkan/codd.yaml"],
            "docs/codd/": ["docs/codd", "shogunate_mod/gunkan/docs"],
            "skills/ and .cursor/skills/": [
                "skills",
                ".cursor/skills",
                "shogunate_mod/skills/claude",
                "shogunate_mod/skills/cursor",
            ],
            "templates/": ["templates", "shogunate_mod/templates"],
            "tests/": ["tests", "shogunate_mod/tests"],
        }
        missing_expectation = synchronized_paths - expected_gates.keys()
        stale_expectation = expected_gates.keys() - synchronized_paths
        missing_gate_tokens = []

        for root_path, tokens in expected_gates.items():
            for token in tokens:
                if token not in prepublish:
                    missing_gate_tokens.append(f"{root_path}: {token}")

        self.assertEqual([], sorted(missing_expectation))
        self.assertEqual([], sorted(stale_expectation))
        self.assertEqual([], sorted(missing_gate_tokens))

    def test_prepublish_mod_sync_targets_are_packaged_unless_intentionally_excluded(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        files = npm_pack_files()
        missing = []

        for _, mod_rel in prepublish_sync_pairs(prepublish):
            if is_intentionally_unpacked_mod_path(mod_rel):
                continue
            if not packed_files_cover_path(files, mod_rel):
                missing.append(mod_rel)

        self.assertEqual([], sorted(set(missing)))

    def test_manifest_compatibility_wrappers_stay_thin(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        thick_wrappers = []
        invalid_python_wrappers = []
        remote_bootstrap_fallbacks = {"scripts/shogunate_package_bootstrap.sh"}

        for rel in manifest_list_values(manifest, "compatibility_wrappers"):
            path = ROOT / rel.rstrip("/")
            text = path.read_text(encoding="utf-8", errors="ignore")
            if rel.endswith(".py"):
                if "shogunate_mod" not in text or ("runpy" not in text and "importlib.util" not in text):
                    invalid_python_wrappers.append(rel)
                continue
            if rel in remote_bootstrap_fallbacks:
                self.assertIn("curl -fsSL", text)
                self.assertIn("shogunate_mod/package/bootstrap.sh", text)
                continue
            if len(non_comment_body(text).splitlines()) > 10:
                thick_wrappers.append(rel)

        self.assertEqual([], invalid_python_wrappers)
        self.assertEqual([], thick_wrappers)

    def test_npm_wrapper_points_to_curl_bootstrap(self):
        package = (ROOT / "package.json").read_text(encoding="utf-8")
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        wrapper = (ROOT / "bin/shogunate.js").read_text(encoding="utf-8")
        npm_cli = (ROOT / "shogunate_mod" / "package" / "npm_cli.js").read_text(encoding="utf-8")
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        self.assertIn('"name": "@tsukinowarin/shogunate"', package)
        self.assertIn('"shogunate": "bin/shogunate.js"', package)
        self.assertIn('".claude/settings.json"', package)
        self.assertIn('"Makefile"', package)
        self.assertIn('"Shutsujin.sh"', package)
        self.assertIn('"Shutsujin.bat"', package)
        self.assertIn('"Shogunate-Runtime.bat"', package)
        self.assertIn('"Shogunate-Configure-Roles.bat"', package)
        self.assertIn('".opencode/tools/mark-as-read.ts"', package)
        self.assertIn('"shutsujin_departure.sh"', package)
        self.assertIn('"setup.sh"', package)
        self.assertIn('"shogunate_mod/cli/"', package)
        self.assertIn('"shogunate_mod/configure/"', package)
        self.assertIn('"shogunate_mod/context/"', package)
        self.assertIn('"shogunate_mod/development/"', package)
        self.assertIn('"shogunate_mod/docs/"', package)
        self.assertIn('"shogunate_mod/git/"', package)
        self.assertIn('"shogunate_mod/github/"', package)
        self.assertIn('"shogunate_mod/package/"', package)
        self.assertIn('"shogunate_mod/gunkan/"', package)
        self.assertIn('"shogunate_mod/hooks/"', package)
        self.assertIn('"shogunate_mod/inbox/"', package)
        self.assertIn('"shogunate_mod/instructions/"', package)
        self.assertIn('"shogunate_mod/localapi/"', package)
        self.assertIn('"shogunate_mod/macos/"', package)
        self.assertIn('"shogunate_mod/notify/"', package)
        self.assertIn('"shogunate_mod/opencode/"', package)
        self.assertIn('"shogunate_mod/pair/server.py"', package)
        self.assertIn('"shogunate_mod/queue/"', package)
        self.assertIn('"shogunate_mod/runtime/"', package)
        self.assertIn('"shogunate_mod/security/"', package)
        self.assertIn('"shogunate_mod/shell/"', package)
        self.assertIn('"skills/shogun-model-switch/SKILL.md"', package)
        self.assertIn('".cursor/skills/inbox-write/SKILL.md"', package)
        self.assertIn('"shogunate_mod/skills/"', package)
        self.assertIn('"templates/context_template.md"', package)
        self.assertIn('"shogunate_mod/templates/"', package)
        self.assertIn('"shogunate_mod/status/"', package)
        self.assertIn('"shogunate_mod/topology/"', package)
        self.assertIn('"shogunate_mod/update/"', package)
        self.assertIn('"shogunate_mod/view/"', package)
        self.assertIn('"shogunate_mod/windows/"', package)
        self.assertIn("shogunate_mod/windows/configure_roles.bat", manifest)
        self.assertIn('"shogunate_mod/watcher/"', package)
        self.assertIn('"!shogunate_mod/**/__pycache__/"', package)
        self.assertIn('"!shogunate_mod/**/*.pyc"', package)
        self.assertIn('"!scripts/**/__pycache__/"', package)
        self.assertIn("!shogunate_mod/manifest.yaml", gitignore)
        self.assertIn("!shogunate_mod/README.md", gitignore)
        self.assertIn("!shogunate_mod/cli/*.sh", gitignore)
        self.assertIn("!shogunate_mod/configure/*.sh", gitignore)
        self.assertIn("!shogunate_mod/configure/*.py", gitignore)
        self.assertIn("!shogunate_mod/configure/*.yaml", gitignore)
        self.assertIn("!shogunate_mod/configure/*.yaml.sample", gitignore)
        self.assertIn("!shogunate_mod/configure/*.json", gitignore)
        self.assertIn("!shogunate_mod/context/README.md", gitignore)
        self.assertIn("!shogunate_mod/development/Makefile", gitignore)
        self.assertIn("!shogunate_mod/development/gitmodules", gitignore)
        self.assertIn("!shogunate_mod/docs/CHANGELOG.md", gitignore)
        self.assertIn("!shogunate_mod/docs/CONTRIBUTING.md", gitignore)
        self.assertIn("!shogunate_mod/docs/philosophy.md", gitignore)
        self.assertIn("!shogunate_mod/docs/README.md", gitignore)
        self.assertIn("!shogunate_mod/docs/README_ja.md", gitignore)
        self.assertIn("!shogunate_mod/docs/SECURITY.md", gitignore)
        self.assertIn("!shogunate_mod/git/*.sh", gitignore)
        self.assertIn("!shogunate_mod/github/*.yml", gitignore)
        self.assertIn("!shogunate_mod/gunkan/docs/*.md", gitignore)
        self.assertIn("!shogunate_mod/gunkan/*.yaml", gitignore)
        self.assertIn("!shogunate_mod/hooks/*.sh", gitignore)
        self.assertIn("!shogunate_mod/hooks/*.json", gitignore)
        self.assertIn("!shogunate_mod/instructions/*.sh", gitignore)
        self.assertIn("!shogunate_mod/instructions/autoload/*.md", gitignore)
        self.assertIn("!shogunate_mod/instructions/source/*.md", gitignore)
        self.assertIn("!shogunate_mod/instructions/source/roles/*.md", gitignore)
        self.assertIn("!shogunate_mod/instructions/source/common/*.md", gitignore)
        self.assertIn("!shogunate_mod/instructions/source/cli_specific/*.md", gitignore)
        self.assertIn("!shogunate_mod/localapi/*.py", gitignore)
        self.assertIn("!shogunate_mod/macos/*.command", gitignore)
        self.assertIn("!shogunate_mod/mobile/android/**", gitignore)
        self.assertIn("shogunate_mod/mobile/android/local.properties", gitignore)
        self.assertIn("shogunate_mod/mobile/android/release/*.apk", gitignore)
        self.assertIn("!shogunate_mod/notify/*.sh", gitignore)
        self.assertIn("!shogunate_mod/notify/*.env.sample", gitignore)
        self.assertIn("!shogunate_mod/opencode/tools/*.ts", gitignore)
        self.assertIn("!shogunate_mod/package/*.json", gitignore)
        self.assertIn("!shogunate_mod/package/gitattributes", gitignore)
        self.assertIn("!shogunate_mod/package/gitignore", gitignore)
        self.assertIn("!shogunate_mod/package/workflows/*.yml", gitignore)
        self.assertIn("config/settings.yaml", gitignore)
        self.assertIn("config/projects.yaml", gitignore)
        self.assertIn("!shogunate_mod/templates/*.md", gitignore)
        self.assertIn("!shogunate_mod/tests/*.bats", gitignore)
        self.assertIn("!shogunate_mod/tests/*.sh", gitignore)
        self.assertIn("!shogunate_mod/tests/specs/*.md", gitignore)
        self.assertIn("!shogunate_mod/tests/fixtures/*.yaml", gitignore)
        self.assertIn("!shogunate_mod/tests/helpers/*.bash", gitignore)
        self.assertIn("!shogunate_mod/tests/unit/*.bats", gitignore)
        self.assertIn("!shogunate_mod/tests/unit/*.py", gitignore)
        self.assertIn("!shogunate_mod/tests/e2e/*.bats", gitignore)
        self.assertIn("!shogunate_mod/tests/e2e/fixtures/*.yaml", gitignore)
        self.assertIn("!shogunate_mod/tests/e2e/helpers/*.bash", gitignore)
        self.assertIn("!shogunate_mod/tests/e2e/mock_behaviors/*.sh", gitignore)
        self.assertIn("!shogunate_mod/tests/e2e/mock_cli.sh", gitignore)
        self.assertIn("!shogunate_mod/skills/claude/**", gitignore)
        self.assertIn("!shogunate_mod/skills/cursor/**", gitignore)
        self.assertIn("!skills/shogun-model-switch/SKILL.md", gitignore)
        self.assertIn("!.cursor/skills/inbox-write/SKILL.md", gitignore)
        self.assertIn("!shogunate_mod/queue/*.py", gitignore)
        self.assertIn("!shogunate_mod/queue/*.sh", gitignore)
        self.assertIn("!shogunate_mod/runtime/*.py", gitignore)
        self.assertIn("!shogunate_mod/security/*.toml", gitignore)
        self.assertIn("!shogunate_mod/status/*.sh", gitignore)
        self.assertIn("!shogunate_mod/topology/*.sh", gitignore)
        self.assertIn("!shogunate_mod/update/*.py", gitignore)
        self.assertIn("!shogunate_mod/update/*.sh", gitignore)
        self.assertIn("!shogunate_mod/view/*.sh", gitignore)
        self.assertIn("!shogunate_mod/view/*.py", gitignore)
        self.assertIn("!shogunate_mod/windows/*.bat", gitignore)
        self.assertIn("!shogunate_mod/watcher/*.sh", gitignore)
        self.assertIn("shogunate_mod/**/__pycache__/", gitignore)
        self.assertIn("shogunate_mod/package/npm_cli.js", wrapper)
        self.assertIn("shogunate_package_bootstrap.sh", npm_cli)
        self.assertIn("shogunate_pair_server.py", npm_cli)
        self.assertIn("SHOGUNATE_PAIR_PASSWORD", npm_cli)
        self.assertIn("curl -fsSL", npm_cli)
        self.assertIn("--target-project", npm_cli)
        self.assertIn("process.cwd()", npm_cli)

    def test_package_json_has_mod_canonical_copy(self):
        root_package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        root_lock = json.loads((ROOT / "package-lock.json").read_text(encoding="utf-8"))
        mod_lock = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package-lock.json").read_text(encoding="utf-8")
        )
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")

        self.assertEqual(root_package, mod_package)
        self.assertEqual(root_lock, mod_lock)
        self.assertEqual(root_package["name"], "@tsukinowarin/shogunate")
        self.assertEqual(root_package["bin"]["shogunate"], "bin/shogunate.js")
        self.assertEqual(root_lock["packages"][""]["bin"]["shogunate"], "bin/shogunate.js")
        self.assertIn("bin/shogunate.js", root_package["files"])
        self.assertIn("CHANGELOG.md", root_package["files"])
        self.assertIn("CLAUDE.md", root_package["files"])
        self.assertIn("CONTRIBUTING.md", root_package["files"])
        self.assertIn("SECURITY.md", root_package["files"])
        self.assertIn("requirements.txt", root_package["files"])
        self.assertIn("Makefile", root_package["files"])
        self.assertIn(".claude/settings.json", root_package["files"])
        self.assertIn(".codd/codd.yaml", root_package["files"])
        self.assertIn(".gitleaks.toml", root_package["files"])
        self.assertIn("memory/MEMORY.md.sample", root_package["files"])
        self.assertIn("saytask/streaks.yaml.sample", root_package["files"])
        self.assertIn("context/README.md", root_package["files"])
        self.assertIn("shogunate_mod/README.md", root_package["files"])
        self.assertIn("instructions/generated/codex-shogun.md", root_package["files"])
        self.assertIn("instructions/roles/shogun_role.md", root_package["files"])
        self.assertIn("shogunate_mod/context/", root_package["files"])
        self.assertIn("shogunate_mod/development/", root_package["files"])
        self.assertIn("shogunate_mod/docs/", root_package["files"])
        self.assertIn("shogunate_mod/github/", root_package["files"])
        self.assertIn(".github/copilot-instructions.md", root_package["files"])
        self.assertIn(".opencode/agents/shogun.md", root_package["files"])
        self.assertIn(".opencode/agents/ashigaru8.md", root_package["files"])
        self.assertIn(".opencode/tools/mark-as-read.ts", root_package["files"])
        self.assertIn("agents/default/agent.yaml", root_package["files"])
        self.assertIn("agents/default/system.md", root_package["files"])
        self.assertIn("shogunate_mod/opencode/", root_package["files"])
        self.assertIn("shogunate_mod/package/", root_package["files"])
        self.assertIn("shogunate_mod/security/", root_package["files"])
        self.assertIn("templates/context_template.md", root_package["files"])
        self.assertIn("skills/shogun-model-switch/SKILL.md", root_package["files"])
        self.assertIn(".cursor/skills/inbox-write/SKILL.md", root_package["files"])
        self.assertIn("shogunate_mod/templates/", root_package["files"])
        self.assertNotIn("shogunate_mod/mobile/", root_package["files"])
        self.assertIn("mod_manifest: shogunate_mod/manifest.yaml", manifest)
        self.assertIn("mod_readme: shogunate_mod/README.md", manifest)
        self.assertIn("package_json: shogunate_mod/package/package.json", manifest)
        self.assertIn("package_lock: shogunate_mod/package/package-lock.json", manifest)
        self.assertIn("package_requirements: shogunate_mod/package/requirements.txt", manifest)
        self.assertIn("package_gitattributes: shogunate_mod/package/gitattributes", manifest)
        self.assertIn("package_gitignore: shogunate_mod/package/gitignore", manifest)
        self.assertIn("development_makefile: shogunate_mod/development/Makefile", manifest)
        self.assertIn("development_gitmodules: shogunate_mod/development/gitmodules", manifest)
        self.assertIn("docs_changelog: shogunate_mod/docs/CHANGELOG.md", manifest)
        self.assertIn("docs_contributing: shogunate_mod/docs/CONTRIBUTING.md", manifest)
        self.assertIn("docs_philosophy: shogunate_mod/docs/philosophy.md", manifest)
        self.assertIn("docs_readme: shogunate_mod/docs/README.md", manifest)
        self.assertIn("docs_readme_ja: shogunate_mod/docs/README_ja.md", manifest)
        self.assertIn("docs_security: shogunate_mod/docs/SECURITY.md", manifest)
        self.assertIn("gunkan_codd_docs: shogunate_mod/gunkan/docs/", manifest)
        self.assertIn("github_funding: shogunate_mod/github/FUNDING.yml", manifest)
        self.assertIn("hooks_claude_settings: shogunate_mod/hooks/claude_settings.json", manifest)
        self.assertIn("context_readme: shogunate_mod/context/README.md", manifest)
        self.assertIn("opencode_mark_as_read_tool: shogunate_mod/opencode/tools/mark-as-read.ts", manifest)
        self.assertIn("security_gitleaks: shogunate_mod/security/gitleaks.toml", manifest)
        self.assertIn(
            "package_memory_template: shogunate_mod/package/templates/memory/MEMORY.md.sample",
            manifest,
        )
        self.assertIn(
            "package_global_context_template: shogunate_mod/package/templates/memory/global_context.md.sample",
            manifest,
        )
        self.assertIn(
            "package_saytask_streaks_template: shogunate_mod/package/templates/saytask/streaks.yaml.sample",
            manifest,
        )
        self.assertIn("Keep root package.json, package-lock.json, and requirements.txt synchronized", manifest)
        self.assertIn("templates_integration: shogunate_mod/templates/", manifest)
        self.assertIn("tests_root: shogunate_mod/tests/", manifest)
        self.assertIn("tests_specs: shogunate_mod/tests/specs/", manifest)
        self.assertIn("tests_fixtures: shogunate_mod/tests/fixtures/", manifest)
        self.assertIn("tests_helpers: shogunate_mod/tests/helpers/", manifest)
        self.assertIn("tests_unit_cases: shogunate_mod/tests/unit/", manifest)
        self.assertIn("tests_e2e_cases: shogunate_mod/tests/e2e/", manifest)
        self.assertIn("tests_e2e_fixtures: shogunate_mod/tests/e2e/fixtures/", manifest)
        self.assertIn("tests_e2e_helpers: shogunate_mod/tests/e2e/helpers/", manifest)
        self.assertIn("tests_e2e_mock_behaviors: shogunate_mod/tests/e2e/mock_behaviors/", manifest)
        self.assertIn("tests_e2e_mock_cli: shogunate_mod/tests/e2e/mock_cli.sh", manifest)

    def test_npm_pack_covers_runtime_mod_manifest_sources(self):
        root_package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = npm_pack_files()
        excluded_prefixes = (
            "shogunate_mod/mobile/android",
            "shogunate_mod/tests",
        )

        self.assertEqual(root_package, mod_package)

        missing = []
        excluded_covered = []
        for rel_path in manifest_mapping_values(manifest, "canonical_paths"):
            normalized = rel_path.rstrip("/")
            if not normalized.startswith("shogunate_mod/"):
                continue
            if any(normalized == prefix or normalized.startswith(prefix + "/") for prefix in excluded_prefixes):
                if any(path == normalized or path.startswith(normalized + "/") for path in files):
                    excluded_covered.append(rel_path)
                continue
            if not any(path == normalized or path.startswith(normalized + "/") for path in files):
                missing.append(rel_path)

        self.assertEqual([], missing)
        self.assertEqual([], excluded_covered)

    def test_package_files_entries_materialize_in_npm_pack(self):
        root_package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        files = npm_pack_files()
        missing = [
            entry
            for entry in root_package["files"]
            if not package_file_entry_has_packed_match(files, entry)
        ]

        self.assertEqual(root_package, mod_package)
        self.assertEqual([], missing)

    def test_package_files_do_not_use_broad_root_runtime_state_directories(self):
        root_package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        broad_root_entries = {
            "android/",
            "bin/",
            "config/",
            "context/",
            "docs/",
            "docs/codd/",
            "images/",
            "instructions/",
            "lib/",
            "memory/",
            "queue/",
            "reports/",
            "runtime_sandboxes/",
            "saytask/",
            "tests/",
            "skills/",
            ".cursor/skills/",
            "templates/",
            ".opencode/agents/",
            ".opencode/tools/",
            "agents/default/",
            "scripts/*.py",
            "scripts/*.sh",
        }

        self.assertEqual(root_package, mod_package)
        self.assertEqual([], sorted(broad_root_entries.intersection(root_package["files"])))

    def test_package_broad_entries_are_mod_canonical_sources(self):
        root_package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_paths = manifest_mapping_values(manifest, "canonical_paths")
        files = npm_pack_files()
        invalid_broad_entries = []
        uncovered_packed_files = []

        for entry in root_package["files"]:
            if entry.startswith("!") or not (entry.endswith("/") or "*" in entry):
                continue
            if not entry.startswith("shogunate_mod/"):
                invalid_broad_entries.append(entry)
                continue
            normalized = entry.rstrip("/")
            for rel in sorted(path for path in files if path.startswith(normalized + "/")):
                if not manifest_canonical_paths_cover_path(canonical_paths, rel):
                    uncovered_packed_files.append(rel)

        self.assertEqual(root_package, mod_package)
        self.assertEqual([], invalid_broad_entries)
        self.assertEqual([], uncovered_packed_files)

    def test_npm_pack_root_scripts_are_manifest_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = npm_pack_files()
        packaged_scripts = sorted(path for path in files if path.startswith("scripts/"))
        declared_scripts = sorted(
            path
            for path in manifest_list_values(manifest, "compatibility_wrappers")
            if path.startswith("scripts/")
        )

        self.assertEqual(declared_scripts, packaged_scripts)

    def test_npm_pack_root_lib_files_are_manifest_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = npm_pack_files()
        packaged_lib_files = sorted(path for path in files if path.startswith("lib/"))
        declared_lib_files = sorted(
            path
            for path in manifest_list_values(manifest, "compatibility_wrappers")
            if path.startswith("lib/")
        )

        self.assertEqual(declared_lib_files, packaged_lib_files)

    def test_npm_pack_root_bin_files_are_manifest_compatibility_wrappers(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        files = npm_pack_files()
        packaged_bin_files = sorted(path for path in files if path.startswith("bin/"))
        declared_bin_files = sorted(
            path
            for path in manifest_list_values(manifest, "compatibility_wrappers")
            if path.startswith("bin/")
        )

        self.assertEqual(declared_bin_files, packaged_bin_files)

    def test_npm_pack_generated_root_files_are_freshness_targets(self):
        files = npm_pack_files()
        packaged_generated_root_files = sorted(
            path
            for path in files
            if path.startswith(".opencode/agents/") or path.startswith("agents/default/")
        )
        expected = sorted(
            path
            for path in generated_root_touchpoint_files()
            if path.startswith(".opencode/agents/") or path.startswith("agents/default/")
        )

        self.assertEqual(expected, packaged_generated_root_files)

    def test_release_archive_generated_root_files_are_freshness_targets(self):
        files = release_archive_files()
        archived_generated_root_files = sorted(
            rel
            for rel in generated_root_touchpoint_files()
            if rel in files
        )

        self.assertEqual(generated_root_touchpoint_files(), archived_generated_root_files)

    def test_npm_pack_root_skills_and_templates_are_mod_sync_targets(self):
        files = npm_pack_files()
        expected_skill_files = []
        for path in sorted((ROOT / "shogunate_mod" / "skills" / "claude").rglob("*")):
            if path.is_file():
                expected_skill_files.append(f"skills/{path.relative_to(ROOT / 'shogunate_mod' / 'skills' / 'claude')}")
        for path in sorted((ROOT / "shogunate_mod" / "skills" / "cursor").rglob("*")):
            if path.is_file():
                expected_skill_files.append(
                    f".cursor/skills/{path.relative_to(ROOT / 'shogunate_mod' / 'skills' / 'cursor')}"
                )
        expected_template_files = [
            f"templates/{path.relative_to(ROOT / 'shogunate_mod' / 'templates')}"
            for path in sorted((ROOT / "shogunate_mod" / "templates").rglob("*"))
            if path.is_file()
        ]

        packaged_skill_files = sorted(
            path
            for path in files
            if path.startswith("skills/") or path.startswith(".cursor/skills/")
        )
        packaged_template_files = sorted(path for path in files if path.startswith("templates/"))

        self.assertEqual(sorted(expected_skill_files), packaged_skill_files)
        self.assertEqual(sorted(expected_template_files), packaged_template_files)

    def test_npm_pack_root_codd_docs_are_mod_sync_targets(self):
        files = npm_pack_files()
        expected = [
            f"docs/codd/{path.relative_to(ROOT / 'shogunate_mod' / 'gunkan' / 'docs')}"
            for path in sorted((ROOT / "shogunate_mod" / "gunkan" / "docs").rglob("*"))
            if path.is_file()
        ]
        packaged = sorted(path for path in files if path.startswith("docs/codd/"))

        self.assertEqual(sorted(expected), packaged)

    def test_npm_pack_actual_runtime_package_boundary(self):
        files = npm_pack_files()
        required = {
            "AGENTS.md",
            "CLAUDE.md",
            ".codd/codd.yaml",
            ".github/copilot-instructions.md",
            ".opencode/agents/shogun.md",
            ".opencode/tools/mark-as-read.ts",
            "agents/default/system.md",
            "CHANGELOG.md",
            "CONTRIBUTING.md",
            "README.md",
            "README_ja.md",
            "SECURITY.md",
            ".claude/settings.json",
            ".gitleaks.toml",
            "Makefile",
            "requirements.txt",
            "context/README.md",
            "memory/MEMORY.md.sample",
            "saytask/streaks.yaml.sample",
            "skills/shogun-model-switch/SKILL.md",
            ".cursor/skills/inbox-write/SKILL.md",
            "templates/context_template.md",
            "docs/codd/gunkan_codd_audit_design.md",
            "shogunate_mod/manifest.yaml",
            "shogunate_mod/package/npm_cli.js",
            "shogunate_mod/package/requirements.txt",
            "shogunate_mod/instructions/autoload/CLAUDE.md",
            "shogunate_mod/gunkan/codd.yaml",
            "shogunate_mod/opencode/tools/mark-as-read.ts",
            "shogunate_mod/hooks/claude_settings.json",
            "shogunate_mod/security/gitleaks.toml",
            "shogunate_mod/development/Makefile",
            "shogunate_mod/docs/philosophy.md",
            "shogunate_mod/templates/context_template.md",
        }
        forbidden_prefixes = (
            "android/",
            "shogunate_mod/mobile/android/",
            "tests/",
            "shogunate_mod/tests/",
            "images/",
            "reports/",
            "queue/",
            "runtime_sandboxes/",
            "skills/.system/",
        )
        forbidden_exact = {
            ".github/FUNDING.yml",
            ".github/workflows/package-release.yml",
            ".github/workflows/test.yml",
            ".gitattributes",
            ".gitignore",
            ".gitmodules",
            "config/projects.yaml",
            "config/settings.yaml",
            "dashboard.md",
            "docs/philosophy.md",
            "memory/MEMORY.md",
            "memory/global_context.md",
            "package-lock.json",
            "saytask/streaks.yaml",
        }
        missing = sorted(required - files)
        forbidden = sorted(
            rel
            for rel in files
            if rel in forbidden_exact
            or rel in {"docs/INDEX.md", "docs/REQS.md", "docs/WORKLOG.md"}
            or rel == "docs/vps_pr118_verification_plan.md"
            or (rel.startswith("context/") and rel != "context/README.md")
            or rel.startswith("docs/EXECPLAN_")
            or rel.startswith("docs/HANDOVER_")
            or rel.startswith("docs/UPSTREAM_SYNC_")
            or rel.endswith((".pyc", ".pyo"))
            or "__pycache__" in rel.split("/")
            or any(rel.startswith(prefix) for prefix in forbidden_prefixes)
        )

        self.assertEqual([], missing)
        self.assertEqual([], forbidden)

    def test_makefile_has_mod_canonical_copy(self):
        root_makefile = (ROOT / "Makefile").read_bytes()
        mod_makefile = (ROOT / "shogunate_mod" / "development" / "Makefile").read_bytes()
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_makefile, mod_makefile)
        text = mod_makefile.decode("utf-8")
        self.assertIn("scripts/build_instructions.sh", text)
        self.assertIn("scripts/codd_check.sh gunkan", text)
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

        self.assertEqual(root_readme, mod_readme)
        self.assertEqual(root_readme_ja, mod_readme_ja)
        self.assertIn("curl -fsSL", mod_readme)
        self.assertIn("shogunate pair", mod_readme)
        self.assertIn("cd /path/to/your-project", mod_readme)
        self.assertIn("curl -fsSL", mod_readme_ja)
        self.assertIn("shogunate pair", mod_readme_ja)
        self.assertIn("cd /path/to/your-project", mod_readme_ja)
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

    def test_public_community_docs_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        files = npm_pack_files()

        self.assertEqual(package, mod_package)
        for filename, marker in (
            ("CHANGELOG.md", "Changelog"),
            ("CONTRIBUTING.md", "Contributing"),
            ("SECURITY.md", "Security Policy"),
        ):
            root_doc = (ROOT / filename).read_text(encoding="utf-8")
            mod_doc = (ROOT / "shogunate_mod" / "docs" / filename).read_text(encoding="utf-8")
            self.assertEqual(root_doc, mod_doc)
            self.assertIn(marker, mod_doc)
            self.assertIn(
                f"require_same_file {filename} shogunate_mod/docs/{filename}",
                prepublish,
            )
            self.assertIn(filename, files)
            self.assertIn(f"shogunate_mod/docs/{filename}", files)

    def test_codd_config_has_mod_canonical_copy(self):
        root_codd = (ROOT / ".codd" / "codd.yaml").read_text(encoding="utf-8")
        mod_codd = (ROOT / "shogunate_mod" / "gunkan" / "codd.yaml").read_text(encoding="utf-8")
        self.assertEqual(root_codd, mod_codd)

    def test_codd_docs_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        root_docs = sorted((ROOT / "docs" / "codd").glob("*.md"))

        self.assertGreaterEqual(len(root_docs), 4)
        for root_path in root_docs:
            rel = root_path.relative_to(ROOT / "docs" / "codd")
            mod_path = ROOT / "shogunate_mod" / "gunkan" / "docs" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD CoDD doc: {rel}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"CoDD doc differs: {rel}")

        self.assertIn("require_directory_files_synced docs/codd shogunate_mod/gunkan/docs", prepublish)

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
        self.assertEqual(non_comment_body(root_permissions), non_comment_body(mod_permissions))
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

    def test_opencode_tools_have_mod_canonical_copy(self):
        root_tool = (ROOT / ".opencode" / "tools" / "mark-as-read.ts").read_text(encoding="utf-8")
        mod_tool = (
            ROOT / "shogunate_mod" / "opencode" / "tools" / "mark-as-read.ts"
        ).read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_tool, mod_tool)
        self.assertIn("OPENCODE_AGENT_ID", mod_tool)
        self.assertIn("queue/inbox", mod_tool)
        self.assertIn(".opencode/tools/mark-as-read.ts", npm_pack_files())
        self.assertIn(
            "require_same_file .opencode/tools/mark-as-read.ts shogunate_mod/opencode/tools/mark-as-read.ts",
            prepublish,
        )

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

    def test_runtime_state_templates_are_mod_owned(self):
        first_setup = (ROOT / "shogunate_mod" / "package" / "first_setup.sh").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        files = npm_pack_files()
        memory_template = (
            ROOT / "shogunate_mod" / "package" / "templates" / "memory" / "MEMORY.md.sample"
        ).read_text(encoding="utf-8")
        global_context_template = (
            ROOT / "shogunate_mod" / "package" / "templates" / "memory" / "global_context.md.sample"
        ).read_text(encoding="utf-8")
        root_memory_template = (ROOT / "memory" / "MEMORY.md.sample").read_text(encoding="utf-8")
        saytask_template = (
            ROOT / "shogunate_mod" / "package" / "templates" / "saytask" / "streaks.yaml.sample"
        ).read_text(encoding="utf-8")
        root_saytask_template = (ROOT / "saytask" / "streaks.yaml.sample").read_text(encoding="utf-8")

        self.assertEqual(root_memory_template, memory_template)
        self.assertEqual(root_saytask_template, saytask_template)
        self.assertIn("グローバルコンテキスト", global_context_template)
        self.assertIn("copy_initial_file_from_template", first_setup)
        self.assertIn("shogunate_mod/package/templates/memory/MEMORY.md.sample", first_setup)
        self.assertIn("shogunate_mod/package/templates/memory/global_context.md.sample", first_setup)
        self.assertIn("shogunate_mod/package/templates/saytask/streaks.yaml.sample", first_setup)
        self.assertIn('"$SCRIPT_DIR/memory/global_context.md"', first_setup)
        self.assertIn('"saytask"', first_setup)
        self.assertIn("shogunate_mod/package/templates/memory/global_context.md.sample", files)
        self.assertNotIn("memory/global_context.md", files)
        self.assertIn(
            "require_same_text_file memory/MEMORY.md.sample shogunate_mod/package/templates/memory/MEMORY.md.sample",
            prepublish,
        )
        self.assertIn(
            "require_same_text_file saytask/streaks.yaml.sample shogunate_mod/package/templates/saytask/streaks.yaml.sample",
            prepublish,
        )
        self.assertIn("today:", saytask_template)

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

        for root_path in root_files:
            rel = root_path.relative_to(ROOT / "instructions")
            mod_path = source_root / rel
            self.assertTrue(mod_path.exists(), f"missing MOD instruction source: {mod_path}")
            self.assertEqual(
                root_path.read_text(encoding="utf-8"),
                mod_path.read_text(encoding="utf-8"),
                f"instruction source compatibility copy differs: {rel}",
            )

    def test_npm_pack_root_instructions_are_mod_source_or_freshness_targets(self):
        ensure_script = (ROOT / "shogunate_mod" / "instructions" / "ensure_generated.sh").read_text(
            encoding="utf-8"
        )
        files = npm_pack_files()
        source_files = set()
        for path in (ROOT / "instructions").rglob("*.md"):
            rel = path.relative_to(ROOT / "instructions")
            if "generated" in rel.parts:
                continue
            source_files.add(str(path.relative_to(ROOT)))

        packed_instruction_files = sorted(path for path in files if path.startswith("instructions/"))
        unexpected = []
        missing_freshness_targets = []
        for rel in packed_instruction_files:
            if not rel.endswith(".md"):
                unexpected.append(rel)
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

    def test_integration_templates_have_mod_canonical_copy(self):
        root_templates = sorted(path for path in (ROOT / "templates").glob("*.md") if path.is_file())
        package = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))
        mod_package = json.loads(
            (ROOT / "shogunate_mod" / "package" / "package.json").read_text(encoding="utf-8")
        )
        files = npm_pack_files()

        self.assertEqual(package, mod_package)
        self.assertGreaterEqual(len(root_templates), 5)
        for root_path in root_templates:
            rel = root_path.relative_to(ROOT / "templates")
            mod_path = ROOT / "shogunate_mod" / "templates" / rel
            self.assertTrue(mod_path.exists(), f"missing MOD template: {rel}")
            self.assertEqual(root_path.read_bytes(), mod_path.read_bytes(), f"template differs: {rel}")
            self.assertIn(str(root_path.relative_to(ROOT)), files)
            self.assertIn(str(mod_path.relative_to(ROOT)), files)

    def test_test_support_files_have_mod_canonical_copy(self):
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        root_test_files = sorted(
            path
            for path in (ROOT / "tests").rglob("*")
            if path.is_file()
            and "__pycache__" not in path.relative_to(ROOT / "tests").parts
            and path.suffix not in {".pyc", ".pyo"}
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
        self.assertIn("require_directory_files_synced tests/specs shogunate_mod/tests/specs", prepublish)
        self.assertIn("require_directory_files_synced tests/fixtures shogunate_mod/tests/fixtures", prepublish)
        self.assertIn("require_directory_files_synced tests/helpers shogunate_mod/tests/helpers", prepublish)

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

        self.assertIn("require_directory_files_synced tests/unit shogunate_mod/tests/unit", prepublish)

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
        self.assertIn("require_directory_files_synced tests/e2e shogunate_mod/tests/e2e", prepublish)
        self.assertIn("require_directory_files_synced tests/e2e/fixtures shogunate_mod/tests/e2e/fixtures", prepublish)
        self.assertIn("require_directory_files_synced tests/e2e/helpers shogunate_mod/tests/e2e/helpers", prepublish)
        self.assertIn(
            "require_directory_files_synced tests/e2e/mock_behaviors shogunate_mod/tests/e2e/mock_behaviors",
            prepublish,
        )
        self.assertIn("require_same_file tests/e2e/mock_cli.sh shogunate_mod/tests/e2e/mock_cli.sh", prepublish)
        self.assertIn(
            "PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution",
            prepublish,
        )
        self.assertLess(
            prepublish.index("PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.unit.test_package_distribution"),
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

    def test_claude_settings_have_mod_canonical_copy(self):
        root_settings = json.loads((ROOT / ".claude" / "settings.json").read_text(encoding="utf-8"))
        mod_settings = json.loads(
            (ROOT / "shogunate_mod" / "hooks" / "claude_settings.json").read_text(encoding="utf-8")
        )
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")

        self.assertEqual(root_settings, mod_settings)
        self.assertIn("SessionStart", mod_settings["hooks"])
        self.assertIn("Stop", mod_settings["hooks"])
        self.assertIn("bash scripts/session_start_hook.sh", str(mod_settings))
        self.assertIn("bash scripts/stop_hook_inbox.sh", str(mod_settings))
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
            self.assertEqual(2, text.count(path))
        self.assertIn('TAG_COMMIT="$(git rev-list -n 1 "$TAG")"', text)
        self.assertIn('HEAD_COMMIT="$(git rev-parse HEAD)"', text)
        self.assertIn('"Release tag $TAG does not point to the checked prepublish commit."', text)
        self.assertIn("git archive --format=tar.gz --prefix=multi-agent-shognate/ HEAD", text)
        self.assertIn("git archive --format=zip --prefix=multi-agent-shognate/ HEAD", text)
        self.assertIn("target_commitish: ${{ steps.asset.outputs.tag }}", text)
        self.assertIn("fetch-depth: 0", text)
        self.assertNotIn("git fetch --force --tags", text)
        self.assertNotIn("target_commitish: ${{ github.sha }}", text)
        self.assertNotIn('git archive --format=tar.gz --prefix=multi-agent-shognate/ "$TAG"', text)
        self.assertNotIn('git archive --format=zip --prefix=multi-agent-shognate/ "$TAG"', text)
        self.assertIn("Setup Python venv with PyYAML", text)
        self.assertIn(".venv/bin/pip install --quiet -r shogunate_mod/package/requirements.txt", text)
        self.assertLess(text.index("Setup Python venv with PyYAML"), text.index("Run prepublish check"))
        self.assertLess(text.index("Run prepublish check"), text.index("Validate release tag format"))
        self.assertLess(text.index("Run prepublish check"), text.index("Prepare release packages"))
        self.assertLess(text.index("bash scripts/prepublish_check.sh"), text.index("git archive --format=tar.gz"))
        self.assertLess(text.index("bash scripts/prepublish_check.sh"), text.index("git archive --format=zip"))
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

    def test_package_archive_excludes_android_app(self):
        attrs = (ROOT / ".gitattributes").read_text(encoding="utf-8")
        mod_attrs = (ROOT / "shogunate_mod" / "package" / "gitattributes").read_text(encoding="utf-8")
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        mod_gitignore = (ROOT / "shogunate_mod" / "package" / "gitignore").read_text(encoding="utf-8")
        package = (ROOT / "package.json").read_text(encoding="utf-8")
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        prepublish = (ROOT / "shogunate_mod" / "package" / "prepublish_check.sh").read_text(encoding="utf-8")
        self.assertEqual(attrs, mod_attrs)
        self.assertEqual(gitignore, mod_gitignore)
        self.assertIn("android export-ignore", attrs)
        self.assertIn("android/** export-ignore", attrs)
        self.assertIn("shogunate_mod/mobile/android export-ignore", attrs)
        self.assertIn("shogunate_mod/mobile/android/** export-ignore", attrs)
        self.assertIn("images export-ignore", attrs)
        self.assertIn("images/** export-ignore", attrs)
        self.assertIn("reports export-ignore", attrs)
        self.assertIn("reports/** export-ignore", attrs)
        self.assertIn("tests export-ignore", attrs)
        self.assertIn("tests/** export-ignore", attrs)
        self.assertIn("shogunate_mod/tests export-ignore", attrs)
        self.assertIn("shogunate_mod/tests/** export-ignore", attrs)
        self.assertIn("queue export-ignore", attrs)
        self.assertIn("queue/** export-ignore", attrs)
        self.assertIn("runtime_sandboxes export-ignore", attrs)
        self.assertIn("runtime_sandboxes/** export-ignore", attrs)
        self.assertIn("dashboard.md export-ignore", attrs)
        self.assertIn("config/settings.yaml export-ignore", attrs)
        self.assertIn("config/projects.yaml export-ignore", attrs)
        self.assertIn("memory/MEMORY.md export-ignore", attrs)
        self.assertIn("memory/global_context.md export-ignore", attrs)
        self.assertIn("saytask/streaks.yaml export-ignore", attrs)
        self.assertIn("docs/REQS.md export-ignore", attrs)
        self.assertIn("docs/INDEX.md export-ignore", attrs)
        self.assertIn("docs/WORKLOG.md export-ignore", attrs)
        self.assertIn("docs/EXECPLAN_* export-ignore", attrs)
        self.assertIn("docs/vps_pr118_verification_plan.md export-ignore", attrs)
        self.assertIn(".github/workflows export-ignore", attrs)
        self.assertIn(".github/workflows/** export-ignore", attrs)
        self.assertIn(".github/FUNDING.yml export-ignore", attrs)
        self.assertIn(".gitmodules export-ignore", attrs)
        self.assertIn("shogunate_mod/github/FUNDING.yml export-ignore", attrs)
        self.assertIn("shogunate_mod/development/gitmodules export-ignore", attrs)
        self.assertIn(".gitignore export-ignore", attrs)
        self.assertIn(".gitattributes export-ignore", attrs)
        self.assertIn("package-lock.json export-ignore", attrs)
        self.assertIn("shogunate_mod/package/package-lock.json export-ignore", attrs)
        self.assertIn("shogunate_mod/package/workflows export-ignore", attrs)
        self.assertIn("shogunate_mod/package/workflows/** export-ignore", attrs)
        self.assertIn("shogunate_mod/package/gitattributes export-ignore", attrs)
        self.assertIn("shogunate_mod/package/gitignore export-ignore", attrs)
        attr_paths = [
            "android",
            "android/README.md",
            "shogunate_mod/mobile/android",
            "shogunate_mod/mobile/android/README.md",
            "images",
            "reports",
            "tests/unit/test_package_distribution.py",
            "shogunate_mod/tests/unit/test_package_distribution.py",
            "queue/runtime/session_name",
            "runtime_sandboxes/example",
            "dashboard.md",
            "config/settings.yaml",
            "config/projects.yaml",
            "memory/MEMORY.md",
            "memory/global_context.md",
            "saytask/streaks.yaml",
            "docs/REQS.md",
            "docs/INDEX.md",
            "docs/WORKLOG.md",
            "docs/EXECPLAN_2026-06-16_upstream_core_mod_split.md",
            "docs/vps_pr118_verification_plan.md",
            ".github/workflows/package-release.yml",
            ".github/workflows/test.yml",
            ".github/FUNDING.yml",
            ".gitmodules",
            "shogunate_mod/github/FUNDING.yml",
            "shogunate_mod/development/gitmodules",
            ".gitignore",
            ".gitattributes",
            "package-lock.json",
            "shogunate_mod/package/package-lock.json",
            "shogunate_mod/package/workflows/package-release.yml",
            "shogunate_mod/package/gitattributes",
            "shogunate_mod/package/gitignore",
            "README.md",
            "package.json",
            ".github/copilot-instructions.md",
            "config/opencode-permissions.yaml",
            "config/opencode-tui.json",
            "first_setup.sh",
            "shogunate_mod/package/first_setup.sh",
            "shogunate_mod/package/requirements.txt",
            "scripts/shogunate_pair_server.py",
            "shogunate_mod/pair/server.py",
            "bin/shogunate.js",
            "Shogunate-Runtime.sh",
            "Shutsujin.sh",
            "shutsujin_departure.sh",
            "shogunate_mod/runtime/runtime_launcher.sh",
            "shogunate_mod/runtime/departure.sh",
            "shogunate_mod/package/templates/memory/global_context.md.sample",
        ]
        attr_result = subprocess.run(
            ["git", "check-attr", "export-ignore", "--", *attr_paths],
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
        self.assertEqual("set", attrs_by_path["android"])
        self.assertEqual("set", attrs_by_path["android/README.md"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/mobile/android"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/mobile/android/README.md"])
        self.assertEqual("set", attrs_by_path["images"])
        self.assertEqual("set", attrs_by_path["reports"])
        self.assertEqual("set", attrs_by_path["tests/unit/test_package_distribution.py"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/tests/unit/test_package_distribution.py"])
        self.assertEqual("set", attrs_by_path["queue/runtime/session_name"])
        self.assertEqual("set", attrs_by_path["runtime_sandboxes/example"])
        self.assertEqual("set", attrs_by_path["dashboard.md"])
        self.assertEqual("set", attrs_by_path["config/settings.yaml"])
        self.assertEqual("set", attrs_by_path["config/projects.yaml"])
        self.assertEqual("set", attrs_by_path["memory/MEMORY.md"])
        self.assertEqual("set", attrs_by_path["memory/global_context.md"])
        self.assertEqual("set", attrs_by_path["saytask/streaks.yaml"])
        self.assertEqual("set", attrs_by_path["docs/REQS.md"])
        self.assertEqual("set", attrs_by_path["docs/INDEX.md"])
        self.assertEqual("set", attrs_by_path["docs/WORKLOG.md"])
        self.assertEqual("set", attrs_by_path["docs/EXECPLAN_2026-06-16_upstream_core_mod_split.md"])
        self.assertEqual("set", attrs_by_path["docs/vps_pr118_verification_plan.md"])
        self.assertEqual("set", attrs_by_path[".github/workflows/package-release.yml"])
        self.assertEqual("set", attrs_by_path[".github/workflows/test.yml"])
        self.assertEqual("set", attrs_by_path[".github/FUNDING.yml"])
        self.assertEqual("set", attrs_by_path[".gitmodules"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/github/FUNDING.yml"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/development/gitmodules"])
        self.assertEqual("set", attrs_by_path[".gitignore"])
        self.assertEqual("set", attrs_by_path[".gitattributes"])
        self.assertEqual("set", attrs_by_path["package-lock.json"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/package/package-lock.json"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/package/workflows/package-release.yml"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/package/gitattributes"])
        self.assertEqual("set", attrs_by_path["shogunate_mod/package/gitignore"])
        self.assertEqual("unspecified", attrs_by_path["README.md"])
        self.assertEqual("unspecified", attrs_by_path["package.json"])
        self.assertEqual("unspecified", attrs_by_path[".github/copilot-instructions.md"])
        self.assertEqual("unspecified", attrs_by_path["config/opencode-permissions.yaml"])
        self.assertEqual("unspecified", attrs_by_path["config/opencode-tui.json"])
        self.assertEqual("unspecified", attrs_by_path["first_setup.sh"])
        self.assertEqual("unspecified", attrs_by_path["shogunate_mod/package/first_setup.sh"])
        self.assertEqual("unspecified", attrs_by_path["shogunate_mod/package/requirements.txt"])
        self.assertEqual("unspecified", attrs_by_path["scripts/shogunate_pair_server.py"])
        self.assertEqual("unspecified", attrs_by_path["shogunate_mod/pair/server.py"])
        self.assertEqual("unspecified", attrs_by_path["bin/shogunate.js"])
        self.assertEqual("unspecified", attrs_by_path["Shogunate-Runtime.sh"])
        self.assertEqual("unspecified", attrs_by_path["Shutsujin.sh"])
        self.assertEqual("unspecified", attrs_by_path["shutsujin_departure.sh"])
        self.assertEqual("unspecified", attrs_by_path["shogunate_mod/runtime/runtime_launcher.sh"])
        self.assertEqual("unspecified", attrs_by_path["shogunate_mod/runtime/departure.sh"])
        self.assertEqual(
            "unspecified",
            attrs_by_path["shogunate_mod/package/templates/memory/global_context.md.sample"],
        )
        self.assertNotIn('"shogunate_mod/mobile/"', package)
        self.assertNotIn('"images/"', package)
        self.assertNotIn('"reports/"', package)
        self.assertIn("  - path: images/ and reports/", manifest)
        self.assertIn("package_gitattributes: shogunate_mod/package/gitattributes", manifest)
        self.assertIn("package_gitignore: shogunate_mod/package/gitignore", manifest)
        self.assertIn("  - path: .gitattributes", manifest)
        self.assertIn("  - path: .gitignore", manifest)
        self.assertIn(
            "require_same_file .gitattributes shogunate_mod/package/gitattributes",
            prepublish,
        )
        self.assertIn(
            "require_same_file .gitignore shogunate_mod/package/gitignore",
            prepublish,
        )
        self.assertIn("not part of the runtime package surface", manifest)

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

    def test_release_archive_actual_runtime_boundary(self):
        files = release_archive_files()
        required = {
            "README.md",
            "README_ja.md",
            "package.json",
            "first_setup.sh",
            "bin/shogunate.js",
            "scripts/shogunate_pair_server.py",
            "shogunate_mod/pair/server.py",
            "shogunate_mod/package/first_setup.sh",
            "shogunate_mod/runtime/departure.sh",
            "config/opencode-permissions.yaml",
            "config/opencode-tui.json",
            "docs/philosophy.md",
            "docs/codd/gunkan_tests.md",
        }
        forbidden_prefixes = (
            "android/",
            "shogunate_mod/mobile/android/",
            "images/",
            "reports/",
            "tests/",
            "shogunate_mod/tests/",
            "queue/",
            "runtime_sandboxes/",
            ".github/workflows/",
            "shogunate_mod/package/workflows/",
        )
        forbidden_exact = {
            ".github/FUNDING.yml",
            ".gitmodules",
            ".gitignore",
            ".gitattributes",
            "package-lock.json",
            "dashboard.md",
            "config/settings.yaml",
            "config/projects.yaml",
            "memory/MEMORY.md",
            "memory/global_context.md",
            "saytask/streaks.yaml",
            "docs/REQS.md",
            "docs/INDEX.md",
            "docs/WORKLOG.md",
            "docs/vps_pr118_verification_plan.md",
            "shogunate_mod/github/FUNDING.yml",
            "shogunate_mod/development/gitmodules",
            "shogunate_mod/package/package-lock.json",
            "shogunate_mod/package/gitattributes",
            "shogunate_mod/package/gitignore",
        }
        missing = sorted(required - files)
        forbidden = sorted(
            rel
            for rel in files
            if rel in forbidden_exact
            or rel.startswith("docs/EXECPLAN_")
            or rel.startswith("docs/HANDOVER_")
            or rel.startswith("docs/UPSTREAM_SYNC_")
            or any(rel.startswith(prefix) for prefix in forbidden_prefixes)
        )

        self.assertEqual([], missing)
        self.assertEqual([], forbidden)

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

    def test_release_archive_includes_runtime_mod_canonical_sources(self):
        manifest = (ROOT / "shogunate_mod" / "manifest.yaml").read_text(encoding="utf-8")
        canonical_files = []

        for rel_path in manifest_mapping_values(manifest, "canonical_paths"):
            normalized = rel_path.rstrip("/")
            if not normalized.startswith("shogunate_mod/"):
                continue
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
        for line in attr_result.stdout.splitlines():
            path, _, value = line.rpartition(": export-ignore: ")
            intentionally_excluded = is_intentionally_release_archive_excluded_mod_path(path)
            if intentionally_excluded and value != "set":
                missing_exclusion.append(path)
            if not intentionally_excluded and value == "set":
                unexpected_excluded.append(path)

        self.assertEqual([], sorted(set(unexpected_excluded)))
        self.assertEqual([], sorted(set(missing_exclusion)))

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

        root_files = []
        for dirpath, dirnames, filenames in os.walk(root_android):
            dirnames[:] = [name for name in dirnames if name not in excluded_dirs]
            current_dir = Path(dirpath)
            for filename in filenames:
                path = current_dir / filename
                rel = path.relative_to(root_android)
                if filename in excluded_names:
                    continue
                if path.suffix in excluded_suffixes:
                    continue
                root_files.append(rel)

        self.assertGreater(len(root_files), 50)
        self.assertIn("require_android_sources_synced", prepublish)
        self.assertIn("import os\nfrom pathlib import Path", prepublish)
        self.assertIn("for dirpath, dirnames, filenames in os.walk(root_android):", prepublish)
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

    def test_docs_describe_curl_and_npm_package_distribution(self):
        docs = "\n".join(
            [
                (ROOT / "README.md").read_text(encoding="utf-8"),
                (ROOT / "README_ja.md").read_text(encoding="utf-8"),
            ]
        )
        self.assertIn("curl -fsSL", docs)
        self.assertIn("npx @tsukinowarin/shogunate install", docs)
        self.assertIn("shogunate pair", docs)
        self.assertIn("multi-agent-shognate-package.tar.gz", docs)
        self.assertIn("multi-agent-shognate-package.zip", docs)
        self.assertIn("v5.0.0.0", docs)
        self.assertIn("v5.0.0.12", docs)
        self.assertNotIn("install.bat", docs)
        self.assertNotIn("android/release", docs)
        self.assertNotIn("multi-agent-shognate-installer-<version>", docs)


if __name__ == "__main__":
    unittest.main()
