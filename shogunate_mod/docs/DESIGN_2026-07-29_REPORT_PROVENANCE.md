# Report Provenance Design

plan_id: PLAN-20260729-RUNTIME-IDENTITY-HARDENING
date: 2026-07-29

## 目的と背景

前回の system matrix で、別 role の pane が self-agent を名乗り、Karo 内蔵
の self-agent report だけで Shogun へ `cmd_done` を送る false completion が
発生した。本設計は、report を受領する inbox/write.sh 経路と completion relay
に対し、「提出元 pane がその role 本人で、現在の generation / CLI /
report digest と一致し、そのreceiptが対象task / parent command専用か」を
機械検出する境界を導入する。

これは暗号境界ではない。同一ローカルユーザが悪意をもって runtime file を
直接偽造する攻撃は防げない。HMAC や secret を導入してもローカルでの secret
管理が成立しにくく、複雑化するだけである。今回の事故は別 role pane からの
偶発的 self-agent 代用なので、role / generation / pane / digest の一致確認で
再現経路を止める十分な境界とする。

## 境界の構成要素

純粋関数 module `shogunate_mod/runtime/report_provenance.py` が以下を提供する。

1. **pane identity 検証** (`verify_pane_identity`):
   inbox/write.sh が tmux から `@agent_id` / `@role_generation` /
   `@agent_cli_running` / `@agent_cli` と `$TMUX_PANE` を集めて渡す。本関数は
   これらと role_failover 状態を照合し、不一致なら理由を返す。
   検証項目:
   - pane 情報が存在する (`missing_pane`)
   - pane の `@agent_id` が role と一致 (`wrong_role`)
   - generation が failover 現 generation と一致 (`stale_generation`)
   - role が停止状態でない (`role_stopped`)
   - CLI pane が running (`cli_stopped`)
   - CLI type が現 slot と一致 (`cli_mismatch`)
   - report path が role の所期 path (`report_path_mismatch`)

2. **atomic receipt** (`build_receipt` / `write_receipt`): 合格時に
   `queue/runtime/report_receipts/<role>.yaml` へ SHA-256 digest を含む receipt
   を原子書き込みする。schema v2は`task_id`と`parent_cmd`も保存するため、古い
   commandのreceiptを同generationの別commandへ再利用できない。missing/empty
   reportとparent command欠落はreceipt作成前に拒否する。role ごとに最新 report
   を置き換え、同じ digest の再提出は冪等。

3. **completion gate** (`validate_completion` / `required_receipt_roles`):
   cmd の `audit_gate`、cmd inline role、`queue/tasks/*.yaml`で`parent_cmd`が一致する
   実task roleの和集合をrequiredとする。required roleが空の場合も完了させない。
   全 role 分の receipt と **現 report 内容** を再照合し、1 件でも欠落・別 role
   ・stale ・改変済みなら `cmd_done` を送らず blocked ledger へ固定 reason を
   1 件だけ記録する。receipt 後の report 改変は digest mismatch で検出される。

4. **strict marker** (`is_strict_mode` / `enable_strict_mode`):
   `queue/runtime/report_provenance_required` marker がある時だけ strict gate
   が有効。marker がない既存 runtime は legacy 扱いで completion relay は従来
   挙動を保つ。`launch.sh` が新 runtime 起動時に marker を作ることで、更新再起動
   後に fail-closed に切り替わる。helper/marker作成に失敗した起動は中止し、strict
   runtimeでhelperが欠落したreport受理も拒否する。

## 連携先 (本 module の利用側)

- `shogunate_mod/inbox/write.sh`: `report_received` / `audit_report` 型のみ
  provenance 必須とし、合格時に receipt を作る。非 report message と daemon の
  `cmd_done` 互換は維持する。
- `shogunate_mod/runtime/karo_done_to_shogun_bridge.py`: marker 有効時に receipt
  gate を通し、不合格なら通知・送信済み state 更新をせず、固定 schema の blocked
  ledger へ記録する。
- Gunkanの正規reportは`queue/reports/gunkan_report.yaml`。report path照合は
  filenameだけでなく`queue/reports/<role report>`全体を要求する。

## Bootstrap readinessとの関係

完了境界と起動表示を同じfail-closed方針にする。summaryはbootstrap pending file数を
readyの代用にせず、各実paneで確認した`ready:<role>`応答数を使う。Karoとpane未解決roleも
総数へ含め、未達時は`bootstrap_ready_state.yaml`へ`degraded`を保存して
「出陣準備未完了」と表示する。fallback promptにはtarget projectとruntime rootを
直接含め、外部bootstrap fileを権威として読むよう要求しない。

## 幂等性と復旧

- receipt は role ごとの最新 report を atomic replace し、同じ digest の再提出
  を安全に上書きできる。
- blocked ledger は cmd identity + reason で重複を抑止する。
- loop 中断後は receipt / ledger と report 現内容から再検証できる。

## 検証

純粋関数とbridge統合testで、tmuxなしでもpane/task/cmd/report境界を検証する
（`tests/unit/test_report_provenance.py`、mirrorは同一）。異種CLI実runtimeでは、
実Codex Ashigaru receipt、別pane相当の偽report拒否、bridgeのblock/正常送信を確認した。
