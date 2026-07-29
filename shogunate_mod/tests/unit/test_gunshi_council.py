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
    CAPABILITY_CONTRACT,
    CouncilConfig,
    CouncilController,
    CouncilError,
    CouncilSecurityError,
    MemberProfile,
    SubprocessBackend,
    apply_session_override,
    capability_contract_snapshot,
    extract_council_command_claims,
    parse_council_config,
    parse_gunkan_profile,
    unsupported_council_command_findings,
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
        started["capability_contract"]["commands"]["start"]["to"],
        started["capability_contract"]["commands"]["advance"]["outcomes"][
            "unresolved_or_not_converged"
        ]["to"],
        started["capability_contract"]["commands"]["advance"]["outcomes"][
            "unresolved_or_not_converged"
        ]["to"],
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
        "resolutions",
        "capability_contract",
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


def test_review_and_synthesis_share_open_and_resolved_objection_ledgers(
    tmp_path: Path,
):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("cycle 1 blocker", blocking=True)),
            (
                "fable",
                "synthesize",
                synthesis_response(
                    "cycle 1 fixed",
                    converged=False,
                    resolutions=[
                        {
                            "objection_id": "obj-1-opus-1",
                            "status": "resolved",
                            "reason": "cycle 1で修正した",
                        }
                    ],
                ),
            ),
            ("opus", "review", review_response("cycle 2 blocker", blocking=True)),
            (
                "fable",
                "synthesize",
                synthesis_response(
                    "cycle 2 fixed",
                    converged=False,
                    resolutions=[
                        {
                            "objection_id": "obj-2-opus-1",
                            "status": "resolved",
                            "reason": "cycle 2で修正した",
                        }
                    ],
                ),
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-resolution-ledger", "r4再掲を防ぐ", config(2))
    controller.advance("council-resolution-ledger")
    final_state = controller.advance("council-resolution-ledger")

    cycle_2_review = backend.calls[3][2]
    cycle_2_synthesis = backend.calls[4][2]
    expected_resolved = [
        {
            "objection_id": "obj-1-opus-1",
            "status": "resolved",
            "reason": "cycle 1で修正した",
            "cycle": 1,
        }
    ]
    assert cycle_2_review["resolutions"] == expected_resolved
    assert cycle_2_synthesis["resolutions"] == expected_resolved
    assert cycle_2_review["open_objections"] == []
    assert [item["id"] for item in cycle_2_synthesis["open_objections"]] == [
        "obj-2-opus-1"
    ]
    resolved_ids = {
        item["objection_id"] for item in cycle_2_synthesis["resolutions"]
    }
    open_ids = {item["id"] for item in cycle_2_synthesis["open_objections"]}
    assert resolved_ids.isdisjoint(open_ids)
    assert "reference only IDs currently listed in open_objections" in cycle_2_synthesis[
        "protocol"
    ]
    assert "Never reference an ID already listed in resolutions" in cycle_2_review[
        "protocol"
    ]
    assert [item["objection_id"] for item in final_state["resolutions"]] == [
        "obj-1-opus-1",
        "obj-2-opus-1",
    ]

    # r4 failed after the representative repeated resolved obj-3-grok-1 while
    # no objections were open. The context must keep those ledgers separate.
    r4_state = copy.deepcopy(final_state)
    r4_state["open_objections"] = []
    r4_state["resolutions"] = [
        {
            "objection_id": "obj-3-grok-1",
            "status": "resolved",
            "reason": "Step 5.5を追加した",
            "cycle": 3,
        }
    ]
    detached = controller._context_snapshot(r4_state, 4)
    assert detached["open_objections"] == []
    assert detached["resolutions"][0]["objection_id"] == "obj-3-grok-1"
    detached["resolutions"][0]["reason"] = "tampered context"
    assert r4_state["resolutions"][0]["reason"] == "Step 5.5を追加した"


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
    contract = state["capability_contract"]
    fail_outcome = contract["commands"]["audit"]["outcomes"]["fail"]
    assert state["status"] == fail_outcome["to"]
    assert fail_outcome["creates"] == []
    assert contract["artifacts"]["lifecycle"]["audit_fail"]["creates"] == []
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


def test_capability_contract_content_is_exact():
    contract = capability_contract_snapshot()
    assert contract == {
        "schema_version": 2,
        "supported_commands": ["start", "advance", "audit", "status", "reopen"],
        "commands": {
            "start": {"from": ["absent"], "to": "deliberating"},
            "advance": {
                "from": ["deliberating", "closing"],
                "outcomes": {
                    "unresolved_or_not_converged": {
                        "to": "deliberating",
                        "when": {
                            "any": [
                                {"converged": False},
                                {"blocking_objections": "present"},
                                {"unresolved": "present"},
                            ]
                        },
                    },
                    "converged_candidate": {
                        "to": "closing",
                        "when": {
                            "all": [
                                {"converged": True},
                                {"blocking_objections": "none"},
                                {"unresolved": "none"},
                                {
                                    "any": [
                                        {"prior_status": "deliberating"},
                                        {"new_blocking_raised": True},
                                        {"plan_unchanged": False},
                                    ]
                                },
                            ]
                        },
                    },
                    "unchanged_final_candidate_without_blockers": {
                        "to": "awaiting_audit",
                        "when": {
                            "all": [
                                {"prior_status": "closing"},
                                {"converged": True},
                                {"blocking_objections": "none"},
                                {"unresolved": "none"},
                                {"new_blocking_raised": False},
                                {"plan_unchanged": True},
                            ]
                        },
                    },
                },
            },
            "audit": {
                "from": ["awaiting_audit"],
                "outcomes": {
                    "pass": {
                        "to": "dissolved",
                        "creates": ["plan.md", "handoff.yaml"],
                    },
                    "fail": {"to": "deliberating", "creates": []},
                },
            },
            "status": {
                "from": [
                    "deliberating",
                    "closing",
                    "awaiting_audit",
                    "dissolved",
                ],
                "mutation": False,
            },
            "reopen": {"from": ["dissolved"], "to": "deliberating"},
        },
        "states": ["deliberating", "closing", "awaiting_audit", "dissolved"],
        "artifacts": {
            "always": ["state.yaml", "brief.txt"],
            "after_gunkan_pass": ["plan.md", "handoff.yaml"],
            "lifecycle": {
                "audit_pass": {"creates": ["plan.md", "handoff.yaml"]},
                "audit_fail": {"creates": []},
                "reopen": {
                    "retains": ["plan.md", "handoff.yaml"],
                    "clears_state_fields": ["handoff_path"],
                },
            },
        },
        "handoff": {
            "auto_dispatch": False,
            "next_owner": "gunshi",
            "dispatch_owner": "karo",
            "implementation_owner": "ashigaru",
            "auto_queue": False,
        },
    }
    # Snapshot is a deep copy so callers cannot mutate the module constant.
    contract["supported_commands"].append("end")
    assert "end" not in CAPABILITY_CONTRACT["supported_commands"]


def test_contract_matches_pass_status_reopen_and_artifact_lifecycle(tmp_path: Path):
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
    council_id = "council-contract-lifecycle"
    directory = tmp_path / "queue/council" / council_id

    started = controller.start(council_id, "遷移契約を確認する", config())
    contract = started["capability_contract"]
    assert started["status"] == contract["commands"]["start"]["to"]
    assert all(
        (directory / name).is_file() for name in contract["artifacts"]["always"]
    )

    closing = controller.advance(council_id)
    assert closing["status"] == contract["commands"]["advance"]["outcomes"][
        "converged_candidate"
    ]["to"]
    ready = controller.advance(council_id)
    assert ready["status"] == contract["commands"]["advance"]["outcomes"][
        "unchanged_final_candidate_without_blockers"
    ]["to"]

    state_path = directory / "state.yaml"
    before_status = state_path.read_bytes()
    assert controller.status(council_id) == ready
    assert state_path.read_bytes() == before_status
    assert contract["commands"]["status"]["mutation"] is False

    dissolved = controller.audit(council_id, MemberProfile("gunkan", "codex", ""))
    pass_outcome = contract["commands"]["audit"]["outcomes"]["pass"]
    assert dissolved["status"] == pass_outcome["to"]
    assert all((directory / name).is_file() for name in pass_outcome["creates"])

    reopened = controller.reopen(council_id)
    assert reopened["status"] == contract["commands"]["reopen"]["to"]
    reopen_lifecycle = contract["artifacts"]["lifecycle"]["reopen"]
    assert all((directory / name).is_file() for name in reopen_lifecycle["retains"])
    assert all(
        reopened[field] is None
        for field in reopen_lifecycle["clears_state_fields"]
    )


def test_extract_council_command_claims_is_narrow():
    claims = extract_council_command_claims(
        {
            "objective": "Use shogunate council advance after review.",
            "scope": ["mentioning end without command prefix is fine"],
            "steps": [
                "Run `council end --id x` and then `council handoff`.",
                "Also try council objection create then execute council plan update.",
                "`council status` and ordinary council lifecycle prose are different.",
            ],
            "validation": ["`council audit` when ready"],
            "stop_conditions": ["no NLP: do not invent end semantics"],
            "reconvene_conditions": ["Execute council dissolve if requested"],
        }
    )
    assert claims == [
        "advance",
        "end",
        "handoff",
        "objection create",
        "plan update",
        "status",
        "audit",
        "dissolve",
    ]
    # Identifier substrings must not produce claims (e.g. precouncil end).
    assert (
        extract_council_command_claims(
            {
                "objective": "precouncil end is an identifier, not a command",
                "scope": ["mycouncil handoff stays prose"],
                "steps": ["call precouncil end now"],
                "validation": ["x"],
                "stop_conditions": ["x"],
                "reconvene_conditions": ["x"],
            }
        )
        == []
    )


def test_live_e2e_r3_council_noun_phrases_are_not_command_claims():
    # Regression from live-e2e-4cli-20260728-r3: these are ordinary English
    # noun phrases, not requests to execute council subcommands.
    r3_plan = {
        "objective": "Council system coverage for four CLIs.",
        "scope": ["Council lifecycle coverage."],
        "steps": [
            "Council cycles share transcripts.",
        ],
        "validation": ["Council state transitions match the contract."],
        "stop_conditions": ["Council dissolution stays audit-gated."],
        "reconvene_conditions": [
            "Council prior behavior changed.",
            "Council to deliberating behavior changed.",
        ],
    }
    assert extract_council_command_claims(r3_plan) == []
    assert unsupported_council_command_findings(
        r3_plan, capability_contract_snapshot()
    ) == []


def test_explicit_known_unsupported_claims_stay_detectable():
    findings = unsupported_council_command_findings(
        {
            "objective": "x",
            "scope": ["x"],
            "steps": [
                "`council end --id x`",
                "Run council handoff.",
                "Execute council objection create.",
                "Call council objection resolve.",
                "Use council plan update.",
                "shogunate council advance --id x",
            ],
            "validation": ["x"],
            "stop_conditions": ["x"],
            "reconvene_conditions": ["x"],
        },
        capability_contract_snapshot(),
    )
    assert findings == [
        "unsupported council command: end",
        "unsupported council command: handoff",
        "unsupported council command: objection create",
        "unsupported council command: objection resolve",
        "unsupported council command: plan update",
    ]


def test_draft_review_synthesis_and_audit_share_capability_snapshot(tmp_path: Path):
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
    started = controller.start("council-contract-ctx", "契約を共有する", config())
    assert started["capability_contract"] == capability_contract_snapshot()
    assert controller.advance("council-contract-ctx")["status"] == "closing"
    assert controller.advance("council-contract-ctx")["status"] == "awaiting_audit"
    controller.audit("council-contract-ctx", MemberProfile("gunkan", "codex", ""))

    snapshots = [call[2]["capability_contract"] for call in backend.calls]
    assert len(snapshots) == 8
    assert all(item == capability_contract_snapshot() for item in snapshots)
    assert all("capability_contract" in call[2] for call in backend.calls)
    assert all("trusted authority" in call[2]["protocol"] for call in backend.calls)


def test_live_e2e_unsupported_council_commands_become_controller_blockers(
    tmp_path: Path,
):
    # Regression from live-e2e-4cli-20260728-r1 invented subcommands.
    bad_plan = plan("fictional-commands")
    bad_plan["steps"] = [
        "Run `council end --id live-e2e-4cli-20260728-r1`.",
        "Then `council handoff --id live-e2e-4cli-20260728-r1`.",
        "Register with `council objection create` and `council objection resolve`.",
        "Sync with `council plan update --id live-e2e-4cli-20260728-r1`.",
    ]
    backend = ScriptedBackend(
        [
            (
                "fable",
                "draft",
                {
                    **draft_response(),
                    "plan": bad_plan,
                    "unresolved": [],
                },
            ),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("still-bad", converged=True),
                    "plan": bad_plan,
                },
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    started = controller.start("council-fictional", "架空commandを止める", config())
    assert started["status"] == "deliberating"
    controller_blockers = [
        item
        for item in started["open_objections"]
        if item["speaker"] == "controller" and item["blocking"]
    ]
    summaries = {item["summary"] for item in controller_blockers}
    assert "unsupported council command: end" in summaries
    assert "unsupported council command: handoff" in summaries
    assert "unsupported council command: objection create" in summaries
    assert "unsupported council command: objection resolve" in summaries
    assert "unsupported council command: plan update" in summaries
    assert any(
        entry["speaker"] == "controller" and entry["kind"] == "objection"
        for entry in started["transcript"]
    )

    advanced = controller.advance("council-fictional")
    assert advanced["status"] == "deliberating"
    assert advanced["status"] != "closing"
    assert advanced["status"] != "awaiting_audit"
    cycle_blockers = [
        item
        for item in advanced["open_objections"]
        if item["speaker"] == "controller" and item["cycle"] == 1
    ]
    assert cycle_blockers
    assert all(item["id"].startswith("obj-controller-1-") for item in cycle_blockers)
    assert all(
        not item["id"].startswith("obj-1-controller-") for item in cycle_blockers
    )


def test_supported_commands_only_plan_can_reach_awaiting_audit(tmp_path: Path):
    good_plan = plan("supported-only")
    good_plan["steps"] = [
        "Use council advance after each review cycle.",
        "`council status --id x` inspects progress.",
        "Request shogunate council audit only after awaiting_audit.",
        "If needed, execute council reopen after dissolve.",
        "Execute council start for a new session.",
    ]
    backend = ScriptedBackend(
        [
            (
                "fable",
                "draft",
                {**draft_response(), "plan": good_plan, "unresolved": []},
            ),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("supported-only", converged=True),
                    "plan": good_plan,
                },
            ),
            ("opus", "review", review_response("最終案に異議なし")),
            ("sol", "review", review_response("最終案に異議なし")),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("supported-only", converged=True),
                    "plan": good_plan,
                },
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    started = controller.start("council-supported", "正常commandのみ", config())
    assert started["open_objections"] == []
    assert controller.advance("council-supported")["status"] == "closing"
    ready = controller.advance("council-supported")
    assert ready["status"] == "awaiting_audit"
    assert not any(
        item["speaker"] == "controller" for item in ready["open_objections"]
    )


def test_recovery_resolves_controller_blockers_after_removing_claims(tmp_path: Path):
    bad_plan = plan("needs-cleanup")
    bad_plan["steps"] = ["Execute council end after reviews."]
    clean_plan = plan("cleaned")
    clean_plan["steps"] = ["Use only council advance and council status."]
    backend = ScriptedBackend(
        [
            (
                "fable",
                "draft",
                {**draft_response(), "plan": bad_plan, "unresolved": []},
            ),
            ("opus", "review", review_response("controller blockerを確認")),
            ("sol", "review", review_response("異議なし")),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("cleaned", converged=True),
                    "plan": clean_plan,
                    "resolutions": [
                        {
                            "objection_id": "obj-controller-0-1",
                            "status": "resolved",
                            "reason": "planから council end を除去した",
                        }
                    ],
                },
            ),
            ("opus", "review", review_response("解決を確認")),
            ("sol", "review", review_response("異議なし")),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("cleaned", converged=True),
                    "plan": clean_plan,
                },
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    started = controller.start("council-recover", "違反を除去して復帰する", config())
    assert any(
        item["summary"] == "unsupported council command: end"
        for item in started["open_objections"]
    )
    closing = controller.advance("council-recover")
    assert closing["status"] == "closing"
    assert closing["open_objections"] == []
    ready = controller.advance("council-recover")
    assert ready["status"] == "awaiting_audit"


