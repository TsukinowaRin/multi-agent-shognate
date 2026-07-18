#!/usr/bin/env python3
"""Unit tests for role Primary/Fallback failover controller."""

from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest
import yaml


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (path / "shogunate_mod" / "manifest.yaml").is_file() and (
            path / "shogunate_mod" / "runtime" / "role_failover.py"
        ).is_file():
            return path
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.runtime.role_failover import (  # noqa: E402
    ACTION_ACTIVATE_FALLBACK,
    ACTION_AUTHORIZE,
    ACTION_ENTER_EMERGENCY,
    ACTION_MARK_HANDOFF_REQUIRED,
    ACTION_NONE,
    ACTION_REJECT,
    ACTION_REQUEST_REASSIGNMENT,
    ACTION_RESTART_PRIMARY,
    ACTION_RESTORE_PRIMARY,
    ACTION_RESUME_AFTER_HANDOFF,
    ACTION_SAFE_STOP,
    ACTION_WARN,
    EVENT_EMERGENCY_OUT_OF_SCOPE,
    EVENT_EMERGENCY_AUTHORIZE_WORK,
    EVENT_EMERGENCY_PLAN_COMPLETE,
    EVENT_EXPLICIT_FAILURE,
    EVENT_HANDOFF_COMPLETE,
    EVENT_HANDOFF_VALIDATE,
    EVENT_INIT_ROLE,
    EVENT_NO_PROGRESS,
    EVENT_PRIMARY_RECOVERED,
    EVENT_PROCESS_EXIT,
    EVENT_PROGRESS,
    EVENT_USER_STOP,
    EVENT_WORK_STATE_UPDATE,
    FailoverError,
    FailoverSecurityError,
    RoleConfig,
    RoleFailoverController,
    RoleFailoverStore,
    RoleProfile,
    parse_role_config,
    parse_settings_roles,
    resolve_active_launch_profile,
    validate_managed_write,
    validate_handoff,
)


class FakeClock:
    def __init__(self, start: str = "2026-07-16T09:00:00.000Z") -> None:
        self.current = start
        self._n = 0

    def __call__(self) -> str:
        self._n += 1
        # Keep lexicographic ISO-ish uniqueness without needing real time.
        base = self.current[:-1]
        return f"{base[:-4]}{self._n:04d}Z"


def primary_cfg(role: str = "karo", *, with_fallback: bool = True) -> RoleConfig:
    primary = RoleProfile(type="codex", model="gpt-5", reasoning_effort="high")
    fallback = RoleProfile(type="opencode", model="glm-5", reasoning_effort="medium") if with_fallback else None
    return RoleConfig(role=role, primary=primary, fallback=fallback)


def controller_for(
    role: str = "karo",
    *,
    with_fallback: bool = True,
    clock: FakeClock | None = None,
) -> RoleFailoverController:
    cfg = primary_cfg(role, with_fallback=with_fallback)
    clk = clock or FakeClock()
    ctrl = RoleFailoverController(role_configs={role: cfg, "gunkan": primary_cfg("gunkan"), "shogun": primary_cfg("shogun")}, clock=clk)
    result = ctrl.apply_event(
        {
            "event_id": f"init-{role}",
            "type": EVENT_INIT_ROLE,
            "role": role,
            "reset": True,
            "primary_profile": cfg.primary.to_dict(),
            "fallback_profile": None if cfg.fallback is None else cfg.fallback.to_dict(),
        }
    )
    assert result.action == ACTION_NONE
    # Ensure gunkan/shogun ready for emergency paths when needed.
    for extra in ("gunkan", "shogun"):
        if extra == role:
            continue
        ecfg = primary_cfg(extra)
        ctrl.role_configs[extra] = ecfg
        ctrl.apply_event(
            {
                "event_id": f"init-{extra}",
                "type": EVENT_INIT_ROLE,
                "role": extra,
                "reset": True,
                "primary_profile": ecfg.primary.to_dict(),
                "fallback_profile": ecfg.fallback.to_dict() if ecfg.fallback else None,
            }
        )
    return ctrl


def gen(ctrl: RoleFailoverController, role: str) -> int:
    return int(ctrl.state["roles"][role]["generation"])


