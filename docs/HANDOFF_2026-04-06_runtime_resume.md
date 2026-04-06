# Handoff: 2026-04-06 Runtime Resume

最終更新: 2026-04-06 JST

## この文書の目的

新しいチャットで記憶のないエージェントが、`AGENTS.md` と `docs/INDEX.md` を読んだ直後に、この repo の現状、直近の修正、何が終わっていて何が止まっているか、次に何をすべきかを把握できるようにする。

この文書は 2026-03-29 時点の handoff を置き換える最新の正本である。古い [docs/HANDOFF_2026-03-29_resume.md](docs/HANDOFF_2026-03-29_resume.md) は経緯確認用としてのみ扱うこと。

## 最初に読むべきもの

1. `AGENTS.md`
2. `docs/INDEX.md`
3. この文書
4. 必要に応じて
   - `docs/REQS.md`
   - `docs/EXECPLAN_2026-03-29_isolated_runtime_validation.md`
   - `docs/EXECPLAN_2026-04-05_codex_shared_auth.md`

## 現在の作業対象

- main repo:
  - `/mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate`
- branch:
  - `codex/upstream-sync-2026-03-29`
- 現在の HEAD:
  - `b708faf` `codex: 折返しCodex promptの検知漏れを防ぐ`
- `git status`:
  - clean

## この handoff 時点での重要な事実

### 1. すでに業務運用に効く修正はかなり入っている

以下はすべて main repo へ反映済みで、commit / push 済み。

- `b3d26f7`
  - role ごとの `CODEX_HOME` は維持しつつ、`auth.json` だけを `.shogunate/codex/shared/auth.json` で共有
- `70b4685`
  - watcher / bridge / runtime sync を `goza-runtime` tmux session で常駐化
- `4cecb73`
  - 全役職の event-driven 規則を instruction と bootstrap 文面へ明文化
- `f5e3c2d`
  - watcher 常駐と Codex prompt 回復の安定化
- `ed822ff`
  - `cgo` などの alias を repo-local に自己修復
- `b6b1b2c`
  - wrapped usage-limit prompt の compact 判定、`runtime-pref` window self-heal
- `858cdb6`
  - `runtime_sandboxes/**` を ignore し、VSCode Git の検証生成物ノイズを抑止
- `b708faf`
  - 折返し `switch-confirm` / `Keep current model` prompt を watcher / startup が compact 判定で拾えるよう修正

### 2. 実 runtime では少なくとも 1 本の burn-in 完走を確認済み

main repo runtime で `cmd_900` を投入し、以下を確認した。

- 経路:
  - `shogun -> karo -> ashigaru1/ashigaru2 -> karo -> shogun`
- 結果:
  - `cmd_done` 返却まで完了
  - `runtime_sandboxes/burnin_probe_three/` に blocked 集計追加が反映
  - `python3 -m unittest runtime_sandboxes/burnin_probe_three/tests/test_app.py` PASS

`cmd_900` の内容:
- `blocked_count`
- `blocked_ids`
を CLI 出力へ追加し、README / tests を更新する task だった。

### 3. 2 本目 `cmd_901` は repo bug ではなく外部 quota で停止中

`cmd_901` は次の内容で queue に残っている。

- `runtime_sandboxes/burnin_probe_three/` に
  - `latest_done_id`
  - `latest_blocked_id`
  を追加し、README / tests 更新、検証完了まで閉じる

しかし fresh runtime 直後に `karo` が折返し `rate-limit` prompt を踏み、その dismiss 自体は修正後に成功したものの、その直後 shared auth 側アカウントの hard `usage-limit` へ遷移した。

このため、現在の停止要因は repo ではなく外部 quota である。

### 4. 現在は「tmux session が残っている前提」で再開しないこと

この handoff を書いている時点では、

- `tmux list-sessions`
  - `error connecting to /tmp/tmux-1000/default`

となっており、live tmux runtime は残っていない。  
queue と dashboard には直前状態が残っているが、**次のエージェントは live session 継続ではなく `clean start` 前提で再開すること。**

