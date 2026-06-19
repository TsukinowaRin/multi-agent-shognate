#!/usr/bin/env bash

tmux_has_session_exact() {
    tmux has-session -t "=$1" 2>/dev/null
}

tmux_kill_session_exact() {
    tmux kill-session -t "=$1" 2>/dev/null
}

cleanup_existing_runtime_sessions() {
    log_info "🧹 既存の陣を撤収中..."
    if [ -f "$SCRIPT_DIR/shogunate_mod/runtime/sync_cli_preferences.py" ]; then
        if tmux_has_session_exact "$GOZA_SESSION_NAME" || tmux_has_session_exact "$LEGACY_GOZA_SESSION_NAME" || tmux_has_session_exact shogun || tmux_has_session_exact gunkan || tmux_has_session_exact gunshi || tmux_has_session_exact multiagent; then
            log_info "💾 前回CLI設定を同期中..."
            _runtime_sync_once_log="$SCRIPT_DIR/queue/runtime/runtime_cli_pref_sync_once.log"
            mkdir -p "$SCRIPT_DIR/queue/runtime"
            : > "$_runtime_sync_once_log"
            if python3 "$SCRIPT_DIR/shogunate_mod/runtime/sync_cli_preferences.py" >"$_runtime_sync_once_log" 2>&1; then
                tail -n 1 "$_runtime_sync_once_log" 2>/dev/null || true
            else
                log_info "  └─ runtime CLI同期は失敗しましたが出陣は継続"
            fi
        fi
    fi
    save_goza_layout "$GOZA_SESSION_NAME"
    pkill -f "$SCRIPT_DIR/scripts/goza_layout_autosave.sh ${GOZA_SESSION_NAME} " >/dev/null 2>&1 || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/view/goza_layout_autosave.sh ${GOZA_SESSION_NAME} " >/dev/null 2>&1 || true
    tmux_kill_session_exact "$GOZA_SESSION_NAME" && log_info "  └─ Shogunate本陣、撤収完了" || log_info "  └─ Shogunate本陣は存在せず"
    if [ "$LEGACY_GOZA_SESSION_NAME" != "$GOZA_SESSION_NAME" ]; then
        tmux_kill_session_exact "$LEGACY_GOZA_SESSION_NAME" && log_info "  └─ 旧御座の間 session、撤収完了" || true
    fi
    tmux_kill_session_exact "$RUNTIME_DAEMON_SESSION" && log_info "  └─ runtime監視陣、撤収完了" || log_info "  └─ runtime監視陣は存在せず"
    pkill -f "$SCRIPT_DIR/scripts/inbox_watcher.sh " 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/inbox_watcher.sh " 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/watcher_supervisor.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/watcher/supervisor.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/shogun_to_karo_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/shogun_to_karo_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/karo_done_to_shogun_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/karo_done_to_shogun_bridge_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/runtime_cli_pref_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/runtime/cli_pref_daemon.sh" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/scripts/gunkan_light_watch.py" 2>/dev/null || true
    pkill -f "$SCRIPT_DIR/shogunate_mod/gunkan/light_watch.py" 2>/dev/null || true
    pkill -f "inotifywait.*${SCRIPT_DIR}/queue/inbox" 2>/dev/null || true
    tmux_kill_session_exact multiagent && log_info "  └─ multiagent陣、撤収完了" || log_info "  └─ multiagent陣は存在せず"
    tmux_kill_session_exact shogun && log_info "  └─ shogun本陣、撤収完了" || log_info "  └─ shogun本陣は存在せず"
    tmux_kill_session_exact gunkan && log_info "  └─ gunkan監査陣、撤収完了" || log_info "  └─ gunkan監査陣は存在せず"
    tmux_kill_session_exact gunshi && log_info "  └─ gunshi陣、撤収完了" || log_info "  └─ gunshi陣は存在せず"
}

backup_previous_records_if_clean() {
    [ "$CLEAN_MODE" = true ] || return 0

    BACKUP_DIR="./logs/backup_$(date '+%Y%m%d_%H%M%S')"
    NEED_BACKUP=false

    if [ -f "./dashboard.md" ]; then
        if grep -q "cmd_" "./dashboard.md" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ -f "./queue/shogun_to_karo.yaml" ]; then
        if grep -q "id: cmd_" "./queue/shogun_to_karo.yaml" 2>/dev/null; then
            NEED_BACKUP=true
        fi
    fi

    if [ "$NEED_BACKUP" = true ]; then
        mkdir -p "$BACKUP_DIR" || true
        cp "./dashboard.md" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/reports" "$BACKUP_DIR/" 2>/dev/null || true
        cp -r "./queue/tasks" "$BACKUP_DIR/" 2>/dev/null || true
        cp "./queue/shogun_to_karo.yaml" "$BACKUP_DIR/" 2>/dev/null || true
        log_info "📦 前回の記録をバックアップ: $BACKUP_DIR"
    fi
}

ensure_runtime_queue_dirs() {
    [ -d ./queue/reports ] || mkdir -p ./queue/reports
    [ -d ./queue/tasks ] || mkdir -p ./queue/tasks
    if declare -F ensure_local_inbox_dir >/dev/null 2>&1; then
        ensure_local_inbox_dir "./queue/inbox"
    else
        [ -d ./queue/inbox ] || mkdir -p ./queue/inbox
    fi
    mkdir -p "$SCRIPT_DIR/queue/runtime"
}

