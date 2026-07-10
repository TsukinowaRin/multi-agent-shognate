#!/usr/bin/env bash
set -euo pipefail

: "${AGMSG_CALL_LOG:?AGMSG_CALL_LOG must point to the stub call log}"

printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$AGMSG_CALL_LOG"
exit "${AGMSG_STUB_EXIT_CODE:-0}"