## queue / dashboard の直前状態

### `queue/shogun_to_karo.yaml`

- `cmd_901` が `status: pending` のまま残っている

### `queue/inbox/karo.yaml`

- `cmd_901` の `cmd_new` が `read: false`

### `dashboard.md`

以下の blocked notice が残っている。

- `runtime-blocked/gunshi`
  - `Codex hard usage-limit prompt`
  - detail: `try again at 5:25 PM.`
- `runtime-blocked/karo`
  - `Codex hard usage-limit prompt`
  - detail: `You've hit your usage limit`

つまり、再開時にこの queue 状態をそのまま流すか、`-c` で clean start して task を再投入するかを決める必要がある。

## 直近で確認した重要挙動

### 1. shared auth は機能している

- `auth.json` は `.shogunate/codex/shared/auth.json` を正本にしている
- role ごとの `auth.json` は shared file への参照で揃う
- model / `reasoning_effort` は launch flag 側で維持される

運用上の意味:

- 1 role だけログインすれば、同じ shared auth を全 role が使う
- ただし **すでに起動中の Codex プロセスは新しい auth を自動再読込しない**
- account 切替をしたら `clean start` が必要

### 2. event-driven 規則は instruction と bootstrap に反映済み

role ごとの wake 条件は明文化済み。

- shogun:
  - `cmd_done` / 殿の次入力 / `ntfy`
- karo:
  - `cmd_new` / `report_received`
- ashigaru:
  - `task_assigned`
- gunshi:
  - inbox event / 分析 task

### 3. runtime daemon は `goza-runtime` に分離済み

設計上の正本:

- `goza-no-ma`
  - 人が見る本体 pane
- `goza-runtime`
  - watcher / bridge / runtime sync / inbox watcher windows

この系統は `nohup/disown` ではなく tmux session 管理へ移行済み。

### 4. VSCode Git ノイズは fix 済み

`runtime_sandboxes/` の disposable 生成物が Git に見えていた問題は `.gitignore` で抑止済み。  
次のエージェントは、`runtime_sandboxes/` 配下を commit 対象として扱わないこと。

## 次にやるべきこと

### 最優先

1. shared auth を別アカウントへ切り替えるか、quota が戻るのを待つ
2. `bash shutsujin_departure.sh -c` で fresh runtime を立て直す
3. `cmd_901` を再開または再投入する
4. `cmd_done` をもう 1 本以上連続で返せるか burn-in を継続する

### 再開方針

推奨は **queue の残骸を信用しすぎず、fresh runtime で `cmd_901` を再投入し直す** こと。  
理由は、現在 tmux live state が無く、queue だけ旧状態が残っているため。

## 実際の再開手順

### A. 現状確認

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
git status --short --untracked-files=all
sed -n '1,200p' dashboard.md
sed -n '1,240p' queue/shogun_to_karo.yaml
sed -n '1,240p' queue/inbox/karo.yaml
```

期待:

- `git status` は clean
- `dashboard.md` に `runtime-blocked/karo` / `runtime-blocked/gunshi`
- `queue/shogun_to_karo.yaml` に `cmd_901`

### B. 別アカウントへ shared auth を切り替える場合

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate

tmux kill-session -t goza-no-ma 2>/dev/null || true
tmux kill-session -t goza-runtime 2>/dev/null || true
tmux kill-session -t shogun 2>/dev/null || true
tmux kill-session -t gunshi 2>/dev/null || true
tmux kill-session -t multiagent 2>/dev/null || true

mkdir -p .shogunate/codex/shared
mv .shogunate/codex/shared/auth.json ".shogunate/codex/shared/auth.json.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
find .shogunate/codex/agents -maxdepth 2 -name auth.json -delete 2>/dev/null || true

bash shutsujin_departure.sh -c
tmux attach-session -t goza-no-ma
```

ここで **どれか 1 つの Codex pane だけ** でログインする。  
shared auth なので 1 回で十分。

