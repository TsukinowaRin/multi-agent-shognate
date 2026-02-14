# Zellij & Multi-CLI Migration Notes

## Summary
- Multiplexer is now configurable via `config/settings.yaml`.
- `tmux` mode remains backward compatible.
- New `zellij` mode is available through `scripts/shutsujin_zellij.sh` and auto-dispatch from `shutsujin_departure.sh`.

## Multiplexer Setting
```yaml
multiplexer:
  default: tmux   # tmux | zellij
```

When `default: zellij`, running `bash shutsujin_departure.sh` dispatches to zellij startup.

## zellij Mode Design
- One agent per zellij session (`shogun`, `karo`, `ashigaru1..8`).
- `inbox_watcher.sh` sends wake-up and control commands using `zellij action`.
- `AGENT_ID` and `DISPLAY_MODE` are exported per session at bootstrap.

## Extended CLI Types
`lib/cli_adapter.sh` now supports:
- `claude`
- `codex`
- `copilot`
- `kimi`
- `gemini`
- `localapi`

### localapi
- Default command: `python3 scripts/localapi_repl.py`
- Uses OpenAI-compatible local endpoint:
  - `LOCALAI_API_BASE` (default `http://127.0.0.1:11434/v1`)
  - `LOCALAI_MODEL` (default `local-model`)
  - `LOCALAI_API_KEY` (optional)

## Operational Caveats
- zellij CLI external pane-control has limitations; this implementation uses per-agent sessions to keep deterministic control.
- If your zellij version differs, verify `zellij action write-chars/write` and `attach --create-background` compatibility.
