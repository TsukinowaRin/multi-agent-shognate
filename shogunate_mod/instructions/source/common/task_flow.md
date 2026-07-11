# Task Flow

## Workflow: Shogun → Karo → Ashigaru

```
Lord: command → Shogun: write YAML → inbox_write → Karo: decompose → inbox_write → Ashigaru: execute → report YAML → inbox_write → Karo: update dashboard → Shogun: read dashboard
```

## Immediate Delegation Principle (Shogun)

**Delegate to Karo immediately and end your turn** so the Lord can input next command.

```
Lord: command → Shogun: write YAML → inbox_write → END TURN
                                        ↓
                                  Lord: can input next
                                        ↓
                              Karo/Ashigaru: work in background
                                        ↓
                              dashboard.md updated as report
```

## Event-Driven Wait Pattern (Karo)

**After dispatching all subtasks: STOP.** Do not launch background monitors or sleep loops.

```
Step 7: Dispatch cmd_N subtasks → mailbox write to ashigaru via shogunate_mod/inbox/write.sh
Step 8: check_pending → if pending cmd_N+1, process it → then STOP
  → Karo becomes idle (prompt waiting)
Step 9: Ashigaru completes → inbox_write karo → watcher nudges karo
  → Karo wakes, scans reports, acts
```

**Why no background monitor**: shogunate_mod/watcher/inbox_watcher.sh detects ashigaru's mailbox write to karo and sends a nudge. This is true event-driven. No sleep, no polling, no CPU waste.

**Karo wakes via**: inbox nudge from ashigaru report, shogun new cmd, or system event. Nothing else.

## "Wake = Full Scan" Pattern

Claude Code cannot "wait". Prompt-wait = stopped.

1. Dispatch ashigaru
2. Say "stopping here" and end processing
3. Ashigaru wakes you via inbox
4. Scan ALL report files (not just the reporting one)
5. Assess situation, then act

## Report Scanning (Communication Loss Safety)

On every wakeup (regardless of reason), scan ALL `queue/reports/ashigaru*_report.yaml`.
Cross-reference with dashboard.md — process any reports not yet reflected.

**Why**: Ashigaru inbox messages may be delayed. Report files are already written and scannable as a safety net.

### Karo Report Wake Scope

When the wakeup reason is `report_received`, keep the read scope narrow:

1. relevant report YAML
2. parent cmd in `queue/shogun_to_karo.yaml`
3. `dashboard.md`

Do not wander into bridge scripts, relay state TSVs, notification helpers, `streaks.yaml`, `*.sample`, or unrelated docs unless completion genuinely fails. The goal of a report wakeup is closure, not exploration.

### Implementation Cmd Closure Rule

For implementation or file-generation work, "report says tests passed" is not enough.

Karo must:

1. read `result.verification.command` and `result.verification.cwd`
2. rerun that command from that directory
3. close the cmd only if the rerun actually succeeds

If the report has modified code/files but lacks reproducible verification metadata, treat it as incomplete and send it back instead of closing.

## Foreground Block Prevention (24-min Freeze Lesson)

**Karo blocking = entire army halts.** On 2026-02-06, foreground `sleep` during delivery checks froze karo for 24 minutes.

**Rule: NEVER use `sleep` in foreground.** After dispatching tasks → stop and wait for inbox wakeup.

| Command Type | Execution Method | Reason |
|-------------|-----------------|--------|
| Read / Write / Edit | Foreground | Completes instantly |
| shogunate_mod/inbox/write.sh | Foreground | Completes instantly |
| `sleep N` | **FORBIDDEN** | Use inbox event-driven instead |
| tmux capture-pane | **FORBIDDEN** | Read report YAML instead |

### Dispatch-then-Stop Pattern

```
✅ Correct (event-driven):
  cmd_008 dispatch → mailbox write to ashigaru via shogunate_mod/inbox/write.sh → stop (await inbox wakeup)
  → ashigaru completes → inbox_write karo → karo wakes → process report

❌ Wrong (polling):
  cmd_008 dispatch → sleep 30 → capture-pane → check status → sleep 30 ...
```

## Timestamps

**Always use `date` command.** Never guess.
```bash
date "+%Y-%m-%d %H:%M"       # For dashboard.md
date "+%Y-%m-%dT%H:%M:%S"    # For YAML (ISO 8601)
```

## Status Reference (Single Source)

Fixed status vocabulary (do not invent others without updating this section):

- `queue/shogun_to_karo.yaml`: `pending`, `in_progress`, `done`, `cancelled`
- `queue/tasks/ashigaruN.yaml`: `assigned`, `blocked`, `done`, `failed`
- `queue/tasks/pending.yaml`: `pending_blocked` (holding area; do not dispatch to ashigaru from here)
- `queue/ntfy_inbox.yaml`: `pending`, `processed`

Any other status value (e.g., `completed`, `active`, `superseded`) is forbidden. Normalize to the canonical set above when found during archive.

### Per-status forbidden actions

| Status | Forbidden action | Use instead |
|--------|------------------|-------------|
| `pending` (cmd) | Dispatch subtasks while still pending | Move to `in_progress` first |
| `in_progress` | Editing acceptance_criteria, or marking `done` without meeting all criteria | Keep criteria stable; rework until met |
| `done` (cmd) | Editing the old cmd to "reopen" | Open a new cmd |
| `cancelled` | Continuing work under this cmd | Open a new cmd |
| `blocked` | Nudging the agent or starting work | Resolve the blocker; wait event-driven |
| `failed` (ashigaru) | Silent failure | Report the failure explicitly, then escalate |
| `done` (ashigaru) | Reusing the task_id for a redo | Use the Redo Protocol with a new task_id |
| `pending_blocked` | Pre-assigning to ashigaru before ready | Keep in `pending_blocked` until ready |
| `pending` (ntfy) | Leaving it pending without a reason | Process or annotate the reason |
| `processed` (ntfy) | Flipping back to pending without a new entry | Create a new entry |

`status: idle` is allowed only when `task_id: null` (the clean-start template written by `shutsujin_departure.sh --clean`).

## Pre-Commit Gate (CI-Aligned)

Before any commit, run the same checks GitHub Actions will run. Commit only when green.

```bash
bats tests/*.bats tests/unit/*.bats          # local unit suite (no SKIP allowed)
bash shogunate_mod/instructions/build.sh     # regenerate instructions
git diff --exit-code instructions/generated/ # build output must match checked-in source
```

Ask the Lord before any `git push`. A local `git push` without explicit Lord approval is forbidden (see F007).
