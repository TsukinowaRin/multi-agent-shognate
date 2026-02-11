# multi-agent-shogun (運用ガイド)

このリポジトリは、将軍・家老・足軽の階層で複数AI CLIを並列運用するための実行基盤です。  
現在の運用は **zellij モード** と **tmux モード** の両方に対応しています。

## いま使う起動コマンド

### 1. zellij モードで起動
```bash
bash scripts/goza_zellij.sh
```

### 2. tmux モードで起動
```bash
bash scripts/goza_tmux.sh
```

### 3. 単一コマンドでモード指定して起動
```bash
bash scripts/goza_no_ma.sh --mux zellij
bash scripts/goza_no_ma.sh --mux tmux
```

## 主要スクリプト

- `scripts/goza_zellij.sh`
  - `goza_no_ma.sh --mux zellij` のラッパー。
  - zellij バックエンドを起動し、tmux の「御座の間ビュー」に接続します。

- `scripts/goza_tmux.sh`
  - `goza_no_ma.sh --mux tmux` のラッパー。
  - tmux 既存フロー（`shogun` / `multiagent` セッション）で起動します。

- `scripts/goza_no_ma.sh`
  - 共通フロントエンド。
  - `--mux zellij|tmux` で明示的に起動モードを選択できます。
  - zellij モードでは御座の間ビュー（tmux）を作成してエージェントセッションへ attach します。

- `shutsujin_departure.sh`
  - 実際の出陣処理本体。
  - `config/settings.yaml` の `multiplexer.default` を参照。
  - 環境変数 `MAS_MULTIPLEXER=tmux|zellij` で設定を一時上書き可能。

## goza_no_ma オプション

```bash
bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]
```

- `--mux zellij|tmux`
  - 起動モードを指定（デフォルト: `zellij`）。
- `-s, --setup-only`
  - セッションのみ作成（CLI未起動）。
- `--view-only`
  - バックエンドを再起動せず、ビュー接続のみ。
- `--no-attach`
  - tmuxへ自動attachせず、ビュー作成のみ。
- `--session <name>`
  - 御座の間ビュー用の tmux セッション名（デフォルト: `goza-no-ma`）。

## 役職ごとのタブ色（御座の間ビュー）

タブ（ペイン見出し）だけ色が付く設計です。本文の文字色は変更しません。

- 将軍: 紫
- 家老: 紺
- 足軽: 茶

## クイックスタート

### 前提

- Bash
- Python 3
- `tmux`
- `zellij`（zellijモード時）
- 利用する CLI（`codex` / `gemini` / `claude` など）

### 初回

```bash
bash first_setup.sh
```

### 日次運用

```bash
# zellij で運用
bash scripts/goza_zellij.sh

# tmux で運用
bash scripts/goza_tmux.sh
```

## 設定ファイル

`config/settings.yaml` の代表項目:

```yaml
language: ja
shell: bash
multiplexer:
  default: zellij
topology:
  active_ashigaru:
    - ashigaru1
    - ashigaru2
cli:
  default: codex
  agents:
    ashigaru1:
      type: gemini
      model: gemini-2.5-pro
    ashigaru2:
      type: gemini
      model: gemini-2.5-pro
```

## トラブルシュート

- タブ色が変わらない
  - 既存ビューを破棄して再起動:
  ```bash
  tmux kill-session -t goza-no-ma 2>/dev/null || true
  bash scripts/goza_zellij.sh
  ```

- zellij モードで起動できない
  - `zellij --version` を確認。
  - 代替で tmux モードを使用:
  ```bash
  bash scripts/goza_tmux.sh
  ```

- 既存バックエンドを残して再接続したい
  ```bash
  bash scripts/goza_no_ma.sh --view-only --mux zellij
  ```

## 開発者メモ

- `scripts/goza_zellij.sh` / `scripts/goza_tmux.sh` は運用コマンドとして固定。
- `scripts/goza_no_ma.sh` は共通ロジックを持つため、機能追加はここを起点に行う。
- `shutsujin_departure.sh` 側は `MAS_MULTIPLEXER` によりモードを強制可能。
