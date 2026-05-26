# Docs Index

最終更新: 2026-05-26

## Must-read

- `docs/REQS.md` - 現在の要求と受け入れ条件。
- `docs/EXECPLAN_2026-05-22_upstream_base_rebuild.md` - 最新 upstream base で Shogunate を再実装する計画。
- `docs/EXECPLAN_2026-05-22_upstream_agy_pr_local_models.md` - 本家 AGY-only PR と LocalAPI / Ollama / LM Studio 検証計画。

## Notes

- この branch は `upstream/main` を土台にして Shogunate 機能を再移植する作業用。
- 既存 Shogunate 実装の参照元は `codex/upstream-v4.6.0-sync`。
- `Shutsujin.bat` は Codex TUI の表示安定化のため Goza attach 後に CLI を起動し、完了後は `cgo` / `CMA` などを打てる command shell へ移動する。旧手動 shell workflow は `Shutsujin.bat --no-attach` で使う。Windows debug 用に `Shutsujin-Clean.bat` と `Shutsujin-Resume.bat` を置く。alias は本家系 `csst` / `css` / `csm` と Shogunate 系 `cgo` / `csa` / `csg` / `csk` / `ckr` / `cma` を併用する。
