---
codd:
  node_id: "test:gunkan-light-watch"
  type: "test_case"
  depends_on:
    - id: "design:gunkan-light-watch"
      relation: "verifies"
      semantic: "validation"
    - id: "design:gunkan-codd-audit"
      relation: "verifies"
      semantic: "validation"
  source_files:
    - "tests/unit/test_gunkan_audit.bats"
    - "tests/unit/test_watcher_supervisor.bats"
---

# Gunkan Monitoring Tests

軍監の軽量監視は Bats で検証する。
主な検証対象は、検証不足の完了報告検知、cooldown による重複抑止、runtime daemon への `gunkan-watch` window 組み込みである。
