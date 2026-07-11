# CLI Harness: OpenCode

- Treat the generated `.opencode/agents/<agent>.md` file as the active role contract.
- Respect the agent frontmatter permission boundaries and the canonical `agent_id` identity check.
- Use explicit task handoff text and structured reports because OpenCode sessions can run in parallel.
- Keep context compact; use skills or agent definitions for reusable behavior instead of repeating long prompts.
- Do not assume hidden state from another OpenCode session unless it is present in Shogunate queue files or reports.
