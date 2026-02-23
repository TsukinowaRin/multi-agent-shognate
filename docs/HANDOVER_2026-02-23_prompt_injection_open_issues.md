# HANDOVER: Prompt Injection Open Issues (2026-02-23)

## 0. 目的
- ユーザー報告「起動はするが、プロンプト注入されない」を次エージェントへ確実に引き継ぐ。
- 既に実施した対策・未解決点・次の実装手順を1枚で追える状態にする。

## 1. 現在の症状（ユーザー観測）
- zellij セッションとペインは起動する。
- しかし初動命令（`ready:<agent>` を含むブートストラップ）が注入されないケースが残る。
- 結果として、起動後に手動入力しないと自律開始しない。

## 2. 直近で入った対策と現状
### 2.1 実施済み対策
- `scripts/goza_no_ma.sh`
  - フォーカス依存注入を廃止し、各ペインTTYへの自己注入に変更済み。
  - `Waiting to run` 対策として、各ペインへ Enter を順次送信する処理を追加済み。
  - `attach` ブロッキングで resume が動かない問題を修正し、attach前に resume をバックグラウンド予約する実装を追加済み。
- `scripts/shutsujin_zellij.sh`
  - 「CLI起動→ready確認→初動送信」の順次処理は実装済み。
- テスト
  - `tests/unit/test_goza_pure_bootstrap.bats`
  - `tests/unit/test_send_wakeup.bats`
  - いずれも現状 PASS。

### 2.2 未解決
- 実機では依然として「注入されない」報告がある。
- つまりユニットテスト PASS と実機挙動に乖離がある。

## 3. 重要な切り分けポイント（最優先）
現象報告時に、どの起動経路を使ったかで対処箇所が変わる。

1. `bash scripts/goza_no_ma.sh --mux zellij --ui zellij --template goza_room`
- 対象: `scripts/goza_no_ma.sh` 経路（pure zellij）。

2. `bash scripts/shutsujin_zellij.sh`
- 対象: `scripts/shutsujin_zellij.sh` 経路（1エージェント=1セッション起動）。

3. `bash shutsujin_departure.sh`（`multiplexer.default: zellij`）
- 内部で 2 または 1 に分岐。設定値と実行ログの突合が必要。

## 4. 再現時に必ず採取する一次情報
以下がないと原因確定できないため、次エージェントは最初に採取すること。

1. 実行コマンド履歴（ユーザーが打った起動コマンド）
2. 起動直後のセッション状態
```bash
zellij list-sessions -n
```
3. ブートストラップ実行ログ
```bash
ls -l queue/runtime/goza_bootstrap_*.log
for f in queue/runtime/goza_bootstrap_*.log; do echo "### $f"; tail -n 80 "$f"; done
```
4. `shutsujin_zellij` 経路の場合の watcher/起動ログ
```bash
tail -n 120 logs/inbox_watcher_shogun.log
tail -n 120 logs/inbox_watcher_karo.log
tail -n 120 logs/inbox_watcher_ashigaru1.log
```
5. ランタイム割当
```bash
cat queue/runtime/agent_cli.tsv
cat queue/runtime/ashigaru_owner.tsv
```

## 5. 技術的な主要仮説（優先順）
1. 起動経路のミスマッチ
- 修正は `goza_no_ma.sh` 側へ入っているが、実運用が `shutsujin_zellij.sh` 側中心だと未反映経路を踏む可能性がある。

2. ready判定の偽陽性
- `scripts/shutsujin_zellij.sh` の `wait_for_cli_ready()` は画面文字列マッチ依存。
- 早期に `ready` 判定され、CLI入力受付前に送信して取りこぼす可能性。

3. zellij 外部 `action write-chars` の配送タイミング差
- セッションは存在していても、対象ペインが入力受付前で送信落ちする可能性。

4. 実機依存（zellij 0.41 系）で command pane の初期状態が揺らぐ
- テストでは検出されないタイミング依存が残存している可能性。

## 6. 次エージェントがやるべきこと（優先タスク）
### P0（必須）
1. 起動経路別に注入処理を一本化する方針を決める。
- 推奨: `goza_no_ma.sh` / `shutsujin_zellij.sh` で注入基盤を共通関数化。

2. 「送信した」ではなく「受信した」を判定する ACK を導入。
- 例: 初動命令の先頭に `ready:<agent>` 応答義務。
- 応答未検出なら再送・再起動・原因ログを残す。

3. 実機再現ログを run-id で分離する。
- `queue/runtime/bootstrap_run_<timestamp>/...` へ保存して過去ノイズを排除。

### P1（推奨）
4. `wait_for_cli_ready()` の判定を厳密化（CLI別に idle prompt を明確化）。
5. `send_line()` 成否を stderr だけでなくファイルログにも残す（時刻・agent・cmd hash）。

### P2（後続）
6. 統合テストを追加（最低1本、zellij実機前提の smoke）。

## 7. 受け入れ条件（次エージェント向け）
1. 指定起動コマンド直後に、全アクティブエージェントで `ready:<agent>` が確認できる。
2. `queue/runtime/goza_bootstrap_*.log` または後継ログに、全agentの注入成功記録が残る。
3. 手動 Enter なしで、将軍が即入力受付状態になる。

## 8. 関連ファイル（調査起点）
- `scripts/goza_no_ma.sh`
- `scripts/shutsujin_zellij.sh`
- `scripts/inbox_watcher.sh`
- `lib/cli_adapter.sh`
- `tests/unit/test_goza_pure_bootstrap.bats`
- `tests/unit/test_send_wakeup.bats`
- `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md`
- `docs/HANDOVER_2026-02-17_bootstrap_injection.md`

## 9. ブランチ状態メモ
- 現在 `codex/auto` は `origin/codex/auto` より ahead。
- 今回の引き継ぎは「解決済み」ではなく「未解決課題の整理」が目的。
