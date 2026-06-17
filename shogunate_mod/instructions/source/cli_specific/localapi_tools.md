# Local API Tools & Notes

## CLI Command
- Default launch: `python3 scripts/localapi_repl.py`
- This wrapper sends prompts to an OpenAI-compatible local endpoint.

## Required environment variables
- `LOCALAI_API_BASE` (default: `http://127.0.0.1:11434/v1`)
- `LOCALAI_MODEL` (default: `local-model`)
- `LOCALAI_API_KEY` (optional)

## Compatibility in this repository
- Inbox wake-up (`inboxN`) is plain text input.
- `/clear` restarts the localapi wrapper process.
- `/model <name>` is translated into `:model <name>` for the wrapper.

## Operational guidance
- Keep response size bounded for long-running sessions.
- Handle endpoint outage as retriable failure, not fatal crash.
