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
- 2026-02-12 23:52 JST: `goza_zellij` を pure zellij化し、旧動作は `goza_hybrid.sh` へ分離。
- 2026-02-12 23:52 JST: tmux/hybrid起動で Gemini高負荷画面に対する自動 `Keep trying` 再試行を追加。
- 2026-02-13 22:20 JST: pure zellij の初動注入を「インデックス再フォーカス方式」へ変更し、`ashigaru2` 未注入（沈黙）を再発しにくい実装へ更新。
- 2026-02-13 22:20 JST: Gemini向け初動文面を `@AGENTS.md @instructions/...` の明示形式へ調整し、起動直後の読込失敗を低減。
- 2026-02-13 22:20 JST: Gemini初期ゲート（trust/high-demand）に対し、軽い先行入力を追加して初動投入成功率を改善。
- 2026-02-13 22:45 JST: pure zellij の初動注入を各pane内TTY送信方式へ切替（外部フォーカス注入を停止）し、足軽増員時の注入先ずれリスクを低減。
- 2026-02-13 23:20 JST: 足軽番号の上限固定（1..8）を撤廃し、`ashigaru9+` を許容するよう `shutsujin_departure.sh` / `shutsujin_zellij.sh` / `goza_no_ma.sh` / `configure_agents.sh` を更新。
- 2026-02-13 23:20 JST: `watcher_supervisor.sh` を動的足軽配備 + pane不一致再同期 + escalation無効デフォルトに更新し、偽通知ループを抑止。

## Surprises & Discoveries
- `inbox_watcher` で Codex向け `/clear -> /new` 変換がPhase3エスカレーションからも発火し、作業中割り込みを誘発していた。
- zellij custom layout を使うと既定status/helpバーが無効になるため、明示的plugin指定が必要。
- snap配布zellijはこの実行環境の権限制約で直接起動検証ができず、layoutの実機検証はユーザーWSL実行で確認する必要がある。

## Decision Log
- D1: watcherは「配信不能時の最終復旧」より「対話中断回避」を優先し、デフォルトでエスカレーション無効化する。
- D2: Geminiの既定は固定バージョンではなく最新Pro系名（`gemini-3-pro`）へ更新する。
- D3: 歴史書は新規daemonを増やさず、`inbox_write` 完了時に生成して運用コストを抑える。
- D4: 初動命令はCLI起動確認後に送信し、入力欄残留（手動Enter要求）を回避する。
- D5: 「zellij操作を優先したい」要求に合わせ、`goza_zellij` を pure zellij にし、俯瞰用途は `goza_hybrid` へ分離。
- D6: pure zellij の注入順は「現在フォーカス依存」ではなく「将軍アンカーからの再フォーカス」に固定し、レイアウト差で先ずれしない方針を採用。
- D7: GeminiはCLI起動直後の対話ゲートが不安定なため、初動命令の前に軽いゲート通過入力を入れる。
- D8: 足軽増員時の安定性を優先し、pure zellij は「pane内TTYへ直接送信」を正とする（フォーカス移動型注入は採用しない）。
- D9: 足軽上限は固定しない方針とし、`ashigaruN (N>=1)` を正規名として受け付ける。
- D10: watcher の同期ずれ対策は「再起動」ではなく「pane-target一致検証と stale watcher 再生成」を優先する。

## Outcomes & Retrospective
- 主要要求（自動初動送信、イベント駆動抑制、言語統一、Gemini既定更新、歴史書生成、zellij操作バー追加）を実装完了。
- watcher割り込みの根本（Phase3 `/clear`）を既定で抑制したため、`/new is disabled while a task is in progress` 再発リスクを低減。
- 残リスク: Gemini API側の高負荷自体は解消不能であり、自動再試行は対症療法。
- 追加残リスク: pane内TTY送信でも、CLI側が初回画面で入力受理しない場合があり、待機秒数の微調整は環境差で必要になりうる。
- 追加残リスク: 足軽を極端に増やすと tmux の tiled レイアウト可読性が低下するため、実運用ではテンプレート/UI分割方針の追加調整が必要。
