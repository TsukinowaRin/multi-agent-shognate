# OpenCode CLI Tools & Notes

## CLI Command
- Default launch: `opencode`
- Optional model pin: `--model <provider/model>`
- Initial prompt: `--prompt <text>`
- In this repository, generated `opencode.json` defaults `permission` to `allow` so agents run without approval prompts unless you override it.

## Local model usage in this repository
- OpenCode can use local providers such as `ollama/...` and `lmstudio/...`.
- This repository can generate a project-level `opencode.json` from `config/settings.yaml`.
- Generated config is meant for provider options such as `baseURL` and `apiKey` env references, not for storing secrets.

## Compatibility in this repository
- Inbox wake-up remains file/event driven.
- Initial role handoff is passed through `--prompt`, not by active-pane text injection.
- If `opencode.json` is absent, OpenCode falls back to its own global or default configuration.
