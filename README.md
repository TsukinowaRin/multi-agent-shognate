# multi-agent-shogun (運用ガイド)

このリポジトリは、将軍・家老・足軽の階層で複数AI CLIを並列運用するための実行基盤です。  
現在は次の3モードを用途で使い分けます。  
- **純正 zellij**: backend=zellij, ui=zellij（zellij操作をそのまま使う）
- **hybrid**: backend=tmux, ui=zellij（御座の間の俯瞰表示向け）
- **tmux**: backend=tmux, ui=tmux（従来運用）
既定テンプレートは `shogun_only`（将軍セッションへ直接アタッチ）です。

## いま使う起動コマンド

### 1. 純正 zellij モードで起動
```bash
bash scripts/goza_zellij.sh
```

### 2. hybrid モードで起動（zellij表示 + tmux内部）
```bash
bash scripts/goza_hybrid.sh
```

### 3. tmux モードで起動
```bash
bash scripts/goza_tmux.sh
```

### 4. 単一コマンドでモード指定して起動
```bash
bash scripts/goza_no_ma.sh --mux zellij --ui zellij
bash scripts/goza_no_ma.sh --mux tmux --ui zellij
bash scripts/goza_no_ma.sh --mux tmux --ui tmux
```

### 5. 全体俯瞰テンプレートで起動（御座の間）
```bash
bash scripts/goza_hybrid.sh --template goza_room
bash scripts/goza_tmux.sh --template goza_room
```

## 主要スクリプト

- `scripts/goza_zellij.sh`
  - `goza_no_ma.sh --mux zellij --ui zellij` のラッパー。
  - 純正zellij運用（zellij操作をそのまま利用）。

- `scripts/goza_hybrid.sh`
  - `goza_no_ma.sh --mux tmux --ui zellij` のラッパー。
  - 御座の間俯瞰（tmux内部運用をzellijで表示）向け。

- `scripts/goza_tmux.sh`
  - `goza_no_ma.sh --mux tmux --ui tmux` のラッパー。
  - tmux 既存フロー（`shogun` / `multiagent` セッション）で起動します。

- `scripts/goza_no_ma.sh`
  - 共通フロントエンド。
  - `--mux`（バックエンド）と `--ui`（表示）を分離して指定できます。
  - `goza_room` は pure zellij でも複数ペイン表示に対応（ネストした zellij attach ではなく、1セッション内ペインで直接起動）。
  - 役職別の色付き罫線演出は `hybrid` / `tmux` 側で提供します。

- `shutsujin_departure.sh`
  - 実際の出陣処理本体。
  - `config/settings.yaml` の `multiplexer.default` を参照。
  - 環境変数 `MAS_MULTIPLEXER=tmux|zellij` で設定を一時上書き可能。

## goza_no_ma オプション

```bash
bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]
```

- `--mux zellij|tmux`
  - バックエンド起動モードを指定（デフォルト: `zellij`）。
- `--ui zellij|tmux`
  - 表示モードを指定（未指定時は `--mux` と同じ）。
- `-s, --setup-only`
  - セッションのみ作成（CLI未起動）。
- `--view-only`
  - バックエンドを再起動せず、ビュー接続のみ。
- `--no-attach`
  - tmuxへ自動attachせず、ビュー作成のみ。
- `--session <name>`
  - 御座の間ビュー用の tmux セッション名（デフォルト: `goza-no-ma`）。
- `--template shogun_only|goza_room`
  - 表示テンプレートを選択（デフォルト: `shogun_only`）。
- `TMUX_VIEW_WIDTH` / `TMUX_VIEW_HEIGHT`
  - 御座の間ビュー作成時の tmux 仮想サイズを上書き（デフォルト: `200x60`）。

## 構成CUI（足軽人数・CLI割り当て）

`config/settings.yaml` を対話で更新するCUIを用意しています。

```bash
bash scripts/configure_agents.sh
```

設定できる内容:

- `topology.active_ashigaru`（足軽人数/配備）
- `cli.default`
- `cli.agents`（`shogun` / `karo` / `ashigaruN` ごとの `type` / `model`）
- `multiplexer.default`
- `startup.template`

## 役職ごとのタブ色（御座の間ビュー）

御座の間ビュー（tmux）では、枠線色を役職別に分けます。本文の文字色は変更しません。

- 将軍: 紫
- 家老: 紺
- 足軽: 茶

補足:
- この配色は `tmux` の御座の間ビュー（`goza_no_ma.sh`）で適用されます。
- `goza_zellij.sh` 利用時は zellij UI 上で tmux画面を操作するため、役職色は tmux 側の設定が反映されます。

## 操作方法（zellij表示時）

`goza_hybrid.sh` は「zellij UI + tmux backend」です。  
見た目は zellij タブですが、ペイン操作は tmux 側で行います。

- 起動直後のアクティブペイン: 将軍（`shogun`）
- ペイン切替（推奨）: マウスで将軍ペインをクリック
- ペイン切替（キーボード）:
  - `Ctrl+b` → 矢印キー（方向移動）
  - `Ctrl+b` → `o`（次のペイン）

人間が将軍とだけ会話する運用なら、起動後はそのまま左の将軍ペインに入力すれば動作します。

補足:
- 純正 zellij（`goza_zellij.sh`）では zellij標準操作がそのまま使えます。
- hybrid（`goza_hybrid.sh`）では tmux操作が必要です。

## クイックスタート

### 前提

- Bash
- Python 3
- `tmux`
- `zellij`（zellijモード時）
- `inotifywait`（`inbox_watcher` を使う場合。`sudo apt install -y inotify-tools`）
- 利用する CLI（`codex` / `gemini` / `claude` など）

