# AGMSG Bridge 設計書(Phase 1 + Phase 2)

- 状態: 実装中(ブランチ `codex/agmsg-bridge`)
- 実装担当: Codex(レビュー: Claude)
- 発注元要件: テンプレート root の `docs/REQS.md` / `docs/EXECPLAN_AGMSG_BRIDGE.md`

## 目的

inbox 通信の「起床シグナル層」に agmsg (https://github.com/fujibee/agmsg, `~/.agents/skills/agmsg/` に v1.1.6 導入済み) を追加する。
tmux send-keys nudge の脆さ(カーソル位置バグ、drvfs 上の inotify 不発)を、SQLite + hook ベース配信で置き換え可能にする。

## 設計原則(変更禁止の前提)

1. **YAML インボックスは永続層として維持する。** `queue/inbox/{agent}.yaml` への書き込み、`read: false` 管理、エージェントの読み取りプロトコル(instructions/*.md, CLAUDE.md)は一切変更しない。
2. **agmsg は起床シグナルにだけ使う。** agmsg メッセージの body は「未読あり、inbox YAML を読め」というポインタのみ。タスク内容は運ばない。
3. **既定挙動は完全後方互換。** `transport.mode` 未設定または `yaml` のとき、現行と 1 bit も挙動を変えない。
4. **エスカレーション梯子(2分/4分/clear)は全モードで維持する。** agmsg はあくまで優先起床経路であり、安全網は watcher に残す。
5. フォークの CLAUDE.md にある破壊的操作禁止・ルート政策(validate_route_policy)を尊重する。

## 設定仕様(config/settings.yaml に追加)

```yaml
transport:
  mode: yaml          # yaml | agmsg | both。既定: yaml(キー欠落時も yaml)
  agmsg:
    team: shogunate           # agmsg チーム名
    skill_dir: ""             # 空なら ~/.agents/skills/agmsg。テストで stub に差し替えるため
    bridge_agents: []          # mode=yaml でもここに載せた agent には agmsg を併送(Phase 1 実験用)
```

モード仕様(送信側 = write.sh、起床側 = inbox_watcher.sh):

| mode | YAML 書込 | agmsg 送信 | tmux nudge |
|------|-----------|------------|------------|
| yaml(既定) | する | bridge_agents 記載の宛先のみ | する(現行どおり) |
| both | する | する(全宛先) | する(現行どおり) |
| agmsg | する | する(全宛先) | 標準 nudge をスキップ。ただしエスカレーション(2分以降)は現行どおり発動 |

## 実装対象

### 新規: `shogunate_mod/transport/agmsg_bridge.sh`

関数ライブラリ(source して使う)。役割:

- `agmsg_bridge_enabled <target>`: settings.yaml の transport 設定を読み、この宛先に agmsg 送信すべきか判定(mode と bridge_agents から)。settings 読取りは既存の設定読取りパターン(python3 + yaml)を踏襲する。
- `agmsg_bridge_send <target> <type> <from>`: `${skill_dir}/scripts/send.sh` を呼び、body は固定形式 `"[shogunate] inbox: unread message(s) waiting. Read queue/inbox/<target>.yaml and process type=<type> from <from>."` とする。**失敗しても exit code 0 で返し、stderr に警告のみ**(agmsg 障害で YAML 経路を殺さない)。
- `agmsg_bridge_team` / `agmsg_bridge_skill_dir`: 設定の getter。`AGMSG_SKILL_DIR` 環境変数があれば settings より優先(テスト stub 用)。

### 新規: `shogunate_mod/transport/agmsg_setup.sh`

- settings.yaml の `topology.active_ashigaru` + shogun/gunkan/gunshi/karo を、`cli.agents.<name>.type` を agmsg の type(codex→codex, claude→claude-code, opencode→opencode, antigravity→antigravity, gemini→gemini, copilot→copilot, cursor→cursor)にマップして `join.sh <team> <agent> <type> <このリポジトリの絶対パス>` で参加させる。未対応 type(kimi / kilo / localapi 等)や type 空/欠落のエージェントは `[agmsg_setup] skip <agent>: no agmsg driver for cli type '<type>'` 警告を stderr に出して**スキップ**し、残りのエージェントの join を続行する。対応 type が 1 体も join できなかった場合のみ exit 1 とする。
- 冪等であること(再実行してもエラーにしない。join.sh が重複でエラーを返すなら無視して続行)。

### 変更: `shogunate_mod/inbox/write.sh`

- 既存の YAML 書き込み成功後(history_book / event_log と同じ位置)に、`agmsg_bridge_enabled "$TARGET"` なら `agmsg_bridge_send` を呼ぶ。3〜5 行程度の追加に留める。
- agmsg 送信失敗は書き込み全体の失敗にしない。

### 変更: `shogunate_mod/watcher/inbox_watcher.sh`

- mode=agmsg のとき、優先度2 の標準 tmux nudge をスキップする(優先度1 の self-watch 判定とエスカレーション梯子はそのまま)。
- 変更は nudge 送出の判定分岐 1 箇所に絞る。watcher は 2183 行あるので、大規模リファクタ禁止。設定読取りは起動時 1 回 + 変更検知時再読込など、既存の設定読取りパターンに合わせる(なければ起動時 1 回で可)。

### テスト(bats、既存の tests/ 構成に合わせる)

新規 `tests/test_agmsg_bridge.bats`(または tests/unit/ 配下、既存慣習に従う):

1. mode 未設定 → `agmsg_bridge_enabled` が偽、write.sh が agmsg を呼ばない(stub の呼出記録が空)
2. mode=yaml + bridge_agents=[ashigaru1] → ashigaru1 宛だけ agmsg 送信、karo 宛は送信しない
3. mode=both → 全宛先で agmsg 送信 + YAML も書かれる
4. mode=agmsg → agmsg 送信 + YAML も書かれる
5. agmsg send.sh が exit 1 を返しても write.sh は成功し、YAML にメッセージが残る

stub 方法: テスト用の偽 skill_dir(`scripts/send.sh` が引数をログファイルに追記するだけ)を fixtures に置き、`AGMSG_SKILL_DIR` で差し替える。**テストから本物の `~/.agents/skills/agmsg` や実 DB に触れない。**

既存テストへの影響: `make test` が全部通ること。SKIP は FAIL 扱い(このリポジトリのルール)。

## 受け入れ条件

- [ ] 上記テスト 5 件 + 既存 `make test` が green
- [ ] mode 未設定の実挙動が現行と同一(write.sh の diff が示せること)
- [ ] `bash shogunate_mod/transport/agmsg_setup.sh` が冪等に通る
- [ ] shellcheck 相当の静的問題を持ち込まない(既存 lint ターゲットがあれば通す)

## E2E 手順(Phase 1 検証、実装完了後に実施)

1. `agmsg_setup.sh` で karo と足軽 1 体(claude type のもの)を join
2. settings.yaml で `transport.mode: yaml` + `bridge_agents: [<その足軽>]` に設定
3. tmux で該当足軽を実起動(認証済みセッション)
4. `bash shogunate_mod/inbox/write.sh <足軽> "E2E疎通テスト。inboxを読み、read:trueにせよ" task_assigned karo`
5. 確認: (a) agmsg DB にメッセージが入る (b) 足軽が hook 配信で起床して inbox YAML を処理する (c) 配信遅延を記録 (d) 既存 Stop hook(ASW)と衝突しない
6. 結果を本書末尾の「検証記録」に追記

## 検証記録

### 2026-07-10 実エージェント E2E(Phase 1 構成)

- 構成: `transport.mode: yaml` + `bridge_agents: [ashigaru3]`、agmsg delivery=both(monitor 主体 + Stop hook)。inbox_watcher は**起動せず**(nudge なしの純 agmsg 配信を検証)。
- 手順: tmux で ashigaru3(claude-code)を実起動 → SessionStart hook が Monitor(watch.sh)を起動 → karo として `write.sh ashigaru3 ... task_assigned karo` を送信。
- 結果:
  - 1回目: 送信 23:16:32 → inbox YAML 全既読 23:16:56 以前(≤24秒)
  - 2回目: **送信→read:true まで 22 秒**(agmsg monitor 配信 + エージェントの turn 処理込み)
  - YAML 経路は無傷(メッセージは queue/inbox に永続化されたまま処理された)
  - Stop hook 共存: pane 表示「running stop hooks… 1/2」— 既存 hook と agmsg check-inbox が併走し衝突なし
- 発見事項:
  1. **入れ子 CLAUDE.md の trust prompt**: フォークは表層ハーネスの子ディレクトリにあるため、起動時に「親の CLAUDE.md external imports を許可するか」の確認で停止する。自動起動フローでは `--dangerously-skip-permissions` でも出るため、初回起動時の許可操作(または trust 設定の事前投入)が必要。
  2. **agmsg 側の read_at が未設定のまま残る**: monitor 配信されても messages.db の read_at は NULL のまま(YAML 側の read:true とは独立)。ポインタ通知なので再配信されても実害は小さい(inbox 全既読なら no-op)が、未読が蓄積するため、定期 cleanup か受信側での既読化を Phase 3 で検討する。
  3. 遅延 22 秒の内訳はおよそ「monitor 配信 ~5s + エージェント turn(YAML 読取 + Edit)」。分単位のタスクサイクルでは十分実用的。
- 判定: **Phase 1 受け入れ条件を満たす。** hook 同居 OK、nudge なし配信 OK、遅延実用域。
