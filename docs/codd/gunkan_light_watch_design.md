---
codd:
  node_id: "design:gunkan-light-watch"
  type: "design"
  depends_on:
    - id: "req:gunkan-monitoring"
      relation: "satisfies"
      semantic: "governance"
  source_files:
    - "scripts/gunkan_light_watch.py"
    - "scripts/watcher_supervisor.sh"
    - "shutsujin_departure.sh"
  depended_by:
    - id: "test:gunkan-light-watch"
      relation: "verified_by"
      semantic: "validation"
---

# Gunkan Light Watch Design

`scripts/gunkan_light_watch.py` は非LLMの監視器として動く。
監視結果は `queue/runtime/gunkan_watch.yaml`、dedup/cooldown 状態は `queue/runtime/gunkan_light_watch_state.yaml` に保存する。
重大または警告 finding が cooldown を超えて発生した場合だけ、`queue/inbox/gunkan.yaml` に `audit_requested` を追加する。
