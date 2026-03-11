# multi-agent-shogun

このリポジトリは、将軍・軍師・家老・足軽の階層で複数 AI CLI を `tmux` 上で運用するための実行基盤です。

正式対応は `tmux` のみです。  
旧 zellij 実装は `Waste/zellij_2026-03-11/` に退避済みです。`scripts/goza_zellij.sh` などの旧コマンド名は、互換ラッパーとして tmux 起動へ委譲します。

## 起動コマンド

通常起動:
```bash
bash scripts/goza_tmux.sh
```

御座の間ビュー:
```bash
bash scripts/goza_tmux.sh --template goza_room
```

setup-only:
```bash
bash scripts/goza_tmux.sh -s
```

旧コマンド互換:
```bash
bash scripts/goza_zellij.sh
bash scripts/goza_zellij_pure.sh
bash scripts/goza_hybrid.sh
```

## 主なスクリプト

- `shutsujin_departure.sh`
  - 本体。tmux セッションを作成し、各 agent CLI を起動します。
- `scripts/goza_tmux.sh`
  - 公式フロントエンド。
- `scripts/goza_no_ma.sh`
  - tmux ビュー構築用の共通フロントエンド。
- `scripts/configure_agents.sh`
  - `config/settings.yaml` を対話更新します。

## 設定 CUI

```bash
bash scripts/configure_agents.sh
```

設定対象:
- `multiplexer.default` (`tmux` 固定)
- `startup.template`
- `topology.active_ashigaru`
- `cli.default`
- `cli.agents.shogun`
- `cli.agents.gunshi`
- `cli.agents.karo`
- `cli.agents.ashigaruN`
- `cli.opencode_like`

## 設定例

```yaml
language: ja
shell: bash
multiplexer:
  default: tmux
startup:
  template: goza_room
topology:
  active_ashigaru:
    - ashigaru1
    - ashigaru2
    - ashigaru3
    - ashigaru4
cli:
  default: codex
  agents:
    shogun:
      type: gemini
      model: auto
    gunshi:
      type: gemini
      model: auto
    karo:
      type: codex
      model: auto
    ashigaru1:
      type: codex
      model: auto
    ashigaru2:
      type: codex
      model: auto
    ashigaru3:
      type: gemini
      model: auto
    ashigaru4:
      type: gemini
      model: auto
```

## Local AI

`OpenCode` / `Kilo` を使う場合は `config/settings.yaml` の `cli.agents.*` と `cli.opencode_like` を設定します。  
`scripts/sync_opencode_config.py` が `opencode.json` を生成します。

代表例:
- `provider: ollama`
- `base_url: http://127.0.0.1:11434/v1`
- `provider: lmstudio`
- `base_url: http://127.0.0.1:1234/v1`

## 前提

- `tmux`
- `python3`
- `inotifywait` (`sudo apt install -y inotify-tools`)
- 使用する CLI (`codex`, `gemini`, `claude`, `opencode`, `kilo` など)

## 最短手順

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
bash first_setup.sh
bash scripts/goza_tmux.sh
```

## 歴史書

```bash
bash scripts/history_book.sh
sed -n '1,80p' queue/history/rekishi_book.md
```

## トラブルシュート

セッションを壊してやり直す:
```bash
tmux kill-session -t shogun 2>/dev/null || true
tmux kill-session -t multiagent 2>/dev/null || true
tmux kill-session -t gunshi 2>/dev/null || true
tmux kill-session -t goza-no-ma 2>/dev/null || true
bash scripts/goza_tmux.sh
```

`inbox_watcher` が動かない:
```bash
sudo apt install -y inotify-tools
```

CLI 割当確認:
```bash
cat queue/runtime/agent_cli.tsv
```
