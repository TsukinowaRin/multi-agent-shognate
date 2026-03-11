# Upstream Sync 2026-03-11: Compaction Recovery

対象 upstream commit:
- `2ef81f974bbb633a0cdfe00566671d8a64d5f462`
- subject: `fix(compaction): enforce persona restoration after context compaction`

## 要点
- upstream では `CLAUDE.md` に `Post-Compaction Recovery (CRITICAL)` を追加した。
- compaction summary は persona / speech style / forbidden actions を保持しない前提を明文化し、再開前に instructions file を再読することを必須化した。

## このフォークでの反映方針
- upstream の変更は `CLAUDE.md` 1ファイルだったが、このフォークでは複数 CLI ごとに root instruction が分かれている。
- そのため、同一趣旨を以下へ横展開した。
  - `CLAUDE.md`
  - `AGENTS.md`
  - `.github/copilot-instructions.md`
  - `agents/default/system.md`

## 反映内容
1. `Post-Compaction Recovery (CRITICAL)` 節を追加
2. compaction 後も Session Start Step 3 を再実行することを明記
3. role/CLI ごとの instructions file を再読することを明記
4. persona / speech style を復元してから YAML state rebuild と通常復帰へ進むことを明記

## 意図
- このフォークは `Codex` / `Claude` / `Copilot` / `Kimi` / `Gemini` / `OpenCode` / `Kilo` を扱うため、compaction 後の persona drift は upstream より影響面が広い。
- まず root instruction 側で「再読必須」を強制し、その上で各 generated instruction の詳細復帰手順は別途必要に応じて調整する。

## 非対象
- upstream `main` 全体の merge は未実施。
- `upstream/main` は `2ef81f9` 時点で本フォークと大きく乖離しており、今回は compaction recovery の重要差分のみを先行反映した。
