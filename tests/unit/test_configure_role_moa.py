from __future__ import annotations

import copy
import sys
from pathlib import Path

import yaml

from shogunate_mod.configure import runtime_roles
from shogunate_mod.moa.manager import load_moa_config, parse_role_profile


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())


def settings() -> dict:
    return {
        "language": "ja",
        "topology": {"active_ashigaru": ["ashigaru1"]},
        "cli": {
            "default": "codex",
            "agents": {
                role: {"type": "codex"}
                for role in ("shogun", "gunkan", "karo", "gunshi", "ashigaru1")
            },
        },
    }


def run_main(
    monkeypatch,
    settings_path: Path,
    moa_path: Path,
    argv: list[str],
    responses: list[str] | None = None,
) -> int:
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "runtime_roles.py",
            "--settings",
            str(settings_path),
            "--moa-config",
            str(moa_path),
            *argv,
        ],
    )
    if responses is not None:
        answers = iter(responses)
        monkeypatch.setattr("builtins.input", lambda _prompt="": next(answers))
    return runtime_roles.main()


def test_interactive_configure_uses_member_count_to_save_default_moa(
    tmp_path: Path, monkeypatch, capsys
):
    settings_path = tmp_path / "config/settings.yaml"
    moa_path = tmp_path / "config/moa.yaml"
    settings_path.parent.mkdir(parents=True)
    settings_path.write_text(
        yaml.safe_dump(settings(), sort_keys=False), encoding="utf-8"
    )

    responses = [
        "",  # cli.default
        "1", "",  # shogun: single, codex
        "3", "codex", "grok", "antigravity",  # gunkan: representative first
        "1", "",  # karo
        "1", "",  # gunshi
        "1",  # active ashigaru count
        "1", "",  # ashigaru1
    ]
    assert run_main(monkeypatch, settings_path, moa_path, [], responses) == 0

    configured = load_moa_config(moa_path)
    gunkan = configured.roles["gunkan"]
    assert gunkan.mode == "moa"
    assert gunkan.representative == "leader"
    assert list(gunkan.members) == ["leader", "member2", "member3"]
    assert [item.type for item in gunkan.members.values()] == [
        "codex",
        "grok",
        "antigravity",
    ]
    assert gunkan.quorum == 2
    assert gunkan.decision_policy == "critical_veto"
    assert configured.roles["shogun"].mode == "single"
    assert configured.roles["karo"].mode == "single"
    assert configured.roles["gunshi"].mode == "single"
    assert configured.roles["ashigaru1"].mode == "single"
    saved_settings = yaml.safe_load(settings_path.read_text(encoding="utf-8"))
    assert saved_settings["cli"]["agents"]["gunkan"]["type"] == "codex"
    assert "まず代表者を選びます" in capsys.readouterr().out


def test_reconfiguring_moa_preserves_existing_identities_and_policy():
    existing = parse_role_profile(
        {
            "mode": "moa",
            "representative": "gemini",
            "members": {
                "gemini": {
                    "agent": "gunkan-gemini",
                    "type": "gemini",
                    "model": "gemini-3.1-pro",
                    "runtime": "agy-pane",
                },
                "grok": {
                    "agent": "gunkan-grok",
                    "type": "grok",
                    "model": "grok-4.5",
                    "runtime": "grok-pane",
                },
            },
            "quorum": 2,
            "decision_policy": "critical_veto",
            "dissolve_after": "manual",
        },
        field="roles.gunkan",
    )

    updated = runtime_roles.build_role_profile(
        "gunkan", ["antigravity", "codex", "grok"], existing=existing
    )
    assert updated.representative == "gemini"
    assert list(updated.members) == ["gemini", "grok", "member3"]
    assert updated.members["gemini"].agent == "gunkan-gemini"
    assert updated.members["gemini"].runtime == "agy-pane"
    assert updated.members["gemini"].model == "gemini-3.1-pro"
    assert updated.members["grok"].agent == "gunkan-grok"
    assert updated.members["grok"].model == ""
    assert updated.decision_policy == "critical_veto"
    assert updated.dissolve_after == "manual"


def test_noninteractive_configure_does_not_change_moa_defaults(
    tmp_path: Path, monkeypatch
):
    settings_path = tmp_path / "config/settings.yaml"
    moa_path = tmp_path / "config/moa.yaml"
    settings_path.parent.mkdir(parents=True)
    settings_path.write_text(
        yaml.safe_dump(settings(), sort_keys=False), encoding="utf-8"
    )
    original = {
        "schema_version": 1,
        "roles": {"gunkan": {"mode": "single"}},
    }
    moa_path.write_text(
        yaml.safe_dump(copy.deepcopy(original), sort_keys=False), encoding="utf-8"
    )

    args = [
        "--ashigaru-count", "1",
        "--shogun", "codex",
        "--gunkan", "codex",
        "--karo", "codex",
        "--gunshi", "codex",
        "--ashigaru1", "codex",
    ]
    assert run_main(monkeypatch, settings_path, moa_path, args) == 0
    assert yaml.safe_load(moa_path.read_text(encoding="utf-8")) == original
