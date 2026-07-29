#!/usr/bin/env bash
# report provenance / bootstrap readiness (acceptance 7): ready 不足時は runtime state
# を degraded にし、summary を「出陣準備未完了」とする。全 ready 時だけ従来の完了
# 表示を使う。pane は診断用に維持し watcher の後続回復は妨げない。純粋判定を純
# function に分離し unit test で検証する (test_runtime_bootstrap)。
compute_bootstrap_ready_state() {
    # $1: ready 済み agent 数, $2: 構成 agent 総数, $3: bootstrap pending 数
    local ready="${1:-0}"
    local total="${2:-0}"
    local pending="${3:-0}"
    if [ "${pending:-0}" -gt 0 ]; then
        echo "degraded"
        return 0
    fi
    if [ "${total:-0}" -le 0 ]; then
        echo "degraded"
        return 0
    fi
    if [ "${ready:-0}" -ge "${total:-0}" ]; then
        echo "ready"
    else
        echo "degraded"
    fi
}

current_bootstrap_ready_state() {
    # bootstrap.shが実paneで確認したready ack数を唯一の正本にする。
    # pending fileは配信済み時点で消えるため、ready応答の代用にはならない。
    compute_bootstrap_ready_state \
        "${CURRENT_BOOTSTRAP_READY_COUNT:-0}" \
        "${CURRENT_BOOTSTRAP_TOTAL_COUNT:-0}" \
        "${CURRENT_BOOTSTRAP_PENDING_COUNT:-0}"
}

format_departure_readiness_message() {
    # $1: state ("ready" or "degraded")
    local state="${1:-degraded}"
    case "$state" in
        ready)
            echo "出陣準備完了！天下布武！"
            ;;
        *)
            echo "出陣準備未完了（一部エージェント ready 未達成）"
            ;;
    esac
}

write_bootstrap_ready_state() {
    # $1: state, $2: ready_count, $3: total_count, $4: runtime_dir
    local state="${1:-degraded}"
    local ready="${2:-0}"
    local total="${3:-0}"
    local runtime_dir="${4:-$SCRIPT_DIR/queue/runtime}"
    mkdir -p "$runtime_dir"
    python3 - "$runtime_dir/bootstrap_ready_state.yaml" "$state" "$ready" "$total" <<'PY'
import os
import tempfile
import sys
from pathlib import Path

import yaml

path, state, ready, total = sys.argv[1:]
payload = {
    "state": state,
    "ready_count": int(ready or 0),
    "total_count": int(total or 0),
}
fd, tmp = tempfile.mkstemp(dir=Path(path).parent, suffix=".tmp")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        yaml.safe_dump(payload, fh, allow_unicode=True, sort_keys=False)
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
PY
}

