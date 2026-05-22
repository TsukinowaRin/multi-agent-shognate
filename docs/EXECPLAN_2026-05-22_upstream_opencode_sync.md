# ExecPlan: upstream OpenCode support sync

作成日: 2026-05-22

## 目的

`yohey-w/multi-agent-shogun` の最新 `upstream/main` を取得し、v5.0.0 系で追加された OpenCode first-class support を、この fork の Shogunate runtime に本家準拠で取り込む。

## 方針

- 全体 merge は行わない。upstream は docs / installer / Android / CoDD / Antigravity 周辺で fork と大きく違うため、OpenCode 関連の設計だけ選択的に取り込む。
- 本家準拠にする対象:
  - `.opencode/agents/*.md` を `scripts/build_instructions.sh` で生成する。
  - `opencode --agent <agent_id>` を使う。
  - `OPENCODE_TUI_CONFIG=config/opencode-tui.json` を使う。
  - `config/opencode-permissions.yaml` から role boundary frontmatter を生成する。
  - OpenCode reset は `/new`、モデル変更は relaunch-only とする。
  - `variant:` は TUI に渡さず、git-ignored runtime agent に同期する。
- fork 側で維持する対象:
  - Antigravity CLI (`agy`) 対応。
  - Kilo / LocalAPI / package distribution / Android UX 改善。
  - host auth 共有 + role-local settings / model state 分離。
  - shell に戻った OpenCode pane の role-local 起動 command 復旧。

## 進捗

- [x] `git fetch upstream --prune --tags` を実行し、`upstream/main` が `84c8e82` へ更新された。既存 tag clobber は発生したが branch fetch は成功。
- [x] upstream の OpenCode 関連 commit / files を確認した。
- [x] `config/opencode-tui.json` / `config/opencode-permissions.yaml` / `.opencode/tools/mark-as-read.ts` を追加する。
- [x] `lib/cli_adapter.sh` に `--agent` / `OPENCODE_TUI_CONFIG` / runtime variant agent を統合する。
- [x] `scripts/build_instructions.sh` で `.opencode/agents/*.md` を生成する。
- [x] `scripts/switch_cli.sh` と watcher の OpenCode reset/model handling を本家準拠へ寄せる。
- [x] tests / docs を更新し、検証する。

## 検証

1. `bash -n lib/cli_adapter.sh scripts/build_instructions.sh scripts/switch_cli.sh scripts/inbox_watcher.sh`
2. `bash scripts/build_instructions.sh`
3. `bats tests/unit/test_cli_adapter.bats tests/unit/test_build_system.bats tests/unit/test_switch_cli.bats tests/unit/test_send_wakeup.bats`
4. `git diff --check`

## 結果

- `scripts/build_instructions.sh` が `shogun`, `karo`, `karo1-karo3`, `gunshi`, `ashigaru1-8` の `.opencode/agents/*.md` を生成するようになった。
- OpenCode launch は host auth / role-local state 方針を維持しつつ、`OPENCODE_AGENT_ID`, `OPENCODE_TUI_CONFIG=config/opencode-tui.json`, `opencode --agent <agent_id>` を使う。
- `cli.agents.<agent>.variant` がある場合は `<agent>-runtime` を起動対象にし、`scripts/switch_cli.sh --variant` が git-ignored runtime agent frontmatter を同期する。
- OpenCode の `/clear` は Ctrl-C restart ではなく `/new` に変換する。`/model` は restart-only として watcher から送らない。
- `opencode --prompt` 起動はやめ、OpenCode の role prompt / permission は `.opencode/agents/*.md` に寄せた。

検証:

- `bash -n lib/cli_adapter.sh scripts/build_instructions.sh scripts/switch_cli.sh scripts/inbox_watcher.sh` → PASS
- `bash scripts/build_instructions.sh` → PASS
- `bats tests/unit/test_cli_adapter.bats tests/unit/test_build_system.bats tests/unit/test_switch_cli.bats tests/unit/test_send_wakeup.bats` → PASS (`307` tests)
- `git diff --check` → PASS

## 復旧

- OpenCode 選択的取り込みで破綻した場合は、OpenCode 関連変更だけを revert し、fetch 済みの `upstream/main` は保持する。
- Shogunate-test は今回触らないため、実機 runtime 差分への影響は本体 repo の検証後に別作業で反映する。
