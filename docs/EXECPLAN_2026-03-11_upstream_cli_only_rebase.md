# ExecPlan: Upstream CLI-Only Rebase

## Context
- `zellij` と `goza` は廃止し、`tmux` のみを現役運用とする方針が確定した。
- 現在のブランチは `upstream/main` と大きく diverge しており、multiplexer 試行錯誤の差分が多い。
- このフォークの独自価値は multiplexer ではなく、`Gemini CLI` / `OpenCode` / `Kilo` / `localapi` / local provider 設定にある。

## Scope
- `upstream/main` の `tmux` 本線を正本とする方針を docs と導線へ反映する。
- `README.md` / `README_ja.md` / `first_setup.sh` を upstream ベースへ寄せる。
- 独自差分は CLI 拡張に限定し、`Waste/` との責務分離を明確にする。

## Acceptance Criteria
1. 現役運用文書は `tmux` と `shutsujin_departure.sh` のみを前提にする。
2. `README.md` / `README_ja.md` に、このフォーク独自差分が `Gemini/OpenCode/Kilo/localapi/Ollama/LM Studio` であると明記される。
3. `first_setup.sh` に `tmux` 本線と追加 CLI の導入案内が残り、`zellij/goza` への言及がない。
4. `bash -n shutsujin_departure.sh first_setup.sh scripts/configure_agents.sh` が PASS する。
5. tmux 本線 + CLI 拡張の unit test が PASS する。

## Work Breakdown
1. `REQS` / `INDEX` / 同期ノートを更新し、方針を固定する。
2. `README.md` / `README_ja.md` を upstream ベースで再整理する。
3. `first_setup.sh` を upstream ベースで見直し、独自差分を追加 CLI 導線へ限定する。
4. 必要なら `shutsujin_departure.sh` を upstream 本線へさらに寄せる。
5. 主要 shell check と unit test を回し、checkpoint を切る。

## Progress
- 2026-03-11: `tmux` 一本化と `goza/zellij` 廃止を完了。
- 2026-03-11: upstream 正本 + CLI 拡張限定の方針を docs に固定開始。
- 2026-03-11: `README.md` / `README_ja.md` を、upstream 正本に対するこのフォーク独自差分が CLI 拡張であると明示する形へ更新。
- 2026-03-11: `first_setup.sh` に「upstream tmux 本線 + CLI 拡張」方針を反映。

## Surprises & Discoveries
- `README.md` はすでに大幅に簡略化されており、upstream の情報量との差が大きい。
- `first_setup.sh` は追加 CLI チェックを持つ一方、upstream 側の OS/venv/file-watcher 整理も取り込む余地がある。

## Decision Log
- multiplexer の再拡張はしない。
- 現役起動入口は `shutsujin_departure.sh` のみとする。
- upstream 全量 merge ではなく、`README` / `first_setup` / 必要最小限の shell から順に寄せる。

## Outcomes & Retrospective
- 進行中。
- 文書と導入導線の整理を先に行うことで、次段の `shutsujin_departure.sh` 追従範囲を狭めた。
