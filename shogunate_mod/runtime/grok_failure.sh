#!/usr/bin/env bash
# grok_failure.sh — Pure in-memory classifier for short Grok Build pane text.
#
# GB-003B (2026-07-18, attempt 3): Grok Build CLI (`grok`, model `grok-4.5`) を
# role failover 経路へ統合するための helper。設計方針は attempt 1 で失敗した
# 「TUI stdout/stderr を file へ redirect して後で分類する」方針の対極:
#
#   * この helper は単一の純粋関数のみを定義し、グローバル state を持たない。
#   * 呼出元は短い pane snapshot を $1 で渡す。helper は pane 中の「単独の
#     既知 error 行」だけを分類する。合致すれば stdout へ `auth_error` /
#     `rate_limit` のいずれかを1行出力し、それ以外は空を返す。
#   * raw pane text を stdout/stderr へ bytes として出し直すことはない。
#     返されるのは固定 reason 文字列だけ。credential や token 等が pane
#     text に含まれていても、それを永続化・再出力しない設計。
#   * 分類は行全体一致（前後空白は無視）で行う。narrative 中の
#     `please sign in` や `rate limit を実装する` のような語句は、既知 error
#     行として1行全体が一致しない限り分類しない（false-positive 拒否）。
#   * file I/O・network・subprocess を一切行わない。テストは mktemp 配下で
#     純関数として安全に実行できる。
#
# 呼出元 (`shogunate_mod/watcher/inbox_watcher.sh`) は分類結果が空でなければ
# 既存 `role_failover_runner.sh explicit_failure` へ role/generation/reason を
# 一度だけ渡す。反復 event は generation 名入り marker で抑止する。

# grok_classify_failure_text <pane_text>
#   stdout: "auth_error" | "rate_limit" | (empty)
#   return: 常に 0（分類不能は空文字で表現し、非零 exit で呼出元を殺さない）
grok_classify_failure_text() {
    local pane_text="${1:-}"
    [ -n "$pane_text" ] || return 0

    local line
    # pane を行ごとに調べ、行頭・行末の空白を除いた1行が既知 error 行と
    # 完全一致するかを見る。substring 一致ではないので narrative 中の
    # "please sign in" 等の混入を許さない。rate-limit 行は既知 prefix の
    # 直後が句読点または行末の場合だけ受理し、"Rate limit exceeded errors"
    # のような一般説明を除外する。
    while IFS= read -r line; do
        # tmux capture-pane が CRLF を返す環境に備えて行末 \r を除去する。
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] || continue
        case "$line" in
            "You are not authenticated"|\
            "You are not authenticated."|\
            "Authentication failed"|\
            "Authentication failed."|\
            "Authentication required"|\
            "Authentication required.")
                printf 'auth_error'
                return 0
                ;;
            "Rate limit exceeded"|\
            "Rate limit exceeded."*|\
            "Rate limit exceeded,"*|\
            "Rate limit exceeded:"*|\
            "Too many requests"|\
            "Too many requests."*|\
            "Too many requests,"*|\
            "Too many requests:"*)
                printf 'rate_limit'
                return 0
                ;;
        esac
    done <<< "$pane_text"
    return 0
}
