# ExecPlan: Long Running Stability Fixes

最終更新: 2026-06-22

## 目的

長時間実AI E2E `long-ai-e2e-20260622153555` で見つかった実利用上の詰まりを、Shogunate MOD側で改善する。

## 対象課題

1. Gunkan light watch が target project 内成果物を runtime root 基準で解決し、`target-project/app.js` などを欠落誤検知する。
2. Codex の初動命令や長文命令が composer に残り、Enter 追送が必要になる。
3. 起動ログの ready count が実 pane 数とズレる。
4. Antigravity の feedback prompt が作業後の次指示を塞ぐ。
5. Karo が長時間 `Working` のままでも、進行中か停止かが非エンジニアに分かりにくい。

## 実装方針

- 既存 runtime / watcher の契約を小さく拡張する。
- Gunkan artifact 解決は target project を第一候補、runtime root を第二候補にする。
- Codex / Antigravity の prompt 自動処理は既存 `prompts.sh` / watcher retry のパターンに追加する。
- ready count は active role list から期待件数を作り、shogun / gunkan / gunshi / karo / active ashigaru を含める。
- 長時間 busy 表示は、まず非破壊の runtime notice / dashboard notice として実装し、AIへの割込みはしない。

## 検証計画

1. 変更対象 shell / Python の syntax check。
2. 関連 Bats / Python unit tests。
3. `make test` の該当範囲、可能なら `make package-check`。
4. 必要に応じて source runtime smoke。

## 進捗

- [x] Gunkan light watch の artifact path 解決を target project 優先に変更。
- [x] `target-project/app.js` のような target project basename prefix を欠落扱いしない回帰テストを追加。
- [x] Antigravity feedback prompt を `0` で自動 skip する runtime / watcher 処理を追加。
- [x] Codex pasted content が通常 watcher maintenance 中にも残っていたら Enter を追送する処理を追加。
- [x] bootstrap ready 待機の母数を、pending 状態で除外せず実 pane 数基準に変更。
- [x] 長時間 busy pane を `queue/runtime/long_busy_agents.tsv` に記録する非割込み notice を追加。
- [x] root tests と `shogunate_mod/tests` のミラーを同期。

## 検証結果

- PASS: `bash -n shogunate_mod/runtime/prompts.sh shogunate_mod/runtime/bootstrap.sh shogunate_mod/runtime/launch.sh shogunate_mod/watcher/inbox_watcher.sh`
- PASS: `python3 -m py_compile shogunate_mod/gunkan/light_watch.py`
- PASS: `bats tests/unit/test_gunkan_audit.bats tests/unit/test_send_wakeup.bats tests/unit/test_mux_parity.bats`
- PARTIAL: `make package-check` は Python / MOD behavior / generated freshness まで PASS 後、未コミット変更による dirty gate で停止。clean worktree で再実行する。

## 残リスク

- clean worktree で `make package-check` を再実行する。
- 実AIで再度30分超を回すかは、package check 後に判断する。
