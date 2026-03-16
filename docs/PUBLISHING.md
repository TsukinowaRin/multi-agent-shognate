# Publishing Policy

## 目的

- GitHub へ push / release する前に、個人情報、ローカル履歴、退避物、実行時データを公開対象から除外する。
- 「過去履歴は rewrite しないが、これから公開する最新状態は毎回 clean にする」という運用を固定する。

## 公開前の原則

1. 現在ツリーに個人情報やローカル固有値を残さない。
2. 退避フォルダ、履歴メモ、実行時データは Git 追跡対象にしない。
3. README / Android README / docs に、特定ユーザーのパス・IP・ホスト名・アカウント名を残さない。
4. GitHub Releases に載せる APK / asset も、同じ公開基準に従う。

## 非公開対象

以下は公開対象外とする。

- `Waste/`
- `_trash/`
- `_upstream_reference/`
- `docs/WORKLOG.md`
- `docs/HANDOVER_*.md`
- `docs/UPSTREAM_SYNC_*.md`
- `config/settings.yaml`
- 実行時 `queue/` データ
- `dashboard.md`
- ローカル生成ログ、バックアップ、個人用メモ

## 個人情報・ローカル値として扱うもの

以下は原則として公開しない。

- `/mnt/d/...` や `D:\\...` のようなローカル絶対パス
- `muro` など個人ユーザー名
- ローカル IP / Tailscale IP / ホスト名
- 個人用 `ntfy_topic`
- ローカル専用の接続例や private 運用メモ

## 公開前チェック

公開前には少なくとも次を実行する。

```bash
bash scripts/prepublish_check.sh
```

必要に応じて追加確認:

```bash
git status --short
git ls-files | rg '^(Waste/|_trash/|_upstream_reference/|docs/(WORKLOG|HANDOVER|UPSTREAM_SYNC)|config/settings.yaml|dashboard.md|queue/)'
git grep -n -I -E '/mnt/[a-z]/|[A-Za-z]:\\\\|192\\.168\\.|172\\.31\\.|100\\.[0-9]+\\.[0-9]+\\.[0-9]+|muro'
```

## 判定基準

- `prepublish_check.sh` が失敗したら push / release しない。
- 機微情報を消した上で再実行し、PASS してから公開する。
- 過去履歴の rewrite は通常行わない。必要になった場合だけ別判断とする。
