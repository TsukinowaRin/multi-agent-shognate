# Docs Index

最終更新: 2026-03-05

## Must-read
- `docs/DOCS_POLICY.md` - ドキュメント運用方針（index-first / 更新ルール）。
- `docs/PLANS.md` - ExecPlanの作成・更新規約。

## Specs
- `docs/REQS.md` - 直近ユーザー要求の正規化要件と受け入れ条件。
- `docs/philosophy.md` - システム設計思想（原則・背景）。
- `docs/ZELLIJ_AND_MULTI_CLI.md` - zellij運用とgemini/localapi拡張の実装メモ。
- `docs/UPSTREAM_SYNC_2026-02-14.md` - 上流multi-agent-shogunとの差分分析と採用/非採用判断。
- `docs/UPSTREAM_SYNC_2026-02-21.md` - 上流最新（cbad684時点）との差分確認と反映内容（Codex `--search` / watcher抑止条件 / zellij起動補正）。
- `docs/UPSTREAM_SYNC_2026-03-05.md` - 上流最新（86ee80b時点）の取得方法と反映差分（watcher busy保護 / zellij ACKログ）。
- `docs/HANDOVER_2026-02-14_codex_limit.md` - Codex利用制限前の引き継ぎ（現状/即対応/次アクション）。
- `docs/HANDOVER_2026-02-17_bootstrap_injection.md` - zellij初動注入混線の原因分析と暫定/恒久対策案。
- `docs/HANDOVER_2026-02-23_prompt_injection_open_issues.md` - 「起動するが注入されない」未解決事象の課題整理と次エージェント向け実行計画。

## Plans
- `docs/EXECPLAN_2026-02-10_zellij_multi_cli.md` - zellij移植とCLI拡張の実行計画。
- `docs/EXECPLAN_2026-02-12_role_instruction_sync.md` - 役職別正本MDの必読化と最適化MD自動同期の実行計画。
- `docs/EXECPLAN_2026-02-12_startup_event_driven.md` - 初動自動送信/イベント駆動安定化/履歴要約（歴史書）導入の実行計画。
- `docs/EXECPLAN_2026-02-14_multi_karo_round_robin.md` - 複数家老時の足軽均等割り振りと経路制約の実行計画。
- `docs/EXECPLAN_2026-02-14_mux_behavior_parity.md` - tmux/zellijのinbox初期化差異を解消し挙動同一化する実行計画。
- `docs/EXECPLAN_2026-02-14_upstream_sync.md` - 上流更新の差分取り込み（Codex model / watcher判定）の実行計画。
- `docs/EXECPLAN_2026-02-17_zellij_bootstrap_stability.md` - zellij初動注入の混線抑止（順次起動・ready判定厳密化）の実行計画。
- `docs/EXECPLAN_TEMPLATE.md` - ExecPlanテンプレート。

## Logs
- `docs/WORKLOG.md` - 実装途中の詳細ログ（チェックポイント記録）。
