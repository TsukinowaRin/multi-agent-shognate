# ExecPlan: Standard CoDD Integration

## 目的

CoDD (`yohey-w/codd-dev`) を Shogunate に vendoring せず、標準の外部 coherence gate として導入・更新・実行できるようにする。

## 要件

- `.codd/codd.yaml` を repository 用に用意する。
- `scripts/codd_check.sh` で install / build / verify / audit を呼べるようにする。
- `make codd` で通常導線から実行できるようにする。
- CI は既定で `codd dag verify` を走らせる。
- `Update.bat` / `scripts/update_manager.py manual` で CoDD package を導入・更新する。
- package は latest を優先し、失敗時は開発時確認版へ fallback する。
- `python3` / `python3-venv` が無い場合は導入手順つきで停止する。

## 方針

- CoDD は Python package `codd-dev` として扱う。
- install 先は `.shogunate/codd-venv` とし、公開物や通常 runtime state に混ぜない。
- 既定の実行は `codd dag verify` とする。
- `codd audit` は CoDD 側 optional bridge がある環境向けの入口だけ用意する。
- `scripts/codd_check.sh install` は PyPI latest/spec を試し、失敗時に `CODD_FALLBACK_VERSION`（既定 `1.34.0`）を入れる。

## 進捗

- [x] CoDD upstream の README / config / CLI を確認した。
- [x] `.codd/codd.yaml` を追加した。
- [x] `scripts/codd_check.sh` を追加した。
- [x] `Makefile` に `codd*` targets を追加した。
- [x] GitHub Actions に default gate を追加した。
- [x] `Update.bat` / `scripts/update_manager.py manual` から CoDD 更新を呼ぶ。
- [x] README / README_ja / REQS を更新した。
- [x] 検証を実行し、結果を記録する。

## 検証

- `bash -n scripts/codd_check.sh`
- `bats tests/unit/test_codd_integration.bats`
- `python3 -m unittest tests.unit.test_update_manager`
- `bash scripts/codd_check.sh version`
  - PASS: `codd 1.34.0`, `Version check: PASS (requires >=1.34.0)`
- `bash scripts/codd_check.sh verify`
  - PASS with amber warning: `node_completeness`, `edge_validity`, `depends_on_consistency`, `transitive_closure` は red failure なし。`transitive_closure` は unreachable nodes を amber として報告。
- `CODD_VERSION_SPEC='>=9999' CODD_FALLBACK_VERSION=1.34.0 bash scripts/codd_check.sh install`
  - PASS: latest/spec 導入失敗後、`codd-dev==1.34.0` へ fallback する。
- `python3 scripts/update_manager.py manual`
  - PASS: git-local のため code update は skip し、integrated tools として CoDD install/update を実行した。
- `make codd`
  - PASS with amber warning: `codd dag verify` は red failure なし。`transitive_closure` は unreachable nodes を amber として報告。
- `PYTHONPATH=/tmp/codd-dev-inspect-20260507 python3 -m codd dag build --path .`
  - PASS: `Built DAG: 113 nodes, 40 edges, 0 cycles`
- `PYTHONPATH=/tmp/codd-dev-inspect-20260507 python3 -m codd dag verify --path .`
  - PASS with amber warning: `node_completeness`, `edge_validity`, `depends_on_consistency`, `transitive_closure` は red failure なし。`transitive_closure` は unreachable nodes を amber として報告。

## 残リスク

- CoDD の `audit` は optional bridge 依存のため、通常環境では使えない可能性がある。
- CoDD の最新 package version と README 表記に差がある場合があるため、wrapper は `CODD_VERSION_SPEC` で上書きできるようにする。
- source tree smoke では installed version が `1.30.0` と表示されたため警告が出た。PyPI package は `1.34.0` を確認済み。project config は `codd_required_version_strict: false` とし、実運用では `scripts/codd_check.sh install` で PyPI package を入れる。
