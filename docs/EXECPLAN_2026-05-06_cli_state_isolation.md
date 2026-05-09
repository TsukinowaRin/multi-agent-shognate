# ExecPlan: 対応CLIのホスト認証と pane-local state を両立する

最終更新: 2026-05-09

## 目的

OpenCode / Kilo がユーザー home 側の既存ログイン情報やモデル設定を拾っていた。新方針では、認証情報そのものはホスト PC の既存ログインを使い、モデル選択・CLI 設定・履歴などの runtime state だけを Shogunate の agent / pane ごとに repo-local へ分離する。

## 経緯

- `docs/EXECPLAN_2026-03-17_codex_role_isolation.md` では、役職ごとの Codex model / reasoning を分けたい一方、Codex runtime state が共有されていたため、role-local `CODEX_HOME` を導入した。
- 同文書の理由は、Shogunate 側の Codex tuning が VSCode Codex や無関係な Codex CLI session へ漏れないようにすることだった。
- `docs/EXECPLAN_2026-04-05_codex_shared_auth.md` では、role ごとに完全分離するとログイン運用が重いため、full `CODEX_HOME` 共有ではなく `auth.json` だけを共有する方針へ更新した。
- `docs/EXECPLAN_2026-03-17_multi_cli_gaps.md` と 2026-03-07 の worklog では OpenCode / Kilo の project provider 設定を `opencode.json` に生成する対応までは入ったが、HOME / XDG 側の login / model state 隔離は未実装だった。
- 2026-05-06 のユーザー方針により、認証情報はホスト computer のものを使い、各 pane で独立させる対象は settings / model / history state に限定する。
- 2026-05-09 の確認により、OpenCode / Kilo も host `auth.json` だけを共有し、SQLite DB / model state / prompt history は初期コピーせず pane-local に保持する方針へ更新した。

## 方針

- Codex は `CODEX_HOME=<repo>/.shogunate/codex/agents/<agent>` を維持し、ホスト `~/.codex/auth.json` があれば agent local `auth.json` へ symlink する。ホスト auth がない場合のみ、既存の repo-local shared `auth.json` fallback を使う。
- Claude / Copilot / Kimi / Gemini / OpenCode / Kilo は、起動時に `HOME` と XDG paths を `<repo>/.shogunate/cli-state/<cli>/agents/<agent>/home` 配下へ向ける。
- 既知の host auth file は、上記 repo-local home 内の同じ相対パスへ symlink する。対象は現時点で Claude `.claude/.credentials.json`、Gemini `.gemini/oauth_creds.json` / `.gemini/google_accounts.json`、OpenCode `.local/share/opencode/auth.json`、Kilo `.local/share/kilo/auth.json`、Copilot / Kimi の一般的な auth path。OpenCode / Kilo の SQLite DB、model state、prompt history、telemetry state は共有も host seed もせず、古い symlink だけ起動時に外す。
- Gemini CLI は credential file だけでは auth method が未選択になるため、既定で `GEMINI_DEFAULT_AUTH_TYPE=oauth-personal` を付与する。`cli.gemini.auth_type` で `gemini-api-key` / `vertex-ai` などへ変更できる。
- `localapi` は外部 CLI login state を持たない repo script なので対象外とする。
- secrets は読まずコピーしない。auth file がホストに存在するかだけを shell の `-f` で確認し、存在する場合は symlink する。

## 進捗

- [x] docs から Codex 隔離の理由を確認した。
- [x] `lib/cli_adapter.sh` に generic CLI state home helper を追加した。
- [x] OpenCode / Kilo / Gemini / Claude / Copilot / Kimi 起動コマンドに state env と host auth symlink bootstrap を付与した。
- [x] Codex は host `~/.codex/auth.json` を優先し、repo-local shared auth を fallback に変更した。
- [x] OpenCode / Kilo は host `auth.json` だけを共有し、DB / model / history state を pane-local に保つ挙動へ更新した。
- [x] unit test を更新した。
- [x] README 英日を更新した。
- [x] 検証結果を記録した。

## 検証

- `bash -n lib/cli_adapter.sh`
- `bats tests/unit/test_cli_adapter.bats`
- `git diff --check`

## 検証結果

- `bash -n lib/cli_adapter.sh` → PASS。
- 2026-05-06: `bats tests/unit/test_cli_adapter.bats` → PASS (`114` tests)。
- 2026-05-09: `bats tests/unit/` → PASS (`578` tests)。
- 2026-05-09: `bash -n lib/cli_adapter.sh scripts/inbox_watcher.sh shutsujin_departure.sh` → PASS。
- 2026-05-09: `bats tests/unit/test_cli_adapter.bats` に role × CLI matrix を追加し、`shogun` / `gunshi` / `karo` / `karo2` / `ashigaruN` に任意対応 CLI を割り当てても role-local state になることを確認。
- `git diff --check` → PASS。

## 実装結果

- `lib/cli_adapter.sh` に `.shogunate/cli-state/<cli>/agents/<agent>/home` を作る helper と、host auth file symlink helper を追加した。
- `claude` / `copilot` / `kimi` / `gemini` / `opencode` / `kilo` の起動コマンドは、`HOME` / `XDG_CONFIG_HOME` / `XDG_DATA_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` を repo-local state home へ向け、既知の auth file だけ host から symlink する。
- `opencode` / `kilo` は host DB / model / prompt history を初期コピーしない。既存の role-local regular file は残し、古い symlink だけ外す。
- `gemini` の起動コマンドは、host OAuth credentials を使えるよう `GEMINI_DEFAULT_AUTH_TYPE=oauth-personal` を既定付与する。
- `codex` は role-local `CODEX_HOME` を維持し、host `~/.codex/auth.json` を優先する。host auth がない場合だけ、既存の repo-local shared auth fallback を使う。
- `localapi` は外部 CLI login state を持たないため対象外。

## 残リスク

- 各 CLI が `HOME` / XDG 以外の専用環境変数や OS keychain を使う場合、その state はこの変更だけでは分離できない。
- `cli.commands.*` に `HOME` / `XDG_*` を明示する custom command を書いた場合、command 側の指定が CLI 内部で優先される可能性がある。
- OpenCode / Kilo の project-level `opencode.json` は引き続き repo 共有設定として使う。これは provider / permission の runtime 設定であり、global login state とは分けて扱う。