def full_handoff(role: str, generation: int) -> dict:
    return {
        "role": role,
        "generation": generation,
        "work_id": "cmd_001",
        "purpose": "implement failover",
        "acceptance_criteria": ["tests pass"],
        "approved_plan_id": "PLAN-1",
        "approved_plan_revision": 1,
        "progress": {"done": [], "in_progress": ["core"], "todo": ["docs"]},
        "scope": {"paths": ["shogunate_mod/runtime/role_failover.py"]},
        "next_step": "write unit tests",
    }


# --- schema / profile ---


def test_legacy_flat_role_is_primary_without_fallback():
    cfg = parse_role_config("karo", {"type": "codex", "model": "m1"})
    assert cfg.primary.type == "codex"
    assert cfg.primary.model == "m1"
    assert cfg.fallback is None


def test_string_role_legacy():
    cfg = parse_role_config("ashigaru1", "opencode")
    assert cfg.primary.type == "opencode"
    assert cfg.fallback is None


def test_fallback_profile_and_null():
    cfg = parse_role_config(
        "karo",
        {
            "type": "codex",
            "fallback": {"type": "kilo", "model": "x", "thinking": True},
        },
    )
    assert cfg.fallback is not None
    assert cfg.fallback.type == "kilo"
    assert cfg.fallback.thinking is True
    cfg2 = parse_role_config("karo", {"type": "codex", "fallback": None})
    assert cfg2.fallback is None


def test_invalid_cli_and_secret_keys_rejected():
    with pytest.raises(FailoverError):
        parse_role_config("karo", {"type": "not-a-cli"})
    with pytest.raises(FailoverSecurityError):
        parse_role_config("karo", {"type": "codex", "api_key": "secret"})
    with pytest.raises(FailoverSecurityError):
        parse_role_config(
            "karo",
            {"type": "codex", "fallback": {"type": "opencode", "access_token": "x"}},
        )


def test_gemini_alias_and_model_length():
    cfg = parse_role_config("gunshi", {"type": "gemini"})
    assert cfg.primary.type == "antigravity"
    with pytest.raises(FailoverError):
        parse_role_config("karo", {"type": "codex", "model": "x" * 200})


def test_parse_settings_roles():
    settings = {
        "cli": {
            "agents": {
                "shogun": {"type": "codex", "fallback": {"type": "opencode"}},
                "ignored": {"type": "codex"},
            }
        }
    }
    roles = parse_settings_roles(settings)
    assert "shogun" in roles
    assert "ignored" not in roles
    assert roles["shogun"].fallback is not None


# --- process exit / explicit failure ---


def test_process_exit_restarts_primary_once_then_fallback():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    r1 = ctrl.apply_event(
        {
            "event_id": "exit-1",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0,
            "reason": "process_exit",
        }
    )
    assert r1.action == ACTION_RESTART_PRIMARY
    assert gen(ctrl, "karo") == g0 + 1
    assert ctrl.state["roles"]["karo"]["primary_restart_count"] == 1
    assert ctrl.state["roles"]["karo"]["active_slot"] == "primary"

    g1 = gen(ctrl, "karo")
    r2 = ctrl.apply_event(
        {
            "event_id": "exit-2",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g1,
            "reason": "process_exit",
        }
    )
    assert r2.action == ACTION_ACTIVATE_FALLBACK
    assert ctrl.state["roles"]["karo"]["active_slot"] == "fallback"
    assert gen(ctrl, "karo") == g1 + 1
    assert ctrl.state["roles"]["karo"]["status"] == "awaiting_handoff"


def test_process_exit_without_fallback_stops_upper_role_army():
    ctrl = controller_for("karo", with_fallback=False)
    g0 = gen(ctrl, "karo")
    # First exit → primary restart
    ctrl.apply_event(
        {
            "event_id": "e1",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0,
        }
    )
    g1 = gen(ctrl, "karo")
    r = ctrl.apply_event(
        {
            "event_id": "e2",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g1,
        }
    )
    assert r.action == ACTION_SAFE_STOP
    assert ctrl.state["army_mode"] == "safe_stopped"


