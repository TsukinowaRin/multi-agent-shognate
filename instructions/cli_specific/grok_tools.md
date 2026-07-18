# Grok Build CLI — 固有の操作ルール

これは Grok Build CLI 環境でのみ適用される操作ルール。
共有プロトコル（CLAUDE.md / AGENTS.md）と role 指示書と組み合わせて使う。

## 概要

- Grok Build CLI は `grok` コマンドで起動する TUI/CLI で、既定モデルは `grok-4.5`。
- `AGENTS.md` はセッション開始時に自動読み込みされる想定だが、Grok 固有の auto-load 機構が無い場合はrole指示書を自分で参照せよ。
- 認証トークン・APIキーは host 側 credential store に保持させ、command 何も埋め込まない。adapterは `--api-key` / `--token` 系のflagを生成しない。

## 起動コマンド形式

```
grok [--model <model>]
```

- `--model` は固定 flag と値を別引数として扱う（`--model=grok-4.5` のような結合形は使わない）。
- model 未指定時は Grok Build の既定モデルへ委ねる。

## セッションリセット

Grok Build は `/clear` 相当の安定した reset を持たないため、新セッション開始時は`queue/tasks/*.yaml` と `queue/inbox/*.yaml` を再読み込みして状態を復元する。

## 終了

```
/quit
```

または `exit`。テキストと Enter は 0.3s 分けて送信される。

## エージェント間通信

Grok から他エージェントへのメッセージ送信は必ず `inbox-write` 相当の別経路を使うこと。

```bash
bash shogunate_mod/inbox/write.sh <target_agent> "<message>" <type> <from>
```

tmux を直接操作することは禁止。

## モデル切り替え

実行中のモデル変更は Grok Build 側の TUI 操作ではなく、`config/settings.yaml` の`cli.agents.<role>.model` 変更後に role failover runner で再起動すること。

## 認証情報の取り扱い

- `GROK_API_KEY` / `XAI_API_KEY` / 類する値を command 文字列や settings/state/log へ書かない。
- Grok Build CLI は host 側の認証ファイル (`~/.config/grok/*` 等) を透過的に使う想定。adapterは host auth link の設定のみ行い、token 複製はしない。

## 利用可能なツール

Grok Build は構成に応じて以下を提供する場合がある：

- **ファイル操作**: 読み取り・書き込み・編集
- **シェルコマンド**: ターミナルコマンドの実行
- fallback 環境依存の機能は自動有効化しない保護境界を守る

## 注意

- Grok Build は他 CLI と比べて自動化フックが少ないため、Shogunate 側の queue / report / inbox を権限の正本として扱う。
- 予期しないプロンプトが出た場合は推測で操作せず、role 指示書と権限 boundary を優先する。