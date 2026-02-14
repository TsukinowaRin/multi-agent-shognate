# Handover (Codex利用制限前) — 2026-02-14

## 1. 結論（次の担当者が最初に知るべきこと）
- 直近で2件の修正を反映済み。
  1. 上流同期: Codex `--model` の安全対応 + watcher self-watch誤判定対策
  2. 実機不具合対応: pure zellij初動注入の安定化 + tmux自動attach改善
- コード変更はコミット済み。
  - `a5ab625` `codex: 上流差分を同期しwatcherとcodex起動を改善`
  - `08c0ccc` `codex: goza起動の初動注入とtmux接続を安定化`
- **未解決は「実機での最終確認」**。とくに `goza_zellij --template goza_room` の初動注入がユーザー環境で安定するかを要確認。

## 2. いま考えていること（判断の前提）
- 技術的にボトルネックは「機能不足」より「環境差分（WSL/TTY/tmuxネスト/CLI起動タイミング）」。
- そのため、次フェーズは新機能追加より **起動シーケンスの実機安定性確認とログ基準化** を優先すべき。
- `queue/` 以下はランタイム生成物が多く、開発速度を下げる要因。Git追跡方針の明確化が必要。

## 3. 今やらなければならないこと（Must-Do）
1. 実機で再検証（最優先）
   - `MAS_CLI_READY_TIMEOUT=8 bash scripts/goza_zellij.sh --template goza_room`
   - `MAS_CLI_READY_TIMEOUT=8 bash scripts/goza_tmux.sh --template goza_room`
2. 当日ログのみで判定する運用へ統一
   - 旧ログ混在で誤判定しやすいため、`grep "$(date '+%a %b %d')"` で当日行だけ見る。
3. `queue/` 追跡方針の決定
   - 今はランタイム更新が大量に `git status` を汚す。
   - 追跡維持するファイルと ignore するファイルを分離して、コミット事故を減らす。

## 4. これからやること（Next）
1. **E2E確認を2モードで完了**
   - pure zellij（goza_room）で初動命令が全役職へ送信されるか。
   - tmuxモードで実行後に確実にアタッチされるか。
2. **watcher閾値の運用調整**
   - Geminiでの `/clear` 連発を抑えるため、必要ならエスカレーション閾値をCLI別に再調整。
3. **queueランタイムのGit整理**
   - `.gitignore` のランタイム除外を見直し、必要なら `queue/runtime` の一部だけ追跡に限定。
4. **READMEの実機トラブルシュート補強**
   - 「tmuxが戻る」「初動未注入」時の確認手順（`TMUX=` attach, 当日ログ抽出）を明文化。

## 5. 現在の既知リスク
- R1: ユーザー環境のTTY/セッション状態次第で初動注入が取りこぼされる可能性。
- R2: 古いログが混ざると「未導入依存の現行エラー」と誤認しやすい。
- R3: `queue/` 更新が大量に残り、`git add -A` 事故を起こしやすい。

## 6. 再開時のチェックリスト
1. `git log --oneline -n 5` で `08c0ccc` と `a5ab625` が存在することを確認。
2. `bash -n scripts/goza_no_ma.sh shutsujin_departure.sh` を実行。
3. `bats tests/unit/test_mux_parity.bats tests/unit/test_mux_parity_smoke.bats tests/unit/test_send_wakeup.bats` を実行。
4. 実機E2E（zellij/tmux）を実施し、当日ログのみ抽出して判定。

## 7. 実機検証コマンド（コピペ用）
```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
sudo apt install -y inotify-tools

# セッション掃除（任意）
tmux kill-server 2>/dev/null || true
for s in $(zellij list-sessions -n 2>/dev/null | awk '{print $1}'); do
  zellij delete-session "$s" --force 2>/dev/null || zellij kill-session "$s" 2>/dev/null || true
done

MAS_CLI_READY_TIMEOUT=8 bash scripts/goza_zellij.sh --template goza_room
MAS_CLI_READY_TIMEOUT=8 bash scripts/goza_tmux.sh --template goza_room
```

```bash
# ログは当日行のみで判定
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
TODAY="$(date '+%a %b %d')"
grep "$TODAY" logs/inbox_watcher_shogun.log | tail -n 60
grep "$TODAY" logs/inbox_watcher_karo.log | tail -n 60
grep "$TODAY" logs/inbox_watcher_ashigaru1.log | tail -n 60
grep "$TODAY" logs/inbox_watcher_ashigaru2.log | tail -n 60
```

## 8. 補足（引き継ぎ範囲外）
- `queue/` 配下の実データ（task/report/metrics）は運用状態に依存するため、本ドキュメントでは内容評価しない。
- 次担当者は「コードの動作」と「運用データ」を分離して扱うこと。
