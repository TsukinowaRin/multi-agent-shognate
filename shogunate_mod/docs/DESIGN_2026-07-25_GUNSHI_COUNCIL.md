# Gunshi 軍議

## 目的

Gunshiが新しい計画を立てるときだけ、複数の上位モデルを短時間招集する。
常設の役職は増やさず、計画がまとまったらGunkanが独立監査する。監査PASS後に
成果物をGunshiへ渡して解散する。

出席者に固定担当は割り当てない。代表者だけを決め、誰がどの観点を担うかは
議題と会話に応じて変える。

## 人数に依存しない会話

2名と3名以上でsystemを分けない。すべての軍議で1つの共有議事録と同じ
cycle protocolを使う。2名なら非代表者が1名、3名以上なら非代表者が複数に
なるだけで、状態遷移、context、収束条件は変わらない。

```text
代表が初案
  ↓
cycle開始時の計画・議事録を全非代表者へ配布
  ↓
各自が同じsnapshotに反証・改善を返す
  ↓
全発言を共有議事録へ追加
  ↓
代表が統合して計画を改訂
  ↓
次cycleでは全員が前cycleの全発言を読める
```

同じcycle内の非代表者は互いの新規発言を見ない。全員が同じsnapshotから
考えることで発言順の有利不利を避ける。2名の場合も代表者の統合発言が共有
議事録へ入り、次cycleで非代表者がそれを読むため、同じ仕組みで双方向の
反証・改善が続く。3名以上では次cycleから他の非代表者の発言も見える。

## 収束

代表者が`converged`を宣言しても、その場では解散しない。状態を`closing`に
して、改訂された最終候補に対する異議受付cycleを必ず1回置く。

次の条件をすべて満たすと`awaiting_audit`になり、Gunkanへ渡せる。

- blocking objectionが残っていない
- 未解決項目がない
- 目的、範囲、手順、検証、停止条件、再軍議条件がそろっている
- 最終候補を見た出席者の異議受付cycleが済んでいる

Gunkan監査がPASSしたときだけ`dissolved`になる。FAILなら指摘をblocking
objectionとして共有議事録へ追加し、`deliberating`へ戻す。

固定cycle数は設けない。未収束は失敗でも完成でもなく、同じ軍議を次の
`advance`へ進める。議事録が上限に達した場合は自動要約で情報を落とさず、
checkpointが必要として停止する。

## 状態と成果物

軍議ごとに`queue/council/<council-id>/`を作る。

- `brief.txt`: 開催時の議題
- `state.yaml`: 最新計画、共有議事録、異議、解決記録、状態
- `plan.md`: Gunkan監査に合格した人間向け計画
- `handoff.yaml`: 監査結果と実装責任者を含む機械可読な引き継ぎ

`reopen`は既存成果物を削除せず、revisionを進めて審議へ戻す。

## Gunkan監査と実装への引き継ぎ

```text
軍議リーダーが最終候補をまとめる
  ↓
Gunkanが独立監査する
  ↓ PASS
軍議を解散し、Gunshiが確定計画を受け取る
  ↓
GunshiがKaroへ計画を渡す
  ↓
Karoが作業を分け、Ashigaruへ割り当てる
  ↓
Ashigaruが実装し、Gunshiが品質を確認する
```

Gunkanは軍議メンバーではなく、計画を作り直したりAshigaruへ指示したりしない。
FAIL時は修正点だけを返す。`handoff.yaml`は`next_owner: gunshi`、
`dispatch_owner: karo`、`implementation_owner: ashigaru`を固定する。

## agmsgとの境界

agmsgは複数CLI間のローカルメッセージ配送に向く。一方、発言順、broadcast、
異議の解決、収束判定、停止条件は軍議側のprotocolとして別に必要になる。

Shogunateの既存agmsg bridgeは「YAML inboxに未読がある」という起床通知だけを
運び、task本文は運ばない。pilotではこの責務を変えず、軍議の会話は
`state.yaml`の共有議事録で扱う。将来、軍議メンバーを長寿命のinteractive
sessionにする場合は、agmsgを起床・配送層として追加できる。その場合も
共有議事録と収束gateは軍議controllerに残す。

## 安全境界

- 実モデル呼び出しには`--allow-paid-models`を明示する。
- Codexはread-only・ephemeral、Claudeはtoolなし・session非永続で起動する。
- Grokはtool、web、memory、subagentを無効化し、Antigravityはplan modeとsandboxで起動する。
- Opencodeはinlineの専用agent policyで全toolをdenyし、`--auto`なしのone-shotで起動する。
- brief、repository文書、モデル出力はuntrusted dataとして扱う。
- stateやモデル出力をshell commandとして実行しない。
- 軍議メンバーへedit、admin、delete、publish、secret accessを与えない。
- Gunkan監査もread-only one-shotで実行し、実装指揮や自動dispatchを許可しない。
