# multi-agent-shogun

このフォークは `yohey-w/multi-agent-shogun` の `tmux` 本線を基準に、CLI 対応だけを拡張した版です。

現役運用は `tmux` のみです。  
起動入口は `shutsujin_departure.sh` のみです。  
`zellij` / `goza*` は廃止済みで、履歴が必要なら `Waste/` を参照します。

## このフォーク独自の対応
- `Gemini CLI`
- `OpenCode`
- `Kilo`
- `localapi`
- `Ollama` / `LM Studio` 向け provider 設定
- `gunshi` を含む役職別 CLI / model / thinking 設定

## クイックスタート
```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
bash first_setup.sh
bash scripts/configure_agents.sh
bash shutsujin_departure.sh
```

接続:
```bash
tmux attach-session -t shogun
tmux attach-session -t gunshi
tmux attach-session -t multiagent
```

## 設定 CUI
```bash
bash scripts/configure_agents.sh
```

設定できるもの:
- 有効な足軽人数
- 役職ごとの CLI 種別
- 役職ごとの model
- `Codex` の `reasoning_effort`
- `Gemini` の `thinking_level` / `thinking_budget`
- `OpenCode/Kilo` 用 provider 設定

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
`OpenCode` / `Kilo` は `scripts/sync_opencode_config.py` により `opencode.json` を生成して使います。

代表的な provider:
- `ollama`
- `lmstudio`
- `openai-compatible`

既定の接続先:
- `ollama` → `http://127.0.0.1:11434/v1`
- `lmstudio` → `http://127.0.0.1:1234/v1`
- `openai-compatible` → `http://127.0.0.1:1234/v1`

## 主なファイル
- `shutsujin_departure.sh`
  - tmux セッションを立ち上げ、CLI と watcher を起動する本体です。
- `lib/cli_adapter.sh`
  - 対応 CLI の抽象化レイヤーです。
- `scripts/configure_agents.sh`
  - `config/settings.yaml` を更新します。
- `scripts/build_instructions.sh`
  - CLI 別 generated instructions を再生成します。
- `scripts/sync_gemini_settings.py`
  - `.gemini/settings.json` を同期します。
- `scripts/sync_opencode_config.py`
  - `opencode.json` を同期します。

## 前提
- `tmux`
- `python3`
- `inotifywait` (`sudo apt install -y inotify-tools`)
- 使用する CLI 本体

## トラブルシュート
セッションをやり直す:
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
