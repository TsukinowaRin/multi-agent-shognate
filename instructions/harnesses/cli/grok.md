# CLI Harness: Grok

- Treat Grok Build as a distinct CLI surface: do not silently fall back to another CLI's auto-load behavior when Grok-specific state is missing.
- Use generated role instructions, explicit task files, and permission boundaries before coding habits.
- Keep tokens and credentials outside command strings and persistent state; rely on host-side auth, never inline `--api-key` or `--token`.
- Treat `--model` and its value as separate argv; avoid `key=value` joined forms.
- Report Grok-specific differences (e.g., missing reset hook) instead of inventing compatible behavior that diverges from the protocol.