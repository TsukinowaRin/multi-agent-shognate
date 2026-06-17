#!/usr/bin/env bash

ensure_tmux_tmpdir() {
    local tmux_tmp="${TMUX_TMPDIR:-}"
    [ -n "$tmux_tmp" ] || return 0
    mkdir -p "$tmux_tmp"
    chmod 700 "$tmux_tmp" 2>/dev/null || true
}

acquire_startup_lock() {
    local lock_root="$SCRIPT_DIR/.shogunate/locks"
    local lock_dir="$lock_root/shutsujin.lock.d"
    local pid_file="$lock_dir/pid"
    local _attempt
    local holder_pid=""

    mkdir -p "$lock_root"
    for _attempt in 1 2 3 4; do
        if mkdir "$lock_dir" 2>/dev/null; then
            printf '%s\n' "$$" > "$pid_file"
            STARTUP_LOCK_DIR="$lock_dir"
            trap 'rm -rf "${STARTUP_LOCK_DIR:-}"' EXIT INT TERM
            return 0
        fi

        holder_pid=""
        if [ -f "$pid_file" ]; then
            holder_pid="$(tr -d '\r' < "$pid_file" | head -n1)"
        fi
        if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
            rm -rf "$lock_dir"
            continue
        fi
        sleep 0.5
    done

    echo -e "\033[1;31m【ERROR】\033[0m 既に別の shutsujin_departure.sh が実行中です。" >&2
    echo "  二重起動を避けるため停止しました。先行プロセスの完了後に再実行してください。" >&2
    exit 1
}

load_runtime_language_shell_settings() {
    LANG_SETTING="ja"
    if [ -f "./config/settings.yaml" ]; then
        LANG_SETTING=$(grep "^language:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "ja")
    fi

    SHELL_SETTING="bash"
    if [ -f "./config/settings.yaml" ]; then
        SHELL_SETTING=$(grep "^shell:" ./config/settings.yaml 2>/dev/null | awk '{print $2}' || echo "bash")
    fi
}

detect_early_help_request() {
    EARLY_HELP_REQUESTED=false
    local _arg
    for _arg in "$@"; do
        case "$_arg" in
            -h|--help)
                EARLY_HELP_REQUESTED=true
                break
                ;;
        esac
    done
}

select_runtime_python_or_die() {
    RUNTIME_PYTHON=""
    if [ -x "$SCRIPT_DIR/.venv/bin/python3" ] && "$SCRIPT_DIR/.venv/bin/python3" -c "import yaml" >/dev/null 2>&1; then
        RUNTIME_PYTHON="$SCRIPT_DIR/.venv/bin/python3"
    elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
        RUNTIME_PYTHON="$(command -v python3)"
    fi

    if [ "$EARLY_HELP_REQUESTED" != true ] && [ -z "$RUNTIME_PYTHON" ]; then
        echo -e "\033[1;31m【ERROR】\033[0m Python 実行環境が不足しています。"
        echo "  必要条件:"
        echo "    - python3"
        echo "    - PyYAML (python3 -c 'import yaml' が成功すること)"
        echo ""
        echo "  まず次を実行してください:"
        echo "    bash first_setup.sh"
        echo ""
        echo "  あるいは Ubuntu/Debian なら:"
        echo "    sudo apt-get install -y python3 python3-yaml inotify-tools"
        exit 1
    fi
}

sync_opencode_like_workspace_settings() {
    local sync_script="$SCRIPT_DIR/scripts/sync_opencode_config.py"
    if [ ! -x "$sync_script" ]; then
        return 0
    fi
    if ! python3 "$sync_script" >/dev/null 2>&1; then
        log_info "⚠️  OpenCode/Kilo project config の同期に失敗しました。既存 opencode.json を使用して継続します"
    fi
}

run_startup_update_check() {
    local update_script="$SCRIPT_DIR/shogunate_mod/update/manager.py"
    [ -x "$update_script" ] || return 0
    [ "${MAS_SKIP_STARTUP_UPDATE:-0}" = "1" ] && return 0

    log_info "🆙 起動前アップデート確認を実行中..."
    if python3 "$update_script" startup; then
        return 0
    fi

    case "$?" in
        10)
            log_info "🆙 更新を適用したため first_setup.sh を再実行します"
            bash "$SCRIPT_DIR/shogunate_mod/package/first_setup.sh" || true
            log_info "🆙 新しいコードで出陣をやり直します"
            exec env MAS_SKIP_STARTUP_UPDATE=1 bash "$0" "$@"
            ;;
        *)
            log_info "⚠️  起動前アップデート確認に失敗しました。現行コードで継続します"
            return 0
            ;;
    esac
}

run_pending_update_request() {
    local update_script="$SCRIPT_DIR/shogunate_mod/update/manager.py"
    [ -x "$update_script" ] || return 0
    [ "${MAS_SKIP_PENDING_UPDATE:-0}" = "1" ] && return 0

    log_info "🆙 予約済みアップデート有無を確認中..."
    if python3 "$update_script" apply-pending; then
        return 0
    fi

    case "$?" in
        10)
            log_info "🆙 予約済みアップデートを適用したため first_setup.sh を再実行します"
            bash "$SCRIPT_DIR/shogunate_mod/package/first_setup.sh" || true
            log_info "🆙 新しいコードで出陣をやり直します"
            exec env MAS_SKIP_PENDING_UPDATE=1 MAS_SKIP_STARTUP_UPDATE=1 bash "$0" "$@"
            ;;
        *)
            log_info "⚠️  予約済みアップデート適用に失敗しました。現行コードで継続します"
            return 0
            ;;
    esac
}

notify_pending_merge_candidates() {
    local update_script="$SCRIPT_DIR/shogunate_mod/update/manager.py"
    [ -x "$update_script" ] || return 0
    python3 "$update_script" notify-karo >/dev/null 2>&1 || true
}

log_info() {
    echo -e "\033[1;33m【報】\033[0m $1"
}

log_success() {
    echo -e "\033[1;32m【成】\033[0m $1"
}

log_war() {
    echo -e "\033[1;31m【戦】\033[0m $1"
}

ensure_generated_instructions() {
    local ensure_script="$SCRIPT_DIR/scripts/ensure_generated_instructions.sh"
    if [ ! -f "$ensure_script" ]; then
        log_info "⚠️  指示書再生成スクリプトが見つからないため、既存 generated を使用します"
        return 0
    fi

    if ! bash "$ensure_script"; then
        log_info "⚠️  指示書再生成に失敗しました。既存 generated を使用して継続します"
    fi
}
