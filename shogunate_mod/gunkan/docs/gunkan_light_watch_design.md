---
codd:
  node_id: "design:gunkan-light-watch"
  type: "design"
  depends_on:
    - id: "req:gunkan-monitoring"
      relation: "satisfies"
      semantic: "governance"
  source_files:
    - "shogunate_mod/gunkan/light_watch.py"
    - "shogunate_mod/watcher/supervisor.sh"
    - "shogunate_mod/runtime/entrypoint.sh"
  depended_by:
    - id: "test:gunkan-light-watch"
      relation: "verified_by"
      semantic: "validation"
---

# Gunkan Light Watch Design

`shogunate_mod/gunkan/light_watch.py` は非LLMの監視器として動く。
監視結果は `queue/runtime/gunkan_watch.yaml`、dedup/cooldown 状態は `queue/runtime/gunkan_light_watch_state.yaml` に保存する。
重大または警告 finding が cooldown を超えて発生した場合だけ、`queue/inbox/gunkan.yaml` に `audit_requested` を追加する。
検出対象は YAML parse error、失敗 report、完了扱いなのに検証証跡が弱い report、done command と failed report/open task/dashboard の矛盾、
完了 report の明示成果物 path 欠落、report filename と `worker_id` の不一致、CoDD 設定欠落、git dirty file の secret/destructive pattern。
成果物 path の存在確認は path/artifact/output/file 系の明示キーだけを対象にし、URL、絶対 path、自然文、glob は除外して誤検知を抑える。
