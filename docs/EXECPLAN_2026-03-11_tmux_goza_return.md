# ExecPlan: Tmux御座の間の復活

## Context
- `zellij` は廃止し、現役 multiplexer は `tmux` のみになった。
- その後、ユーザーから `gunshi` への短縮 attach コマンド `csg` と、全エージェントを一望できる `御座の間` の再導入要求が出た。
- 旧 `goza*` 実装は `Waste/` に退避済みだが、そのまま戻すと `zellij` 前提の設計や互換オプションまで復活してしまう。

## Scope
- `tmux` 専用の `御座の間` スクリプトを現役コードへ復活する。
- `first_setup.sh` に `csg` と `御座の間` 用の alias を追加する。
- `README` と `shutsujin_departure.sh` の案内文を `csg` / `御座の間` 前提に更新する。
- `zellij` は再導入しない。

## Acceptance Criteria
1. `first_setup.sh` が `csg='tmux attach-session -t gunshi'` を設定する。
2. `bash scripts/goza_no_ma.sh -s --no-attach` が `tmux` ベースの俯瞰ビュー session を作成できる。
3. `README.md` / `README_ja.md` / `shutsujin_departure.sh` に `csg` と `御座の間` の導線がある。
4. `zellij` 前提の active code を復活させない。

## Work Breakdown
1. `REQS` / `INDEX` / ExecPlan を更新する。
2. `scripts/goza_no_ma.sh` を tmux-only で新規実装する。
3. `first_setup.sh` に `csg` / `cgo` alias を追加する。
4. `README` と `shutsujin_departure.sh` の導線を更新する。
5. 関連 Bats を更新し、tmux-only の smoke を通す。

## Progress
- 2026-03-11: 開始。
- 2026-03-11: `scripts/goza_no_ma.sh` を tmux-only で新規実装。`shogun / gunshi / multiagent` を一望する `goza-no-ma` session を作成する。
- 2026-03-11: `first_setup.sh` に `csg` / `cgo` alias を追加。
- 2026-03-11: `README.md` / `README_ja.md` / `shutsujin_departure.sh` に `軍師 attach` と `御座の間` の導線を追加。
- 2026-03-11: detached session で `size missing` が出る問題に対し、`bootstrap_goza_view.sh` を追加して `client-attached` hook で pane を本物の session attach へ差し替える構造に変更。
- 2026-03-11: `tests/unit/test_mux_parity.bats` を更新し、`zellij` 不在・`御座の間` 存在・`csg/cgo` 案内を回帰確認。
- 2026-03-11: `cgo` と通常の `goza_no_ma.sh` は既存 `shogun / gunshi / multiagent` session を再利用し、backend 起動は `--ensure-backend` または `-s` 指定時だけ行うよう修正。

## Surprises & Discoveries
- 旧 `goza_no_ma.sh` は `zellij` 互換オプション込みの巨大 frontend だったため、そのまま戻す価値は薄い。
- detached 状態の `tmux split-window -p` は `size missing` を起こすため、`-l` の固定サイズ指定へ切り替える必要があった。
- detached 状態で nested `tmux attach-session` を即実行すると不安定なため、`client-attached` hook で後から respawn する方が安全だった。

## Decision Log
- `御座の間` は `tmux` 専用で最小再実装する。
- `gunshi` attach 短縮は `csg` とする。
- 俯瞰ビュー attach 短縮として `cgo` も追加する。
- `cgo` の既定挙動は通常の `goza_no_ma.sh` と同じく「既存 backend 再利用」とする。
- backend 起動は暗黙では行わず、必要なら `--ensure-backend` または `-s` を明示する。

## Outcomes & Retrospective
- `tmux` 本線を崩さず、`御座の間` を俯瞰ビューとして最小再実装できた。
- `csg` により `gunshi` への attach 導線が `css/csm` と揃った。
- `cgo` により人間が全陣を一望する入口を `first_setup` の alias と README に統一できた。
- `cgo` / `goza_no_ma.sh` 実行時に backend を毎回再起動しない構造にできたため、通常運用時の無駄な再起動を避けられる。
- detached smoke と hook 本体の動作確認までは完了。通常の人間 attach 時の俯瞰体験を以後の実機確認対象とする。
