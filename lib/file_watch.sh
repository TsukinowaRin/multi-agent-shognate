#!/usr/bin/env bash
# Cross-platform file watch helpers.
# Linux/WSL uses inotifywait, macOS uses fswatch, and a timed polling fallback
# keeps the runtime alive when neither tool is installed.

file_watch_backend() {
    local forced="${MAS_FILE_WATCH_BACKEND:-auto}"

    case "$forced" in
        inotifywait|fswatch|polling)
            printf '%s\n' "$forced"
            return 0
            ;;
        auto|"")
            ;;
        *)
            printf 'polling\n'
            return 0
            ;;
    esac

    if command -v inotifywait >/dev/null 2>&1; then
        printf 'inotifywait\n'
    elif command -v fswatch >/dev/null 2>&1; then
        printf 'fswatch\n'
    else
        printf 'polling\n'
    fi
}

file_watch_backend_available() {
    case "$(file_watch_backend)" in
        inotifywait)
            command -v inotifywait >/dev/null 2>&1
            ;;
        fswatch)
            command -v fswatch >/dev/null 2>&1
            ;;
        polling)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

file_watch_wait_once() {
    local path="$1"
    local wait_timeout="${2:-30}"
    local backend
    local pid=""
    local elapsed=0

    backend="$(file_watch_backend)"
    case "$backend" in
        inotifywait)
            if ! command -v inotifywait >/dev/null 2>&1; then
                sleep "$wait_timeout"
                return 2
            fi
            inotifywait -q -t "$wait_timeout" -e modify -e close_write "$path" 2>/dev/null
            return $?
            ;;
        fswatch)
            if ! command -v fswatch >/dev/null 2>&1; then
                sleep "$wait_timeout"
                return 2
            fi
            # fswatch has no portable timeout flag. Run one-shot mode in the
            # background and enforce our own timeout so escalation still ticks.
            fswatch -1 "$path" >/dev/null 2>&1 &
            pid="$!"
            while kill -0 "$pid" 2>/dev/null; do
                if [ "$elapsed" -ge "$wait_timeout" ]; then
                    kill "$pid" >/dev/null 2>&1 || true
                    wait "$pid" 2>/dev/null || true
                    return 2
                fi
                sleep 1
                elapsed=$((elapsed + 1))
            done
            wait "$pid" 2>/dev/null
            return $?
            ;;
        polling|*)
            sleep "$wait_timeout"
            return 2
            ;;
    esac
}
