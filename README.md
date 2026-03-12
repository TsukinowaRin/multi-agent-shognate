# multi-agent-shogun

このフォークは `yohey-w/multi-agent-shogun` の `tmux` 本線を基準に、CLI 対応を拡張した実行基盤です。

現役運用は `tmux` のみです。  
起動入口の本体は `shutsujin_departure.sh` です。  
俯瞰ビューとして `scripts/goza_no_ma.sh` による `御座の間` を使えます。  
`御座の間` は `shogun / karo / gunshi / ashigaru` の live mirror を並べる read-only 俯瞰です。  
`zellij` は廃止済みで、履歴が必要なら `Waste/` を参照します。

## このフォーク独自の差分
- `Gemini CLI`
- `OpenCode`
- `Kilo`
- `localapi`
- `Ollama` / `LM Studio` 用 provider 設定
- `gunshi` を含む役職別 CLI / model / thinking 設定

## 起動
セットアップのみ:
```bash
bash shutsujin_departure.sh -s
```

通常起動:
```bash
bash shutsujin_departure.sh
```

接続:
```bash
tmux attach-session -t shogun
tmux attach-session -t gunshi
tmux attach-session -t multiagent
bash scripts/goza_no_ma.sh
```

短縮 alias:
```bash
css   # 将軍
csg   # 軍師
csm   # 家老・足軽
cgo   # 御座の間
```

## 最短手順
```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
bash first_setup.sh
bash scripts/configure_agents.sh
bash shutsujin_departure.sh
```

御座の間だけ開く:
```bash
bash scripts/goza_no_ma.sh
```

backend が未起動なら明示:
```bash
bash scripts/goza_no_ma.sh --ensure-backend
```

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

補足:
- `Codex` / `Gemini` は、pane 内で変更した live の `model` / `reasoning` / 一部 `thinking` を、起動中に daemon が約1秒ごとに `config/settings.yaml` へ同期します。
- 即時同期の対象は現時点で `Codex` / `Gemini` のみです。
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
      type: opencode
      model: ollama/qwen3-coder:30b
    ashigaru4:
      type: kilo
      model: lmstudio/codellama-7b.Q4_0.gguf
  opencode_like:
    provider: ollama
    base_url: http://127.0.0.1:11434/v1
    instructions:
      - AGENTS.md
```

## Local AI
`OpenCode` / `Kilo` を使う場合は `scripts/sync_opencode_config.py` が `opencode.json` を生成します。

代表例:
- `provider: ollama`
- `base_url: http://127.0.0.1:11434/v1`
- `provider: lmstudio`
- `base_url: http://127.0.0.1:1234/v1`
- `provider: openai-compatible`
- `base_url: http://127.0.0.1:1234/v1`

## 主なスクリプト
- `shutsujin_departure.sh`
  - 本体。tmux セッション生成、CLI 起動、watcher 起動を行います。
- `scripts/goza_no_ma.sh`
  - `shogun / karo / gunshi / ashigaru` を優先度付きで一望する `tmux` 俯瞰ビューです。
- `scripts/configure_agents.sh`
  - `config/settings.yaml` を対話更新します。
- `scripts/build_instructions.sh`
  - 役職共通指示書から CLI 別 generated instructions を再生成します。
- `scripts/sync_gemini_settings.py`
  - `.gemini/settings.json` を同期します。
- `scripts/sync_opencode_config.py`
  - `opencode.json` を同期します。
- `scripts/history_book.sh`
  - 履歴要約（歴史書）を生成します。

## 前提
- `tmux`
- `python3`
- `inotifywait` (`sudo apt install -y inotify-tools`)
- 利用する CLI (`claude`, `codex`, `gemini`, `opencode`, `kilo`, `copilot`, `kimi` など)

## トラブルシュート
セッションを壊してやり直す:
```bash
tmux kill-session -t shogun 2>/dev/null || true
tmux kill-session -t gunshi 2>/dev/null || true
tmux kill-session -t multiagent 2>/dev/null || true
bash shutsujin_departure.sh
```

CLI 割当確認:
```bash
cat queue/runtime/agent_cli.tsv
```

watcher 確認:
```bash
tail -n 80 logs/inbox_watcher_shogun.log
tail -n 80 logs/inbox_watcher_karo.log
```