### 初回

```bash
bash first_setup.sh
```

### 日次運用

```bash
# 純正 zellij で運用（既定: shogun_only）
bash scripts/goza_zellij.sh

# hybrid（zellij表示 + tmux内部）で運用
bash scripts/goza_hybrid.sh

# tmux で直接運用（既定: shogun_only）
bash scripts/goza_tmux.sh

# 全体俯瞰（御座の間）で運用
bash scripts/goza_zellij.sh --template goza_room
bash scripts/goza_hybrid.sh --template goza_room
bash scripts/goza_tmux.sh --template goza_room
```

`tmux` モードでも `config/settings.yaml` の `topology.active_ashigaru` に追従して、家老+指定足軽人数で起動します。
起動バナーの「足軽配備人数」表示も `topology.active_ashigaru` の人数に連動します。

## 設定ファイル

`config/settings.yaml` の代表項目:

```yaml
language: ja
shell: bash
multiplexer:
  default: zellij
startup:
  template: shogun_only
topology:
  active_ashigaru:
    - ashigaru1
    - ashigaru2
cli:
  default: codex
  agents:
    ashigaru1:
      type: gemini
      model: gemini-3-preview
    ashigaru2:
      type: gemini
      model: gemini-3-preview
```

## CLI割り当て例（Codex / Gemini / LocalAPI）

役職ごとにCLIを混在できます。以下は将軍・家老を `codex`、足軽を `gemini` と `localapi` に分ける例です。

```yaml
cli:
  default: codex
  agents:
    shogun:
      type: codex
      model: gpt-5
    karo:
      type: codex
      model: gpt-5
    ashigaru1:
      type: gemini
      model: gemini-3-preview
    ashigaru2:
      type: localapi
      model: qwen2.5-coder
```

`localapi` は `python3 scripts/localapi_repl.py` で起動され、以下の環境変数を参照します。

- `LOCALAPI_BASE_URL`（例: `http://127.0.0.1:11434/v1`）
- `LOCALAPI_API_KEY`
- `LOCALAPI_MODEL`

## WSL再起動後の最短手順

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
bash scripts/goza_zellij.sh
```

セッション確認は次のコマンドをそのまま実行します（括弧や補足文を付けない）。

```bash
zellij list-sessions -n
```

## 歴史書（会話履歴要約）

人間向け要約は `queue/history/rekishi_book.md` に自動生成されます。

```bash
bash scripts/history_book.sh
sed -n '1,80p' queue/history/rekishi_book.md
```

## トラブルシュート

- タブ色が変わらない
  - 既存ビューを破棄して再起動（hybrid/tmux）:
  ```bash
  tmux kill-session -t goza-no-ma 2>/dev/null || true
  bash scripts/goza_hybrid.sh
  ```
  - 反映確認（役職別の色付きヘッダ書式）:
  ```bash
  tmux show-options -w -t goza-no-ma:overview | rg '^pane-border-format'
  ```

- `Claude Code CLI not found` で止まる
  - 現在は未導入CLIを自動フォールバックします。意図したCLIで固定したい場合は `config/settings.yaml` の `cli.default` / `cli.agents` を明示してください。

- 枠色/背景色はどこで変えるか
  - 御座の間（`goza_no_ma.sh`）の枠色は、このリポジトリ側で制御しています（役職別に自動適用）。
  - `zellij attach` で直接開いた画面の配色は zellij テーマ設定の影響を受けます。こちらはユーザー環境側（`~/.config/zellij/config.kdl` など）で調整する方式です。

- zellij UI モードで起動できない
  - `zellij --version` を確認。
  - 代替で tmux モードを使用:
  ```bash
  bash scripts/goza_tmux.sh
  ```

- Gemini が `We are currently experiencing high demand` を出す
  - API側の混雑です（CLIバグではありません）。
  - tmux/hybrid起動では `Keep trying` を自動選択するよう対策済みです。
  - 継続する場合はモデルを軽量に変更してください（例: `gemini-2.5-flash`）。

- `size missing` が出る
  - 御座の間ビューの仮想サイズ不足が原因です。次で再実行してください。
  ```bash
  TMUX_VIEW_WIDTH=220 TMUX_VIEW_HEIGHT=70 bash scripts/goza_zellij.sh --template goza_room
  ```

- 既存バックエンドを残して再接続したい
  ```bash
  bash scripts/goza_no_ma.sh --view-only --mux tmux --ui zellij
  ```

- Codex/Gemini が起動していないように見える
  - `-s`（setup-only）を付けていないコマンドで起動しているか確認。
  - `inotifywait` がないと watcher は起動しません（対話自体は可能ですが、通知連携は無効）。
  ```bash
  sudo apt install -y inotify-tools
  ```
  - 起動割り当て確認:
  ```bash
  cat queue/runtime/agent_cli.tsv
  ```
  - watcherログ確認:
  ```bash
  tail -n 80 logs/inbox_watcher_shogun.log
  tail -n 80 logs/inbox_watcher_karo.log
  ```

## 開発者メモ

- `scripts/goza_zellij.sh` / `scripts/goza_tmux.sh` は運用コマンドとして固定。
- `scripts/goza_no_ma.sh` は共通ロジックを持つため、機能追加はここを起点に行う。
- `shutsujin_departure.sh` 側は `MAS_MULTIPLEXER` によりモードを強制可能。
- テンプレート定義は `templates/multiplexer/tmux_templates.yaml` と `templates/multiplexer/zellij_templates.yaml`。
