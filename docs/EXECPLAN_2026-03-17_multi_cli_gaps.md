# Multi-CLI 拡張の残課題

date: 2026-03-17
status: in_progress

## Context

`cli_adapter.sh` / `configure_agents.sh` / `build_instructions.sh` は
claude / codex / copilot / kimi / gemini / localapi / opencode / kilo の 8 CLI に対応済み。
ただし、一部の運用スクリプトが古い CLI セットのままになっており、
opencode / kilo / gemini エージェントを使うと不整合が起きる。

---

## 課題 1: `inbox_watcher.sh` — opencode / kilo を未認識

**ファイル**: `scripts/inbox_watcher.sh`

### 問題

| 箇所 | 現状 | 影響 |
|---|---|---|
| `is_valid_cli_type` | `claude\|codex\|copilot\|kimi\|gemini\|localapi` のみ | opencode / kilo が不正な CLI 種別とみなされる |
| `send_cli_command` case | opencode / kilo のケースなし | `/clear` が claude のデフォルト処理（`/clear` をそのまま送信）になる。opencode / kilo は `/clear` 非対応のため Ctrl-C + 再起動が必要 |
| 33行目コメント | `gemini/localapi` まで | ドキュメント不正確 |

### 修正内容

1. `is_valid_cli_type` に `opencode|kilo` を追加
2. `send_cli_command` に以下を追加:
   - `opencode)`: `/clear` → Ctrl-C + `${OPENCODE_RESTART_CMD:-opencode}` 再起動、`/model` → スキップ
   - `kilo)`: `/clear` → Ctrl-C + `${KILO_RESTART_CMD:-kilo}` 再起動、`/model` → スキップ
3. 33行目コメントを更新

### テスト

`tests/unit/test_send_wakeup.bats` に以下を追加:
- `is_valid_cli_type opencode` → 0
- `is_valid_cli_type kilo` → 0
- opencode `/clear` 送信テスト
- kilo `/clear` 送信テスト

---

## 課題 2: `switch_cli.sh` — gemini / opencode / kilo の `/exit` 処理なし

**ファイル**: `scripts/switch_cli.sh`

### 問題

`send_exit()` の case 文が `codex / claude / copilot / kimi` のみ。
gemini / opencode / kilo は `*)` のフォールバック（`/exit` + Enter）に落ちる。
各 CLI の実際の終了方法:

| CLI | 正しい終了手順 |
|---|---|
| `gemini` | Ctrl-C で停止（`/exit` は未対応） |
| `opencode` | Ctrl-C で停止（`/exit` は未対応） |
| `kilo` | Ctrl-C で停止（`/exit` は未対応） |

### 修正内容

`send_exit()` に以下のケースを追加:
```bash
gemini|opencode|kilo)
    tmux send-keys -t "$pane" C-c 2>/dev/null || true
    sleep 0.5
    ;;
```

`usage()` の `--type` ヘルプに `gemini | opencode | kilo | localapi` を追記。

---

## 課題 3: `ratelimit_check.sh` — Gemini / OpenCode / Kilo のレート表示なし

**ファイル**: `scripts/ratelimit_check.sh`

### 問題

現在 claude と codex のレートリミットのみ表示。
Gemini CLI / OpenCode / Kilo を使うエージェントがいても何も表示されない。

### 修正内容（調査が必要）

各 CLI のレートリミット情報の取得方法:
- **Gemini**: `~/.gemini/` 配下のログ or Codex `/status` 相当のコマンド（未調査）
- **OpenCode / Kilo**: 独自ログ形式（未調査）

調査完了後に実装する。現状は「未対応 CLI はスキップ」で問題なし。

---

## 課題 4: `inbox_watcher.sh` — opencode / kilo の busy 検出パターン未検証

**ファイル**: `scripts/inbox_watcher.sh`

### 問題

`agent_is_busy()` は `Working / Thinking / Planning / Sending` 等の文字列でスクリーンを検索する。
opencode / kilo が busy 時にどういうテキストを表示するか未確認。
現在の汎用パターンに引っかからない場合、Working 中でも nudge が飛んでしまう。

### 対応

opencode / kilo を実際に動かしてスクリーンキャプチャを取り、
busy パターン文字列を確認してから追加する。

---

## Acceptance Criteria（全課題共通）

- [x] 課題 1 の修正 + テスト追加
- [x] 課題 2 の修正
- [ ] 課題 3 の調査メモ追記（実装は調査後）
- [ ] 課題 4 のパターン文字列調査・追記

## Work Order

優先度順: 課題 1 → 課題 2 → 課題 4 → 課題 3

## Progress

- 2026-03-17: 課題 1 着手。`scripts/inbox_watcher.sh` に `opencode` / `kilo` を有効 CLI として追加し、`/clear` 時の Ctrl-C + 再起動、`/model` のスキップを実装。
- 2026-03-17: `tests/unit/test_send_wakeup.bats` に `opencode` / `kilo` の受理と `/clear` / `/model` テストを追加し、`bats tests/unit/test_send_wakeup.bats` を PASS。
- 2026-03-17: 課題 2 着手。`scripts/switch_cli.sh` の `send_exit()` に `gemini|opencode|kilo` の Ctrl-C 停止を追加し、`usage()` の `--type` ヘルプも拡張。
- 2026-03-17: `tests/unit/test_switch_cli.bats` に `usage()` と `send_exit()` の回帰を追加し、`bats tests/unit/test_switch_cli.bats` を PASS。

## Decision Log

- 課題 1 は `inbox_watcher.sh` の CLI スイッチ分岐へ直接追加する。`opencode` / `kilo` は `/clear` を内部コマンドとして扱わず、`gemini` と同じ Ctrl-C + 再起動系で揃える。
- 課題 2 の `switch_cli.sh` では、`gemini` / `opencode` / `kilo` に `/exit` を送らず Ctrl-C のみにする。CLI 自体の実際の終了方法に合わせる。
- 課題 3 と 4 は実機・ログ調査が要るため、今回の commit ではコード推測で埋めず open のまま残す。

## Outcomes & Retrospective

- `opencode` / `kilo` を使うエージェントでも、watcher 経由の `clear_command` と `switch_cli.sh` の終了処理が古い CLI セットに落ちなくなった。
- 既存テストには `.venv` の PyYAML 依存や古い Codex 表示名期待値が残っていたため、現行実装に合わせて unit test を安定化した。
