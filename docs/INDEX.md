# Docs Index

最終更新: 2026-05-21

## Must-read
- `docs/DOCS_POLICY.md` - ドキュメント運用方針（index-first / 更新ルール）。
- `docs/PLANS.md` - ExecPlanの作成・更新規約。
- `docs/HANDOFF_2026-05-08_runtime_resume.md` - 新しいチャットで `codex/upstream-v4.6.0-sync` の runtime / Git / CLI 状態を再開するための最新 handoff。現状の正本。
- `docs/HANDOFF_2026-04-10_runtime_resume.md` - 旧 handoff。main repo の shared-auth runtime burn-in 経緯確認用。
- `docs/HANDOFF_2026-04-06_runtime_resume.md` - 旧 handoff。`Shogunate-test` 起点の経緯確認用。
- `docs/HANDOFF_2026-03-29_resume.md` - 旧 handoff。`Shogunate-test` 起点の経緯確認用。

## Specs
- `docs/REQS.md` - 直近ユーザー要求の正規化要件と受け入れ条件。2026-05-21 時点では Shogunate runtime での Agy keyring 起動、Gemini CLI 廃止と Antigravity CLI (`agy`) 対応、Antigravity keyring / Secret Service preflight、旧 installer asset 廃止と package distribution 移行を含む。
- `docs/PUBLISHING.md` - 公開前の個人情報・履歴・退避物の除外ポリシーと確認手順。
- `docs/philosophy.md` - システム設計思想（原則・背景）。
- `docs/NOTES_2026-03-29_portable_install_uninstall_release.md` - 旧 portable installer / uninstaller 事故対応の履歴。現行配布は package distribution を正とする。

## Plans (open)
- `docs/EXECPLAN_2026-05-20_antigravity_cli.md` - Gemini CLI 対応を廃止し、Antigravity CLI (`agy`) を runtime / 設定 UI / docs / tests に追加する計画。
- `docs/EXECPLAN_2026-05-18_package_distribution.md` - OS 別 installer asset を廃止し、GitHub Release package + cURL bootstrap + npm wrapper へ移行する計画。
- `docs/EXECPLAN_2026-05-14_shogunate_test_android_setup.md` - Shogunate-test へ最新コードを反映し、Shogun へのデモ制作依頼と Android 接続セットアップ UX 改善を並行して進める計画。
- `docs/EXECPLAN_2026-05-13_upstream_issue_apply.md` - 本家 open Issue (#151/#143/#48/#131) をこの fork に適用し、README / role instruction / pane mapping regression を同期する計画。
- `docs/EXECPLAN_2026-05-07_codd_integration.md` - CoDD (`yohey-w/codd-dev`) を標準 coherence gate として導入・更新する計画。
- `docs/EXECPLAN_2026-05-13_android_agent_targeting.md` - Android App から任意 agent へ送信し、Tailscale / USB 接続プロファイルで SSH セットアップを簡略化する計画。
- `docs/EXECPLAN_2026-05-07_runtime_role_config.md` - CLI種別と足軽数だけを設定し、Linux / Windows WSL / macOS launcher から起動できる簡易設定の計画。
- `docs/EXECPLAN_2026-05-06_cli_state_isolation.md` - 対応CLIのホスト認証利用と pane-local 設定 / モデル state 分離の計画。
- `docs/EXECPLAN_2026-05-06_isolated_mixed_cli_runtime.md` - 隔離コピーで指定された Gemini preview / GPT-5.5 / opencode 混在 runtime を起動検証する計画。
- `docs/EXECPLAN_2026-05-06_android_v4600_release.md` - upstream `v4.6.0` 同期後の Android / release 計画。installer asset 部分は package distribution 計画で置き換え。
- `docs/EXECPLAN_2026-05-06_upstream_v460_sync.md` - upstream `main` / v4.6.0 の最新変更を取り込み、fork 独自機能を保持して再検証する計画（完了）。
- `docs/EXECPLAN_2026-03-29_isolated_runtime_validation.md` - ワークスペース内 clone / sandbox で runtime を実起動し、実Codex認証待ち・trust prompt・rate-limit / usage-limit prompt・実タスク経路まで検証する計画。
- `docs/EXECPLAN_2026-04-05_codex_shared_auth.md` - Codex の role local `CODEX_HOME` を保ちながら、`auth.json` だけを repo-local shared path で共通化する実行計画。
- `docs/EXECPLAN_2026-03-29_upstream_v441_sync.md` - upstream `main` の v4.4.1 系更新をこの fork の独自機能と両立させて統合する計画。
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
- `docs/EXECPLAN_2026-02-14_multi_karo_round_robin.md` - 足軽7人以上で複数家老を実働させ、`karo1` を筆頭家老にする均等割り振りと経路制約の計画。
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

## Resume
- 新しいチャットで再開する場合は、`AGENTS.md` の後にこの `docs/INDEX.md` の Must-read を順に読む。
- 2026-05-08 時点の正本は `docs/HANDOFF_2026-05-08_runtime_resume.md`。最初に `cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && git status -sb` を実行し、branch / clean state / `.git` の `rw` を確認する。
