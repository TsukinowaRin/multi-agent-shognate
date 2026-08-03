# Requirements

最終更新: 2026-08-03

## 現在の依頼

Shogunateコマンドから任意の役職を常設または任務限定のMoAとして設定・展開できるようにし、AGMSG経由の割当、提案提出、代表者による正式成果物の確定、自動解散が実際に動くことを検証する。

追加要求として、Shogunate本体のnpm package metadata、lockfile、Node製CLI、npm/npxによる初回自動導入を廃止する。導入経路はcURL bootstrapとGitHub Release archiveだけにし、cURL導入後のBash製`shogunate`コマンドからMoAと軍議を操作できるようにする。

`shogunate configure`を役職ごとのデフォルト構成を決める入口にする。役職の担当者数を選び、1人なら通常のsingle構成、2人以上ならMoA構成として保存する。MoAでは先に代表者1人を選び、残りのメンバーを必要人数分選ぶ。

実装と検証を意味ある履歴としてコミットし、現在の`codex/ci-green`をoriginへpushする。同じcommitからcURL release archiveを作り、このPCの通常ユーザー領域にShogunateを導入して実コマンドを確認する。

## 受け入れ条件

1. 任意の役職に`single`またはデフォルト`moa`を設定できる。
2. MoAでは代表者、2〜8名のメンバー、定足数、決定policy、解散条件が必須である。
3. `deploy`へ完全なprofileを渡すと現在の任務だけ構成を変更でき、保存済みデフォルトは変わらない。
4. task ID、role generation、member identity、assignment digest、model/runtime provenanceが一致しない提案を拒否する。
5. 代表者以外の確定、定足数不足、重複model/runtime、未解決critical vetoを完了扱いにしない。
6. AGMSG本文はassignment pathだけを運び、任務、提案、正式成果物、receiptの正本は`queue/moa/`に置く。
7. `shogunate moa agmsg-setup`が公式AGMSG scriptでidentityを登録し、複数identityへの別assignment配送を検証できる。
8. npm/Node package資材がworktreeとcURL release archiveに存在せず、初回セットアップがnpm/npx/nvmを自動実行しない。
9. cURL導入後の`shogunate`が`council`と`moa`を直接実行できる。
10. unit、cURL distribution、security、template smokeを弱めずPASSする。
11. `shogunate configure`で役職の担当者数を1〜8人から選べ、1人を`single`、2人以上を`moa`として保存できる。
12. MoA選択時は代表者を先に選び、残りのメンバーを同一人物・同一model/runtimeの重複なしで選ぶ。
13. 既存の非対話`shogunate moa configure`は維持し、CIや自動化から引き続き使える。
14. commit後のpackage gateを通し、そのcommitかcURL導入した`shogunate help`、`configure --help`、`moa --help`がこのPCで動作する。
15. push先は現在の`codex/ci-green`に限定し、main/master、tag、GitHub Releaseは変更しない。

## 制約

- 既存Gunshi councilのリーダー責任制、Gunkan監査、Ashigaru handoffを変更しない。
- 既存queue、project、tmux session、secret、credentialを変更しない。
- AGMSGのDB/configを直接操作せず、公式付属scriptだけを使う。
- AI CLI自体が採用する内部runtimeや第三者CLIの導入方式は、このnpm配布廃止の対象外とする。Shogunate本体はnpmを導入・実行しない。
- ユーザは現在ブランチへのcommit/pushとこのPCの通常ユーザ領域への導入を明示許可した。release、tag、main/master操作、管理者権限は行わない。

## 過去の要求

2026-06-27までの要求は`docs/legacy/REQS_ARCHIVE_2026-06-27.md`へ移動した。
