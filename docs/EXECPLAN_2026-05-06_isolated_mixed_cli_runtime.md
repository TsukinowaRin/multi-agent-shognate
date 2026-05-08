# ExecPlan: 隔離コピーで混在CLI / 最新preview runtimeを起動検証する

最終更新: 2026-05-06

## 目的

開発中の本体 repo を汚染せず、独立フォルダに最新 tracked 内容を展開したうえで、指定された役職別 CLI / model 構成が runtime に反映され、起動または環境依存 blocker まで観測できることを確認する。

## 指定構成

- 将軍: Gemini CLI、`gemini-3.1-pro-preview`、`thinking_level: low`
- 家老: Codex、`gpt-5.5`、`reasoning_effort: high`
- 足軽1: Codex、`gpt-5.5`、`reasoning_effort: medium`
- 足軽2: opencode
- 足軽3: opencode
- 軍師: Codex、`gpt-5.5`

`gemini-3.1-pro-preview` は、Gemini CLI 公式 docs で Gemini 3.1 Pro Preview の直接起動例として示されているため、今回の「最新 Gemini preview」の実行候補として採用する。軍師の reasoning effort はユーザー指定がないため、設定では model のみ明示して CLI 既定に任せる。

## 進捗

- [x] 要求を `docs/REQS.md` に正規化した。
- [x] 独立フォルダへ最新 tracked 内容を展開した。
- [x] 隔離コピー内に指定構成の `config/settings.yaml` を作成した。
- [x] Gemini / opencode 設定生成と CLI adapter の静的確認を行った。
- [x] 隔離 tmux server で runtime を起動した。
- [x] smoke task を投入し、完走または blocker を記録した。

## 手順

1. 本体 repo の `git status --short --branch` を確認し、現在 HEAD を把握する。
2. `/mnt/d/git_workspace/multi-agent-shognate/isolated-mixed-cli-runtime-20260506*` のような本体外ディレクトリへ `git archive HEAD` で tracked 内容を展開する。
3. 隔離コピー内で `config/settings.yaml` を作成し、active ashigaru を `ashigaru1..3` に限定する。
4. `python3 scripts/sync_gemini_settings.py` と `python3 scripts/sync_opencode_config.py` を実行する。
5. `lib/cli_adapter.sh` の `build_cli_command` 結果、`.gemini/settings.json`、`opencode.json`、`queue/runtime/*.tsv` を確認する。
6. 独立した `TMUX_TMPDIR` を使って `bash shutsujin_departure.sh -c` を実行する。
7. 起動できた場合は `scripts/inbox_write.sh shogun` で軽い smoke task を投入し、pane / queue / dashboard / logs を観測する。
8. 結果と残リスクをこの ExecPlan と `docs/WORKLOG.md` へ記録する。

## 検証

- `python3 scripts/sync_gemini_settings.py` → PASS。`.gemini/settings.json` に `mas-shogun` alias を生成し、base model は `gemini-3.1-pro-preview`、`thinkingLevel` は `LOW`。
- `python3 scripts/sync_opencode_config.py` → PASS。`opencode.json` は `permission: allow`、provider 未指定。
- `source lib/cli_adapter.sh; build_cli_command <agent>` → PASS。将軍は `gemini --yolo --model mas-shogun`、家老は `codex --model gpt-5.5 -c model_reasoning_effort='high'`、足軽1は `codex --model gpt-5.5 -c model_reasoning_effort='medium'`、足軽2/3は `opencode`、軍師は `codex --model gpt-5.5`。
- `TMUX_TMPDIR=/tmp/mas_mixed_cli_runtime_20260506 bash shutsujin_departure.sh -c` → runtime 起動完了。`goza-no-ma`、`goza-runtime`、Android 互換 session が作成され、watcher / bridge / runtime-pref daemon が起動。
- `tmux capture-pane` / `dashboard.md` 観測:
  - 将軍: Gemini CLI は起動したが `Model "mas-shogun" was not found or is invalid.` で停止。
  - 家老 / 足軽1 / 軍師: 隔離コピーに Codex 認証 state を持ち込まなかったため、Codex auth prompt で停止。dashboard と将軍 inbox に `runtime_blocked` relay が記録された。
  - 足軽2 / 足軽3: opencode pane は起動し、足軽3は `AGENTS.md` と generated instruction 読み込みまで進んだ。
- `bash scripts/inbox_write.sh shogun "<mixed_cli_smoke>" task_assigned user` → 投入は PASS。ただし将軍が Gemini model error 画面で停止しているため、20 秒後も `queue/shogun_to_karo.yaml` は空、`runtime_sandboxes/mixed_cli_smoke` は未作成。

## 結果

隔離コピーで指定構成の設定生成、tmux runtime 起動、watcher / bridge 起動、blocker relay までは確認できた。end-to-end smoke task は、将軍の Gemini alias/model error と Codex 認証待ちにより未完走。

## 残リスク / 次手

- Gemini CLI `mas-shogun` alias が最新 CLI で解決されない。`gemini-3.1-pro-preview` への direct model 指定、preview features 設定、または最新 Gemini CLI の model config schema 追従が必要。
- Codex 系は隔離コピーへ secrets を持ち込まない方針のため auth prompt で止まる。実完走にはユーザー側で隔離先の Codex login / API key 設定が必要。
- opencode は default provider として Kimi K2.6 が選ばれて起動した。明示 provider/model が必要なら `cli.opencode_like` または agent model 設定を追加する。

## 復旧と安全策

- 本体 repo では runtime を起動しない。
- secrets はコピー、閲覧、出力しない。`git archive HEAD` は tracked file のみを展開し、既存の認証 state は含めない。
- 隔離 tmux server は専用 `TMUX_TMPDIR` で起動し、検証後に不要なら `tmux kill-server` で停止できる。
- 既存の同名隔離フォルダがある場合は削除せず、新しい suffix のフォルダを作る。
