---
codd:
  node_id: "req:gunkan-monitoring"
  type: "requirement"
  source_files:
    - "docs/REQS.md"
  depended_by:
    - id: "design:gunkan-light-watch"
      relation: "satisfies"
      semantic: "governance"
    - id: "design:gunkan-codd-audit"
      relation: "supports"
      semantic: "governance"
---

# Gunkan Monitoring Requirement

軍監LLMは常時動かさず、非LLMの軽量 watcher が queue、reports、dashboard、git diff、CoDD 設定を監視する。
軽量 watcher は不正、破壊的操作、報告矛盾、検証不足を見つけた時だけ `audit_requested` を軍監 inbox へ送る。
