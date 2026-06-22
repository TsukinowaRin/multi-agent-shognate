# Docs Index

最終更新: 2026-06-21

## Must-read

- `docs/REQS.md` - 現在の要求と受け入れ条件。
- `docs/EXECPLAN_2026-05-22_upstream_base_rebuild.md` - 最新 upstream base で Shogunate を再実装する計画。
- `docs/EXECPLAN_2026-05-22_upstream_agy_pr_local_models.md` - 本家 AGY-only PR と LocalAPI / Ollama / LM Studio 検証計画。
- `docs/EXECPLAN_2026-05-28_gunkan_role.md` - Shogunate 独自の軍監 role 追加計画。
- `docs/EXECPLAN_2026-05-28_upstream_v5_1_sync.md` - 本家 `upstream/main` v5.1.0 反映計画と検証記録。
- `docs/EXECPLAN_2026-06-10_upstream_v5_2_test_runtime.md` - 本家 `upstream/main` v5.2.0 反映と `Shogunate-test` 再起動計画。
- `docs/EXECPLAN_2026-06-10_android_release_local_install.md` - Android APK release とこのPCへの release package install 計画。
- `docs/EXECPLAN_2026-06-15_android_wireless_pair.md` - Android app から PC 側 `shogunate pair` へ USB/Tailscale/LAN 共通の初回 pairing を行う計画。
- `docs/EXECPLAN_2026-06-16_cwd_project_runtime.md` - `cd project && shogunate` と project ごとの並列 runtime / Pair 統合計画。
- `docs/EXECPLAN_2026-06-16_upstream_core_mod_split.md` - 本家 Shogun core + Shogunate MOD 構造へ移行する計画。
- `docs/EXECPLAN_2026-06-21_runtime_sync_mod.md` - 実AI runtimeで見つかった command/report/dashboard/Gunkan 同期不整合をMOD側で直す計画。
- `docs/EXECPLAN_2026-06-21_optimization_harnesses.md` - 最適化 advisory と role/CLI harness をMOD正本へ追加する計画。
- `docs/EXECPLAN_2026-06-21_real_machine_harness_test.md` - harness refresh 後の source/package/runtime/Android 実機検証計画。
- `docs/EXECPLAN_2026-05-30_android_setup.md` - Android app の SSH / tmux target 設定改善計画。
- `docs/EXECPLAN_2026-05-31_android_host_setup.md` - Android app の USB/無線 SSH セットアップと将軍単体表示計画。

## Notes

