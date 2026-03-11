# ExecPlan: upstream restart for zellij / gemini

## Context
- ユーザーは、コピー元で内部構造が大きく変わったため、実装を最初からやり直してよいと明示した。
- 上流 2026-03 時点では `agent_status` や `AGENTS.md` が進化しており、このフォークの古い基盤より整っている。

## Scope
- 上流共通基盤の再採用
- `zellij` 対応
- `Gemini CLI` 対応
- 関連 Docs とテスト

## Acceptance Criteria
- 上流基盤の一部が本ワークツリーに再導入される。
- 置換前ファイルは `_trash/restart_2026-03-07_core/` に退避される。
- watcher は `lib/agent_status.sh` を用いた busy 判定に更新される。
- 次段の `shutsujin_departure.sh` / `cli_adapter.sh` 再構築方針が文書化される。

## Work Breakdown
1. REQS を再定義する。
2. 置換前ファイルを退避する。
3. 上流 `AGENTS.md` と `lib/agent_status.sh` を導入する。
4. watcher を上流 busy 判定基盤へ接続する。
5. 次段で `shutsujin_departure.sh` / `cli_adapter.sh` / `build_instructions.sh` を上流ベースで再構築する。

## Progress
- 2026-03-07: 再出発方針を採用。
- 2026-03-07: 旧基盤を `_trash/restart_2026-03-07_core/` に退避し、`AGENTS.md` と `lib/agent_status.sh` を上流基準へ更新。
- 2026-03-07: 上流完全クローン `original_full_2026-03-07` を基準参照として追加し、追跡可能な `Waste/` を正式な退避先として使う方針へ更新。
- 2026-03-07: pure zellij の bootstrap 再失敗を受け、`goza_zellij.sh` を安定経路（zellij UI + tmux backend）へ戻し、pure zellij は `goza_zellij_pure.sh` へ分離。
- 2026-03-07: pure zellij の bootstrap を「外側のアクティブペイン注入」から「paneごとの dedicated runner + bootstrap file」へ切り替えた。
- 2026-03-07: `configure_agents.sh` を拡張し、`gunshi` / `Codex reasoning_effort` / `Gemini thinking_level|thinking_budget` を永続設定できるようにした。
- 2026-03-07: `scripts/sync_gemini_settings.py` を追加し、workspace `.gemini/settings.json` の `customAliases` へ per-agent Gemini 設定を同期するようにした。
- 2026-03-07: `OpenCode` / `Kilo` を CLI種別として追加し、`scripts/sync_opencode_config.py` で project-level `opencode.json` を生成、`configure_agents.sh` から shared provider 設定も保存できるようにした。
- 2026-03-09: `Ollama` / `LM Studio` を `OpenCode/Kilo` 用 provider として明示化し、`base_url` 未指定時の既定URL補完と `first_setup.sh` の存在確認/案内を追加した。
- 2026-03-09: 実機ログで `shogun` の Gemini implicit alias (`mas-shogun`) が UX と初動安定性を損ねたため、Gemini は explicit thinking 指定時のみ alias を生成する方針へ変更した。
- 2026-03-09: `pure zellij` の Codex 起動は、起動引数へ本文を即埋め込む方式をやめ、pane 内 PTY runner が `update prompt` / `ready pattern` を見てから bootstrap を送る方式へ変更した。
- 2026-03-09: agent 自己識別は `tmux display-message` 固定をやめ、`AGENT_ID` 優先に変更した。これにより `ashigaru1` が `ashigaru4` と誤認する混線を防ぐ。
- 2026-03-09: `goza_zellij_pure.sh -s` と通常起動が同じ session 名を共有しないよう変更し、setup-only pane command が次回通常起動へ残留する回帰を防いだ。

## Surprises & Discoveries
- 上流とこのフォークは merge base を素直に辿れないほど履歴が離れている。
- よって Git 履歴マージではなく、ファイル単位での基盤再採用が現実的。

