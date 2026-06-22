# ExecPlan: runtime同期最適化をShogunate MOD側へ実装

## Goal

実AI runtimeで再現した「足軽は完了したが command / dashboard / Gunkan / 将軍通知が同期しない」問題を、Shogunate MOD側の常駐同期機能として修正する。古い archive の command が現在の `cmd_id` と混ざる誤通知も止める。

## Background

- 実AI検証では Shogun が `cmd_001` を発行し、Karo が足軽へ分配し、target project に成果物とテストが作られた。
- ただし `karo_done_to_shogun_bridge.py` が active queue と archive の両方を既定で見ていたため、過去の `cmd_001` が現在の `cmd_001` と混ざり、古い `cmd_done` が将軍へ届いた。
- 足軽reportが揃っても command は `in_progress` のまま残り、Gunkan最終監査も起きなかった。

## Design

1. `shogunate_mod/runtime/karo_done_to_shogun_bridge.py`
   - 既定では active `queue/shogun_to_karo.yaml` のみを通知対象にする。
   - `MAS_KARO_DONE_INCLUDE_ARCHIVE=1` のときだけ archive を互換的に見る。
2. `shogunate_mod/runtime/sync_state.py`
   - active command、task、report、dashboard、Gunkan inbox を同期するMOD正本。
   - 足軽reportが揃ったら task を `done` にし、command を `audit_requested` にし、Gunkanへ最終監査を1回だけ依頼する。
   - Gunkan report が返ったら command を `done` にし、dashboardの戦果へ反映する。
3. `shogunate_mod/runtime/daemon.sh`
   - runtime daemon session に `runtime-sync` window を追加し、source/package runtimeの両方で常駐させる。

## Acceptance

- archive command は既定で `cmd_done` 通知されない。
- 明示フラグ付きでは archive互換通知が維持される。
- 足軽report完了後、Gunkan inboxに `audit_requested` が1回だけ作られる。
- Gunkan report後、active command が `done` になる。
- 実装は `shogunate_mod/` 正本で、root側へ新しい本体ロジックを増やさない。

## Verification

- `python3 -m py_compile shogunate_mod/runtime/karo_done_to_shogun_bridge.py shogunate_mod/runtime/sync_state.py`
- `bash -n shogunate_mod/runtime/daemon.sh`
- `bats shogunate_mod/tests/unit/test_karo_done_to_shogun_bridge.bats`
- `python3 -m unittest shogunate_mod.tests.unit.test_runtime_sync_state`
- `git diff --check`
