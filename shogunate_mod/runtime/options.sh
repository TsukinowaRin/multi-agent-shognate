#!/usr/bin/env bash

show_shutsujin_help() {
    echo ""
    echo "🏯 multi-agent-shogun 出陣スクリプト"
    echo ""
    echo "使用方法: bash shogunate_mod/runtime/entrypoint.sh [オプション]"
    echo ""
    echo "オプション:"
    echo "  -c, --clean         キューとダッシュボードをリセットして起動（クリーンスタート）"
    echo "                      未指定時は前回の状態を維持して起動"
    echo "  -k, --kessen        決戦の陣（Claude系エージェントをOpus優先で起動）"
    echo "                      未指定時は config/settings.yaml のCLI/モデル設定を使用"
    echo "  -s, --setup-only    セッションのセットアップのみ（CLI起動なし）"
    echo "  -t, --terminal      Windows Terminal で新しいタブを開く"
    echo "  -shell, --shell SH  シェルを指定（bash または zsh）"
    echo "                      未指定時は config/settings.yaml の設定を使用"
    echo "  --auto-mode-on      Claude を --permission-mode auto-approved で起動"
    echo "  --permission-mode M Claude の permission mode を明示指定"
    echo "  -S, --silent        サイレントモード（足軽の戦国echo表示を無効化・API節約）"
    echo "                      未指定時はshoutモード（タスク完了時に戦国風echo表示）"
    echo "  -h, --help          このヘルプを表示"
    echo ""
    echo "マルチプレクサ設定:"
    echo "  config/settings.yaml の multiplexer.default は tmux 専用です"
    echo ""
    echo "例:"
    echo "  bash shogunate_mod/runtime/entrypoint.sh              # 前回の状態を維持して出陣"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -c           # クリーンスタート（キューリセット）"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -s           # セットアップのみ（CLI起動なし）"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -t           # 全エージェント起動 + ターミナルタブ展開"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -shell bash  # bash用プロンプトで起動"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -k           # 決戦の陣（Claude系をOpus優先）"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -c -k         # クリーンスタート＋決戦の陣"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -shell zsh   # zsh用プロンプトで起動"
    echo "  bash shogunate_mod/runtime/entrypoint.sh --shogun-no-thinking  # 将軍のthinkingを無効化（中継特化）"
    echo "  bash shogunate_mod/runtime/entrypoint.sh --auto-mode-on        # permission auto-approved で起動"
    echo "  bash shogunate_mod/runtime/entrypoint.sh --permission-mode plan  # permission mode を明示指定"
    echo "  bash shogunate_mod/runtime/entrypoint.sh -S           # サイレントモード（echo表示なし）"
    echo ""
    echo "CLI/モデル構成:"
    echo "  config/settings.yaml の cli.default / cli.agents.* を使用"
    echo "  変更は shogunate_mod/configure/agents.sh から行う"
    echo "  --kessen は Claude 系エージェントのみ Opus 優先に上書き"
    echo ""
    echo "表示モード:"
    echo "  shout（デフォルト）:  タスク完了時に戦国風echo表示"
    echo "  silent（--silent）:   echo表示なし（API節約）"
    echo ""
    echo "エイリアス:"
    echo "  csst  → cd $SCRIPT_DIR && bash shogunate_mod/runtime/entrypoint.sh"
    echo "  css   → bash shogunate_mod/view/focus_agent_pane.sh shogun"
    echo "  csg   → bash shogunate_mod/view/focus_agent_pane.sh gunshi"
    echo "  csm   → bash shogunate_mod/view/focus_agent_pane.sh karo"
    echo "  cgo   → bash shogunate_mod/view/goza_no_ma.sh"
    echo ""
}

parse_runtime_options() {
    SETUP_ONLY=false
    OPEN_TERMINAL=false
    CLEAN_MODE=false
    KESSEN_MODE=false
    SHOGUN_NO_THINKING=false
    SILENT_MODE=false
    SHELL_OVERRIDE=""
    PERMISSION_FLAG="--setting-sources local --permission-mode auto"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--setup-only)
                SETUP_ONLY=true
                shift
                ;;
            -c|--clean)
                CLEAN_MODE=true
                shift
                ;;
            -k|--kessen)
                KESSEN_MODE=true
                shift
                ;;
            -t|--terminal)
                OPEN_TERMINAL=true
                shift
                ;;
            --shogun-no-thinking)
                SHOGUN_NO_THINKING=true
                shift
                ;;
            --auto-mode-on)
                PERMISSION_FLAG="--setting-sources local --permission-mode auto"
                shift
                ;;
            --permission-mode)
                if [[ -n "$2" && "$2" != -* ]]; then
                    PERMISSION_FLAG="--setting-sources local --permission-mode $2"
                    shift 2
                else
                    echo "エラー: --permission-mode オプションにはモード名を指定してください"
                    exit 1
                fi
                ;;
            -S|--silent)
                SILENT_MODE=true
                shift
                ;;
            -shell|--shell)
                if [[ -n "$2" && "$2" != -* ]]; then
                    SHELL_OVERRIDE="$2"
                    shift 2
                else
                    echo "エラー: -shell オプションには bash または zsh を指定してください"
                    exit 1
                fi
                ;;
            -h|--help)
                show_shutsujin_help
                exit 0
                ;;
            *)
                echo "不明なオプション: $1"
                echo "bash shogunate_mod/runtime/entrypoint.sh -h でヘルプを表示"
                exit 1
                ;;
        esac
    done

    if [ -n "$SHELL_OVERRIDE" ]; then
        if [[ "$SHELL_OVERRIDE" == "bash" || "$SHELL_OVERRIDE" == "zsh" ]]; then
            SHELL_SETTING="$SHELL_OVERRIDE"
        else
            echo "エラー: -shell オプションには bash または zsh を指定してください（指定値: $SHELL_OVERRIDE）"
            exit 1
        fi
    fi
}
