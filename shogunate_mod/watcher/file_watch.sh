#!/usr/bin/env bash
# Cross-platform file watch helpers.
# Linux/WSL uses inotifywait, macOS uses fswatch, and a timed polling fallback
# keeps the runtime alive when neither tool is installed.

file_watch_find_command() {
    local name="$1"
    local candidate

    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    case "$name" in
        fswatch|brew)
            [ "${MAS_FILE_WATCH_DISABLE_COMMON_PATHS:-0}" = "1" ] && return 1
            for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
                if [ -x "$candidate" ]; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            done
            ;;
    esac

    return 1
}

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

    if file_watch_find_command inotifywait >/dev/null 2>&1; then
        printf 'inotifywait\n'
    elif file_watch_find_command fswatch >/dev/null 2>&1; then
        printf 'fswatch\n'
    else
        printf 'polling\n'
    fi
}

file_watch_backend_available() {
    case "$(file_watch_backend)" in
        inotifywait)
            file_watch_find_command inotifywait >/dev/null 2>&1
            ;;
        fswatch)
            file_watch_find_command fswatch >/dev/null 2>&1
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
    local watch_cmd
    local pid=""
    local elapsed=0

    backend="$(file_watch_backend)"
    case "$backend" in
        inotifywait)
            watch_cmd="$(file_watch_find_command inotifywait || true)"
            if [ -z "$watch_cmd" ]; then
                sleep "$wait_timeout"
                return 2
            fi
            "$watch_cmd" -q -t "$wait_timeout" -e modify -e close_write "$path" 2>/dev/null
            return $?
            ;;
        fswatch)
            watch_cmd="$(file_watch_find_command fswatch || true)"
            if [ -z "$watch_cmd" ]; then
                sleep "$wait_timeout"
                return 2
            fi
            # fswatch has no portable timeout flag. Run one-shot mode in the
            # background and enforce our own timeout so escalation still ticks.
            "$watch_cmd" -1 "$path" >/dev/null 2>&1 &
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
