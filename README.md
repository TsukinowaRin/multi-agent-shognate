# multi-agent-shogun

このリポジトリは、将軍・軍師・家老・足軽の階層で複数 AI CLI を `tmux` 上で運用するための実行基盤です。

現役の起動入口は `shutsujin_departure.sh` のみです。  
旧 `zellij` / `goza*` 実装は `Waste/` に退避しており、現役運用には含めません。

## 起動

セットアップのみ:
```bash
bash shutsujin_departure.sh -s
```

通常起動:
```bash
bash shutsujin_departure.sh
```

将軍本陣へ接続:
```bash
tmux attach-session -t shogun
```

家老・足軽陣へ接続:
```bash
tmux attach-session -t multiagent
```

軍師へ接続:
```bash
tmux attach-session -t gunshi
```

## 主なスクリプト

- `shutsujin_departure.sh`
  - 本体。tmux セッション生成、CLI 起動、watcher 起動を行います。
- `scripts/configure_agents.sh`
  - `config/settings.yaml` を対話更新します。
- `scripts/history_book.sh`
  - 履歴要約（歴史書）を生成します。

## 設定 CUI

```bash
bash scripts/configure_agents.sh
```

設定対象:
- `multiplexer.default` (`tmux` 固定)
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
bash shutsujin_departure.sh
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
bash shutsujin_departure.sh
```

`inbox_watcher` が動かない:
```bash
sudo apt install -y inotify-tools
```

CLI 割当確認:
```bash
cat queue/runtime/agent_cli.tsv
```