def test_explicit_failure_skips_primary_restart():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    r = ctrl.apply_event(
        {
            "event_id": "rl-1",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "karo",
            "expected_generation": g0,
            "reason": "rate_limit",
        }
    )
    assert r.action == ACTION_ACTIVATE_FALLBACK
    assert ctrl.state["roles"]["karo"]["primary_restart_count"] == 0


@pytest.mark.parametrize(
    ("event_type", "reason"),
    [
        (EVENT_PROCESS_EXIT, "crash"),
        (EVENT_PROCESS_EXIT, "process_exit\nsecret"),
        (EVENT_PROCESS_EXIT, "x" * 65),
        (EVENT_PROCESS_EXIT, 7),
        (EVENT_EXPLICIT_FAILURE, None),
        (EVENT_EXPLICIT_FAILURE, "provider_said_token=example"),
        (EVENT_PROGRESS, "process_exit"),
        (EVENT_USER_STOP, "rate_limit"),
    ],
)
def test_event_reason_rejects_free_text_wrong_type_and_control_characters(event_type, reason):
    ctrl = controller_for("karo")
    before = copy.deepcopy(ctrl.state)
    with pytest.raises(FailoverError):
        ctrl.apply_event(
            {
                "event_id": "bad-reason",
                "type": event_type,
                "role": "karo",
                "expected_generation": gen(ctrl, "karo"),
                "reason": reason,
            }
        )
    assert ctrl.state == before


def test_process_exit_accepts_shell_return_and_known_explicit_failure_reasons():
    shell_ctrl = controller_for("karo")
    shell_result = shell_ctrl.apply_event(
        {
            "event_id": "shell-return",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": gen(shell_ctrl, "karo"),
            "reason": "shell_return",
        }
    )
    assert shell_result.action == ACTION_RESTART_PRIMARY
    assert shell_result.audit[0]["reason"] == "shell_return"

    failure_ctrl = controller_for("karo")
    failure_result = failure_ctrl.apply_event(
        {
            "event_id": "process-auth-failure",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": gen(failure_ctrl, "karo"),
            "reason": "auth_error",
        }
    )
    assert failure_result.action == ACTION_ACTIVATE_FALLBACK
    assert failure_result.audit[0]["reason"] == "auth_error"


def test_explicit_auth_error_on_fallback_requests_reassignment_for_ashigaru():
    ctrl = controller_for("ashigaru1")
    g0 = gen(ctrl, "ashigaru1")
    ctrl.apply_event(
        {
            "event_id": "a-rl",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "ashigaru1",
            "expected_generation": g0,
            "reason": "auth_error",
        }
    )
    assert ctrl.state["roles"]["ashigaru1"]["active_slot"] == "fallback"
    g1 = gen(ctrl, "ashigaru1")
    r = ctrl.apply_event(
        {
            "event_id": "a-rl2",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "ashigaru1",
            "expected_generation": g1,
            "reason": "model_unavailable",
        }
    )
    assert r.action == ACTION_REQUEST_REASSIGNMENT
    assert ctrl.state["pending_reassignments"]
    assert ctrl.state["pending_reassignments"][-1]["from_role"] == "ashigaru1"
    assert ctrl.state["army_mode"] == "normal"


def test_intentional_process_exit_no_restart():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    r = ctrl.apply_event(
        {
            "event_id": "stop",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0,
            "intentional": True,
        }
    )
    assert r.action == ACTION_NONE
    assert gen(ctrl, "karo") == g0 + 1
    assert ctrl.state["roles"]["karo"]["status"] == "stopped"


# --- no-progress ---


def test_no_progress_warning_at_3_failure_at_6_reset_on_progress():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    actions = []
    for i in range(1, 4):
        r = ctrl.apply_event(
            {
                "event_id": f"np-{i}",
                "type": EVENT_NO_PROGRESS,
                "role": "karo",
                "expected_generation": g0,
            }
        )
        actions.append(r.action)
    assert actions[-1] == ACTION_WARN
    assert ctrl.state["roles"]["karo"]["no_progress_count"] == 3

    pr = ctrl.apply_event(
        {
            "event_id": "prog-1",
            "type": EVENT_PROGRESS,
            "role": "karo",
            "expected_generation": g0,
        }
    )
    assert pr.action == ACTION_NONE
    assert ctrl.state["roles"]["karo"]["no_progress_count"] == 0

    for i in range(1, 7):
        r = ctrl.apply_event(
            {
                "event_id": f"np2-{i}",
                "type": EVENT_NO_PROGRESS,
                "role": "karo",
                "expected_generation": g0,
            }
        )
    assert r.action == ACTION_RESTART_PRIMARY
    assert ctrl.state["roles"]["karo"]["no_progress_count"] == 0


