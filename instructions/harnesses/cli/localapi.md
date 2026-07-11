# CLI Harness: LocalAPI

- Treat LocalAPI as model-agnostic: do not rely on provider-specific hidden tools or behaviors.
- Keep prompts and reports structured because local models may be less reliable with long implicit context.
- Prefer short checklists, explicit file paths, and exact commands.
- Avoid broad speculative optimization; only act on assigned scope and observable evidence.
- If model capability is insufficient, report the blocker and the smallest fallback path instead of inventing results.
