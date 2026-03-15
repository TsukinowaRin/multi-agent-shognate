# multi-agent-shogun

このフォークは `yohey-w/multi-agent-shogun` の `tmux` 本線を基準に、CLI 対応だけを拡張した版です。

現役運用は `tmux` のみです。  
起動入口の本体は `shutsujin_departure.sh` です。  
実 runtime は `goza-no-ma:overview` を正本とする `tmux` セッションです。

- `goza-no-ma:overview` に `shogun / karo / gunshi / ashigaruN` の実 pane を配置
- Android 互換用に `shogun:main` / `gunshi:main` / `multiagent:agents` を proxy session として併設

`cgo` はこの本体 `goza-no-ma` を開きます。  
Android アプリは補助 proxy session を通して既存アプリのまま接続できます。  
`zellij` は廃止済みで、履歴が必要なら `Waste/` を参照します。

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
tmux attach-session -t goza-no-ma
tmux attach-session -t shogun     # Android 互換 proxy
tmux attach-session -t gunshi     # Android 互換 proxy
tmux attach-session -t multiagent # Android 互換 proxy
```

個別移動:
```bash
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh gunshi
bash scripts/focus_agent_pane.sh karo
```

短縮 alias:
```bash
css   # 将軍
csg   # 軍師
csm   # 家老
cgo   # 御座の間
```

御座の間を開く:
```bash
bash scripts/goza_no_ma.sh
```

backend が未起動なら明示:
```bash
bash scripts/goza_no_ma.sh --ensure-backend
```

御座の間を作り直す:
```bash
bash scripts/goza_no_ma.sh --refresh
```

## Android アプリ互換
upstream Android アプリはそのまま次の tmux target を前提に動きます。

- 将軍タブ: `shogun:main`
- エージェントタブ: `multiagent:0`
- ダッシュボード: `dashboard.md`

このフォークでは、実体は `goza-no-ma` に置いたまま、上記 target へは proxy session で互換を提供します。

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

補足:
- `Codex` / `Gemini` は、pane 内で変更した live の `model` / `reasoning` / 一部 `thinking` を、起動中に daemon が約1秒ごとに `config/settings.yaml` へ同期します。
- 即時同期の対象は現時点で `Codex` / `Gemini` のみです。

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
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: auto
      reasoning_effort: auto
    gunshi:
      type: codex
      model: auto
      reasoning_effort: auto
    karo:
      type: codex
      model: auto
      reasoning_effort: auto
    ashigaru1:
      type: codex
      model: auto
      reasoning_effort: auto
    ashigaru2:
      type: codex
      model: auto
      reasoning_effort: auto
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
  - `goza-no-ma:overview` に `shogun / karo / gunshi / ashigaruN` の実 pane を構築し、あわせて Android 互換 proxy session を起動する本体です。
- `scripts/goza_no_ma.sh`
  - 本体 `goza-no-ma` session を開く wrapper です。
- `scripts/focus_agent_pane.sh`
  - `goza-no-ma` 内の `shogun / karo / gunshi / ashigaruN` の実 pane へ直接移動します。
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
tmux kill-session -t goza-no-ma 2>/dev/null || true
tmux kill-session -t shogun 2>/dev/null || true
tmux kill-session -t gunshi 2>/dev/null || true
tmux kill-session -t multiagent 2>/dev/null || true
bash shutsujin_departure.sh
```

CLI 割当確認:
```bash
cat queue/runtime/agent_cli.tsv
```
