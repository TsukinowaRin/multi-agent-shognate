# Plans Policy

## ExecPlan 作成基準
以下のいずれかに該当する場合、ExecPlanを作成する。
- 複数モジュールを横断する機能追加
- 既存運用に影響する重要リファクタ
- 実装段階が複数に分かれる移行作業

## ファイル命名
- `docs/EXECPLAN_YYYY-MM-DD_<topic>.md`

## 必須セクション
- Context
- Scope
- Acceptance Criteria
- Work Breakdown
- Progress
- Surprises & Discoveries
- Decision Log
- Outcomes & Retrospective

## 運用
- 停止点ごとに `Progress` / `Decision Log` / `Outcomes` を更新する。
- 仕様変更が発生したら `docs/REQS.md` と整合させる。
