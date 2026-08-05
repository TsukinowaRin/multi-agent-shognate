#!/usr/bin/env python3
"""Role-scoped MoA configuration and lifecycle tests."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.moa.manager import (  # noqa: E402
    MemberProfile,
    MoaError,
    MoaManager,
    RoleProfile,
    load_moa_config,
    main,
    parse_member_specs,
    parse_role_profile,
)


class RecordingTransport:
    def __init__(self, failures: set[str] | None = None) -> None:
        self.failures = failures or set()
        self.calls: list[tuple[str, str, str]] = []

    def send(self, sender: str, target: str, pointer: str) -> tuple[bool, str]:
        self.calls.append((sender, target, pointer))
        if target in self.failures:
            return False, "simulated failure"
        return True, "sent"


def member(
    alias: str,
    *,
    agent: str | None = None,
    cli_type: str = "codex",
    model: str = "gpt-5.6",
    runtime: str | None = None,
) -> MemberProfile:
    return MemberProfile(
        alias=alias,
        agent=agent or f"gunkan-{alias}",
        type=cli_type,
        model=model,
        runtime=runtime or f"pane-{alias}",
    )


def profile(*, dissolve_after: str = "finalized") -> RoleProfile:
    members = {
        "gemini": member(
            "gemini",
            cli_type="gemini",
            model="gemini-3.1-pro",
        ),
        "grok": member("grok", cli_type="grok", model="grok-4.5"),
        "codex": member("codex"),
    }
    return RoleProfile(
        mode="moa",
        representative="gemini",
        members=members,
        quorum=2,
        decision_policy="representative",
        dissolve_after=dissolve_after,
    )


def make_manager(tmp_path: Path, transport: RecordingTransport | None = None) -> MoaManager:
    project = tmp_path / "project"
    runtime = tmp_path / "runtime"
    project.mkdir()
    runtime.mkdir()
    return MoaManager(project, runtime, transport=transport or RecordingTransport())


def write_brief(manager: MoaManager, text: str = "監査計画を作る") -> Path:
    brief = manager.project_root / "brief.txt"
    brief.write_text(text, encoding="utf-8")
    return brief


def write_artifact(manager: MoaManager, name: str, text: str) -> Path:
    artifact = manager.project_root / name
    artifact.write_text(text, encoding="utf-8")
    return artifact


def test_parse_role_profile_requires_representative_and_unique_runtime_model():
    parsed = parse_role_profile(profile().to_dict(), field="roles.gunkan")
    assert parsed.representative == "gemini"
    assert parsed.quorum == 2

    missing = profile().to_dict()
    missing["representative"] = "unknown"
    with pytest.raises(MoaError, match="representative must be a member"):
        parse_role_profile(missing, field="roles.gunkan")

    duplicate = profile().to_dict()
    duplicate["members"]["codex-copy"] = duplicate["members"]["codex"].copy()
    duplicate["members"]["codex-copy"]["agent"] = "another-name"
    with pytest.raises(MoaError, match="same model and runtime"):
        parse_role_profile(duplicate, field="roles.gunkan")


def test_parse_member_specs_is_strict_and_rejects_duplicate_alias():
    parsed = parse_member_specs(
        [
            "gemini=gunkan-gemini,gemini,gemini-3.1-pro,agy-pane",
            "codex=gunkan-codex,codex,gpt-5.6,codex-pane",
        ]
    )
    assert parsed["gemini"].agent == "gunkan-gemini"
    assert parsed["codex"].runtime == "codex-pane"

    with pytest.raises(MoaError, match="ALIAS=AGENT,TYPE,MODEL,RUNTIME"):
        parse_member_specs(["bad=codex"])
    with pytest.raises(MoaError, match="duplicate member alias"):
        parse_member_specs(
            [
                "same=a,codex,m,r1",
                "same=b,codex,m,r2",
            ]
        )


def test_persistent_config_supports_default_moa_and_single(tmp_path: Path):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    manager.configure("ashigaru1", RoleProfile.single())

    config = load_moa_config(manager.config_path)
    assert config.roles["gunkan"].mode == "moa"
    assert config.roles["ashigaru1"].mode == "single"
    assert manager.resolve_profile("gunkan").representative == "gemini"
    with pytest.raises(MoaError, match="configured as single"):
        manager.resolve_profile("ashigaru1")


def test_deploy_writes_bound_assignments_and_notifies_only_the_representative(
    tmp_path: Path,
):
    transport = RecordingTransport()
    manager = make_manager(tmp_path, transport)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-42", write_brief(manager), sender="shogun")

    assert state["status"] == "active"
    assert state["generation"] == 1
    assert len(state["assignments"]) == 3

    # External traffic keeps one address per role: only the representative is
    # woken, so the existing watcher escalation ladder covers the whole role.
    assert len(transport.calls) == 1
    sender, target, body = transport.calls[0]
    assert sender == "shogun"
    assert target == "gunkan-gemini"
    assert "assignment pointer:" in body
    assert state["deployment_id"] in body
    assert "監査計画を作る" not in body

    assert state["assignments"]["gemini"]["delivery"]["ok"] is True
    for alias in ("grok", "codex"):
        # None separates "not sent yet" from "send failed"; the representative
        # relays these through notify_members.
        assert state["assignments"][alias]["delivery"]["ok"] is None
        assert state["assignments"][alias]["delivery"]["detail"] == (
            "representative-relay"
        )

    assignment_path = manager.runtime_root / state["assignments"]["codex"]["path"]
    assignment = yaml.safe_load(assignment_path.read_text(encoding="utf-8"))
    assert assignment["task_id"] == "task-42"
    assert assignment["role"] == "gunkan"
    assert assignment["generation"] == 1
    assert assignment["brief_path"].endswith("/generation-1/brief.txt")
    assert "<assignment_digest>" in assignment["submission"]["command"]
    assert assignment["assignment_digest"] == state["assignments"]["codex"]["digest"]


def test_deploy_records_representative_delivery_failure(tmp_path: Path):
    transport = RecordingTransport(failures={"gunkan-gemini"})
    manager = make_manager(tmp_path, transport)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-fail", write_brief(manager), sender="shogun")

    assert state["status"] == "active"
    assert state["assignments"]["gemini"]["delivery"]["ok"] is False
    assert state["assignments"]["gemini"]["delivery"]["detail"] == "simulated failure"


def test_notify_members_fans_out_from_the_representative(tmp_path: Path, monkeypatch):
    transport = RecordingTransport()
    manager = make_manager(tmp_path, transport)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-fan", write_brief(manager), sender="shogun")
    deployment_id = state["deployment_id"]
    transport.calls.clear()

    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    with pytest.raises(MoaError, match="only the representative"):
        manager.notify_members("gunkan", "task-fan")

    monkeypatch.setenv("AGENT_ID", "gunkan-gemini")
    fanned = manager.notify_members("gunkan", "task-fan")

    assert {target for _, target, _ in transport.calls} == {
        "gunkan-grok",
        "gunkan-codex",
    }
    for sender, _, body in transport.calls:
        assert sender == "gunkan-gemini"
        assert deployment_id in body
        assert "監査計画を作る" not in body
    for alias in ("grok", "codex"):
        assert fanned["assignments"][alias]["delivery"]["ok"] is True


def test_members_roster_is_published_on_deploy_and_cleared_on_dissolve(
    tmp_path: Path,
):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile(dissolve_after="manual"))
    manager.deploy("gunkan", "task-roster", write_brief(manager), sender="shogun")

    roster = manager.runtime_root / "queue/runtime/moa_members.tsv"
    rows = [
        line.split("\t")
        for line in roster.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    assert {row[0] for row in rows} == {
        "gunkan-gemini",
        "gunkan-grok",
        "gunkan-codex",
    }
    assert all(row[1] == "gunkan" and row[2] == "task-roster" for row in rows)

    manager.dissolve("gunkan", "task-roster")
    # The supervisor treats an absent roster as "no MoA members", so the file
    # is removed rather than left empty.
    assert not roster.exists()


def test_status_reports_inbox_read_state(tmp_path: Path):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-read", write_brief(manager), sender="shogun")
    deployment_id = state["deployment_id"]

    assert "read" not in manager.status("gunkan", "task-read")["assignments"]["gemini"][
        "delivery"
    ]

    inbox_dir = manager.runtime_root / "queue/inbox"
    inbox_dir.mkdir(parents=True, exist_ok=True)
    inbox = inbox_dir / "gunkan-gemini.yaml"
    inbox.write_text(
        yaml.safe_dump(
            {
                "messages": [
                    {
                        "id": "msg-1",
                        "from": "shogun",
                        "type": "task_assigned",
                        "content": f"pointer deployment_id={deployment_id}",
                        "read": False,
                    }
                ]
            },
            allow_unicode=True,
        ),
        encoding="utf-8",
    )
    assert manager.status("gunkan", "task-read")["assignments"]["gemini"]["delivery"][
        "read"
    ] is False

    data = yaml.safe_load(inbox.read_text(encoding="utf-8"))
    data["messages"][0]["read"] = True
    inbox.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    assert manager.status("gunkan", "task-read")["assignments"]["gemini"]["delivery"][
        "read"
    ] is True


def test_temporary_profile_overrides_default_without_mutating_it(tmp_path: Path):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    temporary = RoleProfile(
        mode="moa",
        representative="codex",
        members={
            "codex": member("codex"),
            "grok": member("grok", cli_type="grok", model="grok-4.5"),
        },
        quorum=2,
        decision_policy="representative",
        dissolve_after="manual",
    )
    state = manager.deploy(
        "gunkan",
        "task-temp",
        write_brief(manager),
        sender="shogun",
        override=temporary,
    )
    assert state["profile"]["representative"] == "codex"
    assert manager.resolve_profile("gunkan").representative == "gemini"


def test_active_deploy_is_idempotent_but_rejects_different_input(tmp_path: Path):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    brief = write_brief(manager)
    first = manager.deploy("gunkan", "task-idem", brief, sender="shogun")
    second = manager.deploy("gunkan", "task-idem", brief, sender="shogun")
    assert second["deployment_id"] == first["deployment_id"]

    brief.write_text("別の任務", encoding="utf-8")
    with pytest.raises(MoaError, match="active deployment already exists"):
        manager.deploy("gunkan", "task-idem", brief, sender="shogun")


def test_submit_checks_actor_assignment_digest_and_generation(tmp_path: Path, monkeypatch):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-submit", write_brief(manager), sender="shogun")
    digest = state["assignments"]["codex"]["digest"]
    proposal = write_artifact(manager, "codex-proposal.txt", "Codex案")

    monkeypatch.setenv("AGENT_ID", "wrong-agent")
    with pytest.raises(MoaError, match="actor does not match"):
        manager.submit("gunkan", "task-submit", "codex", digest, proposal)

    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    with pytest.raises(MoaError, match="assignment digest mismatch"):
        manager.submit("gunkan", "task-submit", "codex", "0" * 64, proposal)

    result = manager.submit("gunkan", "task-submit", "codex", digest, proposal)
    assert result["proposals"]["codex"]["artifact_digest"]

    assignment_path = manager.runtime_root / state["assignments"]["codex"]["path"]
    assignment = yaml.safe_load(assignment_path.read_text(encoding="utf-8"))
    assignment["generation"] = 999
    assignment_path.write_text(yaml.safe_dump(assignment), encoding="utf-8")
    with pytest.raises(MoaError, match="assignment provenance mismatch"):
        manager.submit("gunkan", "task-submit", "codex", digest, proposal)


def test_only_representative_can_finalize_and_quorum_is_fail_closed(tmp_path: Path, monkeypatch):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-final", write_brief(manager), sender="shogun")

    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    codex = write_artifact(manager, "codex.txt", "Codex提案")
    manager.submit(
        "gunkan",
        "task-final",
        "codex",
        state["assignments"]["codex"]["digest"],
        codex,
    )
    final = write_artifact(manager, "final.txt", "正式なGunkan判定")
    with pytest.raises(MoaError, match="only the representative"):
        manager.finalize("gunkan", "task-final", final)

    monkeypatch.setenv("AGENT_ID", "gunkan-gemini")
    with pytest.raises(MoaError, match="quorum not met"):
        manager.finalize("gunkan", "task-final", final)

    gemini = write_artifact(manager, "gemini.txt", "Gemini提案")
    manager.submit(
        "gunkan",
        "task-final",
        "gemini",
        state["assignments"]["gemini"]["digest"],
        gemini,
    )
    completed = manager.finalize("gunkan", "task-final", final)
    assert completed["status"] == "dissolved"
    receipt = yaml.safe_load(
        (manager.runtime_root / completed["final"]["receipt_path"]).read_text(encoding="utf-8")
    )
    assert receipt["representative"] == "gemini"
    assert sorted(receipt["proposal_digests"]) == ["codex", "gemini"]


def test_dissolved_task_redeploys_with_next_generation(tmp_path: Path):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile(dissolve_after="manual"))
    brief = write_brief(manager)
    first = manager.deploy("gunkan", "task-next", brief, sender="shogun")
    dissolved = manager.dissolve("gunkan", "task-next")
    assert dissolved["status"] == "dissolved"
    second = manager.deploy("gunkan", "task-next", brief, sender="shogun")
    assert second["generation"] == first["generation"] + 1


def test_critical_veto_blocks_representative_until_new_generation(tmp_path: Path, monkeypatch):
    manager = make_manager(tmp_path)
    configured = profile(dissolve_after="manual").to_dict()
    configured["decision_policy"] = "critical_veto"
    manager.configure("gunkan", parse_role_profile(configured, field="roles.gunkan"))
    state = manager.deploy("gunkan", "task-veto", write_brief(manager), sender="shogun")

    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    manager.submit(
        "gunkan",
        "task-veto",
        "codex",
        state["assignments"]["codex"]["digest"],
        write_artifact(manager, "veto.txt", "重大問題あり"),
        blocking=True,
    )
    monkeypatch.setenv("AGENT_ID", "gunkan-gemini")
    manager.submit(
        "gunkan",
        "task-veto",
        "gemini",
        state["assignments"]["gemini"]["digest"],
        write_artifact(manager, "leader.txt", "代表案"),
    )
    with pytest.raises(MoaError, match="critical veto is unresolved"):
        manager.finalize(
            "gunkan",
            "task-veto",
            write_artifact(manager, "veto-final.txt", "誤って確定してはいけない"),
        )


def test_artifacts_must_stay_inside_project(tmp_path: Path, monkeypatch):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-path", write_brief(manager), sender="shogun")
    outside = tmp_path / "outside.txt"
    outside.write_text("outside", encoding="utf-8")
    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    with pytest.raises(MoaError, match="must be inside the project"):
        manager.submit(
            "gunkan",
            "task-path",
            "codex",
            state["assignments"]["codex"]["digest"],
            outside,
        )


def test_tampered_assignment_path_cannot_escape_runtime(tmp_path: Path, monkeypatch):
    manager = make_manager(tmp_path)
    manager.configure("gunkan", profile())
    state = manager.deploy("gunkan", "task-escape", write_brief(manager), sender="shogun")
    state_path = (
        manager.runtime_root
        / "queue/moa/gunkan/task-escape/generation-1/state.yaml"
    )
    stored = yaml.safe_load(state_path.read_text(encoding="utf-8"))
    stored["assignments"]["codex"]["path"] = "../../../../../../outside.yaml"
    state_path.write_text(yaml.safe_dump(stored), encoding="utf-8")
    monkeypatch.setenv("AGENT_ID", "gunkan-codex")
    with pytest.raises(MoaError, match="assignment path escapes"):
        manager.submit(
            "gunkan",
            "task-escape",
            "codex",
            state["assignments"]["codex"]["digest"],
            write_artifact(manager, "escape-proposal.txt", "提案"),
        )


def test_cli_config_show_and_deploy_json(tmp_path: Path, capsys):
    project = tmp_path / "project"
    runtime = tmp_path / "runtime"
    project.mkdir()
    runtime.mkdir()
    brief = project / "brief.txt"
    brief.write_text("CLI試験", encoding="utf-8")
    common = [
        "--project-root",
        str(project),
        "--runtime-root",
        str(runtime),
        "--json",
    ]
    member_args = [
        "--member",
        "gemini=gunkan-gemini,gemini,gemini-3.1-pro,agy-pane",
        "--member",
        "codex=gunkan-codex,codex,gpt-5.6,codex-pane",
        "--representative",
        "gemini",
        "--quorum",
        "2",
    ]
    assert main([*common, "configure", "gunkan", "--mode", "moa", *member_args]) == 0
    configured = json.loads(capsys.readouterr().out)
    assert configured["roles"]["gunkan"]["mode"] == "moa"

    assert main([*common, "show", "gunkan"]) == 0
    shown = json.loads(capsys.readouterr().out)
    assert shown["representative"] == "gemini"

    assert (
        main(
            [
                *common,
                "deploy",
                "gunkan",
                "--task-id",
                "cli-task",
                "--brief-file",
                str(brief),
                "--sender",
                "shogun",
            ]
        )
        == 0
    )
    deployed = json.loads(capsys.readouterr().out)
    assert deployed["role"] == "gunkan"
    assert deployed["task_id"] == "cli-task"


def test_curl_bootstrap_exposes_generic_moa_command_without_node():
    source = (ROOT / "shogunate_mod/package/bootstrap.sh").read_text(encoding="utf-8")
    assert "shogunate moa" in source
    assert "shogunate_mod/moa/manager.py" in source
    assert "npm_cli.js" not in source
    assert "bin/shogunate.js" not in source


def test_official_agmsg_scripts_deliver_distinct_moa_assignments(
    tmp_path: Path, monkeypatch
):
    """Exercise official join/send/inbox scripts over a real SQLite database."""
    source_skill = Path.home() / ".agents/skills/agmsg"
    if not (source_skill / "scripts/send.sh").is_file():
        pytest.fail("installed AGMSG scripts are required")

    isolated_skill = tmp_path / "agmsg"
    shutil.copytree(source_skill / "scripts", isolated_skill / "scripts")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    sqlite_wrapper = bin_dir / "sqlite3"
    helper = ROOT / "tests/helpers/sqlite3_python_cli.py"
    sqlite_wrapper.write_text(
        "#!/usr/bin/env bash\nexec python3 "
        + repr(str(helper))
        + " \"$@\"\n",
        encoding="utf-8",
    )
    sqlite_wrapper.chmod(0o755)
    storage = tmp_path / "agmsg-storage"
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ.get('PATH', '')}")
    monkeypatch.setenv("AGMSG_SKILL_DIR", str(isolated_skill))
    monkeypatch.setenv("AGMSG_STORAGE_PATH", str(storage))
    monkeypatch.setenv("AGMSG_RESOLVE_PROJECT", "0")

    e2e_root = tmp_path / "moa-e2e"
    e2e_root.mkdir()
    project = e2e_root / "project"
    runtime = e2e_root / "runtime"
    project.mkdir()
    runtime.mkdir()
    # inbox is the default transport now; this case covers the AGMSG path that
    # environments without tmux panes still depend on, so opt in explicitly.
    (runtime / "config").mkdir()
    (runtime / "config/settings.yaml").write_text(
        yaml.safe_dump({"transport": {"mode": "agmsg"}}), encoding="utf-8"
    )
    manager = MoaManager(project, runtime)
    manager.configure("gunkan", profile())
    setup = manager.agmsg_setup("gunkan")
    assert setup["members"]
    assert all(item["ok"] for item in setup["members"].values()), setup

    state = manager.deploy(
        "gunkan",
        "agmsg-e2e",
        write_brief(manager, "AGMSG MoA E2E"),
        sender="shogun",
    )
    assert state["assignments"]["gemini"]["delivery"]["ok"] is True

    # deploy wakes the representative only; the rest arrive via the fan-out.
    monkeypatch.setenv("AGENT_ID", "gunkan-gemini")
    state = manager.notify_members("gunkan", "agmsg-e2e")
    assert all(
        item["delivery"]["ok"] for item in state["assignments"].values()
    ), state["assignments"]

    inbox_script = isolated_skill / "scripts/inbox.sh"
    bodies: dict[str, str] = {}
    for alias, item in profile().members.items():
        result = subprocess.run(
            ["bash", str(inbox_script), "shogunate", item.agent],
            env=os.environ.copy(),
            text=True,
            capture_output=True,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        assert "1 new message(s)" in result.stdout
        assignment_path = state["assignments"][alias]["path"]
        assert assignment_path in result.stdout
        bodies[alias] = result.stdout
    assert len(set(bodies.values())) == 3

    for alias in ("codex", "gemini"):
        item = profile().members[alias]
        monkeypatch.setenv("AGENT_ID", item.agent)
        manager.submit(
            "gunkan",
            "agmsg-e2e",
            alias,
            state["assignments"][alias]["digest"],
            write_artifact(manager, f"{alias}-e2e.txt", f"{alias}の独立提案"),
        )
    monkeypatch.setenv("AGENT_ID", "gunkan-gemini")
    completed = manager.finalize(
        "gunkan",
        "agmsg-e2e",
        write_artifact(manager, "agmsg-e2e-final.txt", "代表が統合した正式成果物"),
    )
    assert completed["status"] == "dissolved"
    assert sorted(completed["final"]) == [
        "artifact_digest",
        "artifact_path",
        "receipt_path",
    ]
