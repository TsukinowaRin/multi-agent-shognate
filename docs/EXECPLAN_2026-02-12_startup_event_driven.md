# ExecPlan: Startup Event-Driven Stabilization

## Context
- 起動直後の初動命令がCLIの準備前に投入され、手動Enterが必要になるケースがある。
- `inbox_watcher` のエスカレーションが Codex で `/clear -> /new` を誘発し、`/new is disabled while a task is in progress` で割り込みが発生している。
- 言語設定・連携順序・報告フローの明示が不足し、将軍/家老/足軽の役割挙動にブレが出る。
- Geminiモデル指定が古く、運用設定とREADMEが乖離している。
- 人間向けの会話履歴要約（歴史書）が存在しない。
- zellij UI（tmux backend表示）で下部操作バーが表示されず、操作性が下がっている。

## Scope
- 対象:
  - `shutsujin_departure.sh`
  - `scripts/shutsujin_zellij.sh`
  - `scripts/inbox_watcher.sh`
  - `scripts/goza_no_ma.sh`
  - `lib/cli_adapter.sh`
  - `scripts/inbox_write.sh`
  - 新規 `scripts/history_book.sh`
  - `config/settings.yaml`
  - `README.md`
  - `tests/unit/test_cli_adapter.bats`（必要最小限）
- 非対象:
  - 外部CLIそのもの（Codex/Gemini/Claude）の挙動変更
  - ワークスペース外の設定ファイル編集

## Acceptance Criteria
1. 起動初動:
   - 起動後、初動命令が自動送信され、ユーザーが手動Enterを追加しなくても進行する。
2. watcher安定化:
   - 通常運用で watcher の Phase3 `/clear` が発火しない設定がデフォルトで適用される。
3. 言語統一:
   - `config/settings.yaml` の `language` を初動命令へ反映し、全エージェントに適用される。
4. Geminiモデル:
   - 既定モデルが最新Pro系（`gemini-3-pro`）へ更新される。
5. 歴史書:
   - `queue/history/rekishi_book.md` が生成され、最新cmd/タスク/報告の要約が確認できる。
6. zellij UI補助バー:
   - zellij layout に tab/status bar plugin が含まれる。

## Work Breakdown
1. 現状解析
   - watcherログと起動フローを再確認。
2. 起動フロー修正
   - 初動命令の投入タイミングと文面を調整。
   - 言語・イベント駆動・連携順序・報告フローを明文化。
3. watcher抑制
   - 起動時の watcher 環境変数を統一し、過剰エスカレーションを抑止。
4. Gemini既定更新
   - adapter/config/docs/testsのモデル指定を更新。
5. 歴史書導入
   - 生成スクリプト追加、inbox書込フックで更新。
6. zellij UI操作補助
   - layoutへstatus/tab bar pluginを追加。
7. テスト・整合
   - 構文チェック、bats、README/REQS/WORKLOG更新。

## Progress
- 2026-02-12 23:20 JST: ExecPlan作成。要件を `docs/REQS.md` に追補し、実装対象を確定。
- 2026-02-12 23:23 JST: 起動系（tmux/zellij）の初動命令文面を改修し、`ready:<agent>` 即時送信 + 言語規則 + イベント駆動 + 報告連鎖を注入。
- 2026-02-12 23:23 JST: watcher起動時の既定envを全役職で `ASW_DISABLE_ESCALATION=1` / `ASW_PROCESS_TIMEOUT=0` に統一。
- 2026-02-12 23:24 JST: `scripts/history_book.sh` を新規追加し、`inbox_write.sh` および起動スクリプトから自動生成を接続。
- 2026-02-12 23:24 JST: zellij UI layoutへ `tab-bar` / `status-bar` pluginを追加。
- 2026-02-12 23:24 JST: Gemini既定モデルを `gemini-3-pro` へ更新（adapter/config/README/tests）。
- 2026-02-12 23:24 JST: `bash -n` と `bats`（108件）で検証PASS。

## Surprises & Discoveries
- `inbox_watcher` で Codex向け `/clear -> /new` 変換がPhase3エスカレーションからも発火し、作業中割り込みを誘発していた。
- zellij custom layout を使うと既定status/helpバーが無効になるため、明示的plugin指定が必要。
- snap配布zellijはこの実行環境の権限制約で直接起動検証ができず、layoutの実機検証はユーザーWSL実行で確認する必要がある。

## Decision Log
- D1: watcherは「配信不能時の最終復旧」より「対話中断回避」を優先し、デフォルトでエスカレーション無効化する。
- D2: Geminiの既定は固定バージョンではなく最新Pro系名（`gemini-3-pro`）へ更新する。
- D3: 歴史書は新規daemonを増やさず、`inbox_write` 完了時に生成して運用コストを抑える。
- D4: 初動命令はCLI起動確認後に送信し、入力欄残留（手動Enter要求）を回避する。

## Outcomes & Retrospective
- 主要要求（自動初動送信、イベント駆動抑制、言語統一、Gemini既定更新、歴史書生成、zellij操作バー追加）を実装完了。
- watcher割り込みの根本（Phase3 `/clear`）を既定で抑制したため、`/new is disabled while a task is in progress` 再発リスクを低減。
- 残リスク: zellij UI plugin表示は実機TTY環境での最終確認が必要。
