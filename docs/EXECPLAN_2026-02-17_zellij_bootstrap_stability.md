# ExecPlan: zellij 初動注入の安定化

## Context
- 実機で zellij 起動時に初動命令の混線（別役職への誤注入）が断続発生している。
- 既存実装は「全CLI起動→全エージェントへ初動送信」で、`wait_for_cli_ready` 判定も広すぎるため未起動CLIへ送信される余地がある。
- 本件は運用開始時の品質を直接損なうため、優先度は高い。

## Scope
- `scripts/shutsujin_zellij.sh` の起動フローを、エージェント単位の順次処理へ変更する。
- CLI ready 判定を厳密化し、シェルプロンプト誤判定を除去する。
- 最小限の静的ユニットテストを追加し、回帰検知を入れる。
- `docs/REQS.md` / `docs/WORKLOG.md` を更新する。

## Acceptance Criteria
1. `scripts/shutsujin_zellij.sh` で「CLI起動→ready確認→初動送信」がエージェント単位で順次実行される。
2. `wait_for_cli_ready` でシェルプロンプト（`$`）に依存した ready 判定を行わない。
3. `bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats` が PASS する。
4. `bash -n scripts/shutsujin_zellij.sh` が PASS する。

## Work Breakdown
1. 現行の zellij 起動/初動送信フローを確認し、誤判定ポイントを特定。
2. ready 判定の厳密化（CLI種別パターン化）を実装。
3. 起動と初動送信を agent 単位直列化。
4. テスト追加・実行。
5. docs 更新（REQS/WORKLOG）。

## Progress
- 2026-02-17: ExecPlan を作成。
- 2026-02-17: `wait_for_cli_ready` の判定条件を CLI種別ベースへ変更し、`$` 依存を除去。
- 2026-02-17: 起動フローを agent 単位（起動→ready→送信）へ直列化。
- 2026-02-17: `tests/unit/test_zellij_bootstrap_delivery.bats` を追加し、静的回帰検証を追加。
- 2026-02-17: `bash -n scripts/shutsujin_zellij.sh` と `bats tests/unit/test_zellij_bootstrap_delivery.bats tests/unit/test_mux_parity.bats` がPASS。
- 2026-02-21: pure zellij の `Waiting to run` 停止を再現し、`scripts/goza_no_ma.sh` に command pane 自動開始（Enter送信）を追加。

## Surprises & Discoveries
- 従来の ready 判定は `\$` を含んでおり、CLI未起動でもシェル表示だけで ready 扱いになり得た。
- zellij 0.41 系では `start_suspended=false` 指定でも command pane が待機するケースがあり、実行開始トリガが別途必要だった。

## Decision Log
- D1: 並列起動より確実性を優先し、zellij起動を逐次化する。
- D2: ready 判定は CLI UI文字列ベースに限定し、シェル記号は除外する。
- D3: アクティブペインへの本文注入は再導入せず、Enterのみ外部送信して本文は各ペインTTY自己注入を維持する。

## Outcomes & Retrospective
- zellij の初動注入は「全体一括」から「エージェント単位順次」に変更され、混線リスクの主要因（未起動CLIへの早期送信）を下げた。
- ready 判定の誤検知源だったシェルプロンプト依存を撤去し、CLI画面文字列ベースへ切り替えた。
- 残課題は実機E2Eでの最終確認（特に Gemini 初回 trust 画面と高負荷時）であり、必要に応じて `MAS_ZELLIJ_BOOTSTRAP_GAP` の調整余地を残した。
- `Waiting to run` 由来で初動未注入に見えるケースの主要因を除去したため、以後の切り分けは `queue/runtime/goza_bootstrap_*.log` で行える状態になった。
