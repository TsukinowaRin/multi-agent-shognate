# Upstream Sync Notes (2026-02-21)

対象上流: `yohey-w/multi-agent-shogun`  
比較基準: `upstream/main`（先頭 `cbad684`）

## 1) 確認した上流更新
- `b01d56b`: Codex 起動オプションに `--search` を追加。
- `300eafc`: `inbox_watcher` の Phase3 `/clear` を command-layer（`shogun/karo/gunshi`）で抑止。
- `cf4bd27` / `73e5623` 系: Codex の `/clear` を `/new` へ寄せる回帰テスト強化。

## 2) 本リポジトリへの反映
- 採用:
  - `lib/cli_adapter.sh`
    - Codex 起動コマンドを `codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen` に更新。
  - `scripts/inbox_watcher.sh`
    - Codex の escalation `/clear` 抑止を「command-layer のみ」に限定。
    - 対象: `shogun|gunshi|karo|karoN|karo_gashira`
- 既存維持:
  - zellij/tmux 両対応、多CLI（gemini/localapi 含む）分岐は本リポジトリ実装を維持。
  - Codex `/clear`→`/new` 変換ロジックは継続（上流方針と整合）。

## 3) 反映しなかった点
- 上流のファイルを丸ごと置換する同期は未実施。
  - 理由: 本リポジトリは zellij 純正モードや multi-CLI 拡張が進んでおり、単純置換で退行リスクが高い。

## 4) 実装時の追加修正（zellij 側）
- `scripts/goza_no_ma.sh`
  - pure zellij レイアウトで `Waiting to run` が残るケースに対応。
  - セッション作成直後、各ペインへ `Enter` を自動送信して command pane を実行開始。
  - 初動命令本文は従来どおり「各ペインTTYへの自己注入」を維持し、アクティブペイン誤注入を回避。

## 5) 検証観点
- `tests/unit/test_cli_adapter.bats`: Codex `--search` 期待値へ更新。
- `tests/unit/test_send_wakeup.bats`: command-layer の escalation 抑止ケースを追加。
- `tests/unit/test_goza_pure_bootstrap.bats`: pure zellij の command pane 自動解除（Enter送信）を追加。
