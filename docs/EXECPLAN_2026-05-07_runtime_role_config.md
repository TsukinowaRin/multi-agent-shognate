# ExecPlan: CLI種別と足軽数だけを設定する簡易スクリプト

最終更新: 2026-05-07

## 目的

Shogunate 側の設定を「どの役職がどの CLI を使うか」と「足軽を何人出すか」に絞る。model / reasoning / thinking は tmux pane 上の各 CLI で手動設定し、pane-local state または既存 runtime sync により次回起動へ残す。

## 背景

- 2026-05-07 の隔離 runtime 起動で、OpenCode は Shogunate 側で model 未指定でも CLI 側の既定 model / provider により残高エラーで止まった。
- 既存 `scripts/configure_agents.sh` は詳細設定用で、model / reasoning / Gemini thinking / OpenCode provider まで対話入力する。
- ユーザーは、通常運用では詳細 model を設定ファイルで指定せず、Codex / Gemini CLI / OpenCode などの大まかな CLI 種別だけ選びたい。

## 方針

- 既存の詳細 `configure_agents.sh` は互換のため残す。
- 新規 `scripts/configure_runtime_roles.py` を追加し、簡易設定の正本にする。
- 表層 launcher として `Shogunate-Configure-Roles.sh` / `.bat` / `.command` を追加し、Linux / Windows WSL / macOS から同じ正本 script を起動する。
- 簡易スクリプトは `topology.active_ashigaru` と `cli.agents.<role>.type` を更新する。
- 対象 role の `model` / `reasoning_effort` / `thinking_level` / `thinking_budget` は既定で削除し、CLI ごとの pane-local state に任せる。
- 対話 prompt は `cli.default`、将軍、家老、軍師、足軽人数、足軽ごとの CLI の順にする。
- デフォルト設定は全エージェント `type: codex` とし、model は pin しない。
- 非対話 flags と対話 prompt の両方を提供する。

## 進捗

- [x] 要求を `docs/REQS.md` に正規化した。
- [x] 実装方針を決めた。
- [x] `scripts/configure_runtime_roles.py` を追加する。
- [x] unit test を追加する。
- [x] README 英日と `docs/INDEX.md` を更新する。
- [x] `first_setup.sh` の初回 default を全役職 `codex` / model pin なしへ更新する。
- [x] Linux / Windows WSL / macOS 用の表層 launcher を追加する。
- [x] 検証結果を記録する。

## 検証

- `python3 -m py_compile scripts/configure_runtime_roles.py`
- `bats tests/unit/test_configure_runtime_roles.bats`
- `bash -n Shogunate-Configure-Roles.sh Shogunate-Configure-Roles.command`
- `bats tests/unit/test_configure_role_launchers.bats`
- `bash -n first_setup.sh`
- `git diff --check`

## 検証結果

- `python3 -m py_compile scripts/configure_runtime_roles.py` → PASS。
- `bash -n first_setup.sh` → PASS。
- `bats tests/unit/test_configure_runtime_roles.bats` → PASS (`4` tests)。
- `bash -n Shogunate-Configure-Roles.sh Shogunate-Configure-Roles.command` → PASS。
- `bats tests/unit/test_configure_role_launchers.bats` → PASS (`2` tests)。
- `git diff --check` → PASS。

## 残リスク

- OpenCode / Kilo の provider や account 側 default model は CLI 内部の挙動に依存する。Shogunate の簡易スクリプトはそれを直接選ばない。
- Codex / Gemini の live model sync は既存 daemon が `config/settings.yaml` へ書き戻す場合がある。簡易スクリプトを再実行すると role の model field は削除され、pane-local state 優先へ戻る。
