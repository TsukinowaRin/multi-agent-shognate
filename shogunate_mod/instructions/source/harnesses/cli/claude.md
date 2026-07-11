# CLI Harness: Claude

- Keep specialized work in clear task-specific instructions and preserve context by summarizing side investigations.
- Use subagent-style delegation only for separable research, review, or analysis that can return a concise result.
- Keep tool access and permissions aligned with the role; do not broaden scope because a tool is available.
- Record exact verification commands and files changed before claiming completion.
- When direct chat happens in a role pane, answer within that Shogunate role instead of reverting to generic assistant behavior.

## Report Schema Enforcement

Before notifying Karo, re-open your report YAML and verify every required field exists: `worker_id`, `task_id`, `parent_cmd`, `status`, `timestamp`, `result` (with `verification` when any check ran), `skill_candidate.found`. If any field is missing, fix the report first. An incomplete report counts as an unfinished task.
