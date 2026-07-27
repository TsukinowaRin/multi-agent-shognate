#!/usr/bin/env python3
"""Gunshi council protocol tests."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file() and (
            candidate / "shogunate_mod" / "gunshi" / "council.py"
        ).is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.gunshi.council import (  # noqa: E402
    CouncilConfig,
    CouncilController,
    CouncilError,
    CouncilSecurityError,
    MemberProfile,
    SubprocessBackend,
    apply_session_override,
    parse_council_config,
    parse_gunkan_profile,
)


def plan(label: str) -> dict:
    return {
        "objective": f"{label} objective",
        "scope": ["gunshi council"],
        "steps": [f"{label} step"],
        "validation": ["targeted tests pass"],
        "stop_conditions": ["scope change"],
        "reconvene_conditions": ["assumption changes"],
    }


class ScriptedBackend:
    def __init__(self, responses: list[tuple[str, str, dict]]) -> None:
        self.responses = list(responses)
        self.calls: list[tuple[str, str, dict]] = []

    def ask(self, member: MemberProfile, phase: str, context: dict) -> dict:
        self.calls.append((member.alias, phase, copy.deepcopy(context)))
        expected_alias, expected_phase, response = self.responses.pop(0)
        assert (member.alias, phase) == (expected_alias, expected_phase)
        return copy.deepcopy(response)


class FailingBackend:
    def ask(self, member: MemberProfile, phase: str, context: dict) -> dict:
        raise CouncilError("simulated model failure")


def config(member_count: int = 3) -> CouncilConfig:
    members = {
        "fable": MemberProfile("fable", "claude", "fable"),
        "opus": MemberProfile("opus", "claude", "opus"),
        "sol": MemberProfile("sol", "codex", "gpt-5.6-sol"),
    }
    return CouncilConfig(
        members=dict(list(members.items())[:member_count]),
        representative="fable",
    )


def draft_response() -> dict:
    return {
        "message": "初案を提示する。",
        "plan": plan("draft"),
        "converged": False,
        "resolutions": [],
        "minority_views": [],
        "unresolved": ["レビュー待ち"],
    }


def review_response(message: str, *, blocking: bool = False) -> dict:
    objections = []
    if blocking:
        objections.append({"summary": "rollback条件が曖昧", "blocking": True})
    return {
        "message": message,
        "objections": objections,
        "improvements": ["検証手順を具体化する"],
    }


def synthesis_response(
    label: str,
    *,
    converged: bool,
    resolutions: list[dict] | None = None,
) -> dict:
    return {
        "message": f"{label}へ改訂する。",
        "plan": plan(label),
        "converged": converged,
        "resolutions": resolutions or [],
        "minority_views": [],
        "unresolved": [] if converged else ["追加検討"],
    }


def audit_response(
    verdict: str = "pass",
    *,
    summary: str = "Gunkan監査に合格した。",
    findings: list[str] | None = None,
    required_changes: list[str] | None = None,
) -> dict:
    return {
        "verdict": verdict,
        "summary": summary,
        "findings": findings or [],
        "required_changes": required_changes or [],
    }


def test_parse_default_config_is_minimal_and_strict():
    settings = {
        "council": {
            "default": {
                "members": {
                    "fable": {"type": "claude", "model": "fable"},
                    "sol": {"type": "codex", "model": "gpt-5.6-sol"},
                },
                "representative": "fable",
            }
        }
    }
    parsed = parse_council_config(settings)
    assert list(parsed.members) == ["fable", "sol"]
    assert parsed.representative == "fable"

    settings["council"]["default"]["members"]["fable"]["role"] = "chair"
    with pytest.raises(CouncilError, match="unknown field"):
        parse_council_config(settings)


@pytest.mark.parametrize(
    "cli_type", ["antigravity", "claude", "codex", "grok", "opencode"]
)
def test_config_accepts_supported_live_council_backends(cli_type: str):
    settings = {
        "council": {
            "default": {
                "members": {
                    "candidate": {"type": cli_type, "model": "test-model"},
                    "sol": {"type": "codex", "model": "gpt-5.6-sol"},
                },
                "representative": "candidate",
            }
        }
    }
    assert parse_council_config(settings).members["candidate"].type == cli_type


def test_config_rejects_missing_representative_and_secret_like_keys():
    missing = {
        "council": {
            "default": {
                "members": {
                    "fable": {"type": "claude", "model": "fable"},
                    "sol": {"type": "codex", "model": "gpt-5.6-sol"},
                },
                "representative": "opus",
            }
        }
    }
    with pytest.raises(CouncilError, match="must be a member"):
        parse_council_config(missing)

    secret = copy.deepcopy(missing)
    secret["council"]["default"]["representative"] = "fable"
    secret["council"]["default"]["members"]["fable"]["api_token"] = "x"
    with pytest.raises(CouncilSecurityError, match="secret-like"):
        parse_council_config(secret)


def test_session_override_replaces_members_without_mutating_default():
    default = config()
    overridden = apply_session_override(
        default,
        [
            "opus=claude:opus5",
            "sol=codex:gpt-5.6-sol",
        ],
        "sol",
    )
    assert list(overridden.members) == ["opus", "sol"]
    assert overridden.representative == "sol"
    assert list(default.members) == ["fable", "opus", "sol"]
    assert default.representative == "fable"

    cli_default = apply_session_override(
        default,
        ["open=opencode", "sol=codex:gpt-5.6-sol"],
        "open",
    )
    assert cli_default.members["open"] == MemberProfile("open", "opencode", "")


@pytest.mark.parametrize("member_count", [2, 3])
def test_two_and_three_member_councils_use_the_same_protocol(
    tmp_path: Path, member_count: int
):
    council_config = config(member_count)
    reviewers = [
        alias for alias in council_config.members if alias != council_config.representative
    ]
    responses = [("fable", "draft", draft_response())]
    for cycle in (1, 2):
        responses.extend(
            (
                alias,
                "review",
                review_response(f"{alias} cycle {cycle}"),
            )
            for alias in reviewers
        )
        responses.append(
            (
                "fable",
                "synthesize",
                synthesis_response(f"revision {cycle + 1}", converged=False),
            )
        )

    backend = ScriptedBackend(responses)
    controller = CouncilController(tmp_path, backend)
    started = controller.start(
        f"common-{member_count}", "共通protocolを確認する", council_config
    )
    after_first = controller.advance(f"common-{member_count}")
    after_second = controller.advance(f"common-{member_count}")

    assert [started["status"], after_first["status"], after_second["status"]] == [
        "deliberating",
        "deliberating",
        "deliberating",
    ]
    assert [started["cycle"], after_first["cycle"], after_second["cycle"]] == [0, 1, 2]
    assert after_second["plan_revision"] == 3

    review_calls = [call for call in backend.calls if call[1] == "review"]
    expected_snapshot_keys = {
        "council_id",
        "plan_id",
        "plan_revision",
        "cycle",
        "status",
        "representative",
        "brief",
        "plan",
        "transcript",
        "open_objections",
        "protocol",
    }
    assert all(set(context) == expected_snapshot_keys for _, _, context in review_calls)
    second_cycle_calls = [call for call in review_calls if call[2]["cycle"] == 2]
    first_cycle_messages = {f"{alias} cycle 1" for alias in reviewers}
    for _, _, context in second_cycle_calls:
        messages = {entry["message"] for entry in context["transcript"]}
        assert first_cycle_messages <= messages


def test_every_member_reads_prior_cycle_shared_transcript(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("opus cycle 1")),
            ("sol", "review", review_response("sol cycle 1")),
            ("fable", "synthesize", synthesis_response("revision 2", converged=False)),
            ("opus", "review", review_response("opus replies to sol")),
            ("sol", "review", review_response("sol replies to opus")),
            ("fable", "synthesize", synthesis_response("revision 3", converged=False)),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-1", "Gunshi拡張を計画する", config())
    controller.advance("council-1")
    controller.advance("council-1")

    second_opus = backend.calls[4][2]
    second_sol = backend.calls[5][2]
    for context in (second_opus, second_sol):
        messages = [entry["message"] for entry in context["transcript"]]
        assert "opus cycle 1" in messages
        assert "sol cycle 1" in messages
        assert context["cycle"] == 2

    # Same-cycle reviewers receive the same snapshot; neither gets ordering advantage.
    assert second_opus["transcript"] == second_sol["transcript"]


def test_closing_proposal_requires_a_final_objection_cycle(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("opus", "review", review_response("最終案に異議なし")),
            ("sol", "review", review_response("最終案に異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("gunkan", "audit", audit_response()),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-2", "計画を作る", config())

    closing = controller.advance("council-2")
    assert closing["status"] == "closing"
    assert not (tmp_path / "queue/council/council-2/handoff.yaml").exists()

    audit_ready = controller.advance("council-2")
    assert audit_ready["status"] == "awaiting_audit"
    assert not (tmp_path / "queue/council/council-2/plan.md").exists()
    assert not (tmp_path / "queue/council/council-2/handoff.yaml").exists()

    dissolved = controller.audit(
        "council-2", MemberProfile("gunkan", "codex", "")
    )
    assert dissolved["status"] == "dissolved"
    assert (tmp_path / "queue/council/council-2/plan.md").is_file()
    handoff = yaml.safe_load(
        (tmp_path / "queue/council/council-2/handoff.yaml").read_text(encoding="utf-8")
    )
    assert handoff["plan_id"] == "COUNCIL-COUNCIL-2"
    assert handoff["plan_revision"] == 3
    assert handoff["representative"] == "fable"
    assert handoff["audit"]["verdict"] == "pass"
    assert handoff["next_owner"] == "gunshi"
    assert handoff["dispatch_owner"] == "karo"
    assert handoff["implementation_owner"] == "ashigaru"


def test_new_blocker_reopens_closing_instead_of_false_convergence(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("opus", "review", review_response("blocker", blocking=True)),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("revision", converged=True)),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-3", "計画を作る", config())
    controller.advance("council-3")
    state = controller.advance("council-3")
    assert state["status"] == "deliberating"
    assert state["open_objections"][0]["blocking"] is True
    assert not (tmp_path / "queue/council/council-3/handoff.yaml").exists()


def test_failed_gunkan_audit_returns_plan_to_deliberation(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("opus", "review", review_response("最終案に異議なし")),
            ("sol", "review", review_response("最終案に異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            (
                "gunkan",
                "audit",
                audit_response(
                    "fail",
                    summary="停止条件が不足している。",
                    findings=["監査で不足を確認"],
                    required_changes=["停止条件を具体化する"],
                ),
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-audit-fail", "計画を作る", config())
    controller.advance("council-audit-fail")
    assert controller.advance("council-audit-fail")["status"] == "awaiting_audit"

    state = controller.audit(
        "council-audit-fail", MemberProfile("gunkan", "codex", "")
    )
    assert state["status"] == "deliberating"
    assert state["audits"][0]["verdict"] == "fail"
    assert state["open_objections"][-1] == {
        "id": "obj-audit-1-1",
        "cycle": 2,
        "speaker": "gunkan",
        "summary": "停止条件を具体化する",
        "blocking": True,
    }
    assert state["unresolved"] == ["停止条件を具体化する"]
    assert state["transcript"][-1]["kind"] == "audit"
    assert not (tmp_path / "queue/council/council-audit-fail/plan.md").exists()
    assert not (tmp_path / "queue/council/council-audit-fail/handoff.yaml").exists()
    audit_context = backend.calls[-1][2]
    assert audit_context["status"] == "awaiting_audit"
    assert audit_context["open_objections"] == []
    assert audit_context["unresolved"] == []
    assert "gunkan" not in audit_context["members"]


def test_audit_is_rejected_before_final_candidate_is_ready(tmp_path: Path):
    backend = ScriptedBackend([("fable", "draft", draft_response())])
    controller = CouncilController(tmp_path, backend)
    controller.start("council-audit-early", "計画を作る", config())

    with pytest.raises(CouncilError, match="awaiting_audit"):
        controller.audit(
            "council-audit-early", MemberProfile("gunkan", "codex", "")
        )

    assert controller.status("council-audit-early")["status"] == "deliberating"
    assert len(backend.calls) == 1


def test_audit_rejects_non_gunkan_identity_without_calling_model(tmp_path: Path):
    backend = ScriptedBackend([("fable", "draft", draft_response())])
    controller = CouncilController(tmp_path, backend)
    controller.start("council-wrong-auditor", "計画を作る", config())

    with pytest.raises(CouncilError, match="Gunkan identity"):
        controller.audit(
            "council-wrong-auditor", MemberProfile("gunshi", "codex", "")
        )

    assert len(backend.calls) == 1


def test_invalid_gunkan_response_leaves_audit_ready_state_unchanged(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("opus", "review", review_response("最終案に異議なし")),
            ("sol", "review", review_response("最終案に異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            (
                "gunkan",
                "audit",
                audit_response("fail", required_changes=[]),
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-invalid-audit", "計画を作る", config())
    controller.advance("council-invalid-audit")
    before = controller.advance("council-invalid-audit")
    assert before["status"] == "awaiting_audit"

    with pytest.raises(CouncilError, match="at least one change"):
        controller.audit(
            "council-invalid-audit", MemberProfile("gunkan", "codex", "")
        )

    assert controller.status("council-invalid-audit") == before
    assert not (tmp_path / "queue/council/council-invalid-audit/plan.md").exists()
    assert not (tmp_path / "queue/council/council-invalid-audit/handoff.yaml").exists()


def test_gunkan_profile_uses_existing_cli_settings_without_new_council_config():
    settings = {
        "cli": {
            "default": "codex",
            "agents": {"gunkan": {"type": "gemini", "fallback": None}},
        }
    }
    profile = parse_gunkan_profile(settings)
    assert profile == MemberProfile("gunkan", "antigravity", "")
    assert parse_gunkan_profile(settings, "grok:grok-4.5") == MemberProfile(
        "gunkan", "grok", "grok-4.5"
    )
    assert parse_gunkan_profile(settings, "opencode") == MemberProfile(
        "gunkan", "opencode", ""
    )
    with pytest.raises(CouncilError, match="unsupported Gunkan CLI"):
        parse_gunkan_profile(settings, "kilo")


def test_resolved_blocker_can_converge_after_another_final_window(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("blocker", blocking=True)),
            ("sol", "review", review_response("異議なし")),
            (
                "fable",
                "synthesize",
                synthesis_response(
                    "fixed",
                    converged=True,
                    resolutions=[
                        {
                            "objection_id": "obj-1-opus-1",
                            "status": "resolved",
                            "reason": "rollback条件を追加した",
                        }
                    ],
                ),
            ),
            ("opus", "review", review_response("解決を確認")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("fixed", converged=True)),
            ("gunkan", "audit", audit_response()),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-4", "計画を作る", config())
    state = controller.advance("council-4")
    assert state["status"] == "closing"
    state = controller.advance("council-4")
    assert state["status"] == "awaiting_audit"
    state = controller.audit("council-4", MemberProfile("gunkan", "codex", ""))
    assert state["status"] == "dissolved"


def test_changed_closing_candidate_gets_another_objection_window(tmp_path: Path):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("candidate", converged=True)),
            ("opus", "review", review_response("軽微な改善")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("changed", converged=True)),
            ("opus", "review", review_response("変更を確認")),
            ("sol", "review", review_response("変更を確認")),
            ("fable", "synthesize", synthesis_response("changed", converged=True)),
            ("gunkan", "audit", audit_response()),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-change", "計画を作る", config())
    assert controller.advance("council-change")["status"] == "closing"
    assert controller.advance("council-change")["status"] == "closing"
    assert controller.advance("council-change")["status"] == "awaiting_audit"
    assert controller.audit(
        "council-change", MemberProfile("gunkan", "codex", "")
    )["status"] == "dissolved"


def test_concurrent_advance_is_rejected(tmp_path: Path):
    backend = ScriptedBackend([("fable", "draft", draft_response())])
    controller = CouncilController(tmp_path, backend)
    controller.start("council-lock", "計画を作る", config())
    with controller.store.mutation_lock("council-lock"):
        with pytest.raises(CouncilError, match="already being advanced"):
            controller.advance("council-lock")


def test_tampered_state_cannot_redirect_writes_or_inject_profile_fields(tmp_path: Path):
    backend = ScriptedBackend([("fable", "draft", draft_response())])
    controller = CouncilController(tmp_path, backend)
    controller.start("council-state", "計画を作る", config())
    state_path = tmp_path / "queue/council/council-state/state.yaml"
    state = yaml.safe_load(state_path.read_text(encoding="utf-8"))
    state["council_id"] = "other-council"
    state_path.write_text(yaml.safe_dump(state), encoding="utf-8")
    with pytest.raises(CouncilSecurityError, match="does not match"):
        controller.status("council-state")


def test_brief_and_model_output_are_bounded(tmp_path: Path):
    controller = CouncilController(tmp_path, ScriptedBackend([]))
    with pytest.raises(CouncilSecurityError, match="control"):
        controller.start("council-5", "bad\x00brief", config())

    backend = ScriptedBackend(
        [
            (
                "fable",
                "draft",
                {
                    **draft_response(),
                    "message": "x" * 70000,
                },
            )
        ]
    )
    controller = CouncilController(tmp_path, backend)
    with pytest.raises(CouncilError, match="too long"):
        controller.start("council-6", "safe brief", config())


def test_failed_initial_model_call_does_not_reserve_council_id(tmp_path: Path):
    controller = CouncilController(tmp_path, FailingBackend())
    with pytest.raises(CouncilError, match="simulated model failure"):
        controller.start("retryable-council", "safe brief", config())
    assert not (tmp_path / "queue/council/retryable-council").exists()

    retry = CouncilController(
        tmp_path,
        ScriptedBackend([("fable", "draft", draft_response())]),
    )
    assert retry.start("retryable-council", "safe brief", config())["status"] == "deliberating"


def test_codex_backend_uses_fixed_read_only_one_shot_argv(tmp_path: Path, monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        output_path = Path(argv[argv.index("-o") + 1])
        output_path.write_text(json.dumps(review_response("review")), encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, "", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    backend = SubprocessBackend(tmp_path)
    result = backend.ask(
        MemberProfile("sol", "codex", "gpt-5.6-sol"),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "review"
    argv, kwargs = calls[0]
    assert argv[:2] == ["codex", "exec"]
    assert ["--sandbox", "read-only"] == argv[2:4]
    assert "--ephemeral" in argv
    assert "--ignore-user-config" in argv
    assert ["--model", "gpt-5.6-sol"] == argv[
        argv.index("--model") : argv.index("--model") + 2
    ]
    assert argv[-1] == "-"
    assert kwargs["shell"] is False
    assert kwargs["input"] is not None


def test_claude_backend_disables_tools_and_session_persistence(tmp_path: Path, monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        payload = {"structured_output": review_response("review")}
        return subprocess.CompletedProcess(argv, 0, json.dumps(payload), "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    backend = SubprocessBackend(tmp_path)
    result = backend.ask(
        MemberProfile("opus", "claude", "opus5"),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "review"
    argv, kwargs = calls[0]
    assert argv[0] == "claude"
    assert argv[argv.index("--tools") + 1] == ""
    assert "--no-session-persistence" in argv
    assert argv[argv.index("--permission-mode") + 1] == "plan"
    assert kwargs["shell"] is False


def test_grok_backend_removes_tools_web_memory_and_subagents(tmp_path: Path, monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        payload = {
            "structuredOutput": review_response("review"),
            "modelUsage": {"grok-4.5": {"requests": 1}},
            "requestId": "request-1",
        }
        return subprocess.CompletedProcess(argv, 0, json.dumps(payload), "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    backend = SubprocessBackend(tmp_path)
    result = backend.ask(
        MemberProfile("grok", "grok", "grok-4.5"),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "review"
    argv, kwargs = calls[0]
    assert argv[0] == "grok"
    assert argv[argv.index("--permission-mode") + 1] == "plan"
    assert "--sandbox" not in argv
    assert argv[argv.index("--tools") + 1] == ""
    assert "--disable-web-search" in argv
    assert "--no-memory" in argv
    assert "--no-subagents" in argv
    assert argv[argv.index("--max-turns") + 1] == "1"
    assert argv[argv.index("--model") + 1] == "grok-4.5"
    assert "--json-schema" in argv
    assert kwargs["shell"] is False


def test_antigravity_backend_uses_plan_mode_and_sandbox(tmp_path: Path, monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        return subprocess.CompletedProcess(argv, 0, json.dumps(review_response("review")), "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    backend = SubprocessBackend(tmp_path)
    result = backend.ask(
        MemberProfile("agy", "antigravity", "gemini-3.1-pro-high"),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "review"
    argv, kwargs = calls[0]
    assert argv[0] == "agy"
    assert Path(argv[argv.index("--add-dir") + 1]).is_absolute()
    assert argv[argv.index("--mode") + 1] == "plan"
    assert "--sandbox" in argv
    assert argv[argv.index("--model") + 1] == "gemini-3.1-pro-high"
    assert argv[argv.index("--print-timeout") + 1] == "900s"
    assert kwargs["shell"] is False


def test_antigravity_backend_omits_model_flag_for_cli_default(tmp_path: Path, monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        return subprocess.CompletedProcess(argv, 0, json.dumps(audit_response()), "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    result = SubprocessBackend(tmp_path).ask(
        MemberProfile("gunkan", "antigravity", ""),
        "audit",
        {"status": "awaiting_audit"},
    )
    assert result["verdict"] == "pass"
    assert "--model" not in calls[0][0]


def test_opencode_backend_uses_tool_deny_agent_and_strict_json_events(
    tmp_path: Path, monkeypatch
):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        payload = json.dumps(review_response("review"))
        events = [
            {"type": "step_start", "part": {"type": "step-start"}},
            {"type": "text", "part": {"type": "text", "text": payload}},
            {"type": "step_finish", "part": {"type": "step-finish"}},
        ]
        stdout = "\n".join(json.dumps(event) for event in events)
        return subprocess.CompletedProcess(argv, 0, stdout, "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    result = SubprocessBackend(tmp_path).ask(
        MemberProfile("open", "opencode", ""),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "review"
    argv, kwargs = calls[0]
    assert argv[:2] == ["opencode", "run"]
    assert "--pure" in argv
    assert argv[argv.index("--agent") + 1] == "council"
    assert argv[argv.index("--format") + 1] == "json"
    assert Path(argv[argv.index("--dir") + 1]).is_absolute()
    assert "--auto" not in argv
    assert "--model" not in argv
    inline = json.loads(kwargs["env"]["OPENCODE_CONFIG_CONTENT"])
    assert inline["agent"]["council"]["permission"] == {"*": "deny"}
    assert kwargs["shell"] is False


def test_opencode_backend_rejects_non_json_event_stream(tmp_path: Path, monkeypatch):
    def fake_run(argv, **kwargs):
        return subprocess.CompletedProcess(argv, 0, "not-json\n", "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    with pytest.raises(CouncilError, match="invalid JSON event"):
        SubprocessBackend(tmp_path).ask(
            MemberProfile("open", "opencode", ""),
            "review",
            {"transcript": []},
        )


def test_grok_backend_uses_strict_text_fallback_when_structured_output_is_null(
    tmp_path: Path, monkeypatch
):
    def fake_run(argv, **kwargs):
        payload = {
            "structuredOutput": None,
            "text": json.dumps(review_response("fallback review")),
            "modelUsage": {"grok-4.5": {"requests": 1}},
        }
        return subprocess.CompletedProcess(argv, 0, json.dumps(payload), "")

    monkeypatch.setattr(subprocess, "run", fake_run)
    result = SubprocessBackend(tmp_path).ask(
        MemberProfile("grok", "grok", "grok-4.5"),
        "review",
        {"transcript": []},
    )
    assert result["message"] == "fallback review"
