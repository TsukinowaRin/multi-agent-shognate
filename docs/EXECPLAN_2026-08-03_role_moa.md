# 任意役職MoAとAGMSG配送

plan_id: PLAN-20260803-ROLE-MOA
基準commit: 31c1340
plan_revision: 2

<!-- execplan:original:start -->

## 目的 / 全体像

任意のShogunate役職を、設定上のデフォルトまたは任務限定の一時MoAとして扱えるようにする。MoAは複数の独立したメンバーと代表者1名から成るが、外部には1つの役職として正式成果物を返す。AGMSGはメンバーへの起床通知とShogunate成果物へのポインタ配送だけに使う。

## 背景と見取り図

- 既存`shogunate council`はGunshi専用で、モデルを直接呼び出す計画会議である。
- 既存AGMSG bridgeはYAML inboxを正本として、AGMSGを起床通知に限定している。
- 新機能は既存軍議を壊さず、役職共通の`shogunate moa`制御面を追加する。
- 優先順位は「任務限定の一時指定 > 役職デフォルト > single」。
- secret、workspace、git履歴、既存queue、既存tmux session、CLI権限境界を保護対象とする。
- 入力はユーザーCLI引数、settings YAML、MoA成果物、AGMSG tool output。すべてschema検証し、AGMSG本文を命令の正本にしない。
- 操作分類はruntime内のread/writeとAGMSG script呼び出し。network、admin、delete、publishは行わない。

## 作業計画

1. `moa.roles.<role>`の厳格schemaとrole/member識別子を定義する。
2. 常設設定の表示・設定・single復帰、一時MoAのdeploy/status/dissolveをCLIに追加する。
3. deploy時にtask、role generation、assignment digestを固定したメンバー別YAMLを作り、AGMSGでその相対pathだけを送る。
4. member submitと代表者finalizeを追加し、task/generation/digest不一致、同一runtime/model重複、定足数不足、非代表finalizeをfail-closedにする。
5. unit/CLI/package/bridge security testと、実AGMSG付属scriptによる複数identity配送・受信を検証する。

## 予定変更範囲

- 予定変更ファイル:
  - `shogunate_mod/moa/`
  - `shogunate_mod/package/npm_cli.js`
  - `shogunate_mod/configure/settings.yaml.sample`
  - `shogunate_mod/manifest.yaml`
  - `shogunate_mod/package/package.json`
  - `tests/unit/test_role_moa.py`
  - `tests/test_agmsg_bridge.bats`
  - 関連するShogunate公開docs
- 許容する付随変更:
  - package distribution contract test、AGMSG test helper、REQS/WORKLOG/本ExecPlanの同期
- 変更禁止範囲:
  - 既存`queue/`実データ、`projects/`、`.env`/credential、既存tmux session、既存Gunshi council状態遷移、test/gateの弱体化

## 検証と受け入れ条件

- strict config parsing、優先順位、代表者、定足数、重複多様性、task/generation/provenance、解散をpytestで検証する。
- npm CLI routeとpackage収録契約を検証する。
- AGMSG failureでも正本を失わず、配送成功時は複数memberが同じdeploymentの別assignmentを受信する。
- `pytest`対象、関連Bats、`make check`、`bash scripts/security_smoke.sh`相当の利用可能なgate、`git diff --check`を通す。
- SKIPは完了に数えない。sqlite3など前提不足で実AGMSGが不能ならNo-Goまたは未検証として明示する。

<!-- execplan:original:end -->

## 進捗

- [x] (2026-08-03 JST) 現行council、AGMSG bridge、npm CLI、設定sample、package境界を確認。
- [x] (2026-08-03 JST) role MoA core、Bash CLI、常設/任務限定設定、代表者確定、自動解散を実装。
- [x] (2026-08-03 JST) MoA、approval、cURL配布、旧来のnon-npm配布契約、structure/security/template smokeを実行。
- [x] (2026-08-03 JST) 公式AGMSG scriptで3 identityへ個別assignmentを配送し、2提案、代表者finalize、自動解散を確認。
- [x] (2026-08-03 JST) Shogunate本体のnpm metadata、lockfile、Node CLI、npm/npx/nvm自動導入を削除し、cURL release archiveのみへ移行。
- [x] (2026-08-03 JST) `shogunate configure`に役職ごとの人数選択を統合し、1人をsingle、2〜8人を代表者主導のデフォルトMoAとして保存。

## 現在の停止点

