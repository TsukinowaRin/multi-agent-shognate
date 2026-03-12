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
1. `first_setup.sh` が `css/csg/csm/cgo` を `goza-no-ma` 本体 session 前提で設定する。
2. `bash shutsujin_departure.sh -s` が `goza-no-ma` session と role 別の実 pane を作成できる。
3. `README.md` / `README_ja.md` / `shutsujin_departure.sh` に `csg` と `御座の間` の導線があり、`cgo` は既存 session を再利用する。
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
- 2026-03-12: `御座の間` を nested attach 3枚から役職別 live mirror 方式へ変更し、`shogun > karo > gunshi > ashigaru` の優先度レイアウトへ再編成。
- 2026-03-12: `goza-dispatch` と `goza_focus_target.sh` を接続し、御座の間で最後に選択した pane の agent を送信先へ自動追従させた。
- 2026-03-12: mirror 方式をやめ、`shutsujin_departure.sh` が `goza-no-ma` を本体 session として構築する方向へ移行開始。
- 2026-03-12: `shogun / karo / gunshi / ashigaru` の実 pane を `goza-no-ma` に直接配置し、`css/csg/csm` は `focus_agent_pane.sh` で pane focus する構成へ変更中。
- 2026-03-12: `cgo` は既存 `goza-no-ma` を開く wrapper に簡素化し、runtime sync / watcher / bootstrap は `goza-no-ma` の `@agent_id` / `@agent_cli` を優先するよう段階的に移行中。
- 2026-03-12: `goza-no-ma` が複数 window を持つ前提になったため、pane 解決を `tmux list-panes -s -t goza-no-ma` の session 全体探索へ揃えた。

## Surprises & Discoveries
- 旧 `goza_no_ma.sh` は `zellij` 互換オプション込みの巨大 frontend だったため、そのまま戻す価値は薄い。
- detached 状態の `tmux split-window -p` は `size missing` を起こすため、`-l` の固定サイズ指定へ切り替える必要があった。
- detached 状態で nested `tmux attach-session` を即実行すると不安定なため、`client-attached` hook で後から respawn する方が安全だった。
- `karo` を二番目に大きく見せるには、`multiagent` session 全体の attach ではなく `karo` pane を独立 mirror 化する必要がある。
- 「全部見つつ直接入力したい」を満たすには、mirror + dispatch の継ぎ足しでは限界がある。tmux の制約上、最終的には `goza-no-ma` を本体 session にするしかない。
- `tmux` では 1 pane を複数 window に同時配置できないため、`shogun:main / gunshi:main / multiagent:agents` を残したまま別 window に同じ実 pane を見せる設計は取れない。

## Decision Log
- `御座の間` は `tmux` 専用で最小再実装する。
- `gunshi` attach 短縮は `csg` とする。
- 俯瞰ビュー attach 短縮として `cgo` も追加する。
- `cgo` の既定挙動は通常の `goza_no_ma.sh` と同じく「既存 backend 再利用」とする。
- backend 起動は暗黙では行わず、必要なら `--ensure-backend` または `-s` を明示する。
- pane 優先度は `shogun > karo > gunshi > ashigaru` とする。
- `goza-no-ma` は最終的に read-only 俯瞰ではなく本体 session とする。
- `css/csg/csm` は別 session attach ではなく、`goza-no-ma` 内の pane focus コマンドに変更する。
- `shogun:main / gunshi:main / multiagent:agents` は最終的に補助互換または廃止対象とし、watcher / bootstrap / runtime sync の正本は `goza-no-ma` に置く。
- `goza-no-ma` の pane 解決は current window に依存させず、session 全体の pane を `@agent_id` で引く。

## Outcomes & Retrospective
- `tmux` 本線を崩さず、`御座の間` を俯瞰ビューとして最小再実装できた。
- `csg` により `gunshi` への attach 導線が `css/csm` と揃った。
- `cgo` により人間が全陣を一望する入口を `first_setup` の alias と README に統一できた。
- `cgo` / `goza_no_ma.sh` 実行時に backend を毎回再起動しない構造にできたため、通常運用時の無駄な再起動を避けられる。
- role 別 mirror 方式に変えたことで、将軍・家老・軍師・足軽のサイズ優先度を個別に制御できるようになった。
- `goza-no-ma` 本体化により、pane を選んでそのまま直接入力する要求は満たせるようになった。
- 残る完成条件は、README / REQS / tests / watcher / runtime sync の記述と実装を `goza-no-ma` 正本へ完全に揃えること。