# --- generation ---


def test_stale_generation_rejected_without_side_effects():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    before = copy.deepcopy(ctrl.state)
    r = ctrl.apply_event(
        {
            "event_id": "stale",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0 - 1 if g0 > 1 else 999,
            "reason": "process_exit",
        }
    )
    assert r.action == ACTION_REJECT
    assert r.rejected is True
    assert r.reason == "stale_generation"
    assert r.audit == []
    assert r.outbox == []
    assert ctrl.state == before


def test_duplicate_event_id_is_idempotent():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    e = {
        "event_id": "same",
        "type": EVENT_PROCESS_EXIT,
        "role": "karo",
        "expected_generation": g0,
    }
    r1 = ctrl.apply_event(e)
    assert r1.action == ACTION_RESTART_PRIMARY
    g_after = gen(ctrl, "karo")
    r2 = ctrl.apply_event(e)
    assert r2.action == ACTION_NONE
    assert r2.reason == "duplicate_event"
    assert gen(ctrl, "karo") == g_after


# --- handoff ---


def test_handoff_requires_fields_and_rejects_secrets():
    with pytest.raises(FailoverError):
        validate_handoff({"role": "karo", "generation": 1})
    with pytest.raises(FailoverSecurityError):
        validate_handoff({**full_handoff("karo", 1), "api_token": "nope"})


def test_handoff_complete_allows_resume_only_when_valid():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    ctrl.apply_event(
        {
            "event_id": "to-fb",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "karo",
            "expected_generation": g0,
            "reason": "rate_limit",
        }
    )
    g1 = gen(ctrl, "karo")
    bad = ctrl.apply_event(
        {
            "event_id": "hv-bad",
            "type": EVENT_HANDOFF_VALIDATE,
            "role": "karo",
            "expected_generation": g1,
            "handoff": {"role": "karo", "generation": g1},
        }
    )
    assert bad.rejected is False
    assert bad.action == ACTION_MARK_HANDOFF_REQUIRED
    assert ctrl.state["roles"]["karo"]["handoff_complete"] is False

    ok = ctrl.apply_event(
        {
            "event_id": "hc-ok",
            "type": EVENT_HANDOFF_COMPLETE,
            "role": "karo",
            "expected_generation": g1,
            "handoff": full_handoff("karo", g1),
        }
    )
    assert ok.action == ACTION_RESUME_AFTER_HANDOFF
    assert ctrl.state["roles"]["karo"]["handoff_complete"] is True
    assert ctrl.state["roles"]["karo"]["status"] == "ready"


def test_work_state_update_persists_handoff_before_process_exit():
    ctrl = controller_for("karo")
    generation = gen(ctrl, "karo")
    work = {key: value for key, value in full_handoff("karo", generation).items() if key not in {"role", "generation"}}
    result = ctrl.apply_event(
        {
            "event_id": "work-1",
            "type": EVENT_WORK_STATE_UPDATE,
            "role": "karo",
            "expected_generation": generation,
            "work_state": work,
        }
    )
    assert result.action == ACTION_NONE
    assert ctrl.state["roles"]["karo"]["current_work"]["work_id"] == "cmd_001"
    assert ctrl.state["roles"]["karo"]["handoff"]["generation"] == generation


