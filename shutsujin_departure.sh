#!/usr/bin/env bash
# 🏯 multi-agent-shogun 出陣スクリプト（毎日の起動用）
# Daily Deployment Script for Multi-Agent Orchestration System
#
# 使用方法:
#   ./shutsujin_departure.sh           # 全エージェント起動（前回の状態を維持）
#   ./shutsujin_departure.sh -c        # キューをリセットして起動（クリーンスタート）
#   ./shutsujin_departure.sh -s        # セットアップのみ（Claude起動なし）
#   ./shutsujin_departure.sh --auto-mode-on          # Claude permission auto-approved で起動
#   ./shutsujin_departure.sh --permission-mode plan  # Claude permission mode を明示指定
#   ./shutsujin_departure.sh -h        # ヘルプ表示

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/shogunate_mod/runtime/entrypoint.sh" "$@"
