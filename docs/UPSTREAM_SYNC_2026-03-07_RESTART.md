# Upstream Restart Notes (2026-03-07)

対象上流: `yohey-w/multi-agent-shogun`  
参照基準: `_upstream_reference/upstream_clone_2026-03-06_86ee80b`

## 背景
- このフォークは `zellij` と `Gemini CLI` を追加する過程で、上流から独自構造が大きく増えた。
- 一方、上流側も 2026-03 時点で内部構造が進み、以下の共通基盤が整理されている。

## 上流で進んだ構造変化
1. `AGENTS.md` の責務拡張
   - `gunshi`
   - `memory/MEMORY.md`
   - `pending_tasks`
   - `/new` ベースの回復手順
2. `lib/agent_status.sh`
   - busy/idle 判定を共有ライブラリ化
3. `scripts/build_instructions.sh`
   - CLI auto-load ファイル生成の基盤整理
4. `scripts/inbox_watcher.sh`
   - false-busy deadlock 対策
   - throttle / stop hook / context reset 周りの整理
5. `README_ja.md`
   - 現在の上流仕様に沿った説明へ更新

## このフォークでの再出発方針
1. 上流の共通基盤を優先採用する。
2. その上で、このフォーク固有の対象は次の2点に限定する。
   - `zellij`
   - `Gemini CLI`
3. `localapi` や過去の複雑な派生機能は今回の主要対象から外す。
4. 置換前のローカル基盤は `_trash/restart_2026-03-07_core/` に退避する。

## 2026-03-07 時点で実施済み
1. `AGENTS.md` を上流最新版へ更新。
2. `lib/agent_status.sh` を上流最新版から導入。
3. `scripts/inbox_watcher.sh` が `lib/agent_status.sh` を利用するよう補正。

## 次に置き換える候補
1. `shutsujin_departure.sh`
2. `lib/cli_adapter.sh`
3. `scripts/build_instructions.sh`
4. `first_setup.sh`
5. `README_ja.md`

## 注意
- これは「上流へ単純リセット」ではない。
- 目標は「上流最新を土台に、zellij と Gemini だけをきれいに載せ直す」こと。
