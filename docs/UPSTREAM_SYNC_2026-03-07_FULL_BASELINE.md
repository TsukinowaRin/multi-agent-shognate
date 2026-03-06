# Upstream Full Baseline Sync (2026-03-07)

対象上流: `yohey-w/multi-agent-shogun`  
取得方法: ワークスペース内フルクローン  
参照パス: `_upstream_reference/original_full_2026-03-07`

## 目的
- shallow clone や過去時点の参照ではなく、上流の完全な現行ツリーを基準に再出発する。
- このフォークで維持する独自要素を次の2点へ限定する。
  1. `zellij`
  2. `Gemini CLI`

## 2026-03-07 に確認した事実
1. フルクローン HEAD は `86ee80b`。
2. 上流には `zellij` 対応は存在しない。
3. 上流には `Gemini CLI` 対応は存在しない。
4. それ以外の共通基盤は、このフォークより上流の方が整理されている箇所が多い。
   - `AGENTS.md`
   - `lib/agent_status.sh`
   - `lib/cli_adapter.sh`
   - `scripts/build_instructions.sh`
   - `scripts/inbox_watcher.sh`
   - `shutsujin_departure.sh`
   - `first_setup.sh`

## 採用方針
1. 上流をそのまま全面コピーするのではなく、基盤ファイル単位で置換する。
2. 置換前のローカル基盤は `Waste/` に退避し、参照可能な状態で残す。
3. `zellij` と `Gemini CLI` は、上流基盤の上に最小差分で再実装する。
4. `localapi` やその他派生拡張は、今回の再出発では主目標から外す。

## 優先順
1. `first_setup.sh`
2. `scripts/build_instructions.sh`
3. `lib/cli_adapter.sh`
4. `shutsujin_departure.sh`
5. `README.md` / `README_ja.md`

## 受け入れの見方
- `Waste/` に退避資産が残っている。
- `lib/cli_adapter.sh` が上流骨格を保ちつつ `gemini` を扱える。
- `scripts/build_instructions.sh` が `gemini` 用 generated instructions を生成できる。
- `shutsujin_departure.sh` は `MAS_MULTIPLEXER=zellij` で zellij 起動導線へ分岐できる。