reset_or_keep_runtime_queue() {
    if [ "$CLEAN_MODE" = true ]; then
        log_info "📜 前回の軍議記録を破棄中..."

        local _agent
        local _num
        for _agent in "${KNOWN_ASHIGARU[@]}"; do
            _num="${_agent#ashigaru}"
            cat > "./queue/tasks/${_agent}.yaml" << EOF
# 足軽${_num}専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
        done

        for _agent in "${KNOWN_ASHIGARU[@]}"; do
            cat > "./queue/reports/${_agent}_report.yaml" << EOF
worker_id: ${_agent}
task_id: null
timestamp: ""
status: idle
result: null
EOF
        done

        cat > "./queue/tasks/gunshi.yaml" << EOF
# 軍師専用タスクファイル
task:
  task_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
        cat > "./queue/reports/gunshi_report.yaml" << EOF
worker_id: gunshi
task_id: null
timestamp: ""
status: idle
result: null
EOF

        cat > "./queue/tasks/gunkan.yaml" << EOF
# 軍監専用監査ファイル
task:
  audit_id: null
  parent_cmd: null
  description: null
  target_path: null
  status: idle
  timestamp: ""
EOF
        cat > "./queue/reports/gunkan_report.yaml" << EOF
worker_id: gunkan
audit_id: null
parent_cmd: null
timestamp: ""
status: idle
result: null
EOF
        cat > "./queue/runtime/gunkan_events.yaml" << EOF
events: []
summary:
  updated_at: ""
  total_events: 0
  by_agent: {}
  by_type: {}
EOF

        echo "inbox:" > ./queue/ntfy_inbox.yaml

        for _agent in shogun gunkan gunshi "${KARO_AGENTS[@]}" "${KNOWN_ASHIGARU[@]}"; do
            echo "messages: []" > "./queue/inbox/${_agent}.yaml"
        done

        # clean start では前回 run の pending cmd と bridge state を再配送しない。
        cat > "./queue/shogun_to_karo.yaml" << 'EOF'
commands: []
EOF
        rm -f \
            "./queue/runtime/shogun_to_karo_bridge.tsv" \
            "./queue/runtime/karo_done_to_shogun.tsv"

        log_success "✅ 陣払い完了"
    else
        log_info "📜 前回の陣容を維持して出陣..."
        log_success "✅ キュー・報告ファイルはそのまま継続"
    fi
}

write_runtime_coordination_state() {
    date +%s > "$SCRIPT_DIR/queue/runtime/runtime_start_epoch"
    if [ "$TOPOLOGY_ADAPTER_LOADED" = true ]; then
        build_even_ownership_map "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv" "${ACTIVE_ASHIGARU[@]}"
    else
        : > "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
        local _agent
        for _agent in "${ACTIVE_ASHIGARU[@]}"; do
            printf "%s\tkaro\n" "$_agent" >> "$SCRIPT_DIR/queue/runtime/ashigaru_owner.tsv"
        done
    fi
    printf "%s\n" "$LEAD_KARO" > "$SCRIPT_DIR/queue/runtime/lead_karo"
    if [ "$CLEAN_MODE" = true ] || [ ! -f "$SCRIPT_DIR/queue/runtime/karo_coordination.yaml" ]; then
        {
            echo "coordination:"
            echo "  lead_karo: ${LEAD_KARO}"
            echo "  active_karo:"
            local _karo
            for _karo in "${KARO_AGENTS[@]}"; do
                echo "    - ${_karo}"
            done
            echo "  allowed_types:"
            echo "    - dependency_notice"
            echo "    - conflict_notice"
            echo "    - handoff_request"
            echo "    - merge_request"
            echo "    - status_sync"
            echo "  rules:"
            echo "    - \"karo1/lead_karo owns shogun reporting and final integration.\""
            echo "    - \"Each karo commands only ashigaru assigned in queue/runtime/ashigaru_owner.tsv.\""
            echo "    - \"Karo-to-karo inbox messages are only wake-up notices for this board.\""
            echo "  items: []"
        } > "$SCRIPT_DIR/queue/runtime/karo_coordination.yaml"
    fi
}

initialize_dashboard_if_clean() {
    if [ "$CLEAN_MODE" = true ]; then
        log_info "📊 戦況報告板を初期化中..."
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

        if [ "$LANG_SETTING" = "ja" ]; then
            cat > ./dashboard.md << EOF
# 📊 戦況報告
最終更新: ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております
なし

## 🔄 進行中 - 只今、戦闘中でござる
なし

## ✅ 本日の戦果
| 時刻 | 戦場 | 任務 | 結果 |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち
なし

## 🛠️ 生成されたスキル
なし

## ⏸️ 待機中
なし

## ❓ 伺い事項
なし
EOF
        else
            cat > ./dashboard.md << EOF
# 📊 戦況報告 (Battle Status Report)
最終更新 (Last Updated): ${TIMESTAMP}

## 🚨 要対応 - 殿のご判断をお待ちしております (Action Required - Awaiting Lord's Decision)
なし (None)

## 🔄 進行中 - 只今、戦闘中でござる (In Progress - Currently in Battle)
なし (None)

## ✅ 本日の戦果 (Today's Achievements)
| 時刻 (Time) | 戦場 (Battlefield) | 任務 (Mission) | 結果 (Result) |
|------|------|------|------|

## 🎯 スキル化候補 - 承認待ち (Skill Candidates - Pending Approval)
なし (None)

## 🛠️ 生成されたスキル (Generated Skills)
なし (None)

## ⏸️ 待機中 (On Standby)
なし (None)

## ❓ 伺い事項 (Questions for Lord)
なし (None)
EOF
        fi

        log_success "  └─ ダッシュボード初期化完了 (言語: $LANG_SETTING, シェル: $SHELL_SETTING)"
    else
        log_info "📊 前回のダッシュボードを維持"
    fi
    echo ""
}
