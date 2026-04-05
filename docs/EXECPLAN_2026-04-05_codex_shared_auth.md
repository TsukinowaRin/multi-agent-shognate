# ExecPlan: Codex Shared Auth

## Context
- 現状の Codex runtime は role ごとに別 `CODEX_HOME` を使うため、pane ごとに auth が分離され、再ログインの運用コストが高い。
- 一方で model / `reasoning_effort` の preset は role ごとに維持したい。
- 要求は「full state を共有」ではなく、「Auth だけ共通にして、役職ごとの preset は保つ」ことである。

## Scope
- `auth.json` だけを repo-local shared path に寄せる。
- role ごとの `CODEX_HOME`、model、`reasoning_effort` は維持する。
- 既存 role home にある `auth.json` から shared auth へ seed できるようにする。
- docs / settings / tests を新方針へ更新する。

## Acceptance Criteria
- `lib/cli_adapter.sh` の Codex 起動コマンドは、agent ごとに別 `CODEX_HOME` を保ちつつ、既定で `.shogunate/codex/shared/auth.json` を共通参照する。
- `shared_auth: false` を設定すると、旧来どおり role local `auth.json` のみを使う。
- custom `shared_auth_file` を設定すると、その path を使う。
- `tests/unit/test_cli_adapter.bats` が shared auth / disabled / custom path / role preset 維持を含めて PASS する。

## Work Breakdown
1. `cli_adapter` の Codex 起動前処理を `auth-only shared` 対応へ分解する。
2. `settings.yaml` に shared auth の既定値を追加する。
3. `test_cli_adapter.bats` を shared auth contract へ更新する。
4. README 英日と `docs/REQS.md` を更新する。
5. 検証して checkpoint commit を切る。

## Progress
- 2026-04-05: `lib/cli_adapter.sh` に shared auth helper を追加し、role local `auth.json` から shared auth への seed と symlink 優先 / copy fallback を実装した。
- 2026-04-05: `config/settings.yaml` に `cli.codex.shared_auth` と `cli.codex.shared_auth_file` の既定値を追加した。
- 2026-04-05: `tests/unit/test_cli_adapter.bats` を shared auth contract へ更新し、disabled / custom path 回帰を追加した。
- 2026-04-05: `bash -n lib/cli_adapter.sh` と `bats tests/unit/test_cli_adapter.bats` を通し、shared auth / disabled / custom path / role preset 維持を確認した。

## Surprises & Discoveries
- 実 runtime の role home には `auth.json`, `config.toml`, `history.jsonl`, `sessions/`, `state_5.sqlite` などが同居しており、full `CODEX_HOME` 共有は過剰だった。
- `auth.json` 単独共有なら、login state を共通化しつつ model / history / memories を role ごとに残せる。

## Decision Log
- `CODEX_HOME` 全共有ではなく、`auth.json` のみ共有する。
- shared auth は既定で有効にし、必要なら `shared_auth: false` で旧動作へ戻せるようにする。
- live 共有は symlink を優先し、環境差異で symlink が使えない場合は copy fallback を入れる。

## Outcomes & Retrospective
- role ごとの `CODEX_HOME` を維持したまま、`auth.json` は既定で `.shogunate/codex/shared/auth.json` を共通利用する形へ移行できた。
- model / `reasoning_effort` は launch flag に残しているため、auth 共有で role preset は混ざらない。
- symlink が使える環境では login state が role 間で即時共有され、使えない環境でも copy fallback により次回起動時の seed は維持される。
- 残リスクは、symlink 非対応環境では「即時共有」ではなく「起動時 seed」に留まる点である。必要なら後続で runtime sync を足す余地がある。
