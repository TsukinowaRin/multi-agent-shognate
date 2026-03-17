<div align="center">

# multi-agent-shognate

**複数の AI エージェントを戦国の軍制で動かす、tmux / Zellij マルチエージェント基盤**

fork of [multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) — extended for multi-CLI and Zellij.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-bash-green)]()
[![CLIs](https://img.shields.io/badge/CLI-Claude%20|%20Codex%20|%20Gemini%20|%20Copilot%20|%20LocalAPI-blue)]()

</div>

---

## これは何か

`claude`、`codex`、`gemini` などの AI CLI を **複数のターミナルペインで並列に動かし、役割ごとに連携させる**基盤。

各エージェントは独立したペインで動作し、YAML ファイルベースのメッセージパッシングで連携する。通信はポーリングなし — `inotifywait` による純粋なイベント駆動。エージェントは自分の inbox が更新されたときだけ起きる。

```
あなた (Lord)
  └─ Shogun    ── 方針策定・タスク分解・家老への委任
       ├─ Karo       ── 並列度決定・足軽への割り当て・QC・ルーティング
       │    └─ Ashigaru × N  ── 実コーディング・調査・テスト
       └─ Gunshi     ── 戦略立案・設計判断（Thinking モデル専任）
```

---

## upstream との違い

| 機能 | upstream | this fork |
|---|---|---|
| 対応 CLI | claude / codex / copilot / kimi | + **Gemini / OpenCode / Kilo / localapi** |
| マルチプレクサ | tmux のみ | **tmux + Zellij**（pure / hybrid モード） |
| ビュー | 手動 tmux セッション切替 | `goza-no-ma` — 全エージェントを1画面に集約 |
| 設定方法 | YAML 直接編集 | **`configure_agents.sh`** インタラクティブ TUI |
| Codex 状態 | セッション共有 | **役職ごとに `CODEX_HOME` を分離**（VSCode と干渉しない） |
| Gemini thinking | 未対応 | `thinking_level` / `thinking_budget` をエージェントごとに設定可能 |
| Karo ルーティング | 標準 | **Bloom フィルタ QC ルーティング**（Gunshi トークンコスト最適化） |

---

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│                   御座の間 (goza-no-ma)                       │
│                                                               │
│  ┌─────────────┬─────────────┬───────────────────────────┐   │
│  │   shogun    │   gunshi    │  karo   |  ashigaru × N   │   │
│  │  (任意 CLI) │  (Thinking) │  (任意) |     (任意)      │   │
│  └──────┬──────┴──────┬──────┴────────┬──────────────────┘   │
└─────────│─────────────│──────────────│──────────────────────┘
          │             │              │
          └─────────────┴──────────────┘
                YAML mailbox — inotifywait ベース、ポーリングなし
                queue/inbox/{agent}.yaml
                queue/tasks/ashigaru{N}.yaml
                queue/reports/{agent}_report.yaml
```

**通信の仕組み**: 書き手が `inbox_write.sh` で YAML を更新 → `inotifywait` が検知 → `inbox_watcher.sh` が対象エージェントのペインに短い wake-up signal を `tmux send-keys` → エージェントが自分の inbox を read して処理。**メッセージ本文は tmux を一切通らない。**

---

## クイックスタート

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh

# 全エージェント起動
bash shutsujin_departure.sh
```

Windows（WSL2 Ubuntu 前提）は `install.bat` をダブルクリック。

起動後、将軍ペインに話しかけるだけでよい:

```
あなた: 「auth モジュールのリファクタを全体設計から始めてほしい」
Shogun: タスク分解して Karo に委任
Karo:   足軽を 3 名アサイン、並列で着手
Ashigaru 1-3: コーディング・テスト・レビュー
```

---

## マルチプレクサの選択

### tmux（デフォルト）

```bash
bash shutsujin_departure.sh         # エージェント起動
bash scripts/goza_no_ma.sh          # 御座の間（全ペイン一画面）を開く
```

### Zellij

```bash
# Pure Zellij — ネイティブ Zellij UI + バックエンド
bash scripts/goza_zellij.sh --template goza_room

# Hybrid — tmux バックエンド + Zellij UI（既存 tmux セッションを Zellij で表示）
bash scripts/goza_hybrid.sh --template goza_room
```

Windows ダブルクリック:

| ファイル | モード |
|---|---|
| `start_tmux_goza.bat` | ネイティブ tmux |
| `start_zellij_pure.bat` | Pure Zellij |
| `start_zellij_goza.bat` | Hybrid（tmux + Zellij UI） |

Zellij モードでのレイアウト（KDL が自動生成される）:

```
┌────────────────────────────────────────────────────┐
│ tab: 御座の間 (zellij-core)                         │
│                                                     │
│ ┌──────────┬──────────┬──────────────────────────┐  │
│ │ shogun   │ karo     │ ashigaru1                │  │
│ │          │          ├──────────────────────────┤  │
│ ├──────────┤          │ ashigaru2                │  │
│ │ gunshi   │          │                          │  │
│ └──────────┴──────────┴──────────────────────────┘  │
└────────────────────────────────────────────────────┘
```

---

## CLI の設定

### インタラクティブ TUI

```bash
bash scripts/configure_agents.sh
```

役職ごとに設定できる:

- CLI 種別（claude / codex / gemini / copilot / kimi / opencode / kilo / localapi）
- モデル（opus / sonnet / gemini-2.5-pro / auto / ...）
- Codex reasoning effort（low / medium / high）
- Gemini thinking level（minimal / low / medium / high）+ thinking budget（token 数）
- アクティブ足軽数

### settings.yaml による直接設定

```yaml
cli:
  default: codex
  agents:
    shogun:
      type: claude
      model: opus
    gunshi:
      type: gemini
      model: gemini-2.5-pro
      thinking_level: high
      thinking_budget: 16000
    karo:
      type: codex
      model: auto
    ashigaru1:
      type: claude
      model: sonnet
    ashigaru2:
      type: gemini
      thinking_level: minimal
```

### 対応 CLI

| CLI | デフォルト起動オプション | 備考 |
|---|---|---|
| `claude` | `--dangerously-skip-permissions` | |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` | 役職ごとに `CODEX_HOME` 分離 |
| `gemini` | `--yolo` | thinking_level / budget 対応 |
| `copilot` | `--yolo` | |
| `kimi` | `--yolo` | |
| `opencode` | `opencode.json` 自動生成（permission: allow） | |
| `kilo` | 同上 | |
| `localapi` | `localapi_repl.py` | Ollama / LM Studio / llama.cpp 対応 |

### Codex 状態分離

```bash
# 役職ごとに CODEX_HOME を持つ → VSCode の Codex と完全分離
~/.codex/shogun/     # 将軍のモデル設定・会話履歴
~/.codex/karo/       # 家老の設定
~/.codex/ashigaru1/  # ...
```

---

## inbox_watcher の設計

### ポーリングをやめた理由

エージェントがループで inbox を読み続けるとトークンを消費し続ける。代わりに:

1. **書き手**が `inbox_write.sh` で YAML を更新
2. **`inotifywait`** がファイル変更イベントを検知（WSL2 向け 30 秒フォールバックつき）
3. **`inbox_watcher.sh`** が対象ペインに `tmux send-keys` で wake-up signal（`inbox3` など）を送信
4. **エージェント**が自分の inbox を read して処理

nudge はごく短い文字列のみ。**メッセージ本文は tmux を通らない**。

### 未読放置時のエスカレーション

| 経過時間 | アクション | 備考 |
|---|---|---|
| 0〜2 分 | 標準 nudge（send-keys） | Working 中はスキップ |
| 2〜4 分 | Escape×2 + nudge | カーソル位置バグ対処 |
| 4 分〜 | `/clear` 送信（5 分に1回まで） | 強制リセット + YAML 再読 |

### ホットスワップ

実行中のエージェントを停止せずに CLI を切り替えられる:

```bash
bash scripts/switch_cli.sh karo gemini
# karo の CLI を codex → gemini に切り替え（inbox_watcher 自動再起動）
```

---

## ファイル構成

```
multi-agent-shognate/
├── shutsujin_departure.sh      # 全エージェント起動エントリポイント
├── lib/
│   ├── cli_adapter.sh          # CLI 抽象化レイヤー（8 CLI 対応）
│   ├── topology_adapter.sh     # 足軽台数・役職構成の読み取り
│   └── inbox_path.sh           # inbox パス解決
├── scripts/
│   ├── goza_no_ma.sh           # 御座の間（tmux/Zellij ビュー）
│   ├── goza_zellij.sh          # Pure Zellij 起動
│   ├── goza_hybrid.sh          # Hybrid 起動（tmux backend + Zellij UI）
│   ├── configure_agents.sh     # インタラクティブ設定 TUI
│   ├── inbox_watcher.sh        # イベント駆動 inbox 監視（inotifywait）
│   ├── inbox_write.sh          # エージェント間メッセージ送信
│   ├── shogun_to_karo_bridge.py    # 将軍→家老コマンドキュー処理
│   ├── karo_done_to_shogun_bridge.py  # 家老完了通知の集約
│   ├── switch_cli.sh           # 実行中エージェントの CLI をホットスワップ
│   ├── slim_yaml.sh            # YAML タスク・レポートの肥大化抑制
│   ├── watcher_supervisor.sh   # ウォッチャー障害検知・自動再起動
│   └── ratelimit_check.sh      # CLI レートリミット監視
├── instructions/
│   ├── generated/              # build_instructions.sh が生成する CLI 別指示書
│   └── *.md                    # 役職共通指示書
├── config/
│   └── settings.yaml           # ローカル設定（git-ignored）
└── queue/
    ├── inbox/                  # エージェント間 YAML メールボックス
    ├── tasks/                  # 家老→足軽タスク割り当て
    └── reports/                # 足軽→家老完了レポート
```

---

## テスト

```bash
bats tests/unit/    # ユニットテスト（183 ケース）
make test           # CI と同じ full suite
```

---

## upstream からの移行

このフォークは upstream の YAML スキーマ・inbox 形式・エージェント指示書を維持している。`config/settings.yaml` と `queue/` を持ち込めばそのまま動く:

```bash
cp /path/to/upstream/config/settings.yaml config/settings.yaml
bash first_setup.sh
bash shutsujin_departure.sh
```

---

## 関連ドキュメント

- [`AGENTS.md`](AGENTS.md) — エージェントプロトコル・コマンドフォーマット定義
- [`lib/cli_adapter.sh`](lib/cli_adapter.sh) — CLI 抽象化レイヤーの API リファレンス
- [`scripts/configure_agents.sh`](scripts/configure_agents.sh) — 設定 TUI
- [`docs/`](docs/) — 設計書・要件定義
