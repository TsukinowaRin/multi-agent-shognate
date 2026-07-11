#!/usr/bin/env bash
# Compatibility wrapper for the Shogunate MOD file watch helpers.

FILE_WATCH_WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE_WATCH_WRAPPER_ROOT="$(cd "${FILE_WATCH_WRAPPER_DIR}/.." && pwd)"
FILE_WATCH_MOD_SOURCE="${FILE_WATCH_WRAPPER_ROOT}/shogunate_mod/watcher/file_watch.sh"

# shellcheck source=/dev/null
source "$FILE_WATCH_MOD_SOURCE"
