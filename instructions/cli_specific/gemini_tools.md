# Gemini CLI Tools & Notes

## CLI Command
- Default launch: `gemini --yolo`
- Optional model pin: `--model <model_name>`

## Compatibility in this repository
- Inbox wake-up (`inboxN`) is text injection based.
- `/clear` and `/model` special commands are treated as compatibility commands by `inbox_watcher.sh`.
- If `/model` is not supported by the installed Gemini CLI build, the watcher skips it.

## Operational guidance
- Keep commands non-interactive where possible.
- Prefer file-based mailbox flow over ad-hoc terminal conversation state.