def test_invalid_handoff_status_is_persisted_by_store(tmp_path: Path):
    store = RoleFailoverStore(tmp_path, clock=FakeClock())
    cfg = primary_cfg("karo")
    store.apply_event(
        {
            "event_id": "init",
            "type": EVENT_INIT_ROLE,
            "role": "karo",
            "reset": True,
            "primary_profile": cfg.primary.to_dict(),
            "fallback_profile": cfg.fallback.to_dict(),
        },
        role_configs={"karo": cfg},
    )
    state = store.load()
    result = store.apply_event(
        {
            "event_id": "invalid-handoff",
            "type": EVENT_HANDOFF_VALIDATE,
            "role": "karo",
            "expected_generation": state["roles"]["karo"]["generation"],
            "handoff": {"role": "karo"},
        }
    )
    assert result.action == ACTION_MARK_HANDOFF_REQUIRED
    assert not result.rejected
    assert store.load()["roles"]["karo"]["status"] == "awaiting_handoff"


# --- role stop rules / emergency ---


def test_gunkan_unrecoverable_safe_stops_army():
    ctrl = controller_for("gunkan", with_fallback=False)
    g0 = gen(ctrl, "gunkan")
    ctrl.apply_event(
        {
            "event_id": "g1",
            "type": EVENT_PROCESS_EXIT,
            "role": "gunkan",
            "expected_generation": g0,
        }
    )
    g1 = gen(ctrl, "gunkan")
    r = ctrl.apply_event(
        {
            "event_id": "g2",
            "type": EVENT_PROCESS_EXIT,
            "role": "gunkan",
            "expected_generation": g1,
        }
    )
    assert r.action == ACTION_SAFE_STOP
    assert ctrl.state["army_mode"] == "safe_stopped"


def test_shogun_unrecoverable_enters_gunkan_emergency():
    ctrl = controller_for("shogun", with_fallback=False)
    # seed handoff-like work for policy snapshot
    ctrl.state["roles"]["shogun"]["current_work"] = {
        "approved_plan_id": "PLAN-X",
        "approved_plan_revision": 3,
    }
    g0 = gen(ctrl, "shogun")
    ctrl.apply_event(
        {
            "event_id": "s1",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g0,
        }
    )
    g1 = gen(ctrl, "shogun")
    r = ctrl.apply_event(
        {
            "event_id": "s2",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g1,
        }
    )
    assert r.action == ACTION_ENTER_EMERGENCY
    assert ctrl.state["army_mode"] == "emergency"
    assert ctrl.state["roles"]["gunkan"]["status"] == "emergency"
    policy = ctrl.state["roles"]["gunkan"]["emergency"]
    assert policy["plan_id"] == "PLAN-X"
    assert policy["revision"] == 3
    assert policy["mode"] == "approved_plan_only"


def test_shogun_without_approved_plan_safe_stops_instead_of_emergency():
    ctrl = controller_for("shogun", with_fallback=False)
    generation = gen(ctrl, "shogun")
    ctrl.apply_event(
        {
            "event_id": "no-plan-1",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": generation,
        }
    )
    result = ctrl.apply_event(
        {
            "event_id": "no-plan-2",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": gen(ctrl, "shogun"),
        }
    )
    assert result.action == ACTION_SAFE_STOP
    assert ctrl.state["army_mode"] == "safe_stopped"


def test_emergency_authorization_enforces_plan_snapshot():
    ctrl = controller_for("shogun", with_fallback=False)
    ctrl.state["roles"]["shogun"]["current_work"] = {
        "approved_plan_id": "PLAN-X",
        "approved_plan_revision": 3,
    }
    ctrl.apply_event(
        {
            "event_id": "em-start",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "shogun",
            "expected_generation": gen(ctrl, "shogun"),
            "reason": "auth_error",
        }
    )
    allowed = ctrl.apply_event(
        {
            "event_id": "em-allow",
            "type": EVENT_EMERGENCY_AUTHORIZE_WORK,
            "role": "gunkan",
            "expected_generation": gen(ctrl, "gunkan"),
            "plan_id": "PLAN-X",
            "plan_revision": 3,
            "task_id": "task-1",
        }
    )
    assert allowed.action == ACTION_AUTHORIZE

    denied = ctrl.apply_event(
        {
            "event_id": "em-deny",
            "type": EVENT_EMERGENCY_AUTHORIZE_WORK,
            "role": "gunkan",
            "expected_generation": gen(ctrl, "gunkan"),
            "plan_id": "PLAN-OTHER",
            "plan_revision": 1,
            "task_id": "task-2",
        }
    )
    assert denied.action == ACTION_SAFE_STOP


