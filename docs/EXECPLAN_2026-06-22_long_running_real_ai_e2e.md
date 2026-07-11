# ExecPlan: Long Running Real AI E2E

最終更新: 2026-06-22

## 目的

実AI混在構成の Shogunate runtime に大きめの開発タスクを与え、短い smoke では見えない長時間安定性、同期、watcher、bridge、Gunkan audit の詰まりを観察する。

## 前提

- 既存の未コミット変更は巻き戻さない。
- secrets、認証 token、秘密鍵、credential file の内容は読まない・出力しない。
- 既存 tmux session は kill しない。今回作る専用 session のみ停止対象にする。
- target project は `runtime_sandboxes/long-ai-e2e-<timestamp>/target-project` に隔離する。

## 実行構成

- Runtime source: current checkout `codex/cwd-project-runtime`
- CLI config:
  - shogun / gunkan / gunshi / karo: Codex
  - ashigaru1 / ashigaru2: OpenCode
  - ashigaru3: Claude
  - ashigaru4: Antigravity
- Dedicated tmux session: `shogunate-long-ai-e2e-<timestamp>`
- Dedicated daemon session: `goza-runtime-shogunate-long-ai-e2e-<timestamp>`

## 長時間タスク

隔離 project に、複数ファイルからなる小型WebアプリまたはCLIアプリを作らせる。要件は以下。

1. 実装、テスト、README、簡易実行手順を含む。
2. UI または CLI の observable output を持つ。
3. 足軽へ分担できる粒度に分ける。
4. 最終的に Gunkan 監査を通し、dashboard の戦果へ反映させる。

## 観察手順

1. 専用 session 名で clean runtime を起動する。
2. 全 role pane の ready と `queue/runtime/agent_cli.tsv` を確認する。
3. 将軍 pane へ長時間タスクを投入する。
4. 5分ごとに以下を観察する。
   - tmux session / pane 生存
   - pane busy/idle/blocked の兆候
   - `queue/shogun_to_karo.yaml`
   - `queue/tasks/*.yaml`
   - `queue/reports/*.yaml`
   - `queue/inbox/*.yaml`
   - `dashboard.md`
   - target project の成果物
5. 30分以上、可能なら60分程度観察する。
6. 詰まりがあれば原因を切り分け、必要なら修正して再実行する。

## 検証ログ

### 2026-06-22 実AI長時間E2E

- Run ID: `long-ai-e2e-20260622153555`
- Worktree: `runtime_sandboxes/long-ai-e2e-20260622153555/worktree`
- Target project: `runtime_sandboxes/long-ai-e2e-20260622153555/target-project`
- tmux session: `shogunate-long-ai-e2e-20260622153555`
- daemon session: `goza-runtime-shogunate-long-ai-e2e-20260622153555`
- 観察時間: 約15:38から16:20まで。起動から40分超、実タスク投入から30分超。
- 終了処理: 検証用 tmux session / daemon session のみ停止。worktree と成果物は証跡として保持。

#### 起動

- detached worktree の tracked `HEAD` には local `config/settings.yaml` が無いため、初回は既定の1足軽・Claude構成で起動した。検証条件と違うため停止し、worktree内に検証用 `config/settings.yaml` を作成して再起動。
- 再起動後の CLI 構成:
  - shogun / gunkan / gunshi / karo: Codex
  - ashigaru1 / ashigaru2: OpenCode
  - ashigaru3: Claude
  - ashigaru4: Antigravity
- tmux pane 実体では 8/8 ready を確認。
- ただし shogun / gunkan の Codex composer に初動命令が残り、手動で Enter を追送して ready が成立した。
- 起動ログは `7/7 ready` と表示したが、tmux 実体は shogun / gunkan / gunshi / karo / ashigaru1-4 の 8 pane ready。

#### タスク

将軍へ TaskForge 開発タスクを投入した。内容は Vanilla HTML/CSS/JS、Node標準テスト、CLI helper、README、Gunkan監査まで含む大きめの開発タスク。

観測結果:

- `cmd_001` が作成され、Karo に `cmd_new` が届いた。
- Karo が Gunshi / Ashigaru1-4 へ task YAML を分解した。
- Ashigaru1 / Ashigaru2 / Ashigaru3 / Ashigaru4 が実成果物と report を生成した。
- Gunshi が設計・リスク分析 report を生成した。
- Target project 生成物:
  - `index.html`
  - `styles.css`
  - `app.js`
  - `package.json`
  - `src/taskforge.js`
  - `test/taskforge.test.js`
  - `cli/taskforge.mjs`
  - `sample-data.json`
  - `README.md`

#### 検証結果

- 初回実装時:
  - `npm test` PASS（16 tests）
  - `node cli/taskforge.mjs validate sample-data.json` PASS
  - `node cli/taskforge.mjs summary sample-data.json` PASS
- Gunkan 初回監査:
  - `status: failed`
  - 指摘:
    - CLI / sample-data の status schema が `todo/in_progress/done`、UI/src 側が `backlog/doing/review/done` で不一致。
    - README が存在しない `src/core.js` を参照。
    - dashboard stats が priority分布を十分に表示していない。
    - Ashigaru3 の検証証跡が弱い。
    - `gunkan_light_watch` の artifact path 解決が target project 基準でなく、成果物欠落を誤検知。
- Redo 後:
  - CLI / sample-data / UI / src が `backlog/doing/review/done` に統一。
  - README の `src/core.js` 誤記は解消。
  - UI dashboard に priority distribution が追加。
  - `npm test` PASS（41 tests, 0 skipped）
  - `node cli/taskforge.mjs validate sample-data.json` PASS
  - `node cli/taskforge.mjs summary sample-data.json` PASS
- Gunkan 再監査:
  - `status: warn`
  - 破壊的操作や secret 参照は見当たらず。
  - 残注意は artifact path 誤検知と UI smoke / docs verify 証跡の弱さ。
- 最終状態:
  - `cmd_001`: `done`
  - `completed_at`: `2026-06-22T16:17:18+09:00`
  - Shogun が `cmd_done` を処理し、完了と `warn` 残注意を分けて報告。

## 残リスク

- Codex 長文 paste / bootstrap で Enter 追送が必要になるケースが再現した。
  - 起動時 shogun / gunkan の初動命令。
  - 将軍への長文タスク投入。
- 起動ログの ready 件数表示が 8 pane 構成に対して `7/7 ready` となり、実体と表示がズレた。
- Karo pane が30分超 `Working` のまま進行した。最終的に command は `done` になったが、非エンジニア向けには「止まっているように見える」懸念がある。
- Gunkan / light watch の artifact path 解決が target project 基準でなく、`target-project/app.js` などの成果物を誤検知した。
- Claude / Ashigaru3 pane に `git add target-project/ && git commit` のような入力が残る場面があり、実行はされなかったが危険操作候補として監視強化が必要。
- Antigravity が作業後に CLI feedback prompt を出し、手動 `0` skip が必要だった。