- 現在位置: 実装とworktree基準の検証完了。未コミット。
- 未完了: commit後の`make package-check`と、system `sqlite3` CLIがある配布先での最終AGMSG再実行。Batsは未導入のため未実行。
- 次の一手: 差分レビュー後にcommitし、`make package-check`を実行する。
- 次に読む文書: `docs/REQS.md`と本書の「成果と振り返り」。
- 次に実行するコマンド: `git status --short --branch`。

## 発見事項

- 観測: AGMSG付属scriptは現環境で`sqlite3`実行ファイルを見つけられない。
  根拠: `whoami.sh`が`sqlite3: command not found`で停止。Python 3.12のsqlite3 CLIはあるが`readfile()`拡張がない。
- 観測: 当初のnpm廃止差分でpackage distribution testが165件から25件へ減り、npmと無関係な契約も落ちていた。
  対応: npm専用契約だけを廃止し、release/runtime/Android/wrapper/manifestの98件を別moduleで復元。現行25件と合わせ123件を再実行した。
- 観測: 従来の`make package-curl-smoke`は`HEAD`だけをarchiveし、未コミット差分を検証しなかった。
  対応: 実indexを変更しない一時indexからworktree treeを作り、cURL導入スモークに使うよう修正した。
- 観測: MoAの内部identity、runtime名、quorum、policyをすべて対話で聞くと、通常設定が複雑になる。
  対応: `configure`は人数とCLIだけを聞き、代表者を先頭スロットとしてidentity/runtimeを自動生成。詳細指定は既存`moa configure`に残した。

## 逸脱提案

<!-- execplan:deviations -->
deviation: DEV-001 | npm資材とNode製CLIを廃止しcURL-only CLIへ置換 | 対象: package*.json, bin/shogunate.js, shogunate_mod/package/npm_cli.js, bootstrap/release/tests/docs | 日付: 2026-08-03
approval: DEV-001 APPROVED user 2026-08-03 「npmは完全廃止して。もう使わない。」

## 判断ログ

- 判断: 既存Gunshi councilを一般化せず、独立したrole MoA制御面を作る。
  理由: 既存の監査済み状態機械を壊さず、任意役職とAGMSGの非同期性を分離できる。
  日付/記録者: 2026-08-03 Codex
- 判断: npm用metadataとNode dispatcherを削除し、cURL package内の非Node CLIを正本にする。
  理由: ユーザーがnpmの完全廃止を明示した。MoAだけNode dispatcherへ追加すると廃止方針と矛盾する。
  日付/記録者: 2026-08-03 Codex（DEV-001承認済み）

## 成果と振り返り

- 成果: 任意役職MoAの設定、一時展開、AGMSG配送、提案受理、代表者による正式確定、自動解散を実装。Shogunate本体の配布をcURL/GitHub Release archiveに一本化した。
- 検証: package distribution 123 passed + 203 subtests、MoA/approval 31 passed、configure+MoA 18 passed、structure-check 11 passed、`shogunate configure`を含むworktree cURL install smoke PASS、security smoke PASS、template smoke exit 0、`git diff --check` PASS。先行実行でMoA単体15 passedと公式AGMSG E2EもPASS。
- 不足: Bats未導入のためBats suiteは未実行。production AGMSGが要求するsystem `sqlite3` CLIも未導入。隔離E2EではPython 3.12 SQLite互換helperを使用した。
- 学び: 配布方式を廃止するときも、その方式に付属していた非依存の品質契約は別の配布面へ移す必要がある。
- 目的との差分: AI CLIプロセス自体の自動起動は追加せず、AGMSGはidentity登録と起床通知に限定した。これは当初の権限境界を維持する意図的な差分である。

## 具体手順

1. test-firstでschema/state transitionを固定する。
2. core実装、CLI route、package/docs同期を小差分で行う。
3. targeted testから全体gateへ広げる。
4. 実AGMSG前提を満たす安全な経路だけでE2Eする。

## 冪等性と復旧

- 同じrole/taskのdeployは既存generationと一致すれば状態を返し、異なる構成での上書きを拒否する。
- dissolveは成果物を削除せず状態だけを閉じる。
- 中断後の再開手順: 本書、`docs/REQS.md`、`git status --short`を確認し、targeted pytestから再開する。

## 成果物とメモ

- `shogunate_mod/moa/manager.py`
- `shogunate_mod/moa/README.md`
- `shogunate_mod/configure/moa.yaml.sample`
- `tests/unit/test_role_moa.py`
- `tests/unit/test_package_distribution.py`
- `tests/unit/test_package_distribution_legacy_contracts.py`
- `shogunate_mod/package/bootstrap.sh`