def test_emergency_plan_complete_and_out_of_scope_safe_stop():
    ctrl = controller_for("shogun", with_fallback=False)
    ctrl.state["roles"]["shogun"]["current_work"] = {
        "approved_plan_id": "PLAN-X",
        "approved_plan_revision": 1,
    }
    g0 = gen(ctrl, "shogun")
    ctrl.apply_event(
        {
            "event_id": "s1",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g0,
        }
    )
    g1 = gen(ctrl, "shogun")
    ctrl.apply_event(
        {
            "event_id": "s2",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g1,
        }
    )
    gg = gen(ctrl, "gunkan")
    r = ctrl.apply_event(
        {
            "event_id": "em-done",
            "type": EVENT_EMERGENCY_PLAN_COMPLETE,
            "role": "gunkan",
            "expected_generation": gg,
        }
    )
    assert r.action == ACTION_SAFE_STOP
    assert ctrl.state["army_mode"] == "safe_stopped"

    # Fresh emergency then out of scope
    ctrl2 = controller_for("shogun", with_fallback=False)
    ctrl2.state["roles"]["shogun"]["current_work"] = {
        "approved_plan_id": "PLAN-X",
        "approved_plan_revision": 1,
    }
    g0 = gen(ctrl2, "shogun")
    ctrl2.apply_event(
        {
            "event_id": "s1b",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g0,
        }
    )
    g1 = gen(ctrl2, "shogun")
    ctrl2.apply_event(
        {
            "event_id": "s2b",
            "type": EVENT_PROCESS_EXIT,
            "role": "shogun",
            "expected_generation": g1,
        }
    )
    gg = gen(ctrl2, "gunkan")
    r2 = ctrl2.apply_event(
        {
            "event_id": "em-oos",
            "type": EVENT_EMERGENCY_OUT_OF_SCOPE,
            "role": "gunkan",
            "expected_generation": gg,
        }
    )
    assert r2.action == ACTION_SAFE_STOP


def test_shogun_down_without_gunkan_safe_stops():
    ctrl = controller_for("shogun", with_fallback=False)
    ctrl.state["roles"]["gunkan"]["status"] = "stopped"
    g0 = gen(ctrl, "shogun")
    ctrl.apply_event(
        {
            "event_id": "sx1",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "shogun",
            "expected_generation": g0,
            "reason": "auth_error",
        }
    )
    # no fallback → terminal immediately on explicit failure
    assert ctrl.state["army_mode"] == "safe_stopped"


def test_terminal_ashigaru_failure_revokes_old_generation_and_lease():
    ctrl = controller_for("ashigaru1")
    ctrl.apply_event(
        {
            "event_id": "ash-fb",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "ashigaru1",
            "expected_generation": gen(ctrl, "ashigaru1"),
            "reason": "rate_limit",
        }
    )
    failed_generation = gen(ctrl, "ashigaru1")
    result = ctrl.apply_event(
        {
            "event_id": "ash-terminal",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "ashigaru1",
            "expected_generation": failed_generation,
            "reason": "auth_error",
        }
    )
    assert result.action == ACTION_REQUEST_REASSIGNMENT
    item = ctrl.state["pending_reassignments"][-1]
    assert item["failed_generation"] == failed_generation
    assert item["generation"] == failed_generation + 1
    assert item["lease_revoked"] is True


# --- primary restore ---


def test_primary_recovered_keeps_busy_fallback_until_checkpoint():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    ctrl.apply_event(
        {
            "event_id": "fb",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "karo",
            "expected_generation": g0,
            "reason": "rate_limit",
        }
    )
    g1 = gen(ctrl, "karo")
    ctrl.apply_event(
        {
            "event_id": "hc",
            "type": EVENT_HANDOFF_COMPLETE,
            "role": "karo",
            "expected_generation": g1,
            "handoff": full_handoff("karo", g1),
        }
    )
    r = ctrl.apply_event(
        {
            "event_id": "pr",
            "type": EVENT_PRIMARY_RECOVERED,
            "role": "karo",
            "expected_generation": gen(ctrl, "karo"),
        }
    )
    assert r.action == ACTION_NONE
    assert r.reason == "fallback_busy_keep_until_checkpoint"
    assert ctrl.state["roles"]["karo"]["active_slot"] == "fallback"

    r2 = ctrl.apply_event(
        {
            "event_id": "pr2",
            "type": EVENT_PRIMARY_RECOVERED,
            "role": "karo",
            "expected_generation": gen(ctrl, "karo"),
            "force_after_checkpoint": True,
        }
    )
    assert r2.action == ACTION_RESTORE_PRIMARY
    assert ctrl.state["roles"]["karo"]["active_slot"] == "primary"


