# Antigravity CLI Tools & Notes

## CLI Command
- Default launch: `agy --dangerously-skip-permissions`
- Optional model pin: `--model <model_name>` when the installed CLI supports it.

## Compatibility in this repository
- Inbox wake-up (`inboxN`) is text injection based.
- `/clear` is treated as a compatibility command by `shogunate_mod/watcher/inbox_watcher.sh` and restarts the CLI with the configured Antigravity command.
- `/model` should be handled in the Antigravity CLI UI or pane-local settings; the watcher does not force model changes.

## State and authentication
- Shogunate starts each role with role-local `HOME` and XDG paths under `.shogunate/cli-state/antigravity/agents/<agent>/home`.
- Known host Antigravity auth files under `.gemini/antigravity-cli/` are symlinked when present.
- Host OAuth/account files that `agy` relies on, such as `.gemini/oauth_creds.json` and `.gemini/google_accounts.json`, are also symlinked. Treat these as auth-only shared files; do not share settings, history, cache, or project state.
- Settings, model selections, cache, and history remain pane-local.

## Operational guidance
- Keep commands non-interactive where possible.
- Prefer file-based mailbox flow over ad-hoc terminal conversation state.
