---
codd:
  node_id: "design:gunkan-codd-audit"
  type: "design"
  depends_on:
    - id: "req:gunkan-monitoring"
      relation: "supports"
      semantic: "governance"
  source_files:
    - "scripts/gunkan_codd_audit.py"
    - ".codd/codd.yaml"
  depended_by:
    - id: "test:gunkan-light-watch"
      relation: "verified_by"
      semantic: "validation"
---

# Gunkan CoDD Audit Design

軍監は監査イベント時だけ CoDD を呼び出す。
`scripts/gunkan_codd_audit.py` は `PATH` 上の `codd` と repo-local `.shogunate/codd-venv` の `codd` を検出し、
`codd scan`、`codd impact`、`codd validate` の結果を `queue/runtime/codd/gunkan_audit.yaml` に保存する。