# --- store / resolve ---


def test_store_atomic_persist_and_audit_outbox(tmp_path: Path):
    clock = FakeClock()
    store = RoleFailoverStore(tmp_path, clock=clock)
    cfg = primary_cfg("karo")
    store.apply_event(
        {
            "event_id": "init",
            "type": EVENT_INIT_ROLE,
            "role": "karo",
            "reset": True,
            "primary_profile": cfg.primary.to_dict(),
            "fallback_profile": cfg.fallback.to_dict() if cfg.fallback else None,
        },
        role_configs={"karo": cfg},
    )
    state = store.load()
    g0 = state["roles"]["karo"]["generation"]
    result = store.apply_event(
        {
            "event_id": "crash",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0,
        },
        role_configs={"karo": cfg},
    )
    assert result.action == ACTION_RESTART_PRIMARY
    reloaded = store.load()
    assert reloaded["roles"]["karo"]["generation"] == g0 + 1
    audit = yaml.safe_load((tmp_path / "queue/runtime/role_failover_audit.yaml").read_text(encoding="utf-8"))
    assert audit["events"]
    assert "api_key" not in yaml.safe_dump(audit)
    outbox = yaml.safe_load((tmp_path / "queue/runtime/app_outbox.yaml").read_text(encoding="utf-8"))
    assert outbox["events"]
    assert outbox["events"][0]["action"] == ACTION_RESTART_PRIMARY