show_departure_completion_summary() {
    local _agent=""

    log_info "🔍 陣容を確認中..."
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  📺 Tmux陣容 (Sessions)                                  │"
    echo "  └──────────────────────────────────────────────────────────┘"
    tmux list-sessions | sed 's/^/     /'
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  📋 布陣図 (Formation)                                   │"
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
    echo "     【${GOZA_SESSION_NAME}:${GOZA_WINDOW_NAME}】御座の間 view"
    echo "     ┌────────────────────────────────────────────────────────────┐"
    echo "     │  Pane: shogun          ← 総大将・プロジェクト統括        │"
    echo "     │  Pane: gunkan          ← 独立監査・戦況記録              │"
    for _agent in "${KARO_AGENTS[@]}"; do
        if [ "$_agent" = "$LEAD_KARO" ]; then
            echo "     │  Pane: ${_agent}  ← 筆頭家老・統合/将軍報告             │"
        else
            echo "     │  Pane: ${_agent}  ← 家老・担当足軽統制                 │"
        fi
    done
    echo "     │  Pane: gunshi          ← 戦略・分析・助言                │"
    for _agent in "${ACTIVE_ASHIGARU[@]}"; do
        echo "     │  Pane: ${_agent}  ← 足軽                                 │"
    done
    echo "     └────────────────────────────────────────────────────────────┘"
    echo ""
    if is_android_compat_enabled; then
        echo "     【Android 互換 session】補助レイヤ"
        echo "     ┌────────────────────────────────────────────────────────────┐"
        echo "     │  shogun:main   ← 将軍 proxy                               │"
        echo "     │  gunkan:main   ← 軍監 proxy                               │"
        echo "     │  gunshi:main   ← 軍師 proxy                               │"
        echo "     │  multiagent:0  ← 家老・足軽 proxy                         │"
        echo "     └────────────────────────────────────────────────────────────┘"
        echo ""
    fi

    echo ""
    # acceptance 7: ready 不足 (bootstrap pending > 0) 時は runtime state を
    # degraded にし、summary を「出陣準備未完了」として false completion させない。
    local _ready_count=0 _ready_total=0 _ready_state="degraded" _ready_msg=""
    _ready_count="${CURRENT_BOOTSTRAP_READY_COUNT:-0}"
    _ready_total="${CURRENT_BOOTSTRAP_TOTAL_COUNT:-0}"
    _ready_state="$(current_bootstrap_ready_state)"
    if ! write_bootstrap_ready_state "$_ready_state" \
        "$_ready_count" \
        "$_ready_total" "$SCRIPT_DIR/queue/runtime"; then
        _ready_state="degraded"
        echo "[WARN] bootstrap ready stateを保存できないため、起動完了扱いにしません" >&2
    fi
    _ready_msg="$(format_departure_readiness_message "$_ready_state")"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    if [ "$_ready_state" = "ready" ]; then
        printf '  ║  🏯 %s                              ║\n' "$_ready_msg"
    else
        printf '  ║  ⚠️  %s  ║\n' "$_ready_msg"
    fi
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo ""

    if [ "$SETUP_ONLY" = true ]; then
        echo "  ⚠️  セットアップのみモード: CLIは未起動です"
        echo ""
        echo "  手動でCLIを起動するには:"
        echo "  ┌──────────────────────────────────────────────────────────┐"
        echo "  │  # 将軍を召喚                                            │"
        echo "  │  tmux send-keys -t ${SHOGUN_TARGET:-shogun:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "shogun" "${_shogun_cli_type:-$(resolve_cli_type_for_agent "shogun" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 軍師を召喚                                            │"
        echo "  │  tmux send-keys -t ${GUNSHI_TARGET:-gunshi:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "gunshi" "${_gunshi_cli_type:-$(resolve_cli_type_for_agent "gunshi" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 軍監を召喚                                            │"
        echo "  │  tmux send-keys -t ${GUNKAN_TARGET:-gunkan:main} \\                         │"
        echo "  │    '$(build_cli_command_with_type "gunkan" "${_gunkan_cli_type:-$(resolve_cli_type_for_agent "gunkan" 2>/dev/null || echo claude)}")' Enter  │"
        echo "  │                                                          │"
        echo "  │  # 家老・足軽は ${GOZA_SESSION_NAME}:${GOZA_WINDOW_NAME} pane 側で起動      │"
        echo "  │  cat queue/runtime/agent_cli.tsv                         │"
        echo "  └──────────────────────────────────────────────────────────┘"
        echo ""
    fi

    echo "  次のステップ:"
    echo "  ┌──────────────────────────────────────────────────────────┐"
    echo "  │  御座の間へアタッチして命令を開始:                        │"
    echo "  │     tmux attach-session -t ${GOZA_SESSION_NAME}                  │"
    echo "  │                                                          │"
    echo "  │  将軍 pane へ移動:                                        │"
    echo "  │     bash shogunate_mod/view/focus_agent_pane.sh shogun   (または: css) │"
    echo "  │                                                          │"
    echo "  │  軍師 pane へ移動:                                        │"
    echo "  │     bash shogunate_mod/view/focus_agent_pane.sh gunshi   (または: csg) │"
    echo "  │                                                          │"
    echo "  │  軍監 pane へ移動:                                        │"
    echo "  │     bash shogunate_mod/view/focus_agent_pane.sh gunkan   (または: cgn) │"
    echo "  │                                                          │"
    echo "  │  家老 pane へ移動:                                        │"
    echo "  │     bash shogunate_mod/view/focus_agent_pane.sh karo   (または: csm) │"
    echo "  │                                                          │"
    echo "  │  俯瞰ビューを開く:                                        │"
    echo "  │     bash shogunate_mod/view/goza_no_ma.sh            (または: cgo)  │"
    echo "  │                                                          │"
    echo "  │  alias が古い時の即時修復:                                │"
    echo "  │     source shogunate_mod/shell/aliases.sh                 │"
    echo "  │     永続化: bash shogunate_mod/shell/install_aliases.sh   │"
    echo "  │                                                          │"
    if is_android_compat_enabled; then
        echo "  │  Android アプリ互換の補助 session:                        │"
        echo "  │     shogun:main / gunkan:main / gunshi:main / multiagent:0│"
        echo "  │                                                          │"
    fi
    if [ "$SETUP_ONLY" = false ] && [ "${CURRENT_BOOTSTRAP_PENDING_COUNT:-0}" -gt 0 ]; then
        echo "  │  ※ 一部エージェントは認証待ちで初動命令が未配信です。     │"
        echo "  │    ログイン完了後は watcher が bootstrap を再試行します。 │"
    else
        echo "  │  ※ 各エージェントは指示書を読み込み済み。                 │"
        echo "  │    すぐに命令を開始できます。                             │"
    fi
    echo "  └──────────────────────────────────────────────────────────┘"
    echo ""
    finish_goza_startup_window
    echo "  ════════════════════════════════════════════════════════════"
    echo "   天下布武！勝利を掴め！ (Tenka Fubu! Seize victory!)"
    echo "  ════════════════════════════════════════════════════════════"
    echo ""
}

open_windows_terminal_tabs_if_requested() {
    [ "$OPEN_TERMINAL" = true ] || return 0

    log_info "📺 Windows Terminal でタブを展開中..."

    if command -v wt.exe &> /dev/null; then
        wt.exe -w 0 new-tab wsl.exe -e bash -c "tmux attach-session -t ${GOZA_SESSION_NAME}" \; new-tab wsl.exe -e bash -c "bash shogunate_mod/view/focus_agent_pane.sh shogun" \; new-tab wsl.exe -e bash -c "bash shogunate_mod/view/focus_agent_pane.sh gunkan" \; new-tab wsl.exe -e bash -c "bash shogunate_mod/view/focus_agent_pane.sh gunshi"
        log_success "  └─ ターミナルタブ展開完了"
    else
        log_info "  └─ wt.exe が見つかりません。手動でアタッチしてください。"
    fi
    echo ""
}
