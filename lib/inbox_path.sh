#!/usr/bin/env bash
# inbox_path.sh — queue/inbox の安全な正規化ヘルパー
#
# 背景:
# - 環境によって queue/inbox が「通常ディレクトリ」ではなく
#   symlink / 擬似symlinkテキストファイルになる場合がある。
# - その状態は git add や mkdir -p を失敗させる原因になる。
#
# 方針:
# - 常に queue/inbox をローカルディレクトリへ正規化する。
# - 既存メッセージYAMLがあれば可能な範囲で移行する。

set -euo pipefail

ensure_local_inbox_dir() {
    local inbox_dir="${1:-queue/inbox}"
    local tmp_backup=""
    local target_path=""

    mkdir -p "$(dirname "$inbox_dir")"

    # symlink は内容移行後にローカルディレクトリへ統一
    if [ -L "$inbox_dir" ]; then
        target_path="$(readlink "$inbox_dir" 2>/dev/null || true)"
        tmp_backup="$(mktemp -d "${TMPDIR:-/tmp}/inbox-migrate.XXXXXX")"
        if [ -d "$inbox_dir" ]; then
            cp -f "$inbox_dir"/*.yaml "$tmp_backup/" 2>/dev/null || true
        elif [ -n "$target_path" ] && [ -d "$target_path" ]; then
            cp -f "$target_path"/*.yaml "$tmp_backup/" 2>/dev/null || true
        fi
        rm -f "$inbox_dir"
        mkdir -p "$inbox_dir"
        cp -f "$tmp_backup"/*.yaml "$inbox_dir/" 2>/dev/null || true
        rm -rf "$tmp_backup"
        return 0
    fi

    # 擬似symlinkテキストファイル等をディレクトリへ復旧
    if [ -f "$inbox_dir" ] && [ ! -d "$inbox_dir" ]; then
        target_path="$(head -n 1 "$inbox_dir" 2>/dev/null || true)"
        tmp_backup="$(mktemp -d "${TMPDIR:-/tmp}/inbox-migrate.XXXXXX")"
        if [ -n "$target_path" ] && [ -d "$target_path" ]; then
            cp -f "$target_path"/*.yaml "$tmp_backup/" 2>/dev/null || true
        fi
        rm -f "$inbox_dir"
        mkdir -p "$inbox_dir"
        cp -f "$tmp_backup"/*.yaml "$inbox_dir/" 2>/dev/null || true
        rm -rf "$tmp_backup"
        return 0
    fi

    mkdir -p "$inbox_dir"
}
