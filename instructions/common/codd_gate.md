# CoDD Native Gate

CoDD is the repository coherence gate. Use it as a tool-backed check, not as a conversational claim.

## Agent-Facing Command

Use the agent wrapper so every run leaves a durable report and log:

```bash
bash scripts/agent_codd_gate.sh "$AGENT_ID" "<task_or_cmd_id>" verify
```

The wrapper writes:

- `queue/runtime/codd/<agent_id>_<task_or_cmd_id>_verify.yaml`
- `queue/runtime/codd/logs/<agent_id>_<task_or_cmd_id>_verify.log`

It calls `scripts/codd_check.sh` and defaults to `CODD_AUTO_INSTALL=1`, so missing CoDD is handled through the standard `.shogunate/codd-venv` install path.

## When To Run

Run CoDD after ordinary local verification, not instead of it.

Ashigaru should run the gate when the task changes code, shell scripts, runtime behavior, instructions, docs that affect agent behavior, package metadata, Android integration, or release/config files.

Karo should run the gate before closing implementation, refactor, release, multi-file, or instruction-changing cmds unless the cmd is purely informational or the gate is clearly irrelevant.

Gunshi should use CoDD reports as evidence for strategic review and QC, especially when evaluating architecture, dependency, or release readiness.

## How To Report

If you run the gate, include this in your report YAML:

```yaml
result:
  codd:
    command: "bash scripts/agent_codd_gate.sh <agent_id> <task_or_cmd_id> verify"
    report_path: "queue/runtime/codd/<agent_id>_<task_or_cmd_id>_verify.yaml"
    log_path: "queue/runtime/codd/logs/<agent_id>_<task_or_cmd_id>_verify.log"
    status: "pass"
```

If CoDD fails, do not report `done` unless the task explicitly asks only to record the failure. Report `failed` or `blocked`, include the report path, and summarize the first actionable failure from the log.

If CoDD exits 0 with warnings, you may report `done` only when the warnings are non-blocking for the task. Note the warning summary in `result.notes` or `result.codd.warning_summary`.

## Scope Discipline

- Do not run CoDD in idle loops or background monitors.
- Do not use CoDD as a substitute for task-specific tests.
- Do not edit `.codd/scan`, `.codd/verify_report.md`, or `queue/runtime/codd/` by hand.
- Do not vendor CoDD into the repository.
