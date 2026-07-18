#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# shogunate_mod/watcher/inbox_watcher.sh — メールボックス監視＆起動シグナル配信
# Usage: bash shogunate_mod/watcher/inbox_watcher.sh <agent_id> <pane_target> [cli_type] [mux_type]
# Example: bash shogunate_mod/watcher/inbox_watcher.sh karo multiagent:0.0 claude tmux
#
# 設計思想:
#   メッセージ本体はファイル（inbox YAML）に書く = 確実
#   起動シグナルは tmux send-keys（テキストとEnterを分離送信）
#   エージェントが自分でinboxをReadして処理する
#   冪等: 2回届いてもunreadがなければ何もしない
#
# Linux/WSL は inotifywait、macOS は fswatch でファイル変更を検知する。
# Fallback 1: 30秒タイムアウト（WSL2 inotify不発時の安全網）
# Fallback 2: polling backend（監視ツール未導入時の安全網）
# Fallback 3: rc=1処理（Claude Code atomic write = tmp+rename でinode変更時）
#
# エスカレーション（未読メッセージが放置されている場合）:
#   0〜2分: 通常nudge（send-keys）。ただしWorking中はスキップ
#   2〜4分: Escape×2 + nudge（カーソル位置バグ対策）
#   4分〜 : /clear送信（5分に1回まで。強制リセット+YAML再読）
# ═══════════════════════════════════════════════════════════════

# ─── Testing guard ───
# When __INBOX_WATCHER_TESTING__=1, only function definitions are loaded.
# Argument parsing, file watch backend check, and main loop are skipped.
# Test code sets variables (AGENT_ID, PANE_TARGET, CLI_TYPE, INBOX) externally.
if [ "${__INBOX_WATCHER_TESTING__:-}" != "1" ]; then
    set -euo pipefail

    MOD_WATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_DIR="${SHOGUNATE_REPO_ROOT:-$(cd "$MOD_WATCHER_DIR/../.." && pwd)}"
    AGENT_ID="$1"
    PANE_TARGET="$2"
    CLI_TYPE="${3:-claude}"  # CLI種別（claude/codex/copilot/kimi/antigravity/opencode/kilo/localapi/cursor）
    case "$CLI_TYPE" in
        gemini|agy) CLI_TYPE="antigravity" ;;
    esac
    MUX_TYPE="tmux"

    INBOX="$SCRIPT_DIR/queue/inbox/${AGENT_ID}.yaml"
    LOCKFILE="${INBOX}.lock"
    TRANSPORT_MODE="$(python3 - "$SCRIPT_DIR/config/settings.yaml" <<'PY' 2>/dev/null || echo yaml
import sys
from pathlib import Path

try:
    import yaml

    config = yaml.safe_load(Path(sys.argv[1]).read_text(encoding="utf-8")) or {}
    mode = str((config.get("transport") or {}).get("mode") or "yaml").strip().lower()
    print(mode if mode in {"yaml", "agmsg", "both"} else "yaml")
except Exception:
    print("yaml")
PY
)"

    if [ -z "$AGENT_ID" ] || [ -z "$PANE_TARGET" ]; then
        echo "Usage: inbox_watcher.sh <agent_id> <pane_target> [cli_type]" >&2
        exit 1
    fi

    if [ "${4:-tmux}" != "tmux" ]; then
        echo "[$(date)] [INFO] non-tmux watcher mode is deprecated. Falling back to tmux." >&2
    fi

    # Initialize inbox if not exists
    if [ ! -f "$INBOX" ]; then
        mkdir -p "$(dirname "$INBOX")"
        echo "messages: []" > "$INBOX"
    fi

    echo "[$(date)] inbox_watcher started — agent: $AGENT_ID, pane: $PANE_TARGET, cli: $CLI_TYPE, mux: $MUX_TYPE" >&2

    _cli_adapter="${SCRIPT_DIR}/shogunate_mod/cli/adapter.sh"
    if [ -f "$_cli_adapter" ]; then
        # shellcheck source=/dev/null
        source "$_cli_adapter"
    fi

    _agent_status_lib="${SCRIPT_DIR}/shogunate_mod/status/agent_status.sh"
    if [ -f "$_agent_status_lib" ]; then
        # shellcheck source=/dev/null
        source "$_agent_status_lib"
    fi

    _file_watch_lib="${SCRIPT_DIR}/shogunate_mod/watcher/file_watch.sh"
    if [ -f "$_file_watch_lib" ]; then
        # shellcheck source=/dev/null
        source "$_file_watch_lib"
    else
        echo "[inbox_watcher] ERROR: shogunate_mod/watcher/file_watch.sh not found" >&2
        exit 1
    fi

    # upstream追随: Claude は welcome 直後に stop hook がまだ走らず、
    # idle flag 不在のまま false-busy に陥ることがある。起動時に初期 idle flag を作る。
    if [[ "$CLI_TYPE" == "claude" ]]; then
        touch "${IDLE_FLAG_DIR:-/tmp}/shogun_idle_${AGENT_ID}" 2>/dev/null || true
        echo "[$(date)] Created initial idle flag for $AGENT_ID" >&2
    fi

    echo "[$(date)] file watch backend: $(file_watch_backend)" >&2
fi

