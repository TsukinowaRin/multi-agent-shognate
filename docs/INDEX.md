# Docs Index

最終更新: 2026-05-26

## Must-read

- `docs/REQS.md` - 現在の要求と受け入れ条件。
- `docs/EXECPLAN_2026-05-22_upstream_base_rebuild.md` - 最新 upstream base で Shogunate を再実装する計画。
- `docs/EXECPLAN_2026-05-22_upstream_agy_pr_local_models.md` - 本家 AGY-only PR と LocalAPI / Ollama / LM Studio 検証計画。

## Notes

- この branch は `upstream/main` を土台にして Shogunate 機能を再移植する作業用。
- 既存 Shogunate 実装の参照元は `codex/upstream-v4.6.0-sync`。
- `Shogunate` runtime の tmux 本体 session は `shogunate`、御座の間は `shogunate:goza` view。旧 `goza-no-ma` session は互換 fallback としてのみ扱う。
- watcher / bridge / runtime-pref daemon は `SHOGUNATE_SESSION_NAME` / `GOZA_SESSION_NAME` を引き継いで起動する。検証用に `shogunate-llm-demo` などの別 session 名を使う場合も、旧 `goza-no-ma` pane へ誤配信しないこと。
- 家老が `cmd_done` 後に差戻しを受けて同じ `cmd_id` / `timestamp` を再完了した場合、`completed_at` を含む完了 identity で将軍へ再通知する。古い `cmd_done` が inbox に残っていても、新しい完了は抑止しない。
- `Shutsujin.bat` は Codex TUI の表示安定化のため Shogunate attach 後に CLI を起動し、完了後は `cgo` / `CMA` などを打てる command shell へ移動する。旧手動 shell workflow は `Shutsujin.bat --no-attach` で使う。Windows debug 用に `Shutsujin-Clean.bat` と `Shutsujin-Resume.bat` を置く。alias は本家系 `csst` / `css` / `csm` と Shogunate 系 `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を併用する。
- CoDD は現行 Shogunate runtime へ統合しない。必要になった場合は分離した外部 gate / plugin として再評価する。