- この branch は `upstream/main` を土台にして Shogunate 機能を再移植する作業用。
- 既存 Shogunate 実装の参照元は `codex/upstream-v4.6.0-sync`。
- `Shogunate` runtime の tmux 本体 session は `shogunate`、御座の間は `shogunate:goza` view。旧 `goza-no-ma` session は互換 fallback としてのみ扱う。
- watcher / bridge / runtime-pref daemon は `SHOGUNATE_SESSION_NAME` / `GOZA_SESSION_NAME` を引き継いで起動する。検証用に `shogunate-llm-demo` などの別 session 名を使う場合も、旧 `goza-no-ma` pane へ誤配信しないこと。
- 家老が `cmd_done` 後に差戻しを受けて同じ `cmd_id` / `timestamp` を再完了した場合、`completed_at` または command/dashboard の完了指紋を含む identity で将軍へ再通知する。古い `cmd_done` が inbox に残っていても、新しい完了は抑止しない。
- `Shutsujin.bat` は Codex TUI の表示安定化のため Shogunate attach 後に CLI を起動し、完了後は `cgo` / `CMA` などを打てる command shell へ移動する。旧手動 shell workflow は `Shutsujin.bat --no-attach` で使う。Windows debug 用に `Shutsujin-Clean.bat` と `Shutsujin-Resume.bat` を置く。alias は本家系 `csst` / `css` / `csm` と Shogunate 系 `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を併用する。
- CoDD は現行 Shogunate runtime の常駐LLM処理には統合しない。軍監が監査時に MOD 正本 `shogunate_mod/gunkan/codd_audit.py` 経由でオンデマンド実行し、`codd` CLI がない環境では repo-local `.shogunate/codd-venv/` へ `codd-dev` を bootstrap する。導入失敗時だけ組み込み整合性チェックへフォールバックする。`codd` は `PATH` または repo-local venv から検出する。CoDD graph 用の tracked config は `.codd/codd.yaml`、frontmatter docs は `docs/codd/`。
- 軍監（`gunkan`）は Shogunate 独自の将軍直属・家老並列の独立監査 role。主務はセキュリティチェック、システム監視、違反チェック、危険操作検知、報告矛盾検出であり、通常の中間報告取得は `将軍 -> 家老` の仕事として残す。軍監LLMは常時トークン消費する監視AIではない。通常メッセージは非LLMの `queue/runtime/gunkan_events.yaml` に記録し、非LLMの MOD 正本 `shogunate_mod/gunkan/light_watch.py` が異常だけを `audit_requested` として軍監へ送る。軽量 watcher は YAML parse、失敗 report、done command と failed report/open task/dashboard の矛盾、完了 report の成果物 path 欠落、worker_id 不一致、secret/destructive diff を検出する。軍監LLMは `queue/inbox/gunkan.yaml` の `audit_requested` / `audit_failed` / `runtime_blocked` / `emergency_stop_requested` 等で起きる event-driven 監査役として扱う。`direct_message` / `question` / `message` / `chat` または将軍・ユーザー由来の明示メッセージでは会話応答として起きるが、通常の `report_received` では起きない。直接会話でも軍監 persona と冷静・厳格な戦国口調を維持する。canonical report は `queue/reports/gunkan_report.yaml`。軍師は家老配下の参謀・高度QC役のまま。
- Shogunate 系 alias は `cgo` / `csa` / `cgn` / `csg` / `csk` / `ckr` / `cma`。`cgn` は軍監 pane へフォーカスする。
- Android app の将軍タブ既定 target は `agent:shogun`。これは実 tmux target ではなく、`@agent_id=shogun` の pane を自動検出する仮想 target。設定画面の通常導線は `ワンタッチ接続` で、従来の SSH 詳細入力は `マニュアルモード` 配下。通常画面の `接続先` 欄は DNS 名、URL、Tailscale IP、LAN IP を入力中に SSH 用 host/port へ正規化し、URL path/query/fragment は無視する。通常導線は `USB` / `無線` / `接続` に絞り、接続設定リンク貼付、接続診断、接続先反映、標準に戻すボタンは表示しない。USB 接続は `127.0.0.1:2222`、無線接続は前回の無線 host/port を復元し、入力された到達可能な DNS/IP/URL を使う。`shogunate pair` は USB reverse を自動試行しつつ Tailscale/LAN でも待ち受け、端末名確認後の Pair Password prompt 承認で Android app 内生成鍵の公開鍵だけを PC へ登録する。source checkout helper の `--pair-usb` は互換 alias として統合 Pair を起動する。
- Android APK の `versionName` は Shogunate 本体バージョン + fork/app 改訂番号にする。例: 本体 `5.2.0` の Android 側1回目の改訂は `5.2.0.1`。`versionCode` は同じ更新順に単調増加させる。
- npm package の `version` は semver 制約に従うため、同じ意味の改訂番号は `5.2.0-1` のように表す。
- cURL package installer は既定で engine を `~/.shogunate/shogunate` に展開し、`~/.local/bin/shogunate` を登録する。`cd <project> && shogunate` が正本導線で、project ごとの runtime copy は `~/.shogunate/workspaces/<slug>-<hash>/` に作る。`first_setup.sh` より先に command shim を更新するため、依存不足で setup が途中停止しても `shogunate pair` / `shogunate help` は最新化される。PATH に `~/.local/bin` が入っていれば `shogunate` だけで起動できる。package 展開後の helper scripts は executable bit が無くても `bash` 経由で使える前提にする。
- README / README_ja は package install 前提の導入正本。固定導入例は最新 release tag の cURL command を使い、通常 release tag は `v5.2.0.1`, `v5.2.0.2`, `v5.2.0.3` のように `-preview` なしで進める。
- `shogunate pair` は Android app の初回 setup 用。既定で呼び出し元 cwd の project runtime を対象にし、USB reverse を自動試行しつつ Tailscale/LAN でも待ち受ける。`shogunate pair --usb` は廃止し、package command は `shogunate pair` に統一する。Android app は app 内秘密鍵を保持し、PC 側は端末名確認後の Pair Password prompt 承認で公開鍵だけを `~/.ssh/authorized_keys` へ追加する。成功後は PC 側が best-effort でその project の Shogunate runtime を起動し、以後は登録済み SSH 鍵で直接接続する。Pair response の `project` は Android dashboard 用の runtime root、`target_project` は実作業 directory。既定では1台成功後に `Pairing complete` を表示して自動終了し、複数端末を続けて登録する場合だけ `--keep-running` を使う。SSH port は TCP open だけでなく SSH banner で検出し、壊れた Windows portproxy / stale forwarding を避ける。USB は `127.0.0.1`、無線は app が入力した PC address に対して SSH banner を返す port を選び、Pair terminal は app へ返した `user@host:port` を表示する。
