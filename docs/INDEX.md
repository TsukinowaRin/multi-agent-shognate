# Docs Index

最終更新: 2026-05-28

## Must-read

- `docs/REQS.md` - 現在の要求と受け入れ条件。
- `docs/EXECPLAN_2026-05-22_upstream_base_rebuild.md` - 最新 upstream base で Shogunate を再実装する計画。
- `docs/EXECPLAN_2026-05-22_upstream_agy_pr_local_models.md` - 本家 AGY-only PR と LocalAPI / Ollama / LM Studio 検証計画。
- `docs/EXECPLAN_2026-05-28_gunkan_role.md` - Shogunate 独自の軍監 role 追加計画。

## Notes

- この branch は `upstream/main` を土台にして Shogunate 機能を再移植する作業用。
- 既存 Shogunate 実装の参照元は `codex/upstream-v4.6.0-sync`。
- `Shogunate` runtime の tmux 本体 session は `shogunate`、御座の間は `shogunate:goza` view。旧 `goza-no-ma` session は互換 fallback としてのみ扱う。
- watcher / bridge / runtime-pref daemon は `SHOGUNATE_SESSION_NAME` / `GOZA_SESSION_NAME` を引き継いで起動する。検証用に `shogunate-llm-demo` などの別 session 名を使う場合も、旧 `goza-no-ma` pane へ誤配信しないこと。
- 家老が `cmd_done` 後に差戻しを受けて同じ `cmd_id` / `timestamp` を再完了した場合、`completed_at` を含む完了 identity で将軍へ再通知する。古い `cmd_done` が inbox に残っていても、新しい完了は抑止しない。
- `Shutsujin.bat` は Codex TUI の表示安定化のため Shogunate attach 後に CLI を起動し、完了後は `cgo` / `CMA` などを打てる command shell へ移動する。旧手動 shell workflow は `Shutsujin.bat --no-attach` で使う。Windows debug 用に `Shutsujin-Clean.bat` と `Shutsujin-Resume.bat` を置く。alias は本家系 `csst` / `css` / `csm` と Shogunate 系 `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を併用する。
- CoDD は現行 Shogunate runtime の常駐LLM処理には統合しない。軍監が監査時に `scripts/gunkan_codd_audit.py` 経由でオンデマンド実行し、`codd` CLI がない環境では組み込み整合性チェックへフォールバックする。`codd` は `PATH` または repo-local `.shogunate/codd-venv/` から検出する。CoDD graph 用の tracked config は `.codd/codd.yaml`、frontmatter docs は `docs/codd/`。
- 軍監（`gunkan`）は Shogunate 独自の将軍直属・家老並列の独立監査 role。通常の中間報告取得は `将軍 -> 家老` の仕事で、軍監LLMは常時トークン消費する監視AIではない。通常メッセージは非LLMの `queue/runtime/gunkan_events.yaml` に記録し、非LLMの `scripts/gunkan_light_watch.py` が異常だけを `audit_requested` として軍監へ送る。軍監LLMは `queue/inbox/gunkan.yaml` の `audit_requested` / `audit_failed` / `runtime_blocked` / `emergency_stop_requested` 等で起きる event-driven 監査役として扱う。canonical report は `queue/reports/gunkan_report.yaml`。軍師は家老配下の参謀・高度QC役のまま。
- Shogunate 系 alias は `cgo` / `csa` / `cgn` / `csg` / `csk` / `ckr` / `cma`。`cgn` は軍監 pane へフォーカスする。