def test_store_rejects_secret_like_or_unknown_persisted_state(tmp_path: Path):
    state_path = tmp_path / "queue/runtime/role_failover.yaml"
    state_path.parent.mkdir(parents=True)
    state_path.write_text(
        yaml.safe_dump(
            {
                "schema_version": 1,
                "roles": {
                    "karo": {
                        "generation": 1,
                        "current_work": {"work_id": "w", "api_token": "leak"},
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(FailoverSecurityError):
        RoleFailoverStore(tmp_path).load()


def test_stale_event_does_not_write_store(tmp_path: Path):
    store = RoleFailoverStore(tmp_path, clock=FakeClock())
    cfg = primary_cfg("karo")
    store.apply_event(
        {
            "event_id": "init",
            "type": EVENT_INIT_ROLE,
            "role": "karo",
            "reset": True,
            "primary_profile": cfg.primary.to_dict(),
            "fallback_profile": cfg.fallback.to_dict(),
        },
        role_configs={"karo": cfg},
    )
    before = (tmp_path / "queue/runtime/role_failover.yaml").read_text(encoding="utf-8")
    r = store.apply_event(
        {
            "event_id": "stale",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": 999,
        },
        role_configs={"karo": cfg},
    )
    assert r.rejected
    after = (tmp_path / "queue/runtime/role_failover.yaml").read_text(encoding="utf-8")
    assert before == after
    assert not (tmp_path / "queue/runtime/role_failover_audit.yaml").exists()


def test_resolve_active_launch_profile_primary_and_fallback():
    settings = {
        "cli": {
            "agents": {
                "karo": {
                    "type": "codex",
                    "model": "p",
                    "fallback": {"type": "opencode", "model": "f"},
                }
            }
        }
    }
    state = {
        "roles": {
            "karo": {
                "active_slot": "primary",
                "generation": 2,
                "status": "ready",
                "handoff_complete": True,
            }
        }
    }
    resolved = resolve_active_launch_profile(settings, state, "karo")
    assert resolved["slot"] == "primary"
    assert resolved["profile"]["type"] == "codex"
    assert resolved["generation"] == 2

    state["roles"]["karo"]["active_slot"] = "fallback"
    state["roles"]["karo"]["status"] = "awaiting_handoff"
    state["roles"]["karo"]["handoff_complete"] = False
    pending_fb = resolve_active_launch_profile(settings, state, "karo")
    assert pending_fb["profile"]["type"] == "opencode"
    assert pending_fb["status"] == "awaiting_handoff"

    state["roles"]["karo"]["handoff_complete"] = True
    state["roles"]["karo"]["status"] = "ready"
    resolved_fb = resolve_active_launch_profile(settings, state, "karo")
    assert resolved_fb["profile"]["type"] == "opencode"
    assert resolved_fb["profile"]["model"] == "f"


def test_profile_keeps_known_runtime_fields_and_rejects_credential_endpoint():
    cfg = parse_role_config(
        "ashigaru1",
        {
            "type": "opencode",
            "variant": "high",
            "effort": "max",
            "endpoint": "http://127.0.0.1:1234/v1",
            "recommended_model": "model-a",
        },
    )
    assert cfg.primary.variant == "high"
    assert cfg.primary.endpoint == "http://127.0.0.1:1234/v1"
    with pytest.raises(FailoverSecurityError):
        parse_role_config("ashigaru1", {"type": "localapi", "endpoint": "http://user:pass@localhost/v1"})


def test_karo_numbered_role_inherits_base_profile():
    settings = {"cli": {"agents": {"karo": {"type": "codex", "fallback": {"type": "opencode"}}}}}
    resolved = resolve_active_launch_profile(
        settings,
        {"roles": {"karo2": {"active_slot": "primary", "generation": 4, "status": "ready"}}},
        "karo2",
    )
    assert resolved["profile"]["type"] == "codex"
    assert resolved["generation"] == 4


def test_validate_managed_write_rejects_stale_and_safe_stopped():
    state = {
        "army_mode": "normal",
        "roles": {"karo": {"generation": 2, "status": "ready"}},
    }
    assert validate_managed_write(state, "karo", 2) == (True, "authorized")
    assert validate_managed_write(state, "karo", 1) == (False, "stale_generation")
    state["army_mode"] = "safe_stopped"
    assert validate_managed_write(state, "karo", 2) == (False, "army_safe_stopped")


def test_resolve_does_not_invent_cli_when_fallback_missing():
    settings = {"cli": {"agents": {"karo": {"type": "codex", "fallback": None}}}}
    state = {
        "roles": {
            "karo": {
                "active_slot": "fallback",
                "generation": 3,
                "status": "ready",
                "handoff_complete": True,
            }
        }
    }
    with pytest.raises(FailoverError):
        resolve_active_launch_profile(settings, state, "karo")


def test_actions_are_fixed_enums_only():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    r = ctrl.apply_event(
        {
            "event_id": "x",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g0,
        }
    )
    assert r.action in {
        ACTION_NONE,
        ACTION_RESTART_PRIMARY,
        ACTION_ACTIVATE_FALLBACK,
        ACTION_SAFE_STOP,
        ACTION_REQUEST_REASSIGNMENT,
        ACTION_ENTER_EMERGENCY,
        ACTION_WARN,
        ACTION_MARK_HANDOFF_REQUIRED,
        ACTION_RESUME_AFTER_HANDOFF,
        ACTION_RESTORE_PRIMARY,
        ACTION_REJECT,
    }
    # No shell payload fields
    dumped = yaml.safe_dump(r.to_dict())
    assert "shell" not in dumped
    assert "command" not in dumped or "command" not in r.side_effects


def test_fallback_process_exit_is_terminal_for_karo():
    ctrl = controller_for("karo")
    g0 = gen(ctrl, "karo")
    ctrl.apply_event(
        {
            "event_id": "to-fb",
            "type": EVENT_EXPLICIT_FAILURE,
            "role": "karo",
            "expected_generation": g0,
            "reason": "config_error",
        }
    )
    g1 = gen(ctrl, "karo")
    r = ctrl.apply_event(
        {
            "event_id": "fb-exit",
            "type": EVENT_PROCESS_EXIT,
            "role": "karo",
            "expected_generation": g1,
        }
    )
    assert r.action == ACTION_SAFE_STOP