def test_controller_blocker_ids_do_not_collide_with_member_alias_controller(
    tmp_path: Path,
):
    # Alias "controller" remains a valid member name; its member IDs keep the
    # shape obj-{cycle}-{alias}-{index}. Capability blockers use a different
    # namespace so resolution targets stay unambiguous.
    members = {
        "fable": MemberProfile("fable", "claude", "fable"),
        "controller": MemberProfile("controller", "codex", "gpt-5.6-sol"),
    }
    council_config = CouncilConfig(members=members, representative="fable")
    bad_plan = plan("alias-collision")
    bad_plan["steps"] = ["Do not run council end."]
    backend = ScriptedBackend(
        [
            (
                "fable",
                "draft",
                {**draft_response(), "plan": plan("clean-draft"), "unresolved": []},
            ),
            (
                "controller",
                "review",
                {
                    "message": "member named controller objects",
                    "objections": [
                        {"summary": "member objection from alias controller", "blocking": True}
                    ],
                    "improvements": [],
                },
            ),
            (
                "fable",
                "synthesize",
                {
                    **synthesis_response("with-end", converged=True),
                    "plan": bad_plan,
                },
            ),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    started = controller.start("council-alias-ctrl", "alias衝突を防ぐ", council_config)
    assert started["open_objections"] == []
    advanced = controller.advance("council-alias-ctrl")
    member_ids = [
        item["id"]
        for item in advanced["open_objections"]
        if item["speaker"] == "controller"
        and item["summary"] == "member objection from alias controller"
    ]
    capability_ids = [
        item["id"]
        for item in advanced["open_objections"]
        if item["summary"] == "unsupported council command: end"
    ]
    assert member_ids == ["obj-1-controller-1"]
    assert capability_ids == ["obj-controller-1-1"]
    assert member_ids[0] != capability_ids[0]
    assert advanced["status"] == "deliberating"
    transcript_ids = {entry["id"] for entry in advanced["transcript"]}
    assert "msg-1-controller" in transcript_ids  # member review message id
    assert "msg-controller-1-1" in transcript_ids  # capability blocker


def test_legacy_state_without_capability_snapshot_stays_readable_and_advances(
    tmp_path: Path,
):
    backend = ScriptedBackend(
        [
            ("fable", "draft", draft_response()),
            ("opus", "review", review_response("異議なし")),
            ("sol", "review", review_response("異議なし")),
            ("fable", "synthesize", synthesis_response("legacy-ok", converged=False)),
        ]
    )
    controller = CouncilController(tmp_path, backend)
    controller.start("council-legacy", "旧state互換", config())
    state_path = tmp_path / "queue/council/council-legacy/state.yaml"
    state = yaml.safe_load(state_path.read_text(encoding="utf-8"))
    state.pop("capability_contract")
    state["schema_version"] = 2
    state_path.write_text(yaml.safe_dump(state), encoding="utf-8")

    # status must not rewrite missing snapshots.
    loaded = controller.status("council-legacy")
    assert "capability_contract" not in loaded
    reloaded = yaml.safe_load(state_path.read_text(encoding="utf-8"))
    assert "capability_contract" not in reloaded

    advanced = controller.advance("council-legacy")
    assert advanced["status"] == "deliberating"
    assert advanced["capability_contract"] == capability_contract_snapshot()
    review_context = backend.calls[1][2]
    assert review_context["capability_contract"] == capability_contract_snapshot()