# ─── Grok Build failure classifier (GB-003B) ───
# Pure in-memory helper: 引数として渡された短い pane text を分類し、固定
# reason 文字列だけを返す。TUI の stdout/stderr を file へ redirect する
# ことは絶対にしない（attempt 1 の禁止設計の再発防止）。helper は関数定義
# だけを提供し、ここでは関数を load するだけで何も実行しない。
#
# helper の source path は BASH_SOURCE[0] の symlink を解決した実 path だけ
# から決める。MOD_WATCHER_DIR 等の環境変数や、外部directoryに置いた watcher
# symlink 経由で source 先を差し替えることは許さない。
_grok_watcher_source="${BASH_SOURCE[0]}"
while [[ -L "$_grok_watcher_source" ]]; do
    _grok_watcher_dir="$(cd -P "$(dirname "$_grok_watcher_source")" && pwd)"
    _grok_watcher_link="$(readlink "$_grok_watcher_source")"
    if [[ "$_grok_watcher_link" == /* ]]; then
        _grok_watcher_source="$_grok_watcher_link"
    else
        _grok_watcher_source="${_grok_watcher_dir}/${_grok_watcher_link}"
    fi
done
MOD_WATCHER_DIR="$(cd -P "$(dirname "$_grok_watcher_source")" && pwd)"
_grok_failure_helper="${MOD_WATCHER_DIR}/../runtime/grok_failure.sh"
if [[ -f "$_grok_failure_helper" ]]; then
    # shellcheck source=/dev/null
    source "$_grok_failure_helper"
fi
unset _grok_failure_helper _grok_watcher_source _grok_watcher_dir _grok_watcher_link

# ─── Escalation state ───
# Time-based escalation: track how long unread messages have been waiting
FIRST_UNREAD_SEEN=${FIRST_UNREAD_SEEN:-0}
LAST_CLEAR_TS=${LAST_CLEAR_TS:-0}
ESCALATE_PHASE1=${ESCALATE_PHASE1:-120}
ESCALATE_PHASE2=${ESCALATE_PHASE2:-240}
ESCALATE_COOLDOWN=${ESCALATE_COOLDOWN:-300}
# Tracks whether /new or /clear was already sent for the current task_assigned batch.
# Resets to 0 when all messages are read (FIRST_UNREAD_SEEN → 0).
NEW_CONTEXT_SENT=${NEW_CONTEXT_SENT:-0}
# Codex startup prompt includes full recovery; skip the follow-up nudge that cycle.
STARTUP_PROMPT_SENT=${STARTUP_PROMPT_SENT:-0}
LAST_CLI_RESTART_TS=${LAST_CLI_RESTART_TS:-0}
CLI_RESTART_COOLDOWN=${CLI_RESTART_COOLDOWN:-30}
CLI_STARTUP_GRACE_SECONDS=${CLI_STARTUP_GRACE_SECONDS:-20}
RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS=${RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS:-90}
LAST_HARD_USAGE_LIMIT_LOG_TS=${LAST_HARD_USAGE_LIMIT_LOG_TS:-0}
HARD_USAGE_LIMIT_LOG_COOLDOWN=${HARD_USAGE_LIMIT_LOG_COOLDOWN:-600}
LAST_MISSING_REPORT_RECOVERY_TASK_ID=${LAST_MISSING_REPORT_RECOVERY_TASK_ID:-}
LAST_MISSING_REPORT_RECOVERY_TS=${LAST_MISSING_REPORT_RECOVERY_TS:-0}
MISSING_REPORT_RECOVERY_COOLDOWN=${MISSING_REPORT_RECOVERY_COOLDOWN:-120}
GUNKAN_AUDIT_NUDGE_COOLDOWN=${GUNKAN_AUDIT_NUDGE_COOLDOWN:-180}
LAST_GUNKAN_AUDIT_NUDGE_TS=${LAST_GUNKAN_AUDIT_NUDGE_TS:-0}
NUDGE_REPEAT_COOLDOWN=${NUDGE_REPEAT_COOLDOWN:-120}
LAST_NUDGE_SIGNATURE=${LAST_NUDGE_SIGNATURE:-}
LAST_NUDGE_TS=${LAST_NUDGE_TS:-0}

# macOS does not ship flock. Keep the Linux fast path, but use an atomic
# directory lock with the same bounded wait when flock is unavailable.
# Each caller runs this helper inside a subshell, so the EXIT trap releases
# only the lock acquired for that inbox operation.
acquire_inbox_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -x 200
        return $?
    fi

    local lock_dir="${LOCKFILE}.d"
    local lock_attempt=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        lock_attempt=$((lock_attempt + 1))
        [ "$lock_attempt" -lt 50 ] || return 1
        sleep 0.1
    done
    INBOX_LOCK_DIR="$lock_dir"
    trap 'rmdir "${INBOX_LOCK_DIR:-}" 2>/dev/null || true' EXIT
}

# ─── Phase feature flags (cmd_107 Phase 1/2/3) ───
# ASW_PHASE:
#   1 = self-watch base (compatible)
#   2 = disable normal nudge by default
#   3 = FINAL_ESCALATION_ONLY (send-keys is fallback only)
ASW_PHASE=${ASW_PHASE:-1}
ASW_DISABLE_NORMAL_NUDGE=${ASW_DISABLE_NORMAL_NUDGE:-$([ "${ASW_PHASE}" -ge 2 ] && echo 1 || echo 0)}
ASW_FINAL_ESCALATION_ONLY=${ASW_FINAL_ESCALATION_ONLY:-$([ "${ASW_PHASE}" -ge 3 ] && echo 1 || echo 0)}
FINAL_ESCALATION_ONLY=${FINAL_ESCALATION_ONLY:-$ASW_FINAL_ESCALATION_ONLY}
ASW_NO_IDLE_FULL_READ=${ASW_NO_IDLE_FULL_READ:-1}
# Optional safety toggles:
# - ASW_DISABLE_ESCALATION=1: disable phase2/phase3 escalation actions
# - ASW_PROCESS_TIMEOUT=0: do not process unread on timeout ticks (event-only)
ASW_DISABLE_ESCALATION=${ASW_DISABLE_ESCALATION:-0}
ASW_PROCESS_TIMEOUT=${ASW_PROCESS_TIMEOUT:-1}

# ─── Metrics hooks (FR-006 / NFR-003) ───
# unread_latency_sec / read_count / estimated_tokens are intentionally explicit
READ_COUNT=${READ_COUNT:-0}
READ_BYTES_TOTAL=${READ_BYTES_TOTAL:-0}
ESTIMATED_TOKENS_TOTAL=${ESTIMATED_TOKENS_TOTAL:-0}
METRICS_FILE=${METRICS_FILE:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/metrics/${AGENT_ID:-unknown}_selfwatch.yaml}

update_metrics() {
    local bytes_read="${1:-0}"
    local now
    now=$(date +%s)

    READ_COUNT=$((READ_COUNT + 1))
    READ_BYTES_TOTAL=$((READ_BYTES_TOTAL + bytes_read))
    ESTIMATED_TOKENS_TOTAL=$((ESTIMATED_TOKENS_TOTAL + ((bytes_read + 3) / 4)))

    local unread_latency_sec=0
    if [ "$FIRST_UNREAD_SEEN" -gt 0 ] 2>/dev/null; then
        unread_latency_sec=$((now - FIRST_UNREAD_SEEN))
    fi

    mkdir -p "$(dirname "$METRICS_FILE")" 2>/dev/null || true
    cat > "$METRICS_FILE" <<EOF
agent_id: "${AGENT_ID:-unknown}"
timestamp: "$(date -Iseconds)"
unread_latency_sec: $unread_latency_sec
read_count: $READ_COUNT
bytes_read: $READ_BYTES_TOTAL
estimated_tokens: $ESTIMATED_TOKENS_TOTAL
EOF
}

disable_normal_nudge() {
    [ "${ASW_DISABLE_NORMAL_NUDGE:-0}" = "1" ] || [ "${TRANSPORT_MODE:-yaml}" = "agmsg" ]
}

is_valid_cli_type() {
    case "${1:-}" in
        claude|codex|copilot|kimi|antigravity|opencode|kilo|localapi|cursor|grok) return 0 ;;
        *) return 1 ;;
    esac
}

escape_extended_regex() {
    printf '%s' "$1" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g'
}

mux_send_text() {
    local text="$1"
    timeout 5 tmux send-keys -t "$PANE_TARGET" "$text" 2>/dev/null
}

mux_send_text_literal() {
    local text="$1"
    timeout 5 tmux send-keys -l -t "$PANE_TARGET" "$text" 2>/dev/null
}

mux_send_enter() {
    timeout 5 tmux send-keys -t "$PANE_TARGET" Enter 2>/dev/null
}

mux_send_carriage_return() {
    timeout 5 tmux send-keys -t "$PANE_TARGET" C-m 2>/dev/null
}

mux_send_ctrl_c() {
    timeout 5 tmux send-keys -t "$PANE_TARGET" C-c 2>/dev/null
}

mux_send_escape_double() {
    timeout 5 tmux send-keys -t "$PANE_TARGET" Escape Escape 2>/dev/null
}

mux_capture_pane_tail() {
    timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -5
}

send_text_and_enter() {
    local text="$1"
    local action_label="${2:-send-keys}"
    local literal_mode="${3:-0}"

    if [ "$literal_mode" = "1" ]; then
        if ! mux_send_text_literal "$text"; then
            echo "[$(date)] WARNING: ${action_label} text failed or timed out for $AGENT_ID" >&2
            return 1
        fi
    elif ! mux_send_text "$text"; then
        echo "[$(date)] WARNING: ${action_label} text failed or timed out for $AGENT_ID" >&2
        return 1
    fi

    sleep 0.3
    if ! mux_send_enter; then
        echo "[$(date)] WARNING: ${action_label} Enter failed or timed out for $AGENT_ID" >&2
        return 1
    fi

    return 0
}

send_literal_text_and_enter() {
    local text="$1"
    local action_label="${2:-send-keys}"

    if ! mux_send_text_literal "$text"; then
        echo "[$(date)] WARNING: ${action_label} text failed or timed out for $AGENT_ID" >&2
        return 1
    fi

    sleep 0.3
    if ! mux_send_enter; then
        echo "[$(date)] WARNING: ${action_label} Enter failed or timed out for $AGENT_ID" >&2
        return 1
    fi

    return 0
}

tui_nudge_verify_enabled() {
    case "${1:-}" in
        claude|codex|antigravity|opencode|kilo|cursor) return 0 ;;
        *) return 1 ;;
    esac
}

verify_nudge_submitted() {
    local text="$1"
    local effective_cli="${2:-}"
    local action_label="${3:-nudge}"
    local prefix=""
    local pane_text=""
    local attempt

    tui_nudge_verify_enabled "$effective_cli" || return 0
    prefix="$(printf '%s' "$text" | cut -c1-16)"
    [ -n "$prefix" ] || return 0

    for attempt in 1 2; do
        sleep 1
        pane_text="$(mux_capture_pane_tail || true)"
        if ! printf '%s\n' "$pane_text" | grep -Fq -- "$prefix"; then
            return 0
        fi
        echo "[$(date)] [nudge-verify] ${action_label} still visible for $AGENT_ID after Enter; resending C-m (${attempt}/2)" >&2
        if ! mux_send_carriage_return; then
            echo "[$(date)] [nudge-verify] C-m resend failed for $AGENT_ID (${attempt}/2)" >&2
            return 0
        fi
    done

    pane_text="$(mux_capture_pane_tail || true)"
    if printf '%s\n' "$pane_text" | grep -Fq -- "$prefix"; then
        echo "[$(date)] [nudge-verify] ${action_label} remains visible for $AGENT_ID after max C-m retries" >&2
    fi
    return 0
}

gunkan_audit_nudge_rate_limited() {
    local nudge="${1:-}"
    local now

    [[ "${AGENT_ID:-}" == "gunkan" ]] || return 1
    [[ "$nudge" == *"queue/inbox/gunkan.yaml に未読の監査イベント"* ]] || return 1

    now=$(date +%s)
    if [ "${LAST_GUNKAN_AUDIT_NUDGE_TS:-0}" -gt 0 ] && [ $((now - LAST_GUNKAN_AUDIT_NUDGE_TS)) -lt "${GUNKAN_AUDIT_NUDGE_COOLDOWN:-180}" ]; then
        echo "[$(date)] [SKIP] Gunkan audit nudge cooldown active for $AGENT_ID" >&2
        return 0
    fi
    LAST_GUNKAN_AUDIT_NUDGE_TS=$now
    return 1
}

run_runtime_blocker_notice() {
    local action="${1:-record}"
    local issue="${2:-}"
    local detail="${3:-}"
    local project_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local notice_script="${MAS_RUNTIME_BLOCKER_NOTICE_SCRIPT:-${project_root}/shogunate_mod/runtime/blocker_notice.py}"
    local result=""

    if [ ! -f "$notice_script" ]; then
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[$(date)] [WARN] python3 not available; runtime blocker notice skipped for $AGENT_ID" >&2
        return 0
    fi

    result=$(python3 "$notice_script" --project-root "$project_root" --action "$action" --agent "$AGENT_ID" --issue "$issue" --detail "$detail" 2>/dev/null || true)
    if [ -n "$result" ]; then
        result=$(printf '%s' "$result" | tr -d '\r' | tail -n 1)
    fi

    case "$result" in
        updated)
            echo "[$(date)] [INFO] runtime blocker notice recorded for $AGENT_ID ($issue)" >&2
            return 0
            ;;
        duplicate)
            return 0
            ;;
        cleared)
            echo "[$(date)] [INFO] runtime blocker notice cleared for $AGENT_ID ($issue)" >&2
            return 0
            ;;
        not_found)
            return 0
            ;;
    esac

    echo "[$(date)] [WARN] runtime blocker notice ${action} failed for $AGENT_ID ($issue)" >&2
    return 0
}

record_runtime_blocker_notice() {
    run_runtime_blocker_notice "record" "${1:-}" "${2:-}"
}

clear_runtime_blocker_notice() {
    run_runtime_blocker_notice "clear" "${1:-}" "${2:-}"
    return 0
}

runtime_blocked_relay_marker_path() {
    local issue="${1:-}"
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime/runtime_blocked_relay"
    printf '%s/%s__%s.sent' "$runtime_dir" "${AGENT_ID:-agent}" "$issue"
}

runtime_blocked_human_marker_path() {
    local issue="${1:-}"
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime/runtime_blocked_human_relay"
    printf '%s/%s__%s.sent' "$runtime_dir" "${AGENT_ID:-agent}" "$issue"
}

notify_shogun_runtime_blocked_if_needed() {
    local issue="${1:-}"
    local detail="${2:-}"
    local project_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local relay_dir="${project_root}/queue/runtime/runtime_blocked_relay"
    local marker_path
    local inbox_write_script="${project_root}/shogunate_mod/inbox/write.sh"
    local message=""

    [ -n "$issue" ] || return 0
    [ "${AGENT_ID:-}" = "shogun" ] && return 0
    if [ "${__INBOX_WATCHER_TESTING__:-0}" = "1" ] && [ "${ASW_ENABLE_RUNTIME_BLOCKED_RELAY_TEST:-0}" != "1" ]; then
        return 0
    fi
    marker_path="$(runtime_blocked_relay_marker_path "$issue")"
    [ -f "$marker_path" ] && return 0
    [ -f "$inbox_write_script" ] || return 0

    mkdir -p "$relay_dir"

    case "$issue" in
        codex-hard-usage-limit)
            message="queue/inbox/${AGENT_ID}.yaml の担当 agent が Codex hard usage-limit で停止中。dashboard.md の runtime-blocked/${AGENT_ID} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
        codex-auth-required)
            message="queue/inbox/${AGENT_ID}.yaml の担当 agent が Codex auth 待ちで停止中。dashboard.md の runtime-blocked/${AGENT_ID} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
        *)
            message="queue/inbox/${AGENT_ID}.yaml の担当 agent が runtime blocker (${issue}) で停止中。dashboard.md の runtime-blocked/${AGENT_ID} を確認し、殿へ blocked 状態を報告せよ。"
            ;;
    esac

    if bash "$inbox_write_script" shogun "$message" runtime_blocked "inbox_watcher" >/dev/null 2>&1; then
        : > "$marker_path"
        echo "[$(date)] [INFO] runtime blocker relay queued for shogun (${AGENT_ID}, ${issue})" >&2
        return 0
    fi

    echo "[$(date)] [WARN] failed to relay runtime blocker to shogun (${AGENT_ID}, ${issue})" >&2
    return 0
}

notify_lord_runtime_blocked_if_needed() {
    local issue="${1:-}"
    local project_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local relay_dir="${project_root}/queue/runtime/runtime_blocked_human_relay"
    local marker_path
    local inbox_write_script="${project_root}/shogunate_mod/inbox/write.sh"
    local message=""

    [ -n "$issue" ] || return 0
    [ "${AGENT_ID:-}" = "shogun" ] || return 0
    if [ "${__INBOX_WATCHER_TESTING__:-0}" = "1" ] && [ "${ASW_ENABLE_RUNTIME_BLOCKED_HUMAN_RELAY_TEST:-0}" != "1" ]; then
        return 0
    fi
    marker_path="$(runtime_blocked_human_marker_path "$issue")"
    [ -f "$marker_path" ] && return 0
    [ -f "$inbox_write_script" ] || return 0

    mkdir -p "$relay_dir"

    case "$issue" in
        codex-hard-usage-limit)
            message="queue/inbox/shogun.yaml の担当 agent が Codex hard usage-limit で停止中。dashboard.md の runtime-blocked/* を確認し、人手で再開判断を行え。"
            ;;
        codex-auth-required)
            message="queue/inbox/shogun.yaml の担当 agent が Codex auth 待ちで停止中。dashboard.md の runtime-blocked/* を確認し、人手でログインを完了せよ。"
            ;;
        *)
            message="queue/inbox/shogun.yaml の担当 agent が runtime blocker (${issue}) で停止中。dashboard.md の runtime-blocked/* を確認し、人手で再開判断を行え。"
            ;;
    esac

    if bash "$inbox_write_script" lord "$message" runtime_blocked "inbox_watcher" >/dev/null 2>&1; then
        : > "$marker_path"
        echo "[$(date)] [INFO] runtime blocker relay queued for lord (${AGENT_ID}, ${issue})" >&2
        return 0
    fi

    echo "[$(date)] [WARN] failed to relay runtime blocker to lord (${AGENT_ID}, ${issue})" >&2
    return 0
}

clear_shogun_runtime_blocked_relay() {
    local issue="${1:-}"
    local marker_path=""

    [ -n "$issue" ] || return 0
    [ "${AGENT_ID:-}" = "shogun" ] && return 0
    marker_path="$(runtime_blocked_relay_marker_path "$issue")"
    rm -f "$marker_path"
    return 0
}

clear_lord_runtime_blocked_relay() {
    local issue="${1:-}"
    local marker_path=""

    [ -n "$issue" ] || return 0
    [ "${AGENT_ID:-}" = "shogun" ] || return 0
    marker_path="$(runtime_blocked_human_marker_path "$issue")"
    rm -f "$marker_path"
    return 0
}

record_runtime_blocker() {
    local issue="${1:-}"
    local detail="${2:-}"
    record_runtime_blocker_notice "$issue" "$detail"
    notify_shogun_runtime_blocked_if_needed "$issue" "$detail"
    notify_lord_runtime_blocked_if_needed "$issue"
    return 0
}

clear_runtime_blocker() {
    local issue="${1:-}"
    local detail="${2:-}"
    clear_runtime_blocker_notice "$issue" "$detail"
    clear_shogun_runtime_blocked_relay "$issue"
    clear_lord_runtime_blocked_relay "$issue"
    return 0
}

codex_prompt_compact_text() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

codex_usage_limit_prompt_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"youvehityourusagelimit"* || "$compact_text" == *"tryagainat"* ]]
}

codex_usage_limit_switchable() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"gpt51codexmini"* || "$compact_text" == *"switchto"*mini* || "$compact_text" == *"1switch"* ]]
}

codex_switch_confirm_prompt_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"pressentertoconfirm"* || "$compact_text" == *"esctogoback"* ]] || return 1
    [[ "$compact_text" == *"switchto"* || "$compact_text" == *"optimizedforcodex"* ]] || return 1
    [[ "$compact_text" == *"gpt51"* || "$compact_text" == *"mini"* || "$compact_text" == *"optimizedforcodex"* ]]
}

codex_rate_limit_prompt_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"approachingratelimits"* || "$compact_text" == *"keepcurrentmodel"* || "$compact_text" == *"hidefutureratelimit"* ]]
}

codex_hooks_no_hooks_screen_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"nohooksinstalledforthisevent"* ]]
}

codex_hooks_overview_screen_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"lifecyclehooksfromconfigandenabledplugins"* || "$compact_text" == *"pressentertoviewhooks"* ]]
}

codex_hooks_trust_all_shortcut_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"pressttotrustall"* ]]
}

codex_hooks_review_prompt_detected() {
    local compact_text
    compact_text="$(codex_prompt_compact_text "${1:-}")"
    [[ "$compact_text" == *"hooksneedreview"* || "$compact_text" == *"trustallandcontinue"* ]]
}

accept_codex_hooks_prompt_if_present() {
    local effective_cli="${1:-}"
    local pane_text

    if [[ -z "$effective_cli" ]]; then
        effective_cli=$(get_effective_cli_type)
    fi
    [[ "$effective_cli" == "codex" ]] || return 1

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -80 || true)
    if codex_hooks_no_hooks_screen_detected "$pane_text" || codex_hooks_overview_screen_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Closing Codex hooks detail screen for $AGENT_ID" >&2
        timeout 5 tmux send-keys -t "$PANE_TARGET" Escape 2>/dev/null || return 2
        sleep 0.3
        return 0
    fi
    if codex_hooks_trust_all_shortcut_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Trusting all Codex hooks for $AGENT_ID" >&2
        timeout 5 tmux send-keys -t "$PANE_TARGET" t 2>/dev/null || return 2
        sleep 0.3
        return 0
    fi
    if codex_hooks_review_prompt_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Accepting Codex hooks review prompt for $AGENT_ID" >&2
        if ! send_text_and_enter "2" "Codex hooks review prompt"; then
            return 2
        fi
        sleep 0.3
        return 0
    fi

    return 1
}

note_hard_usage_limit_prompt() {
    local now
    now=$(date +%s)

    if [ "${LAST_HARD_USAGE_LIMIT_LOG_TS:-0}" -gt 0 ] && [ $((now - LAST_HARD_USAGE_LIMIT_LOG_TS)) -lt "${HARD_USAGE_LIMIT_LOG_COOLDOWN:-600}" ]; then
        return 0
    fi

    LAST_HARD_USAGE_LIMIT_LOG_TS=$now
    echo "[$(date)] [SKIP] Hard Codex usage-limit prompt detected for $AGENT_ID; no mini switch option present" >&2
    return 0
}

dismiss_codex_rate_limit_prompt_if_present() {
    local effective_cli="${1:-}"
    local pane_text

    if [[ -z "$effective_cli" ]]; then
        effective_cli=$(get_effective_cli_type)
    fi
    [[ "$effective_cli" == "codex" ]] || return 1

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -40 || true)
    if codex_usage_limit_prompt_detected "$pane_text"; then
        if ! codex_usage_limit_switchable "$pane_text"; then
            record_runtime_blocker "codex-hard-usage-limit" "$pane_text"
            note_hard_usage_limit_prompt
            return 3
        fi
        LAST_HARD_USAGE_LIMIT_LOG_TS=0
        clear_runtime_blocker "codex-hard-usage-limit" "$pane_text"
        echo "[$(date)] [SEND-KEYS] Switching Codex to mini after usage-limit prompt for $AGENT_ID" >&2
        if ! send_text_and_enter "1" "Codex usage-limit prompt"; then
            return 2
        fi
        sleep 0.3
        return 0
    fi
    LAST_HARD_USAGE_LIMIT_LOG_TS=0
    clear_runtime_blocker "codex-hard-usage-limit" "$pane_text"
    if codex_switch_confirm_prompt_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Confirming Codex switch prompt for $AGENT_ID" >&2
        if ! mux_send_enter; then
            echo "[$(date)] WARNING: Codex switch-confirm Enter failed or timed out for $AGENT_ID" >&2
            return 2
        fi
        sleep 0.3
        return 0
    fi
    if codex_rate_limit_prompt_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Dismissing Codex rate-limit prompt for $AGENT_ID" >&2
        if ! send_text_and_enter "3" "Codex rate-limit prompt"; then
            return 2
        fi
        sleep 0.3
        return 0
    fi

    return 1
}

maintain_codex_runtime_prompt() {
    local effective_cli="${1:-}"
    local prompt_rc=0

    if [[ -z "$effective_cli" ]]; then
        effective_cli=$(get_effective_cli_type)
    fi

    skip_antigravity_feedback_prompt_if_present "$effective_cli" || true
    if [[ "$effective_cli" == "antigravity" ]]; then
        return 0
    fi

    if [[ "$effective_cli" == "codex" ]]; then
        submit_codex_pending_paste_if_needed "Codex pasted content runtime prompt" || true
    fi

    accept_codex_hooks_prompt_if_present "$effective_cli" || prompt_rc=$?
    case "$prompt_rc" in
        0)
            return 0
            ;;
        2)
            echo "[$(date)] [WARN] failed to accept Codex hooks prompt for $AGENT_ID" >&2
            return 0
            ;;
        *)
            prompt_rc=0
            ;;
    esac

    dismiss_codex_rate_limit_prompt_if_present "$effective_cli" || prompt_rc=$?
    case "$prompt_rc" in
        0|1|3)
            return 0
            ;;
        2)
            echo "[$(date)] [WARN] failed to dismiss Codex runtime prompt for $AGENT_ID" >&2
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}

codex_auth_prompt_detected() {
    local pane_text="${1:-}"
    printf '%s' "$pane_text" | grep -qiE "Finish signing in via your browser|open the following link to authenticate|Sign in with ChatGPT|Sign in with Device Code|Provide your own API key|auth\\.openai\\.com/oauth/authorize|Press Enter to continue|Login server error: Login cancelled|account/login/start failed|failed to start login server"
}

codex_process_running() {
    local current_command=""
    local running_flag=""
    running_flag=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @agent_cli_running 2>/dev/null || true)
    [ "$running_flag" = "1" ] && return 0
    current_command=$(timeout 2 tmux display-message -p -t "$PANE_TARGET" "#{pane_current_command}" 2>/dev/null || true)
    [ "$current_command" = "node" ]
}

rearm_bootstrap_pending_for_restart() {
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    local bootstrap_file="$runtime_dir/bootstrap_${AGENT_ID}.md"
    local pending_file="$runtime_dir/bootstrap_${AGENT_ID}.pending"
    local delivered_file="$runtime_dir/bootstrap_${AGENT_ID}.delivered"

    [ -f "$bootstrap_file" ] || return 0
    : > "$pending_file"
    rm -f "$delivered_file"
}

initial_bootstrap_still_pending() {
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    local bootstrap_file="$runtime_dir/bootstrap_${AGENT_ID}.md"
    local pending_file="$runtime_dir/bootstrap_${AGENT_ID}.pending"
    local delivered_file="$runtime_dir/bootstrap_${AGENT_ID}.delivered"

    [ -f "$bootstrap_file" ] || return 1
    [ -f "$pending_file" ] || return 1
    [ ! -f "$delivered_file" ]
}

bootstrap_acknowledged_in_pane() {
    local pane_text="${1:-}"
    local ack_token=""
    ack_token="ready:${AGENT_ID}"
    [[ -n "$pane_text" && -n "$ack_token" ]] || return 1
    printf '%s\n' "$pane_text" | grep -Eq "^[[:space:]]*([•●][[:space:]]*)?${ack_token}[[:space:]]*$"
}

mark_bootstrap_delivered_from_ack() {
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    local pending_file="$runtime_dir/bootstrap_${AGENT_ID}.pending"
    local delivered_file="$runtime_dir/bootstrap_${AGENT_ID}.delivered"

    [ -f "$pending_file" ] || return 1
    rm -f "$pending_file"
    : > "$delivered_file"
    echo "[$(date)] [INFO] bootstrap acknowledged in pane for $AGENT_ID" >&2
    return 0
}

runtime_startup_recovery_grace_active() {
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    local start_file="$runtime_dir/runtime_start_epoch"
    local start_ts=""
    local now=""

    [ -f "$start_file" ] || return 1
    start_ts=$(awk 'NR==1{print $1}' "$start_file" 2>/dev/null || true)
    [[ "$start_ts" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    [ $((now - start_ts)) -lt "$RUNTIME_STARTUP_RECOVERY_GRACE_SECONDS" ]
}

cli_launch_grace_active() {
    local launch_ts=""
    local now=""

    launch_ts=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @cli_launch_epoch 2>/dev/null || true)
    [[ "$launch_ts" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    [ $((now - launch_ts)) -lt "$CLI_STARTUP_GRACE_SECONDS" ]
}

restart_command_for_cli() {
    local effective_cli="${1:-}"
    local restart_cmd=""

    if declare -F build_cli_command_with_type >/dev/null 2>&1; then
        restart_cmd=$(build_cli_command_with_type "$AGENT_ID" "$effective_cli" 2>/dev/null || true)
    fi
    if [ -n "$restart_cmd" ]; then
        printf '%s\n' "$restart_cmd"
        return 0
    fi

    case "$effective_cli" in
        antigravity) printf '%s\n' "${ANTIGRAVITY_RESTART_CMD:-agy --dangerously-skip-permissions}" ;;
        opencode) printf '%s\n' "${OPENCODE_RESTART_CMD:-opencode}" ;;
        kilo) printf '%s\n' "${KILO_RESTART_CMD:-kilo}" ;;
        localapi) printf '%s\n' "${LOCALAPI_RESTART_CMD:-python3 shogunate_mod/localapi/repl.py}" ;;
        copilot) printf '%s\n' "${COPILOT_RESTART_CMD:-copilot --yolo}" ;;
        cursor) printf '%s\n' "${CURSOR_RESTART_CMD:-cursor-agent --yolo}" ;;
        codex) printf '%s\n' "${CODEX_RESTART_CMD:-codex --search --sandbox danger-full-access --ask-for-approval never}" ;;
        *) return 1 ;;
    esac
}

recover_shell_returned_cli_if_needed() {
    local effective_cli="${1:-}"
    local current_command=""
    local pane_text=""
    local restart_cmd=""
    local now=0

    if [[ -z "$effective_cli" ]]; then
        effective_cli=$(get_effective_cli_type)
    fi
    case "$effective_cli" in
        codex|antigravity|opencode|kilo|localapi|copilot|cursor) ;;
        *) return 0 ;;
    esac

    current_command=$(timeout 2 tmux display-message -p -t "$PANE_TARGET" "#{pane_current_command}" 2>/dev/null || true)
    if [ "$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @agent_cli_running 2>/dev/null || true)" = "1" ]; then
        LAST_CLI_RESTART_TS=0
        return 0
    fi
    case "$effective_cli:$current_command" in
        codex:node|antigravity:agy|antigravity:antigravity|opencode:opencode|kilo:kilo|localapi:python3|copilot:copilot|cursor:cursor-agent|cursor:agent)
            LAST_CLI_RESTART_TS=0
            return 0
            ;;
    esac

    case "$current_command" in
        bash|sh|zsh|fish) ;;
        *) return 0 ;;
    esac

    if runtime_startup_recovery_grace_active; then
        return 0
    fi

    if initial_bootstrap_still_pending; then
        return 0
    fi

    if cli_launch_grace_active; then
        return 0
    fi

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -120 || true)
    if codex_auth_prompt_detected "$pane_text"; then
        return 0
    fi

    now=$(date +%s)
    if [ "${LAST_CLI_RESTART_TS:-0}" -gt 0 ] && [ $((now - LAST_CLI_RESTART_TS)) -lt "$CLI_RESTART_COOLDOWN" ]; then
        return 0
    fi

    # Failover-enabled panes report the generation-scoped exit to the
    # controller. The old direct send-keys restart would bypass its one-restart
    # limit and can start Primary and Fallback at the same time.
    if [ -f "$SCRIPT_DIR/queue/runtime/role_failover.yaml" ] && [ -f "$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh" ]; then
        local generation=""
        local reported=""
        generation=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @role_generation 2>/dev/null | tr -d '\r' | head -n1)
        reported=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @role_exit_reported_generation 2>/dev/null | tr -d '\r' | head -n1)
        if [[ "$generation" =~ ^[1-9][0-9]*$ ]] && [ "$reported" != "$generation" ]; then
            SHOGUNATE_RUNTIME_DIR="$SCRIPT_DIR" bash "$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh" \
                process_exit "$AGENT_ID" "$generation" shell_return "$PANE_TARGET" || true
        fi
        return 0
    fi

    restart_cmd=$(restart_command_for_cli "$effective_cli" 2>/dev/null || true)
    [ -n "$restart_cmd" ] || return 0

    rearm_bootstrap_pending_for_restart
    mux_send_ctrl_c || true
    sleep 0.2
    if send_text_and_enter "$restart_cmd" "${effective_cli} CLI restart" "1"; then
        timeout 2 tmux set-option -p -t "$PANE_TARGET" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
        LAST_CLI_RESTART_TS=$now
        echo "[$(date)] [INFO] restarted shell-returned ${effective_cli} pane for $AGENT_ID" >&2
        return 0
    fi

    echo "[$(date)] [WARN] failed to restart shell-returned ${effective_cli} pane for $AGENT_ID" >&2
    return 0
}

recover_shell_returned_codex_if_needed() {
    recover_shell_returned_cli_if_needed "$@"
}

# ─── Grok Build failure guard (GB-003B, attempt 3) ───
# 設計方針（attempt 1/2 の禁止事項を除く）:
#   * TUI の stdout/stderr を file へ redirect しない。capture-pane の結果
#     は一時変数に入れ、固定 reason だけを取り出した後すぐ捨てる。
#   * raw pane text を state / log / marker file へ書かない。marker に書く
#     のは issue 名と generation 番号を含めた空 file だけで、pane text を
#     含まない。
#   * 通常 process exit は既存 `launch.sh` の process_exit 経路を変えない。
#     ここでは explicit_failure event だけを1回だけ発行する。
#   * generation を取得・検証してから marker path を作る。marker 名へ
#     generation を含め、同一 generation+reason は1回、次 generation は
#     再度1回発火できる。runtime_blocked_relay_marker_path の dir を再利用
#     し、filename を `${AGENT_ID}__grok-${reason}-generation${N}.sent` と
#     する（notify_shogun_runtime_* 用の既存 issue 名 marker とは別物）。
#   * helper (`grok_classify_failure_text`) は pane 中の単独の既知 error 行
#     だけを分類し、narrative 内の語句は分類しない。
maintain_grok_runtime_failure_guard() {
    local effective_cli="${1:-}"
    local pane_text=""
    local reason=""
    local generation=""
    local marker_dir=""
    local marker_path=""

    if [[ -z "$effective_cli" ]]; then
        effective_cli=$(get_effective_cli_type)
    fi
    [[ "$effective_cli" == "grok" ]] || return 0

    # role_failover_runner は managed role + 世代番号を要求する（runner 側の
    # valid_role / generation check と同期）。managed pane でなければ何もしない。
    [[ "${AGENT_ID:-}" =~ ^(shogun|gunkan|gunshi|karo([1-9][0-9]*)?|ashigaru[1-9][0-9]*)$ ]] || return 0
    [[ -f "$SCRIPT_DIR/queue/runtime/role_failover.yaml" ]] || return 0
    [[ -f "$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh" ]] || return 0

    # 短い pane snapshot を capture し純粋 helper へ渡す。raw text は変数の
    # scope 内で使い捨て、永続 file へ書かない。
    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -80 || true)
    reason=$(grok_classify_failure_text "$pane_text")
    [[ -n "$reason" ]] || return 0

    # generation を先に取得・検証してから marker path を作る。generation が
    # 無ければ何もしない（runner 側の check と同期）。
    generation=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @role_generation 2>/dev/null | tr -d '\r' | head -n1)
    [[ "$generation" =~ ^[1-9][0-9]*$ ]] || return 0

    # marker 名に generation を含める。同一 generation+reason は1回だけ、
    # 次 generation は再度1回発火できる。marker 内容は空 file で pane text
    # を絶対に書かない。dir は既存 relay marker helper と同じ場所を使う。
    marker_dir="$(dirname "$(runtime_blocked_relay_marker_path "grok-${reason}")")"
    marker_path="${marker_dir}/${AGENT_ID}__grok-${reason}-generation${generation}.sent"
    [ -f "$marker_path" ] && return 0

    mkdir -p "$marker_dir" 2>/dev/null || true
    if SHOGUNATE_RUNTIME_DIR="$SCRIPT_DIR" bash "$SCRIPT_DIR/shogunate_mod/runtime/role_failover_runner.sh" \
        explicit_failure "$AGENT_ID" "$generation" "$reason" "$PANE_TARGET" >/dev/null 2>&1; then
        : > "$marker_path"
        echo "[$(date)] [INFO] grok ${reason} classified for $AGENT_ID (generation ${generation}); role_failover_runner invoked once" >&2
    fi
    return 0
}

BUSY_SINCE_TS=${BUSY_SINCE_TS:-0}
LAST_LONG_BUSY_NOTICE_TS=${LAST_LONG_BUSY_NOTICE_TS:-0}
LONG_BUSY_NOTICE_THRESHOLD=${LONG_BUSY_NOTICE_THRESHOLD:-600}
LONG_BUSY_NOTICE_COOLDOWN=${LONG_BUSY_NOTICE_COOLDOWN:-300}

record_agent_busy_observation() {
    local effective_cli="${1:-unknown}"
    local now elapsed runtime_dir notice_file

    now=$(date +%s)
    if [ "${BUSY_SINCE_TS:-0}" -le 0 ] 2>/dev/null; then
        BUSY_SINCE_TS=$now
    fi
    elapsed=$((now - BUSY_SINCE_TS))
    [[ "$LONG_BUSY_NOTICE_THRESHOLD" =~ ^[0-9]+$ ]] || LONG_BUSY_NOTICE_THRESHOLD=600
    [[ "$LONG_BUSY_NOTICE_COOLDOWN" =~ ^[0-9]+$ ]] || LONG_BUSY_NOTICE_COOLDOWN=300
    [ "$elapsed" -ge "$LONG_BUSY_NOTICE_THRESHOLD" ] || return 0
    if [ "${LAST_LONG_BUSY_NOTICE_TS:-0}" -gt 0 ] && [ $((now - LAST_LONG_BUSY_NOTICE_TS)) -lt "$LONG_BUSY_NOTICE_COOLDOWN" ]; then
        return 0
    fi

    runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    notice_file="$runtime_dir/long_busy_agents.tsv"
    mkdir -p "$runtime_dir" 2>/dev/null || true
    printf '%s\tagent=%s\tcli=%s\tbusy_seconds=%s\tpane=%s\n' \
        "$(date -Iseconds)" \
        "${AGENT_ID:-unknown}" \
        "$effective_cli" \
        "$elapsed" \
        "${PANE_TARGET:-unknown}" >> "$notice_file"
    LAST_LONG_BUSY_NOTICE_TS=$now
    echo "[$(date)] [INFO] Agent $AGENT_ID has been busy for ${elapsed}s; recorded $notice_file" >&2
    return 0
}

clear_agent_busy_observation() {
    BUSY_SINCE_TS=0
    LAST_LONG_BUSY_NOTICE_TS=0
    return 0
}

bootstrap_ready_pattern() {
    case "${1:-}" in
        claude) printf '%s\n' '(claude code|Claude Code|╰|/model|for shortcuts)' ;;
        codex) printf '%s\n' '(openai codex|context left|/model to change|Use /skills|Tip:|Working|esc to interrupt|% left)' ;;
        antigravity) printf '%s\n' '(agy|antigravity|Antigravity|type your message|Working|esc to interrupt|Initializing the Agent)' ;;
        copilot) printf '%s\n' '(copilot|GitHub Copilot|/model)' ;;
        kimi) printf '%s\n' '(kimi|moonshot|/model)' ;;
        localapi) printf '%s\n' '(localapi|LocalAPI|ready:|\\$)' ;;
        opencode) printf '%s\n' '(opencode|OpenCode|Ask anything|ctrl\+p commands|/model|ready:)' ;;
        kilo) printf '%s\n' '(kilo|Kilo|/model|ready:)' ;;
        cursor) printf '%s\n' '(cursor|Cursor|cursor-agent|/model|ready:|ctrl\\+c to stop)' ;;
        *) printf '%s\n' '(claude|codex|antigravity|agy|copilot|kimi|localapi|opencode|kilo|cursor|ready:)' ;;
    esac
}

opencode_update_prompt_detected() {
    local pane_text="${1:-}"

    printf '%s' "$pane_text" | grep -qiE 'Update Available|A new release .* is available|Would you like to update now\?|Skip[[:space:]]+Confirm'
}

skip_opencode_update_prompt_if_present() {
    local effective_cli="${1:-$(get_effective_cli_type)}"
    local pane_text=""

    [ "$effective_cli" = "opencode" ] || return 0

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -100 || true)
    if opencode_update_prompt_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Skipping OpenCode update prompt for $AGENT_ID" >&2
        mux_send_enter || return 1
        return 0
    fi
    return 0
}

antigravity_feedback_prompt_detected() {
    local pane_text="${1:-}"

    printf '%s' "$pane_text" | grep -qiE "How'?s the CLI experience so far|Help us|\\[0\\][[:space:]]*Skip|0[.)[:space:]]+Skip"
}

skip_antigravity_feedback_prompt_if_present() {
    local effective_cli="${1:-$(get_effective_cli_type)}"
    local pane_text=""

    [ "$effective_cli" = "antigravity" ] || return 0

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -100 || true)
    if antigravity_feedback_prompt_detected "$pane_text"; then
        echo "[$(date)] [SEND-KEYS] Skipping Antigravity feedback prompt for $AGENT_ID" >&2
        send_text_and_enter "0" "Antigravity feedback prompt" || return 1
        return 0
    fi
    return 0
}

codex_ready_prompt_detected() {
    local pane_text="${1:-}"

    printf '%s' "$pane_text" | grep -qiE '(openai codex|/model to change|Use /skills|Tip:|Working|esc to interrupt|% left|context left)'
}

codex_pasted_content_pending() {
    local pane_text="${1:-}"

    printf '%s' "$pane_text" | grep -qi 'pasted content'
}

submit_codex_pending_paste_if_needed() {
    local action_label="${1:-Codex pasted content confirm}"
    local pane_text=""

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -40 || true)
    codex_pasted_content_pending "$pane_text" || return 0

    echo "[$(date)] [INFO] Confirming Codex pasted content for $AGENT_ID" >&2
    if ! mux_send_enter; then
        echo "[$(date)] WARNING: ${action_label} Enter failed or timed out for $AGENT_ID" >&2
        return 1
    fi

    sleep 0.3
    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -40 || true)
    if codex_pasted_content_pending "$pane_text"; then
        echo "[$(date)] WARNING: ${action_label} pasted content still pending for $AGENT_ID" >&2
        return 1
    fi

    return 0
}

codex_bootstrap_input_visible() {
    local pane_text="${1:-}"

    printf '%s' "$pane_text" | grep -qiE "【初動命令】あなたは${AGENT_ID}|【初動命令】|イベント駆動規則|連携順序:|準備が整ったら未読inbox監視へ戻れ"
}

bootstrap_delivery_prompt() {
    local bootstrap_file="$1"

    printf "【初動命令】あなたは%s。詳細正本は %s に保存済み。起動直後は読まず、実タスク/未読inbox/直接指示を受けた時だけ必要最小範囲を読め。今は追加探索せず ready:%s を1行だけ送信し、イベント駆動で待機せよ。" \
        "$AGENT_ID" "$bootstrap_file" "$AGENT_ID"
}

codex_bootstrap_delivery_prompt() {
    bootstrap_delivery_prompt "$@"
}

codex_bootstrap_activity_visible() {
    local pane_text="${1:-}"
    local filtered_text=""

    bootstrap_acknowledged_in_pane "$pane_text" && return 0
    filtered_text="$(printf '%s\n' "$pane_text" | grep -v '【初動命令】' || true)"
    printf '%s' "$filtered_text" | grep -qiE '(Working|esc to interrupt|^• |^[[:space:]]*└ |Ran |Explored|Read )'
}

confirm_codex_bootstrap_submitted() {
    local action_label="${1:-Codex bootstrap submit confirm}"
    local pane_text=""
    local attempt

    if ! submit_codex_pending_paste_if_needed "$action_label"; then
        return 1
    fi

    for attempt in 1 2 3; do
        sleep 1
        pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -60 || true)
        if codex_bootstrap_activity_visible "$pane_text"; then
            return 0
        fi
        if codex_bootstrap_input_visible "$pane_text"; then
            echo "[$(date)] [INFO] ${action_label}: bootstrap still visible in composer for $AGENT_ID; sending Enter ($attempt)" >&2
        else
            echo "[$(date)] [INFO] ${action_label}: Codex bootstrap not active yet for $AGENT_ID; sending Enter ($attempt)" >&2
        fi
        mux_send_enter || return 1
    done

    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -60 || true)
    if codex_bootstrap_activity_visible "$pane_text"; then
        return 0
    fi
    if codex_bootstrap_input_visible "$pane_text"; then
        echo "[$(date)] WARNING: ${action_label} bootstrap still appears unsubmitted for $AGENT_ID" >&2
        return 1
    fi

    echo "[$(date)] WARNING: ${action_label} Codex bootstrap did not show activity for $AGENT_ID" >&2
    return 1
}

deliver_pending_bootstrap_if_ready() {
    local runtime_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/runtime"
    local bootstrap_file="$runtime_dir/bootstrap_${AGENT_ID}.md"
    local pending_file="$runtime_dir/bootstrap_${AGENT_ID}.pending"
    local delivered_file="$runtime_dir/bootstrap_${AGENT_ID}.delivered"
    local effective_cli=""
    local pane_text=""
    local ready_pattern=""
    local msg=""

    [ -f "$bootstrap_file" ] || return 0
    [ -f "$pending_file" ] || return 0

    effective_cli=$(get_effective_cli_type)
    recover_shell_returned_codex_if_needed "$effective_cli"
    if cli_launch_grace_active; then
        return 0
    fi
    pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -120 || true)

    if bootstrap_acknowledged_in_pane "$pane_text"; then
        mark_bootstrap_delivered_from_ack || true
        clear_runtime_blocker "codex-auth-required" "$pane_text"
        return 0
    fi

    if [[ "$effective_cli" == "codex" ]] && codex_auth_prompt_detected "$pane_text"; then
        record_runtime_blocker "codex-auth-required" "$pane_text"
        return 0
    fi
    if [[ "$effective_cli" == "codex" ]]; then
        accept_codex_hooks_prompt_if_present "$effective_cli" || true
        pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -120 || true)
    fi
    if [[ "$effective_cli" == "opencode" ]]; then
        skip_opencode_update_prompt_if_present "$effective_cli" || true
        pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -120 || true)
    fi
    if [[ "$effective_cli" == "antigravity" ]]; then
        skip_antigravity_feedback_prompt_if_present "$effective_cli" || true
        pane_text=$(timeout 2 tmux capture-pane -t "$PANE_TARGET" -p 2>/dev/null | tail -120 || true)
    fi
    if [[ "$effective_cli" == "codex" ]] && ! codex_process_running; then
        return 0
    fi
    clear_runtime_blocker "codex-auth-required" "$pane_text"
    if agent_is_busy; then
        return 0
    fi

    if [[ "$effective_cli" == "codex" ]]; then
        codex_ready_prompt_detected "$pane_text" || return 0
    else
        ready_pattern=$(bootstrap_ready_pattern "$effective_cli")
        if ! printf '%s' "$pane_text" | grep -qiE "$ready_pattern"; then
            return 0
        fi
    fi

    msg=$(bootstrap_delivery_prompt "$bootstrap_file")
    [ -n "$msg" ] || return 0

    if ! send_literal_text_and_enter "$msg" "bootstrap retry"; then
        return 1
    fi
    if [[ "$effective_cli" == "codex" ]] && ! confirm_codex_bootstrap_submitted "bootstrap retry"; then
        return 1
    fi

    rm -f "$pending_file"
    : > "$delivered_file"
    clear_runtime_blocker "codex-auth-required" "$pane_text"
    echo "[$(date)] [INFO] bootstrap retried and delivered for $AGENT_ID" >&2
    return 0
}

get_effective_cli_type() {
    local pane_cli_raw=""
    local pane_cli=""

    if [ "${MAS_WATCHER_TRUST_CLI_ARG:-0}" = "1" ] && is_valid_cli_type "${CLI_TYPE:-}"; then
        echo "${CLI_TYPE}"
        return 0
    fi

    pane_cli_raw=$(timeout 2 tmux show-options -p -t "$PANE_TARGET" -v @agent_cli 2>/dev/null || true)
    pane_cli=$(echo "$pane_cli_raw" | tr -d '\r' | head -n1 | tr -d '[:space:]')

    if is_valid_cli_type "$pane_cli"; then
        if is_valid_cli_type "${CLI_TYPE:-}" && [ "$pane_cli" != "${CLI_TYPE}" ]; then
            echo "[$(date)] [WARN] CLI drift detected for $AGENT_ID: arg=${CLI_TYPE}, pane=${pane_cli}. Using pane value." >&2
        fi
        echo "$pane_cli"
        return 0
    fi

    if is_valid_cli_type "${CLI_TYPE:-}"; then
        if [ -n "$pane_cli" ]; then
            echo "[$(date)] [WARN] Invalid pane @agent_cli for $AGENT_ID: '${pane_cli}'. Falling back to arg=${CLI_TYPE}." >&2
        fi
        echo "${CLI_TYPE}"
        return 0
    fi

    # Fail-closed: when CLI is unknown, take codex-safe path (no C-c, /clear->/new)
    echo "[$(date)] [WARN] CLI unresolved for $AGENT_ID (pane='${pane_cli:-<empty>}', arg='${CLI_TYPE:-<empty>}'). Fallback=codex-safe." >&2
    echo "codex"
}

normalize_special_command() {
    local msg_type="${1:-}"
    local raw_content="${2:-}"

    case "$msg_type" in
        clear_command)
            echo "/clear"
            ;;
        model_switch)
            if [[ "$raw_content" =~ ^/model[[:space:]]+[^[:space:]].* ]]; then
                echo "$raw_content"
            else
                echo "[$(date)] [SKIP] Invalid model_switch payload for $AGENT_ID: ${raw_content:-<empty>}" >&2
            fi
            ;;
    esac
}

enqueue_recovery_task_assigned() {
    local recovery_hint="${1:-}"
    mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true

    (
        acquire_inbox_lock || exit 1
        INBOX_PATH="$INBOX" AGENT_ID="$AGENT_ID" RECOVERY_HINT="$recovery_hint" python3 - << 'PY'
import datetime
import os
import uuid
import yaml

inbox = os.environ.get("INBOX_PATH", "")
agent_id = os.environ.get("AGENT_ID", "agent")
hint = (os.environ.get("RECOVERY_HINT", "") or "").strip()

try:
    with open(inbox, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    messages = data.get("messages", []) or []

    # Dedup guard: keep only one pending auto-recovery hint at a time.
    for m in reversed(messages):
        if (
            m.get("from") == "inbox_watcher"
            and m.get("type") == "task_assigned"
            and m.get("read", False) is False
            and "[auto-recovery]" in (m.get("content") or "")
        ):
            print("SKIP_DUPLICATE")
            raise SystemExit(0)

    now = datetime.datetime.now(datetime.timezone.utc).astimezone()
    if hint:
        content = f"[auto-recovery] {hint}"
    else:
        content = (
            f"[auto-recovery] /clear 後の再着手通知。"
            f"queue/tasks/{agent_id}.yaml を再読し、assigned タスクを即時再開せよ。"
        )
    msg = {
        "content": content,
        "from": "inbox_watcher",
        "id": f"msg_auto_recovery_{now.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}",
        "read": False,
        "timestamp": now.replace(microsecond=0).isoformat(),
        "type": "task_assigned",
    }
    messages.append(msg)
    data["messages"] = messages

    tmp_path = f"{inbox}.tmp.{os.getpid()}"
    with open(tmp_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(
            data,
            f,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )
    os.replace(tmp_path, inbox)
    print(msg["id"])
except Exception:
    # Best-effort safety net only. Primary /clear delivery must not fail here.
    print("ERROR")
PY
    ) 200>"$LOCKFILE" 2>/dev/null
}

no_idle_full_read() {
    local trigger="${1:-timeout}"
    [ "${ASW_NO_IDLE_FULL_READ:-1}" = "1" ] || return 1
    [ "$trigger" = "timeout" ] || return 1
    [ "${FIRST_UNREAD_SEEN:-0}" -eq 0 ] || return 1
    return 0
}

ashigaru_report_recovery_payload() {
    [ -n "${AGENT_ID:-}" ] || return 1
    [[ "${AGENT_ID}" =~ ^ashigaru[0-9]+$ ]] || return 1

    local project_root task_file report_file
    project_root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    task_file="$project_root/queue/tasks/${AGENT_ID}.yaml"
    report_file="$project_root/queue/reports/${AGENT_ID}_report.yaml"
    [ -f "$task_file" ] || return 1

    TASK_FILE="$task_file" REPORT_FILE="$report_file" AGENT_NAME="$AGENT_ID" python3 - << 'PY'
import os
import yaml

task_file = os.environ["TASK_FILE"]
report_file = os.environ["REPORT_FILE"]
agent = os.environ["AGENT_NAME"]

try:
    with open(task_file, "r", encoding="utf-8") as f:
        task_doc = yaml.safe_load(f) or {}
except Exception:
    raise SystemExit(1)

task = task_doc.get("task") or {}
task_id = (task.get("task_id") or "").strip()
task_status = (task.get("status") or "").strip().lower()
if not task_id or task_status not in {"assigned", "in_progress"}:
    raise SystemExit(1)

report = {}
if os.path.exists(report_file):
    try:
        with open(report_file, "r", encoding="utf-8") as f:
            report = yaml.safe_load(f) or {}
    except Exception:
        report = {}

report_task_id = str(report.get("task_id") or "").strip()
report_status = str(report.get("status") or "").strip().lower()
result = report.get("result")

if report_task_id == task_id and report_status == "done" and result not in (None, "", {}):
    raise SystemExit(1)

hint = (
    f"queue/tasks/{agent}.yaml の {task_id} が {task_status} のまま、"
    f"queue/reports/{agent}_report.yaml が未完でござる。"
    f" task YAML を再読し、report YAML 完成と家老通知まで即時閉じよ。"
)
print(f"{task_id}\t{hint}")
PY
}

recover_missing_ashigaru_report_if_idle() {
    local recovery_payload=""
    local recovery_task_id=""
    local recovery_hint=""
    local recovery_id=""
    local now=0

    if agent_is_busy; then
        return 1
    fi

    recovery_payload=$(ashigaru_report_recovery_payload 2>/dev/null || true)
    [ -n "$recovery_payload" ] || return 1
    recovery_task_id="${recovery_payload%%$'\t'*}"
    recovery_hint="${recovery_payload#*$'\t'}"
    [ -n "$recovery_hint" ] || return 1

    now=$(date +%s)
    if [ -n "${LAST_MISSING_REPORT_RECOVERY_TASK_ID:-}" ] \
        && [ "${LAST_MISSING_REPORT_RECOVERY_TASK_ID}" = "$recovery_task_id" ] \
        && [ "${LAST_MISSING_REPORT_RECOVERY_TS:-0}" -gt 0 ] \
        && [ $((now - LAST_MISSING_REPORT_RECOVERY_TS)) -lt "${MISSING_REPORT_RECOVERY_COOLDOWN:-120}" ]; then
        return 1
    fi

    recovery_id=$(enqueue_recovery_task_assigned "$recovery_hint")
    if [ -n "$recovery_id" ] && [ "$recovery_id" != "SKIP_DUPLICATE" ] && [ "$recovery_id" != "ERROR" ]; then
        LAST_MISSING_REPORT_RECOVERY_TASK_ID="$recovery_task_id"
        LAST_MISSING_REPORT_RECOVERY_TS=$now
        echo "[$(date)] [AUTO-RECOVERY] queued missing-report recovery for $AGENT_ID ($recovery_id)" >&2
        send_wakeup 1
        return 0
    fi

    return 1
}

# summary-first: unread_count fast-path before full read
reject_stale_generation_messages() {
    local state_file="$SCRIPT_DIR/queue/runtime/role_failover.yaml"
    [ -f "$state_file" ] || return 0
    mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true
    (
        acquire_inbox_lock || exit 1
        INBOX_PATH="$INBOX" FAILOVER_STATE_PATH="$state_file" python3 - <<'PY'
import datetime as dt
import os
import re
import tempfile

import yaml

inbox_path = os.environ["INBOX_PATH"]
state_path = os.environ["FAILOVER_STATE_PATH"]
managed = re.compile(r"^(shogun|gunkan|gunshi|karo(?:[1-9][0-9]*)?|ashigaru[1-9][0-9]*)$")

def parse_time(value):
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except (TypeError, ValueError):
        return None

try:
    with open(inbox_path, encoding="utf-8") as fh:
        inbox = yaml.safe_load(fh) or {}
    with open(state_path, encoding="utf-8") as fh:
        state = yaml.safe_load(fh) or {}
    roles = state.get("roles") if isinstance(state.get("roles"), dict) else {}
    changed = False
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    for message in inbox.get("messages") or []:
        if not isinstance(message, dict) or message.get("read"):
            continue
        sender = str(message.get("from") or "")
        if not managed.fullmatch(sender):
            continue
        role_state = roles.get(sender)
        if not isinstance(role_state, dict):
            reason = "sender_role_not_initialized"
        else:
            generation = message.get("generation")
            if isinstance(generation, int) and not isinstance(generation, bool):
                reason = "" if generation == role_state.get("generation") else "stale_generation"
            else:
                sent_at = parse_time(message.get("timestamp"))
                initialized_at = parse_time(role_state.get("initialized_at"))
                reason = "" if sent_at and initialized_at and sent_at < initialized_at else "missing_generation_after_init"
        if reason:
            message["read"] = True
            message["rejected"] = True
            message["rejection_reason"] = reason
            message["rejected_at"] = now
            changed = True
    if changed:
        fd, tmp_name = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                yaml.safe_dump(inbox, fh, allow_unicode=True, sort_keys=False)
            os.replace(tmp_name, inbox_path)
        except Exception:
            os.unlink(tmp_name)
            raise
except Exception as exc:
    print(f"[inbox_watcher] generation filter failed: {exc}", file=__import__("sys").stderr)
    raise SystemExit(1)
PY
    ) 200>"$LOCKFILE"
}

sync_completed_inbox_work() {
    local state_file="$SCRIPT_DIR/queue/runtime/role_failover.yaml"
    [ -f "$state_file" ] || return 0
    INBOX_PATH="$INBOX" WATCHER_AGENT_ID="$AGENT_ID" SHOGUNATE_ROOT="$SCRIPT_DIR" python3 - <<'PY'
import datetime as dt
import os
import sys

import yaml

root = os.environ["SHOGUNATE_ROOT"]
agent = os.environ["WATCHER_AGENT_ID"]
inbox_path = os.environ["INBOX_PATH"]
sys.path.insert(0, root)
from shogunate_mod.runtime.role_failover import EVENT_WORK_COMPLETE, RoleFailoverStore, is_role_name  # noqa: E402

def parse_time(value):
    try:
        parsed = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        return parsed.astimezone(dt.timezone.utc)
    except (TypeError, ValueError):
        return None

if not is_role_name(agent):
    raise SystemExit(0)
store = RoleFailoverStore(__import__("pathlib").Path(root))
state = store.load()
role_state = state.get("roles", {}).get(agent)
if not isinstance(role_state, dict) or not isinstance(role_state.get("current_work"), dict):
    raise SystemExit(0)
scope = role_state["current_work"].get("scope")
started_at = parse_time(scope.get("started_at")) if isinstance(scope, dict) else None
with open(inbox_path, encoding="utf-8") as fh:
    messages = (yaml.safe_load(fh) or {}).get("messages") or []
completion_types = {"cmd_done", "report_received", "audit_report"}
completion = None
for message in messages:
    if not isinstance(message, dict) or not message.get("read") or message.get("rejected"):
        continue
    if message.get("type") not in completion_types:
        continue
    completed_at = parse_time(message.get("timestamp"))
    if started_at and completed_at and completed_at < started_at:
        continue
    completion = message
if completion is None:
    raise SystemExit(0)
event_id = f"work-complete-{agent}-{completion.get('id', 'message')}"[:128]
store.apply_event({
    "event_id": event_id,
    "type": EVENT_WORK_COMPLETE,
    "role": agent,
    "expected_generation": role_state["generation"],
})
PY
}

get_unread_count_fast() {
    INBOX_PATH="$INBOX" python3 - << 'PY'
import json
import os
import yaml

inbox = os.environ.get("INBOX_PATH", "")
try:
    with open(inbox, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    messages = data.get("messages", []) or []
    unread_count = sum(1 for m in messages if not m.get("read", False))
    print(json.dumps({"count": unread_count}))
except Exception:
    print(json.dumps({"count": 0}))
PY
}

# ─── Extract unread message info (lock-free read) ───
# Returns JSON lines: {"count": N, "has_special": true/false, "specials": [...]}
# Test anchor for bats awk pattern: get_unread_info\\(\\)
get_unread_info() {
    mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true

    (
        acquire_inbox_lock || exit 1
        INBOX_PATH="$INBOX" python3 - << 'PY'
import json
import os
import yaml

inbox = os.environ.get("INBOX_PATH", "")
try:
    with open(inbox, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    messages = data.get("messages", []) or []
    unread = [m for m in messages if not m.get("read", False)]
    special_types = ("clear_command", "model_switch")
    specials = [m for m in unread if m.get("type") in special_types]

    if specials:
        for m in messages:
            if not m.get("read", False) and m.get("type") in special_types:
                m["read"] = True

        tmp_path = f"{inbox}.tmp.{os.getpid()}"
        with open(tmp_path, "w", encoding="utf-8") as f:
            yaml.safe_dump(
                data,
                f,
                default_flow_style=False,
                allow_unicode=True,
                sort_keys=False,
            )
        os.replace(tmp_path, inbox)

    normal = [m for m in unread if m.get("type") not in special_types]
    normal_count = len(normal)
    has_task_assigned = any((m.get("type") or "") == "task_assigned" for m in normal)
    signature = "|".join(
        f"{m.get('id', '')}:{m.get('type', '')}:{m.get('timestamp', '')}"
        for m in normal
    )
    payload = {
        "count": normal_count,
        "has_task_assigned": has_task_assigned,
        "signature": signature,
        "specials": [{"type": m.get("type", ""), "content": m.get("content", "")} for m in specials],
    }
    print(json.dumps(payload))
except Exception:
    print(json.dumps({"count": 0, "has_task_assigned": False, "specials": []}))
PY
    ) 200>"$LOCKFILE" 2>/dev/null
}

get_wakeup_text() {
    local unread_count="$1"
    local default_nudge="inbox${unread_count}"

    local decision
    decision=$(INBOX_PATH="$INBOX" AGENT_ID_ENV="${AGENT_ID:-}" python3 - << 'PY'
import os
import yaml

inbox = os.environ.get("INBOX_PATH", "")
agent_id = os.environ.get("AGENT_ID_ENV", "")
try:
    with open(inbox, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    messages = data.get("messages", []) or []
    unread = [m for m in messages if not m.get("read", False)]
    audit_types = {
        "audit_requested",
        "audit_warn",
        "audit_failed",
        "runtime_blocked",
        "emergency_stop_requested",
    }
    direct_types = {
        "direct_message",
        "message",
        "question",
        "chat",
        "user_message",
    }
    direct_senders = {"shogun", "lord", "user", "human", "tono"}
    passive_types = {"report_received", "cmd_done"}
    has_roll_call = any((m.get("type") or "") == "roll_call" for m in unread)
    if agent_id == "gunkan":
        has_audit_event = any((m.get("type") or "") in audit_types for m in unread)
        has_direct_message = any(
            (m.get("type") or "") in direct_types
            or (
                (m.get("from") or "") in direct_senders
                and (m.get("type") or "") not in passive_types
            )
            for m in unread
        )
        if has_audit_event:
            print("gunkan_audit_event")
        elif has_roll_call:
            print("roll_call")
        elif has_direct_message:
            print("gunkan_direct_message")
        else:
            print("gunkan_passive")
        raise SystemExit(0)
    has_cmd_done = any((m.get("type") or "") == "cmd_done" for m in unread)
    has_runtime_blocked = any((m.get("type") or "") == "runtime_blocked" for m in unread)
    has_cmd_new = any((m.get("type") or "") == "cmd_new" for m in unread)
    has_report_received = any((m.get("type") or "") == "report_received" for m in unread)
    has_task_assigned = any((m.get("type") or "") == "task_assigned" for m in unread)
    has_auto_recovery = any(
        (m.get("type") or "") == "task_assigned"
        and "[auto-recovery]" in (m.get("content") or "")
        for m in unread
    )
    if has_cmd_done:
        print("cmd_done")
    elif has_runtime_blocked:
        print("runtime_blocked")
    elif has_cmd_new:
        print("cmd_new")
    elif has_report_received:
        print("report_received")
    elif has_roll_call:
        print("roll_call")
    elif has_auto_recovery:
        print("auto_recovery_task")
    elif has_task_assigned:
        print("task_assigned")
    else:
        print("default")
except Exception:
    print("default")
PY
)

    if [[ "${AGENT_ID:-}" == "gunkan" ]]; then
        if [[ "$decision" == "gunkan_audit_event" ]]; then
            echo "queue/inbox/gunkan.yaml に未読の監査イベントがある。queue/runtime/gunkan_events.yaml と関連 queue/report を読み、必要なら python3 shogunate_mod/gunkan/codd_audit.py を実行し、queue/reports/gunkan_report.yaml に監査結果を書け。処理後は発火元 message を read:true にせよ。通常の中間報告取得や進行管理は行うな。"
            return 0
        fi
        if [[ "$decision" == "roll_call" ]]; then
            echo "queue/inbox/gunkan.yaml に未読の点呼がある。内容を読み、発火元 message を read:true にして、送信元へ現在状態を簡潔に返答せよ。監査は依頼されている場合だけ行え。"
            return 0
        fi
        if [[ "$decision" == "gunkan_direct_message" ]]; then
            echo "queue/inbox/gunkan.yaml に未読の直接メッセージがある。内容を読み、発火元 message を read:true にして、軍監として必要最小限に返答せよ。監査・検証・リスク確認・質問への回答はよいが、通常の進行管理や足軽への割当は行うな。"
            return 0
        fi
        echo "__gunkan_passive__"
        return 0
    fi

    if [[ "$decision" == "roll_call" ]]; then
        echo "queue/inbox/${AGENT_ID}.yaml に未読の点呼がある。内容を読み、処理した message を read:true にして、送信元へ現在状態を簡潔に返答せよ。"
        return 0
    fi

    if [[ "$decision" == "cmd_done" ]]; then
        echo "queue/inbox/shogun.yaml に未読の cmd_done がある。dashboard.md を確認し、殿へ完了報告せよ。"
        return 0
    fi

    if [[ "$decision" == "runtime_blocked" ]]; then
        echo "queue/inbox/shogun.yaml に未読の runtime_blocked がある。dashboard.md の runtime-blocked/* を確認し、止まっている役職と要対応を殿へ報告せよ。"
        return 0
    fi

    if [[ "${AGENT_ID:-}" == "karo" ]]; then
        if [[ "$decision" == "cmd_new" ]]; then
            echo "queue/inbox/karo.yaml に未読の cmd_new がある。まず queue/shogun_to_karo.yaml と active ashigaru の task/report YAML を読み、該当 cmd を status: in_progress にせよ。成果物や工程が分けられるなら ashigaru1/2 で止めず、ashigaru3以降も含めた有用で安全な active ashigaru 全体へ queue/tasks/ashigaru{N}.yaml と task_assigned を即時に切れ。複雑・高リスク・分解困難なら queue/tasks/gunshi.yaml に分析taskを並行投入して gunshi へ task_assigned を送れ。"
            return 0
        fi
        if [[ "$decision" == "report_received" ]]; then
            echo "queue/inbox/karo.yaml に未読の report_received がある。まず対応する queue/reports/ashigaru*_report.yaml と queue/shogun_to_karo.yaml を読み、検証・dashboard更新・cmd close を即時に進めよ。"
            return 0
        fi
        echo "$default_nudge"
        return 0
    fi

    if [[ "${AGENT_ID:-}" == "gunshi" ]]; then
        if [[ "$decision" == "task_assigned" ]]; then
            echo "queue/inbox/gunshi.yaml に未読の task_assigned がある。まず queue/tasks/gunshi.yaml を読み、戦略分析・分解案・リスク評価を行い、queue/reports/gunshi_report.yaml を書いて家老へ通知せよ。実装・dashboard更新・cmd close は行うな。"
            return 0
        fi
    fi

    if [[ "${AGENT_ID:-}" =~ ^ashigaru[0-9]+$ ]]; then
        if [[ "$decision" == "auto_recovery_task" ]]; then
            echo "queue/inbox/${AGENT_ID}.yaml に未読の auto-recovery task_assigned がある。queue/tasks/${AGENT_ID}.yaml と queue/reports/${AGENT_ID}_report.yaml を読み、report 未完なら完成と家老通知まで即時閉じよ。"
            return 0
        fi
        if [[ "$decision" == "task_assigned" ]]; then
            echo "queue/inbox/${AGENT_ID}.yaml に未読の task_assigned がある。まず queue/tasks/${AGENT_ID}.yaml を読み、assigned task を進めよ。完了したら queue/reports/${AGENT_ID}_report.yaml を書き、家老へ通知せよ。"
            return 0
        fi
    fi

    echo "$default_nudge"
}

# ─── Send startup prompt after context reset ───
# Claude / Codex clear/new 後に persona と task recovery を再確立する。
send_startup_prompt() {
    local attempt
    for attempt in 1 2 3; do
        sleep 5
        if ! agent_is_busy; then
            echo "[$(date)] [STARTUP] $AGENT_ID idle after ${attempt}x5s — sending startup prompt" >&2
            break
        fi
        echo "[$(date)] [STARTUP] $AGENT_ID still busy after ${attempt}x5s — retrying" >&2
    done

    local startup_prompt=""
    if type get_startup_prompt &>/dev/null; then
        startup_prompt=$(get_startup_prompt "$AGENT_ID" 2>/dev/null || true)
    fi
    if [[ -z "$startup_prompt" ]]; then
        startup_prompt="Session Start — do ALL of this in one turn: identify yourself, read queue/tasks/${AGENT_ID}.yaml, read queue/inbox/${AGENT_ID}.yaml, mark processed inbox read:true, then execute assigned work to completion."
    fi

    echo "[$(date)] [STARTUP] Sending startup prompt to $AGENT_ID: ${startup_prompt:0:80}..." >&2
    send_text_and_enter "$startup_prompt" "startup prompt" || true
}

# ─── Context reset before a new task_assigned batch ───
# Codex は /new 後に AGENTS.md を自動再読しないため、startup prompt を同梱する。
# Claude は /clear のみ（Session Start は CLAUDE.md 側）。OpenCode は /new のみ。
send_context_reset() {
    local effective_cli
    effective_cli=$(get_effective_cli_type)

    if [ "$AGENT_ID" = "shogun" ]; then
        echo "[$(date)] [SKIP] shogun: suppressing context reset" >&2
        return 0
    fi

    local reset_cmd="/new"
    case "$effective_cli" in
        codex|opencode|kilo|localapi|cursor)
            reset_cmd="/new"
            ;;
        claude|copilot|kimi|antigravity|grok)
            reset_cmd="/clear"
            ;;
        *)
            reset_cmd="/new"
            ;;
    esac

    echo "[$(date)] [CONTEXT-RESET] Sending $reset_cmd before task_assigned for $AGENT_ID ($effective_cli)" >&2

    if [[ "$effective_cli" == "codex" ]]; then
        if ! send_text_and_enter "/new" "Codex /new"; then
            return 1
        fi
        sleep 3
        send_startup_prompt
        # Context-reset startup already carries full recovery; skip the same-cycle nudge.
        STARTUP_PROMPT_SENT=1
        return 0
    fi

    if [[ "$effective_cli" == "opencode" ]]; then
        if ! send_text_and_enter "/new" "OpenCode /new"; then
            return 1
        fi
        NEW_CONTEXT_SENT=1
        sleep 3
        return 0
    fi

    # Do not route through send_cli_command here: that path may inject an extra
    # startup prompt (Claude) or restart the CLI. Context-reset only needs the
    # conversation reset itself; the follow-up nudge carries task instructions.
    if ! send_text_and_enter "$reset_cmd" "context reset"; then
        return 1
    fi
    if [[ "$reset_cmd" == "/clear" ]]; then
        LAST_CLEAR_TS=$(date +%s)
        sleep 3
    else
        sleep 3
    fi

    local attempt
    for attempt in 1 2 3; do
        sleep 5
        if ! agent_is_busy; then
            echo "[$(date)] [CONTEXT-RESET] $AGENT_ID idle after ${attempt}x5s — ready for nudge" >&2
            break
        fi
        echo "[$(date)] [CONTEXT-RESET] $AGENT_ID still busy after ${attempt}x5s — retrying" >&2
    done
    if agent_is_busy; then
        echo "[$(date)] [CONTEXT-RESET] $AGENT_ID still busy after 15s — proceeding anyway" >&2
    fi
}

# ─── Send CLI command via pty direct write ───
# For /clear and /model only. These are CLI commands, not conversation messages.
# CLI_TYPE別分岐: claude→そのまま, codex→/clear対応・/modelスキップ,
#                  copilot/antigravity/opencode/kilo/localapi→Ctrl-C+再起動・CLI依存処理
# 実行時にtmux paneの @agent_cli を再確認し、ドリフト時はpane値を優先する。
send_cli_command() {
    local cmd="$1"
    local source_context="${2:-manual}"
    local effective_cli
    effective_cli=$(get_effective_cli_type)

    # Busy guard: Working中の /clear は文脈破壊を起こすため、次サイクルへ延期する。
    if [[ "$cmd" == "/clear" ]] && agent_is_busy; then
        echo "[$(date)] [SKIP] Agent is busy — /clear deferred to next cycle (agent=$AGENT_ID)" >&2
        return 0
    fi

    # CLI別コマンド変換
    local actual_cmd="$cmd"
    case "$effective_cli" in
        codex)
            # Codex: /clear不存在→/newで新規会話開始, /model非対応→スキップ
            # upstream追随: command-layer（shogun / gunshi / karo系）だけ
            # escalation経由の/clearを抑止し、対話中断を防ぐ。
            if [[ "$cmd" == "/clear" ]]; then
                if [[ "$source_context" == "escalation" ]] && [[ "$AGENT_ID" =~ ^(shogun|gunshi|karo|karo[0-9]+|karo_gashira)$ ]]; then
                    echo "[$(date)] [SKIP] Codex escalation /clear suppressed for $AGENT_ID (avoid /new interruption)" >&2
                    return 0
                fi
                # Rapid duplicate clear_commands must not stack multiple /new sessions.
                if [ "${NEW_CONTEXT_SENT:-0}" -eq 1 ]; then
                    echo "[$(date)] [SKIP] Codex /new already sent for $AGENT_ID — skipping duplicate clear_command" >&2
                    return 0
                fi
                echo "[$(date)] [SEND-KEYS] Codex /clear→/new: starting new conversation for $AGENT_ID" >&2
                if ! send_text_and_enter "/new" "Codex /new"; then
                    return 1
                fi
                NEW_CONTEXT_SENT=1
                sleep 3
                send_startup_prompt
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                echo "[$(date)] Skipping $cmd (not supported on codex)" >&2
                return 0
            fi
            ;;
        copilot)
            # Copilot: /clearはCtrl-C+再起動, /model非対応→スキップ
            if [[ "$cmd" == "/clear" ]]; then
                echo "[$(date)] [SEND-KEYS] Copilot /clear: sending Ctrl-C + restart for $AGENT_ID" >&2
                mux_send_ctrl_c
                sleep 2
                if ! send_text_and_enter "copilot --yolo" "Copilot restart"; then
                    return 1
                fi
                sleep 3
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                echo "[$(date)] Skipping $cmd (not supported on copilot)" >&2
                return 0
            fi
            ;;
        antigravity)
            if [[ "$cmd" == "/clear" ]]; then
                echo "[$(date)] [SEND-KEYS] Antigravity /clear: sending Ctrl-C + restart for $AGENT_ID" >&2
                mux_send_ctrl_c
                sleep 1
                if ! send_text_and_enter "$(restart_command_for_cli antigravity)" "Antigravity restart"; then
                    return 1
                fi
                timeout 2 tmux set-option -p -t "$PANE_TARGET" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
                sleep 2
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                echo "[$(date)] Skipping $cmd (model switch should be done in Antigravity /model UI)" >&2
                return 0
            fi
            ;;
        opencode)
            if [[ "$cmd" == "/clear" ]]; then
                if [ "${NEW_CONTEXT_SENT:-0}" -eq 1 ]; then
                    echo "[$(date)] [SKIP] OpenCode /new already sent for $AGENT_ID — skipping duplicate clear_command" >&2
                    return 0
                fi
                echo "[$(date)] [SEND-KEYS] OpenCode /clear→/new: starting new conversation for $AGENT_ID" >&2
                if ! send_text_and_enter "/new" "OpenCode /new"; then
                    return 1
                fi
                NEW_CONTEXT_SENT=1
                sleep 3
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                echo "[$(date)] Skipping $cmd (OpenCode model changes are restart-only)" >&2
                return 0
            fi
            ;;
        kilo)
            if [[ "$cmd" == "/clear" ]]; then
                echo "[$(date)] [SEND-KEYS] Kilo /clear: sending Ctrl-C + restart for $AGENT_ID" >&2
                mux_send_ctrl_c
                sleep 1
                if ! send_text_and_enter "$(restart_command_for_cli kilo)" "Kilo restart"; then
                    return 1
                fi
                timeout 2 tmux set-option -p -t "$PANE_TARGET" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
                sleep 2
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                echo "[$(date)] Skipping $cmd (model switch may be unsupported on kilo CLI)" >&2
                return 0
            fi
            ;;
        localapi)
            if [[ "$cmd" == "/clear" ]]; then
                echo "[$(date)] [SEND-KEYS] LocalAPI /clear: sending Ctrl-C + restart for $AGENT_ID" >&2
                mux_send_ctrl_c
                sleep 1
                if ! send_text_and_enter "$(restart_command_for_cli localapi)" "LocalAPI restart"; then
                    return 1
                fi
                timeout 2 tmux set-option -p -t "$PANE_TARGET" @cli_launch_epoch "$(date +%s)" >/dev/null 2>&1 || true
                sleep 2
                return 0
            fi
            if [[ "$cmd" == /model* ]]; then
                local model_name
                model_name=$(echo "$cmd" | sed -E 's#^/model[[:space:]]+##')
                if [[ -n "$model_name" ]]; then
                    actual_cmd=":model $model_name"
                else
                    echo "[$(date)] Skipping malformed model switch command for localapi: '$cmd'" >&2
                    return 0
                fi
            fi
            ;;
        # claude: commands pass through as-is
    esac

    echo "[$(date)] [SEND-KEYS] Sending CLI command to $AGENT_ID ($effective_cli): $actual_cmd" >&2
    # Clear stale input first, then send command (text and Enter separated for Codex TUI)
    # Codex CLI: C-c when idle causes CLI to exit — skip it
    if [[ "$effective_cli" != "codex" ]]; then
        mux_send_ctrl_c
        sleep 0.5
    fi
    if ! send_text_and_enter "$actual_cmd" "CLI command"; then
        return 1
    fi

    # /clear needs extra wait time before follow-up
    if [[ "$actual_cmd" == "/clear" ]]; then
        sleep 3
        if [[ "$effective_cli" == "claude" ]]; then
            send_startup_prompt
        fi
    else
        sleep 1
    fi
}

# ─── Agent self-watch detection ───
# Check if the agent has an active native watcher on its inbox.
# If yes, the agent will self-wake — no nudge needed.
agent_has_self_watch() {
    # Codex/Antigravity/LocalAPI/Copilot/Kimiは自己watchを持たない想定。
    # 自己watch判定はClaudeのみ有効化し、watcher自身のPGIDは除外する。
    local effective_cli
    effective_cli=$(get_effective_cli_type)
    if [[ "$effective_cli" != "claude" ]]; then
        return 1
    fi

    local my_pgid pid pid_pgid inbox_path inbox_pattern
    inbox_path="${INBOX:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/queue/inbox/${AGENT_ID}.yaml}"
    inbox_pattern=$(escape_extended_regex "$inbox_path")
    my_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
    while IFS= read -r pid; do
        pid="${pid%% *}"
        [ -n "$pid" ] || continue
        pid_pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -z "$my_pgid" || -z "$pid_pgid" || "$pid_pgid" != "$my_pgid" ]]; then
            return 0
        fi
    done < <(pgrep -f "(inotifywait|fswatch).*${inbox_pattern}" 2>/dev/null || true)
    return 1
}

# ─── Agent busy detection ───
# Check if the agent's CLI is currently processing (Working/thinking/etc).
# Sending nudge during Working causes text to queue but Enter to be lost.
# Returns 0 (true) if agent is busy, 1 if idle.
# Only checks bottom 5 lines — old markers linger in scroll-back.
agent_is_busy() {
    local pane_tail
    local idle_flag="${IDLE_FLAG_DIR:-/tmp}/shogun_idle_${AGENT_ID}"
    local effective_cli
    effective_cli=$(get_effective_cli_type)
    local now clear_busy_until
    now=$(date +%s)
    clear_busy_until=$((LAST_CLEAR_TS + 30))

    if [ "${LAST_CLEAR_TS:-0}" -gt 0 ] && [ "$now" -lt "$clear_busy_until" ]; then
        record_agent_busy_observation "$effective_cli"
        return 0
    fi

    # Claude idle-flag short-circuit: stop_hook creates this when a turn ends.
    # A present flag means idle even if pane text or agent_is_busy_check would
    # disagree (welcome banners / mock panes often look busy).
    # Absence does NOT force busy — fall through to pane/check so unit tests and
    # environments without stop_hook still work.
    if [[ "$effective_cli" == "claude" ]] && [ -f "$idle_flag" ]; then
        clear_agent_busy_observation
        return 1
    fi

    if declare -F agent_is_busy_check >/dev/null 2>&1; then
        agent_is_busy_check "$PANE_TARGET"
        case $? in
            0) record_agent_busy_observation "$effective_cli"; return 0 ;;
            1|2) clear_agent_busy_observation; return 1 ;;
        esac
    fi

    pane_tail=$(mux_capture_pane_tail)

    # ── Idle check (takes priority) ──
    if echo "$pane_tail" | grep -qE '(\? for shortcuts|context left)'; then
        clear_agent_busy_observation
        return 1  # idle — Codex idle prompt
    fi
    if echo "$pane_tail" | grep -qE '^(❯|›)\s*$'; then
        clear_agent_busy_observation
        return 1  # idle — Claude Code or Codex bare prompt
    fi

    # ── Busy markers (bottom 5 lines only) ──
    if echo "$pane_tail" | grep -qiF 'esc to interrupt'; then
        record_agent_busy_observation "$effective_cli"
        return 0  # busy
    fi
    if echo "$pane_tail" | grep -qiF 'background terminal running'; then
        record_agent_busy_observation "$effective_cli"
        return 0  # busy
    fi
    if echo "$pane_tail" | grep -qiE '(Working|Thinking|Planning|Sending|Processing|Analyzing|Generating|Executing|task is in progress|Compacting conversation|thought for|思考中|考え中|計画中|送信中|処理中|実行中|解析中|生成中)'; then
        record_agent_busy_observation "$effective_cli"
        return 0  # busy
    fi
    clear_agent_busy_observation
    return 1  # idle
}

# ─── Send wake-up nudge ───
# Layered approach:
#   1. If agent has active native self-watch → skip (agent wakes itself)
#   2. If agent is busy (Working) → skip (nudge during Working loses Enter)
#   3. tmux send-keys (短いnudgeのみ、timeout 5s)
send_wakeup() {
    local unread_count="$1"
    local nudge
    local effective_cli
    local prompt_rc=0
    nudge=$(get_wakeup_text "$unread_count")
    effective_cli=$(get_effective_cli_type)

    if [[ "$nudge" == "__gunkan_passive__" ]]; then
        echo "[$(date)] [SKIP] Gunkan inbox has no audit event; passive event log only" >&2
        return 0
    fi
    if gunkan_audit_nudge_rate_limited "$nudge"; then
        return 0
    fi

    if [ "${FINAL_ESCALATION_ONLY:-0}" = "1" ]; then
        echo "[$(date)] [SKIP] FINAL_ESCALATION_ONLY=1, suppressing normal nudge for $AGENT_ID" >&2
        return 0
    fi

    dismiss_codex_rate_limit_prompt_if_present "$effective_cli" || prompt_rc=$?
    case "$prompt_rc" in
        0|1) ;;
        3) return 0 ;;
        *)
            echo "[$(date)] WARNING: Codex prompt dismiss failed for $AGENT_ID" >&2
            return 1
            ;;
    esac

    # 優先度1: Agent self-watch — nudge不要（エージェントが自分で気づく）
    if agent_has_self_watch; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID has active self-watch, no nudge needed" >&2
        return 0
    fi

    if cli_launch_grace_active; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID CLI launch grace active, deferring nudge" >&2
        return 0
    fi

    # 優先度2: Agent busy — nudge送信するとEnterが消失するためスキップ
    if agent_is_busy; then
        local busy_cli_wakeup
        busy_cli_wakeup=$(get_effective_cli_type)
        if [[ "$busy_cli_wakeup" == "claude" ]]; then
            echo "[$(date)] [SKIP] Agent $AGENT_ID is busy (claude) — Stop hook で配送されるため nudge を抑止" >&2
        else
            echo "[$(date)] [SKIP] Agent $AGENT_ID is busy ($busy_cli_wakeup), deferring nudge" >&2
        fi
        return 0
    fi

    # 優先度3: tmux send-keys（テキストとEnterを分離 — Codex TUI対策）
    echo "[$(date)] [SEND-KEYS] Sending nudge to $PANE_TARGET for $AGENT_ID" >&2
    if send_text_and_enter "$nudge" "send-keys" "1"; then
        verify_nudge_submitted "$nudge" "$effective_cli" "send-keys"
        echo "[$(date)] Wake-up sent to $AGENT_ID (${unread_count} unread)" >&2
        return 0
    fi

    echo "[$(date)] WARNING: send-keys failed or timed out for $AGENT_ID" >&2
    return 1
}

same_unread_recently_nudged() {
    local signature="${1:-}"
    local now

    [ -n "$signature" ] || return 1
    now=$(date +%s)
    if [ "$signature" = "${LAST_NUDGE_SIGNATURE:-}" ] && [ "${LAST_NUDGE_TS:-0}" -gt 0 ] && [ $((now - LAST_NUDGE_TS)) -lt "${NUDGE_REPEAT_COOLDOWN:-120}" ]; then
        echo "[$(date)] [SKIP] same unread set already nudged for $AGENT_ID; waiting for read/change/cooldown" >&2
        return 0
    fi
    LAST_NUDGE_SIGNATURE="$signature"
    LAST_NUDGE_TS="$now"
    return 1
}

# ─── Send wake-up nudge with Escape prefix ───
# Phase 2 escalation: send Escape×2 + C-c to clear stuck input, then nudge.
# Addresses the "echo last tool call" cursor position bug and stale input.
send_wakeup_with_escape() {
    local unread_count="$1"
    local nudge
    local prompt_rc=0
    nudge=$(get_wakeup_text "$unread_count")
    local effective_cli
    effective_cli=$(get_effective_cli_type)
    local c_ctrl_state="skipped"

    if [[ "$nudge" == "__gunkan_passive__" ]]; then
        echo "[$(date)] [SKIP] Gunkan inbox has no audit event; passive event log only" >&2
        return 0
    fi
    if gunkan_audit_nudge_rate_limited "$nudge"; then
        return 0
    fi

    if [ "${FINAL_ESCALATION_ONLY:-0}" = "1" ]; then
        echo "[$(date)] [SKIP] FINAL_ESCALATION_ONLY=1, suppressing phase2 nudge for $AGENT_ID" >&2
        return 0
    fi

    dismiss_codex_rate_limit_prompt_if_present "$effective_cli" || prompt_rc=$?
    case "$prompt_rc" in
        0|1) ;;
        3) return 0 ;;
        *)
            echo "[$(date)] WARNING: Codex prompt dismiss failed for $AGENT_ID" >&2
            return 1
            ;;
    esac

    if agent_has_self_watch; then
        return 0
    fi

    if cli_launch_grace_active; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID CLI launch grace active, deferring Phase 2 nudge" >&2
        return 0
    fi

    # ClaudeはStop hookで未読配送されるため、Escape強制送信は抑止する。
    if [[ "$effective_cli" == "claude" ]]; then
        echo "[$(date)] [SKIP] claude: suppressing Escape escalation for $AGENT_ID; using plain nudge" >&2
        send_wakeup "$unread_count"
        return 0
    fi

    # Phase 2 still skips if agent is busy — Escape during Working would interrupt
    if agent_is_busy; then
        echo "[$(date)] [SKIP] Agent $AGENT_ID is busy ($effective_cli), deferring Phase 2 nudge" >&2
        return 0
    fi

    echo "[$(date)] [SEND-KEYS] ESCALATION Phase 2: Escape×2 + nudge for $AGENT_ID (cli=$effective_cli)" >&2
    # Escape×2 to exit any mode
    mux_send_escape_double
    sleep 0.5
    # C-c to clear stale input (but Codex CLI terminates on C-c when idle, so skip it)
    if [[ "$effective_cli" != "codex" ]]; then
        mux_send_ctrl_c
        sleep 0.5
        c_ctrl_state="sent"
    fi
    if send_text_and_enter "$nudge" "Escape+nudge" "1"; then
        verify_nudge_submitted "$nudge" "$effective_cli" "Escape+nudge"
        echo "[$(date)] Escape+nudge sent to $AGENT_ID (${unread_count} unread, cli=$effective_cli, C-c=$c_ctrl_state)" >&2
        return 0
    fi

    echo "[$(date)] WARNING: send-keys failed for Escape+nudge ($AGENT_ID)" >&2
    return 1
}

# ─── Process cycle ───
process_unread() {
    local trigger="${1:-event}"
    reject_stale_generation_messages || return 0
    sync_completed_inbox_work || return 0

    # summary-first: unread_count fast-path (Phase 2/3 optimization)
    # unread_count fast-path lets us skip expensive full reads when idle.
    local fast_info
    fast_info=$(get_unread_count_fast)
    local fast_count
    fast_count=$(echo "$fast_info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)

    if no_idle_full_read "$trigger" && [ "$fast_count" -eq 0 ] 2>/dev/null; then
        if recover_missing_ashigaru_report_if_idle; then
            return 0
        fi
        # no_idle_full_read guard: unread=0 and timeout path → no full inbox read
        if [ "$FIRST_UNREAD_SEEN" -ne 0 ]; then
            echo "[$(date)] All messages read for $AGENT_ID — escalation reset (fast-path)" >&2
        fi
        FIRST_UNREAD_SEEN=0
        NEW_CONTEXT_SENT=0
        STARTUP_PROMPT_SENT=0
        return 0
    fi

    local info
    info=$(get_unread_info)

    local read_bytes=0
    if [ -f "$INBOX" ]; then
        read_bytes=$(wc -c < "$INBOX" 2>/dev/null || echo 0)
    fi
    update_metrics "${read_bytes:-0}"

    # Handle special CLI commands first (/clear, /model)
    local specials
    specials=$(echo "$info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('specials', []):
    t = s.get('type', '')
    c = (s.get('content', '') or '').replace('\t', ' ').replace('\n', ' ').strip()
    print(f'{t}\t{c}')
" 2>/dev/null)

    local clear_seen=0
    local clear_sent=0
    if [ -n "$specials" ]; then
        local msg_type msg_content cmd
        while IFS=$'\t' read -r msg_type msg_content; do
            [ -n "$msg_type" ] || continue
            if [ "$msg_type" = "clear_command" ]; then
                clear_seen=1
                if agent_is_busy && [[ "$AGENT_ID" != "shogun" ]]; then
                    echo "[$(date)] [SKIP] Agent $AGENT_ID is busy — /clear (clear_command) deferred to next cycle" >&2
                    continue
                fi
            fi
            cmd=$(normalize_special_command "$msg_type" "$msg_content")
            if [ -n "$cmd" ]; then
                if send_cli_command "$cmd" "special"; then
                    [ "$msg_type" = "clear_command" ] && clear_sent=1
                fi
            fi
        done <<< "$specials"
    fi

    # /clear は Codex で /new へ変換される。再起動直後の取りこぼし防止として
    # 追加 task_assigned を自動投入し、次サイクルで確実に wake-up 可能にする。
    if [ "$clear_sent" -eq 1 ]; then
        local recovery_id
        recovery_id=$(enqueue_recovery_task_assigned)
        if [ -n "$recovery_id" ] && [ "$recovery_id" != "SKIP_DUPLICATE" ] && [ "$recovery_id" != "ERROR" ]; then
            echo "[$(date)] [AUTO-RECOVERY] queued task_assigned for $AGENT_ID ($recovery_id)" >&2
        fi
        info=$(get_unread_info)
    fi

    # Send wake-up nudge for normal messages (with escalation)
    local normal_count
    normal_count=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)
    local normal_signature
    normal_signature=$(echo "$info" | python3 -c "import sys,json; print(json.load(sys.stdin).get('signature',''))" 2>/dev/null)
    local has_task_assigned
    has_task_assigned=$(echo "$info" | python3 -c "import sys,json; print(1 if json.load(sys.stdin).get('has_task_assigned') else 0)" 2>/dev/null)

    if [ "$normal_count" -gt 0 ] 2>/dev/null; then
        local now
        local effective_cli
        local prompt_rc=0
        now=$(date +%s)
        effective_cli=$(get_effective_cli_type)

        dismiss_codex_rate_limit_prompt_if_present "$effective_cli" || prompt_rc=$?
        case "$prompt_rc" in
            0|1) ;;
            3) return 0 ;;
            *)
                echo "[$(date)] WARNING: Codex prompt dismiss failed for $AGENT_ID" >&2
                return 1
                ;;
        esac

        # Track when we first saw unread messages
        if [ "$FIRST_UNREAD_SEEN" -eq 0 ]; then
            FIRST_UNREAD_SEEN=$now
        fi

        # Stale busy safety net: if busy detection persists for >5 min with unread,
        # force-create the idle flag so false-busy deadlocks (missed stop_hook) recover.
        if agent_is_busy && [[ "$AGENT_ID" != "shogun" ]]; then
            local stale_busy_limit=300
            if [ "${FIRST_UNREAD_SEEN:-0}" -gt 0 ] && [ "$((now - FIRST_UNREAD_SEEN))" -ge "$stale_busy_limit" ]; then
                echo "[$(date)] WARNING: $AGENT_ID busy for $((now - FIRST_UNREAD_SEEN))s with $normal_count unread — forcing idle flag (stale busy recovery)" >&2
                touch "${IDLE_FLAG_DIR:-/tmp}/shogun_idle_${AGENT_ID}" 2>/dev/null || true
                clear_agent_busy_observation 2>/dev/null || true
            else
                local busy_cli
                busy_cli="$effective_cli"
                if [[ "$busy_cli" == "claude" ]]; then
                    echo "[$(date)] $normal_count unread for $AGENT_ID but agent is busy (claude) — Stop hook will deliver" >&2
                else
                    # Non-Claude: pause escalation while busy so we don't jump phases mid-thought.
                    FIRST_UNREAD_SEEN=$now
                    echo "[$(date)] $normal_count unread for $AGENT_ID but agent is busy ($busy_cli) — pausing escalation timer" >&2
                fi
                return 0
            fi
        fi

        # Context reset once per task_assigned batch (Codex /new + startup, Claude /clear, …).
        # Skip when clear_command already handled the reset above.
        if [ "$has_task_assigned" = "1" ] && [ "${NEW_CONTEXT_SENT:-0}" -eq 0 ] && [ "$clear_seen" -eq 0 ]; then
            send_context_reset
            NEW_CONTEXT_SENT=1
        fi

        # Codex startup prompt already carries full recovery instructions.
        if [ "${STARTUP_PROMPT_SENT:-0}" -eq 1 ]; then
            STARTUP_PROMPT_SENT=0
            echo "[$(date)] [SKIP] Startup prompt just sent to $AGENT_ID — skipping nudge this cycle" >&2
            FIRST_UNREAD_SEEN=$now
            return 0
        fi

        if [ "${ASW_DISABLE_ESCALATION:-0}" = "1" ]; then
            echo "[$(date)] $normal_count unread for $AGENT_ID (escalation disabled)" >&2
            if disable_normal_nudge; then
                echo "[$(date)] [SKIP] disable_normal_nudge=1, no normal nudge for $AGENT_ID" >&2
            elif same_unread_recently_nudged "$normal_signature"; then
                :
            else
                send_wakeup "$normal_count"
            fi
            return 0
        fi

        local age=$((now - FIRST_UNREAD_SEEN))

        if [ "$age" -lt "$ESCALATE_PHASE1" ]; then
            # Phase 1 (0-2 min): Standard nudge
            echo "[$(date)] $normal_count unread for $AGENT_ID (${age}s)" >&2
            if disable_normal_nudge; then
                echo "[$(date)] [SKIP] disable_normal_nudge=1, deferring to escalation-only path" >&2
            elif same_unread_recently_nudged "$normal_signature"; then
                :
            else
                send_wakeup "$normal_count"
            fi
        elif [ "$age" -lt "$ESCALATE_PHASE2" ]; then
            # Phase 2 (2-4 min): Escape + nudge
            echo "[$(date)] $normal_count unread for $AGENT_ID (${age}s — escalating: Escape+nudge)" >&2
            send_wakeup_with_escape "$normal_count"
        else
            # Phase 3 (4+ min): /clear (throttled to once per 5 min)
            if [ "$LAST_CLEAR_TS" -lt "$((now - ESCALATE_COOLDOWN))" ]; then
                echo "[$(date)] ESCALATION Phase 3: Agent $AGENT_ID unresponsive for ${age}s. Sending /clear." >&2
                send_cli_command "/clear" "escalation"
                LAST_CLEAR_TS=$now
                FIRST_UNREAD_SEEN=0  # Reset — will re-detect on next cycle
                NEW_CONTEXT_SENT=0
            else
                # Cooldown active — fall back to Escape+nudge
                echo "[$(date)] $normal_count unread for $AGENT_ID (${age}s — /clear cooldown, using Escape+nudge)" >&2
                send_wakeup_with_escape "$normal_count"
            fi
        fi
    else
        # No unread messages — reset escalation tracker
        if [ "$FIRST_UNREAD_SEEN" -ne 0 ]; then
            echo "[$(date)] All messages read for $AGENT_ID — escalation reset" >&2
        fi
        FIRST_UNREAD_SEEN=0
        NEW_CONTEXT_SENT=0
        STARTUP_PROMPT_SENT=0
        LAST_NUDGE_SIGNATURE=""
        LAST_NUDGE_TS=0

        if ! agent_is_busy; then
            if recover_missing_ashigaru_report_if_idle; then
                return 0
            fi
        fi
    fi
}

process_unread_once() {
    process_unread "startup"
}

# ─── Startup & Main loop (skipped in testing mode) ───
if [ "${__INBOX_WATCHER_TESTING__:-}" != "1" ]; then

# ─── Startup: process any existing unread messages ───
recover_shell_returned_cli_if_needed || true
maintain_codex_runtime_prompt || true
maintain_grok_runtime_failure_guard || true
deliver_pending_bootstrap_if_ready || true
process_unread_once

# ─── Main loop: event-driven via inotifywait/fswatch ───
# Timeout 30s: WSL2 /mnt/c/ can miss inotify events; fswatch needs our own timeout.
# Shorter timeout = faster escalation retry for stuck agents.
FILE_WATCH_TIMEOUT="${FILE_WATCH_TIMEOUT:-30}"

while true; do
    # Block until file is modified OR timeout (safety net for WSL2)
    # set +e: watch backends return non-zero on timeout, which would kill script under set -e
    set +e
    file_watch_wait_once "$INBOX" "$FILE_WATCH_TIMEOUT"
    rc=$?
    set -e

    # rc=0: event fired (instant delivery)
    # rc=1: watch invalidated — Claude Code uses atomic write (tmp+rename),
    #        which replaces the inode. inotifywait sees DELETE_SELF → rc=1.
    #        File still exists with new inode. Treat as event, re-watch next loop.
    # rc=2: timeout (30s safety net for WSL2/fswatch/polling gaps)
    # All cases: check for unread, then loop back to the selected watcher
    sleep 0.3

    recover_shell_returned_cli_if_needed || true
    maintain_codex_runtime_prompt || true
    maintain_grok_runtime_failure_guard || true
    deliver_pending_bootstrap_if_ready || true

    if [ "$rc" -eq 2 ]; then
        if [ "${ASW_PROCESS_TIMEOUT:-1}" = "1" ]; then
            process_unread "timeout"
        fi
    else
        process_unread "event"
    fi
done

fi  # end testing guard
