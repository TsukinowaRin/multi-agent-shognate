# CLI Harness: Antigravity

- Use `.agents/skills/<name>/SKILL.md` for reusable workflows and keep trigger descriptions focused.
- Prefer project-local skills and agents for Shogunate-specific behavior instead of legacy Gemini-compatible structures.
- Keep tool and hook behavior explicit; do not assume a skill ran unless it was invoked or its instructions are in context.
- For UI or browser tasks, capture observable evidence rather than only textual confidence.
- Summarize work as artifacts, verification, and next action so Antigravity monitoring surfaces stay useful.

## Report Schema Enforcement

Before notifying Karo, re-open your report YAML and verify every required field exists: `worker_id`, `task_id`, `parent_cmd`, `status`, `timestamp`, `result` (with `verification` when any check ran), `skill_candidate.found`. If any field is missing, fix the report first. An incomplete report counts as an unfinished task.
