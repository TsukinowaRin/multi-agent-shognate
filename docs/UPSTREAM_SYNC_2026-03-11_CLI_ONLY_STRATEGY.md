# Upstream Sync 2026-03-11: CLI-Only Strategy

## 要旨
- `upstream/main` を正本とし、このフォーク独自の差分は `tmux` 本線のまま CLI 対応を拡張する範囲へ限定する。
- `zellij` / `goza` / hybrid multiplexer は再導入しない。
- このフォークが保持する価値は multiplexer ではなく、`Gemini CLI` / `OpenCode` / `Kilo` / `localapi` / local provider 設定にある。

## 上流を正本にする理由
1. `shutsujin_departure.sh`、README、instructions、tests の本線が upstream 側で継続的に更新されている。
2. multiplexer を分岐させると、起動・watcher・初動注入・docs・test が同時に壊れる。
3. 一方で CLI 追加は `lib/cli_adapter.sh`、`scripts/configure_agents.sh`、`scripts/build_instructions.sh`、同期スクリプトへ閉じ込めやすい。

## このフォークで維持する独自差分
- `Gemini CLI` と thinking 設定同期
- `OpenCode`
- `Kilo`
- `localapi`
- `Ollama` / `LM Studio` provider 設定
- `gunshi` を含む役職別 CLI / model / thinking 設定

## このフォークで捨てる差分
- `zellij`
- `goza*`
- hybrid UI
- pure zellij bootstrap / resize / layout 系

## 実装方針
1. `upstream/main` の `tmux` 本線を基準に README / first_setup / shutsujin_departure を寄せる。
2. 独自差分は CLI 抽象化と設定系へ閉じ込める。
3. 廃止済み multiplexer 実装は `Waste/` に隔離し、現役運用からは切り離す。

## 影響範囲
- 現役運用: `bash shutsujin_departure.sh`
- 現役 multiplexer: `tmux` のみ
- 拡張対象: `cli_adapter` / configurator / instruction generation / provider sync
