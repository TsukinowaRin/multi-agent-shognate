# Kilo CLI Tools & Notes

## CLI Command
- Default launch: `kilo`
- Optional model pin: `--model <provider/model>`
- Initial prompt: `--prompt <text>`
- In this repository, generated `opencode.json` defaults `permission` to `allow` so agents run without approval prompts unless you override it.

## Local model usage in this repository
- Kilo CLI is a fork of OpenCode and uses the same project config format (`opencode.json`).
- This repository can generate `opencode.json` from `config/settings.yaml` for local providers such as Ollama, LM Studio, and OpenAI-compatible endpoints.
- Secrets should stay in environment variables; generated config writes env references only.

## Compatibility in this repository
- Inbox wake-up remains file/event driven.
- Initial role handoff is passed through `--prompt`, not by active-pane text injection.
- If `opencode.json` is absent, Kilo falls back to its own global or default configuration.