ログイン後:

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate
bash shutsujin_departure.sh -c
```

### C. burn-in 再開

`cmd_901` を clean start 後にもう一度流すなら、queue へ pending command を append する。

参考タスク:

- `runtime_sandboxes/burnin_probe_three/app.py`
  - `latest_done_id`
  - `latest_blocked_id`
  の追加

確認は少なくとも以下を見る。

```bash
sed -n '1,240p' queue/shogun_to_karo.yaml
sed -n '1,240p' queue/inbox/karo.yaml
sed -n '1,260p' queue/reports/ashigaru1_report.yaml
sed -n '1,260p' queue/reports/ashigaru2_report.yaml
sed -n '1,260p' queue/inbox/shogun.yaml
sed -n '1,200p' dashboard.md
```

## 追うべきログと pane

### queue 正本

- `queue/shogun_to_karo.yaml`
- `queue/shogun_to_karo_archive.yaml`
- `queue/inbox/karo.yaml`
- `queue/inbox/shogun.yaml`
- `queue/reports/ashigaru1_report.yaml`
- `queue/reports/ashigaru2_report.yaml`

### runtime ログ

- `logs/inbox_watcher_karo.log`
- `logs/inbox_watcher_shogun.log`
- `logs/shogun_to_karo_bridge.log`
- `logs/karo_done_to_shogun_bridge.log`
- `queue/runtime/goza_bootstrap_*.log`

### tmux pane

再起動後のよく使う確認:

```bash
tmux capture-pane -pt goza-no-ma:overview.0 -S -120 | tail -n 100
tmux capture-pane -pt goza-no-ma:overview.1 -S -120 | tail -n 100
tmux capture-pane -pt goza-no-ma:overview.3 -S -120 | tail -n 100
tmux capture-pane -pt goza-no-ma:overview.4 -S -120 | tail -n 100
tmux list-windows -t goza-runtime -F '#{window_index}:#{window_name}:#{window_active}:#{window_panes}'
```

## 「repo bug」と「外部要因」の切り分け

### repo 側で直したもの

- trust prompt 誤判定
- rate-limit prompt variant 取りこぼし
- wrapped usage-limit compact 判定
- switch-confirm / `Keep current model` 折返し prompt
- shell 戻り Codex pane の再起動
- bootstrap pending 復元
- runtime daemon の tmux 常駐化
- stale `cmd_done` replay
- `left` model 誤検出
- verification contract 不足
- Git ノイズ

### repo 側では突破できないもの

- Codex アカウントの hard `usage-limit`
- 認証そのもの
- `exec_command` 親環境に依存する tmux server 生存性

## commit/push の現状

直近 10 commit:

- `b708faf` `codex: 折返しCodex promptの検知漏れを防ぐ`
- `858cdb6` `codex: 検証sandboxのGitノイズを抑止する`
- `b6b1b2c` `codex: runtime prompt判定とpref daemonを安定化`
- `ed822ff` `codex: cgo alias を repo-local に自己修復する`
- `f5e3c2d` `codex: watcher常駐とcodex prompt回復を安定化`
- `4cecb73` `codex: 全役職のイベント駆動を明文化`
- `70b4685` `codex: runtime daemon を tmux 常駐化する`
- `b3d26f7` `codex: codex auth を role 間で共通化する`
- `1954cfd` `codex: idle時のcodex prompt停滞を防ぐ`
- `c52d5fb` `codex: codex rate-limit prompt variant を拾う`

## 次チャット用の依頼文

```text
AGENTS.md と docs/INDEX.md を読んで、docs/HANDOFF_2026-04-06_runtime_resume.md を起点に main repo の runtime burn-in を再開して。shared auth 前提で、external quota と repo bug を切り分けながら cmd_901 以降を続けて。
```

## 最後に

次エージェントは、**「Shogunate-test の旧 handoff から再開する」のではなく、「main repo の shared-auth runtime から再開する」** こと。  
再開の本質は、

1. shared auth の quota を解消する
2. fresh runtime を立てる
3. `cmd_done` をもう 1 本以上連続で返す

の 3 点である。
