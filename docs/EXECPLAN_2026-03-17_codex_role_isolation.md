# ExecPlan: Codex Role Isolation

## Context
- In this fork, different roles can use different Codex models and `reasoning_effort`.
- The user explicitly wanted Shogun-side Codex tuning not to leak into VSCode Codex or unrelated Codex CLI sessions.
- The existing launch path already passed per-role model and reasoning flags, but Codex runtime state was still effectively shared.

## Scope
- Isolate Codex runtime state per role by setting a role-local `CODEX_HOME`.
- Keep existing Codex launch flags intact.
- Document the behavior in public docs.
- Add tests that verify per-role `CODEX_HOME` generation.

## Acceptance Criteria
- `lib/cli_adapter.sh` launches Codex with `CODEX_HOME=<repo>/.codex/agents/<agent_id>`.
- `tests/unit/test_cli_adapter.bats` verifies distinct `CODEX_HOME` values for different Codex roles.
- `README.md`, `README_ja.md`, and `docs/REQS.md` mention that Codex state is isolated per role and does not intentionally share state with VSCode Codex.

## Work Breakdown
1. Inspect current Codex launch command generation.
2. Add role-local `CODEX_HOME` handling.
3. Update CLI adapter tests.
4. Reflect the behavior in README and requirements.
5. Validate, commit, and publish.

## Progress
- 2026-03-17: Verified that per-role model and `reasoning_effort` flags already existed, but `CODEX_HOME` isolation did not.
- 2026-03-17: Implemented role-local `CODEX_HOME` in `lib/cli_adapter.sh`.
- 2026-03-17: Updated `tests/unit/test_cli_adapter.bats` to assert role-specific `CODEX_HOME`.
- 2026-03-17: Updated README English/Japanese and `docs/REQS.md` to describe the isolation behavior.
- 2026-03-17: Validated with `bats tests/unit/test_cli_adapter.bats`, committed as `00100c2`, and pushed to `main` and `codex/auto`.

## Surprises & Discoveries
- The main risk was not command generation but shared Codex state outside the repo.
- Test expectations initially assumed `CODEX_HOME` should live under the test temp directory, but the actual design correctly uses the repo root so the runtime state remains scoped to the project.

## Decision Log
- Use `CODEX_HOME` isolation instead of trying to encode role state separation only through CLI flags.
- Keep the isolated state repo-local under `.codex/agents/<role>`, not under the user home directory.
- Do not attempt to modify VSCode behavior directly; isolate the Shogunate side instead.

## Outcomes & Retrospective
- Codex roles can now use different models and reasoning settings without intentionally sharing runtime state.
- The fork now has a clearer separation between Shogunate Codex sessions and unrelated Codex usage on the same machine.
- This change should remain low-risk as long as per-role Codex state under `.codex/agents/` remains local-only and unpublished.
