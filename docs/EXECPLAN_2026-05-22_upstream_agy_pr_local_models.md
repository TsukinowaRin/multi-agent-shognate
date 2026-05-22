# ExecPlan: upstream AGY PR and local model smoke

作成日: 2026-05-22

## 目的

本家 `yohey-w/multi-agent-shogun` へ送れる最小単位として AGY / Antigravity CLI 対応だけを切り出す。同時に、Shogunate の LocalAPI wrapper が LM Studio / Ollama などの OpenAI-compatible endpoint に対して使えるかを実機または mock で確認する。

## 方針

1. 本家向け PR branch は `upstream/main` から作る。
2. Shogunate の大きな runtime 変更、package 配布、multi-Karo、AGY auth isolation の全量は混ぜない。
3. AGY PR は CLI type 追加、instruction generation、launch command、runtime ready / trust prompt handling、basic tests に絞る。
4. Local model test は既存環境を優先する。Ollama / LM Studio が起動していない場合は、mock OpenAI-compatible endpoint で LocalAPI wrapper を検証し、実 Ollama / LM Studio は環境不足として明記する。
5. 大容量 model download は、Ollama runtime と ROCm GPU backend が実際に使える見込みがある場合だけ行う。

## 現状観測

- Current Shogunate branch: `codex/upstream-main-rebuild-shogunate`
- Current commit: `c9f96a9`
- upstream/main: `84c8e82`
- `agy`: installed, version `1.0.1`
- `ollama`, `lms`, `lmstudio`: PATH では未検出
- Ollama default endpoint `http://127.0.0.1:11434/api/tags`: timeout
- LM Studio default endpoint `http://127.0.0.1:1234/v1/models`: timeout
- ROCm: `rocminfo` sees `AMD Radeon RX 7900 XTX` / `gfx1100`
- `rocm-smi`: `Driver not initialized (amdgpu not found in modules)`

## 進捗

- [x] 要求を `docs/REQS.md` に追記した。
- [x] ローカル CLI / endpoint / ROCm の初期状態を確認した。
- [x] upstream AGY-only branch を作る。
- [x] AGY-only 差分を実装する。
- [x] AGY-only tests を通す。
- [x] LocalAPI mock endpoint smoke を行う。
- [x] Ollama / LM Studio 実 endpoint の可否を記録する。
- [x] 本家向け draft PR を作成する。

## 結果

- Worktree: `/mnt/d/git_workspace/multi-agent-shognate/upstream-agy-pr`
- Branch: `codex/upstream-agy-cli-pr`
- Commit: `23f595e` (`Add Antigravity CLI support`)
- Draft PR: https://github.com/yohey-w/multi-agent-shogun/pull/154

AGY PR には、Shogunate 独自 runtime 機能を混ぜず、次だけを入れた。

- `type: antigravity` の追加。
- `type: agy` / legacy `type: gemini` を `antigravity` へ正規化。
- `agy --dangerously-skip-permissions` 起動。
- model が `auto` / 未指定なら host 側 AGY の default / last-used に任せる。
- 明示 model のときだけ `--model <model>` を渡す。
- Antigravity 用 role instruction 生成。
- `inbox_watcher.sh` / `switch_cli.sh` / startup ready check の最小対応。

LocalAPI は Shogunate 側 `scripts/localapi_repl.py` を mock OpenAI-compatible `/v1/chat/completions` endpoint で検証し、`mock-localapi-ok:ping` 応答を確認した。

実 Ollama / LM Studio / LocalAPI endpoint は、この環境では未起動だった。

- `http://127.0.0.1:11434/api/tags` → timeout
- `http://127.0.0.1:1234/v1/models` → timeout
- `http://127.0.0.1:8080/v1/models` → timeout

ROCm は `rocminfo` で `AMD Radeon RX 7900 XTX` / `gfx1100` が見えたが、`rocm-smi` は `Driver not initialized (amdgpu not found in modules)`。Ollama / LM Studio が未導入か未起動で、ROCm 管理も未初期化のため、`qwen3.6:27b` の実ロードは未実施。

## 検証予定

- AGY branch:
  - `bash -n lib/cli_adapter.sh scripts/build_instructions.sh scripts/inbox_watcher.sh shutsujin_departure.sh`
  - `bash scripts/build_instructions.sh`
  - relevant Bats: `tests/unit/test_cli_adapter.bats`, `tests/unit/test_build_system.bats`, `tests/unit/test_send_wakeup.bats`, `tests/unit/test_switch_cli.bats`
- LocalAPI:
  - mock OpenAI-compatible `/v1/chat/completions` endpoint
  - `LOCALAI_API_BASE=<mock>/v1 LOCALAI_MODEL=<model> python3 scripts/localapi_repl.py`
  - Ollama endpoint: `http://127.0.0.1:11434/v1`
  - LM Studio endpoint: `http://127.0.0.1:1234/v1`

## 復旧

- upstream PR branch は独立 worktree / branch として作る。失敗時は branch を削除し、Shogunate branch へ混ぜない。
- tmux / local model server を起動した場合は、作成した session / process だけを停止する。