## Decision Log
- 全面削除ではなく「退避して再採用」を選ぶ。
- まず runtime 安全性に寄与する `AGENTS.md` / `agent_status` / watcher から着手する。
- `README_ja.md` の全面同期は runtime が再整備されてから行う。
- shallow 参照ではなくフルクローン参照を正本とする。
- 退避先は `_trash/` のみではなく、追跡可能な `Waste/` にも置く。
- pure zellij は保持するが、ユーザー向け既定コマンドには使わない。理由は実機で「CLI未起動・初動未注入」が継続しているため。
- pure zellij の本文配送は multiplexer 注入でなく file-based bootstrap に寄せる。理由は upstream の inbox 設計が「本文はファイル、multiplexer は起床通知のみ」であり、現状の focus 依存注入は agent 取り違えを起こしているため。
- Gemini の思考設定は CLIフラグ直指定ではなく `.gemini/settings.json` 生成を採用する。理由は公式 schema が `modelConfigs.customAliases` を前提としており、role ごとの恒久設定と相性がよいため。
- Codex の思考設定は `-c model_reasoning_effort='<value>'` を採用する。理由は現行 CLI が `-c key=value` オーバーライドを正式に受け付けているため。
- OpenCode と Kilo は同系統の CLI なので、project provider 設定は `opencode.json` へ一本化し、role ごとの差は `config/settings.yaml` の `type/model` に閉じ込める。理由は provider/base URL/API key まで role ごとに持たせるより設定の一貫性が高いため。
- `ollama` と `lmstudio` は free-form provider ではなく、CUI に明示選択肢を出して既定URLを持たせる。理由は local-AI 導線としてのセットアップを短縮し、`base_url` 手入力ミスを減らすため。
- Gemini の implicit alias 既定は採用しない。理由は Shogun pane で `model mas-shogun` 表示となり、実機ログ上も `Auto (Gemini 3)` より初動停滞の切り分けが難しくなったため。
- `pure zellij` の interactive CLI は、pane 内 PTY runner を採用する。理由は `Codex` update prompt と ready 待ちを multiplexer 外側で扱うと、active pane 依存や timing race が避けられないため。
- agent 自己識別の正本は `AGENT_ID` とし、`tmux display-message` は tmux fallback に限定する。理由は pure `zellij` では `@agent_id` が正本にならず、実機で足軽 ID 混線を起こしたため。
- `pure zellij` の setup-only は既定で専用 session 名を使う。理由は `GOZA_SETUP_ONLY=true` を焼いた setup-only layout が通常起動用 session に残ると、次回通常起動でも全paneが shell のままになるため。

## Outcomes & Retrospective
- 進行中。次段は `scripts/zellij_agent_bootstrap.sh` の実機確認、および `OpenCode/Kilo/Ollama/LM Studio` の README 導線補強と実機起動確認。
- 2026-03-11: pure zellij の wide 画面可用性改善として、`shogun` を full-height 左列、`karo` を full-height 中列、`gunshi` を右列上段、足軽を右列下段 grid に再配置した。従来の `shogun/gunshi` 左列縦積みは wide 画面での情報密度と操作性が悪かったため採用しない。
- 2026-03-11: pure zellij の nested PTY runner は、child PTY の winsize 更新に加えて child process group へ `SIGWINCH` を送るよう変更した。これにより WSL ウィンドウリサイズ時の `Codex` / `Gemini` TUI 再レイアウトを tmux に近づける。
- 2026-03-11: pure zellij の画面サイズ差を吸収するため、起動時 terminal 幅から `wide / normal / narrow` を auto 判定する layout profile を追加した。runtime 中の live 構造変更は pure zellij の static layout 制約により別課題とする。
- 2026-03-11: upstream `2ef81f9` の compaction recovery 修正を先行反映した。upstream では `CLAUDE.md` のみ更新だが、このフォークでは `AGENTS.md` / `copilot-instructions` / `agents/default/system.md` も root instruction なので、同一の `Post-Compaction Recovery` 節を横展開した。
