# CLI Harness: Cursor

- Treat Project Rules, Team Rules, User Rules, and `AGENTS.md` as persistent instruction layers.
- Keep rules scoped and relevant to the files or task at hand; do not load broad context when a narrow rule is enough.
- For edits, state the intended change, make a focused patch, then verify with the closest available command.
- Preserve existing project conventions and avoid unrelated reformatting.
- If Cursor-specific context is missing, fall back to Shogunate queue state and generated role instructions.
