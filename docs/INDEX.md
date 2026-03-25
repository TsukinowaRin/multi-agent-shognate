# Docs Index

最終更新: 2026-03-25

## Must-read
- `docs/DOCS_POLICY.md` - ドキュメント運用方針（index-first / 更新ルール）。
- `docs/PLANS.md` - ExecPlanの作成・更新規約。

## Specs
- `docs/REQS.md` - 直近ユーザー要求の正規化要件と受け入れ条件。
- `docs/PUBLISHING.md` - 公開前の個人情報・履歴・退避物の除外ポリシーと確認手順。
- `docs/philosophy.md` - システム設計思想（原則・背景）。

## Plans (open)
- `docs/EXECPLAN_2026-03-25_android_host_update.md` - Android APK から host 側 Shogunate 更新を停止後に安全適用する実行計画（完了）。
- `docs/EXECPLAN_2026-03-17_codex_role_isolation.md` - Codex の model / reasoning state を role ごとに repo-local `CODEX_HOME` へ分離する実行計画（完了）。
- `docs/EXECPLAN_2026-03-17_multi_cli_gaps.md` - `inbox_watcher.sh` / `switch_cli.sh` / `ratelimit_check.sh` に残る opencode / kilo / gemini 未対応箇所の修正計画（完了）。
- `docs/EXECPLAN_2026-03-17_readme_refresh.md` - README 英日をこの fork の実配布・実運用に合わせて全面更新する実行計画（完了）。
- `docs/EXECPLAN_2026-03-16_upstream_layout_alignment.md` - 最新 upstream 同期済みの確認と、現役ファイル構成を upstream に寄せる整理計画。
- `docs/EXECPLAN_2026-03-14_android_compat.md` — upstream Android app compatibility check and options.
- `docs/EXECPLAN_2026-03-11_tmux_only_consolidation.md` - zellij 廃止と tmux 一本化、Waste 退避の実行計画（完了: zellij 廃止済み）。
- `docs/EXECPLAN_2026-03-11_tmux_goza_return.md` - tmux 専用の御座の間復活と `csg/cgo` 導線追加の実行計画。
- `docs/EXECPLAN_2026-03-11_runtime_cli_pref_sync.md` - tmux pane の live CLI 設定を次回起動前に settings へ同期する実行計画。
- `docs/EXECPLAN_2026-03-11_upstream_cli_only_rebase.md` - upstream `main` 正本化と CLI 拡張差分の再整理計画。
- `docs/EXECPLAN_2026-02-12_role_instruction_sync.md` - 役職別正本MDの必読化と最適化MD自動同期の実行計画。
- `docs/EXECPLAN_2026-02-12_startup_event_driven.md` - 初動自動送信/イベント駆動安定化/履歴要約（歴史書）導入の実行計画。
- `docs/EXECPLAN_2026-02-14_multi_karo_round_robin.md` - 複数家老時の足軽均等割り振りと経路制約の実行計画。
- `docs/EXECPLAN_2026-02-14_upstream_sync.md` - 上流更新の差分取り込み（Codex model / watcher判定）の実行計画。

## Plans (superseded / historical)
- `docs/EXECPLAN_2026-02-10_zellij_multi_cli.md` - 旧 zellij 移植とCLI拡張の実行計画（zellij 廃止により無効）。
- `docs/EXECPLAN_2026-02-14_mux_behavior_parity.md` - tmux/zellijのinbox初期化差異を解消し挙動同一化する実行計画（zellij 廃止により無効）。
- `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md` - zellij初動注入の混線抑止（zellij 廃止により無効）。
- `docs/EXECPLAN_2026-03-06_zellij_gemini_upstream_sync.md` - 上流同期を zellij / Gemini スコープに絞って修正する計画（zellij 廃止により無効）。
- `docs/EXECPLAN_2026-03-07_upstream_restart_zellij_gemini.md` - 上流基盤へ戻しつつ zellij / Gemini を再実装する再出発計画（zellij 廃止により無効）。
- `docs/EXECPLAN_TEMPLATE.md` - ExecPlanテンプレート。

## Archive
- `Waste/` / `_trash/` / `_upstream_reference/` - ローカル archive / 退避 / upstream 参照用。公開対象外。

## Logs
- 実運用ログ、引き継ぎメモ、upstream 詳細同期ノートはローカル保持とし、公開対象外。
