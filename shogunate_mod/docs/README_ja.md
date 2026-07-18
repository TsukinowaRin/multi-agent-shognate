<div align="center">

# Shogunate

**AI コーディング CLI を複数体で動かす、package install 対応の multi-agent runtime。**

将軍、家老、足軽、軍師、軍監を `tmux` 上に並べ、YAML queue と release package で運用します。

[![Release](https://img.shields.io/github/v/release/TsukinowaRin/multi-agent-shognate?style=flat-square)](https://github.com/TsukinowaRin/multi-agent-shognate/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) | [日本語](README_ja.md)

</div>

## 概要

Shogunate は、AI コーディング CLI 向けの local-first な multi-agent runtime です。1 つのリポジトリ workspace を `tmux` 上の見える司令室にし、将軍が依頼を受け、家老が計画と統合を行い、足軽が実作業を進め、軍師が戦略を見直し、軍監が完了状態を監査します。

このリポジトリには、その runtime を動かすための package、役職別 instruction、shell orchestration、queue ベースの agent message、Android pairing support、release installer が含まれています。Linux、macOS、Windows の WSL2 で動かす前提です。

Shogunate は次のような用途に向いています。

- hosted control plane なしで multi-agent coding workflow を使う
- `queue/`、`dashboard.md`、runtime metadata という plain file で状態を追う
- Codex、Claude Code、Copilot CLI、OpenCode、Kimi、Cursor、Antigravity を役職ごとに割り当てる
- cURL で入れられ、決まった local directory に展開・更新できる runtime として運用する

## インストール

latest release channel は cURL でインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

その後、Shogunate に作業させたい project directory へ移動して起動します。

```bash
cd /path/to/your-project
shogunate
```

installer は最新の GitHub Release package を取得し、engine を `~/.shogunate/shogunate` に展開し、`~/.local/bin/shogunate` を登録します。project directory で `shogunate` を実行すると、project 専用 runtime が `~/.shogunate/workspaces/` 配下に作られるため、queue、logs、dashboard、`tmux` session は project ごとに分離されます。

`shogunate` が見つからない場合は shell を開き直すか、PATH を追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
```

古い install が `~/.bashrc` に stale な `css()` / `csm()` 関数を残している場合は、latest release channel を再実行してから shell を読み直してください。

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
source ~/.bashrc
```

## 必要なもの

- Linux、macOS、または Windows の WSL2
- `bash`、`curl`、`tar`、`tmux`、`python3`
- 対応 AI coding CLI のいずれか
  - OpenAI Codex
  - Claude Code
  - GitHub Copilot CLI
  - OpenCode
  - Kimi Code
  - Cursor
  - Antigravity (`agy`)

役職へ割り当てる前に、通常の shell で使う CLI へログインしておきます。

```bash
codex
claude
opencode
agy
```

実際に使う CLI だけで大丈夫です。

## よく使うコマンド

```bash
shogunate                 # 現在の directory を対象に runtime 起動
shogunate clean           # 現在の directory を対象に clean start
shogunate resume          # この project の前回状態から resume
shogunate attach          # この project の tmux session に attach
shogunate configure       # この project の役職ごとの CLI を選ぶ
shogunate where           # project/runtime/engine/session の場所を表示
shogunate projects        # 登録済み project を一覧表示
shogunate battlefield     # 登録済み project runtime の一覧・起動・終了
shogunate app             # mobile / desktop app 用 JSON API
shogunate status          # package/update metadata を表示
shogunate aliases         # shell alias の source コマンドを表示
shogunate help            # help
```

別 project を明示する場合:

```bash
shogunate --project /path/to/another-project
shogunate attach --project /path/to/another-project
```

よく開く project は登録して、名前で選べます。

```bash
shogunate projects add /path/to/your-project --name myapp --select
shogunate projects
shogunate --project @myapp resume
shogunate open myapp
```

registry は既定で `~/.shogunate/projects.json` に保存されます。directory から `shogunate` を実行すると、その directory は自動で登録されます。Android の戦場タブも、host 側の `shogunate` が対応していれば、開いた remote project を同じ registry へ同期します。

スマホアプリやデスクトップアプリは、SSH shell や tmux pane 名を推測せず、本体APIを使います。

```bash
shogunate app capabilities --json
shogunate battlefield list --json
shogunate battlefield status myapp --json
shogunate battlefield start myapp --resume
shogunate battlefield start myapp --new
shogunate battlefield stop myapp
shogunate battlefield send myapp --role shogun "次のタスクを進めて"
shogunate battlefield send myapp --role shogun --start "次のタスクを進めて"
shogunate battlefield outbox myapp --json
shogunate battlefield roles myapp --json
shogunate battlefield sessions myapp --json
shogunate battlefield transcript myapp --json
```

このAPIは、接続先PC、登録済みprojectの戦場、app上の会話session、話しかける役職、という階層を前提にしています。
`list`、`sessions`、`transcript`、`outbox` は Shogunate runtime が停止中でも使えます。停止中に role へ送信した message は pending として保存され、`start` または `send --start` で project を resume 起動したあと role inbox へ配送を試みます。

並列 Shogunate も可能です。別々の project directory から起動すると、それぞれ専用の runtime copy と `tmux` session 名が割り当てられます。

alias を読むと view 移動が短くなります。

```bash
eval "$(shogunate aliases)"

cgo   # 御座の間 overview
csg   # 将軍
cgn   # 軍監
csk   # 家老
csa   # 足軽
cma   # multi-agent view
```

## インストールオプション

導入先を明示する場合:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash -s -- --prefix "$HOME/.shogunate/shogunate" --bin-dir "$HOME/.local/bin"
```

runtime の展開・更新だけ行い、初回 setup を走らせない場合:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash -s -- --no-setup
```

再現性のために固定 release を入れたい場合だけ、version tag を指定します。

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.13/scripts/shogunate_package_bootstrap.sh | bash -s -- --version v5.2.0.13
```

各 GitHub Release ページには、その tag 固定の cURL も載せています。

インストール済み bootstrap から再実行する場合:

```bash
shogunate install --no-setup
```

Shogunate本体は、このcURL bootstrapとGitHub Release archiveだけで配布します。npm packageとしては公開しません。

## Shogunate が動かすもの

Shogunate は `tmux` 上に見える runtime を作ります。

```text
あなた
  |
  v
将軍       命令受付と委譲
  |
  v
家老       計画、分割、統合
  |
  +-- 足軽  実作業
  +-- 軍師  戦略・高度レビュー
  +-- 軍監  独立監査
```

エージェント間通信は `queue/`、`dashboard.md`、runtime metadata のファイルで行います。連携層は local shell + `tmux` で、モデル呼び出しは作業する CLI agent だけが行います。

## リポジトリ構造

Shogunate は「本家 Shogun core + Shogunate MOD」へ寄せています。

```text
upstream-facing compatibility surface
  AGENTS.md, instructions/, lib/, scripts/, top-level launchers
  既存 tool と release cURL URL のために維持

Shogunate MOD canonical sources
  shogunate_mod/
    app/        app chat transcript reply helper
    battlefield/ app が使う host / project / session / role API
    gunkan/    independent auditor / CoDD helper
    package/   cURL package install と cwd-first workspace 管理
    pair/      Android Pair server
    projects/  CLI と app launcher が使う登録済み project registry
    runtime/   cwd/project/session helper
    shell/     Shogunate view aliases
    status/    agent / rate-limit status command
    watcher/   inbox / file-watch supervisor
    view/      Goza attach / focus helper

stable compatibility entrypoints
  legacy scripts/*, lib/*, top-level launcher は shogunate_mod/ へ委譲
```

既存 install と release cURL を壊さないため、`scripts/` の入口は残します。新しい Shogunate-only の挙動はまず `shogunate_mod/` 側へ置き、本家 runtime 更新時の衝突を減らします。

## 役職と CLI の設定

設定画面を開きます。

```bash
shogunate configure
```

代表的な構成:

```text
shogun   codex
karo     codex
gunshi   codex
gunkan   codex
ashigaru opencode / codex / claude / agy
```

Shogunate は必要に応じて role-local CLI state を持ちつつ、host 側の認証を再利用します。役職ごとの設定を分けながら、毎回ログインし直す負担を減らします。

各役職には、通常使う `Primary` と、任意の `Fallback` を1つ設定できます。

```bash
python3 scripts/configure_runtime_roles.py \
  --shogun codex --shogun-fallback opencode \
  --karo codex --karo-fallback none
```

Primaryが異常終了した場合は同じPrimaryを1回だけ再起動し、それでも失敗した場合だけFallbackへ移ります。役職の世代番号と作業状態は`queue/runtime/role_failover.yaml`へ保存され、古い世代のmessageは処理されません。上位役職を復旧できない場合は、新しい仕事を始めず安全停止します。

## 軍監

`gunkan` は将軍直属、家老と並列の独立監査 role です。要件、report、dashboard、task 完了、危険変更、release 整合性を確認します。

軍監は足軽へ通常タスクを割り振らず、家老の代わりにもなりません。監査結果はここへ出します。

```text
queue/reports/gunkan_report.yaml
```

軍監 pane へ移動:

```bash
cgn
```

## Android companion

release page には公開時に APK を置きます。

```text
shogunate-android-<version>.apk
```

Android app は SSH で host runtime へ接続し、既定では将軍 pane を対象にします。初回セットアップは Shogunate Pair を使います。秘密鍵はスマホ app 内に残し、PC 側は承認した公開鍵だけを登録します。

```bash
cd /path/to/your-project
shogunate pair        # この project 用に USB auto + Tailscale / LAN
```

その後、Android app で USB を選ぶか Tailscale/LAN IP を入力して、接続を押します。PC terminal に端末名が出るので、確認してから Pair Password prompt に入力すると端末が承認されます。pairing 成功後は terminal に `Pairing complete` と表示され、その project の Shogunate が resume 起動し、Pair は自動終了します。app は Pair が返した project 専用 `tmux` target を保存するため、並列 Shogunate の別 project へ誤接続しません。以後は保存済み SSH 鍵で再セットアップなしに接続できます。

USB の場合、app の接続先は `127.0.0.1` です。`adb reverse` が Android 側 `127.0.0.1:2222` を host の SSH service へ転送します。無線/Tailscale/LAN の場合は、スマホから実際に SSH へ到達できる PC address を使います。Pair terminal には app へ返した接続先が `returning SSH destination: user@host:port` と表示されます。

複数端末を続けて登録したい場合だけ、`shogunate pair --keep-running` を使います。

source checkout 互換 helper:

```bash
bash android/tools/setup_android_ssh.sh --pair-usb
bash android/tools/setup_android_ssh.sh --pair-wireless
```

runtime package archive には Android source は含めません。APK は release asset として配布します。

## 開発者向け checkout

Shogunate 自体を開発する場合だけ source checkout を使います。

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash shogunate_mod/package/first_setup.sh
bash shogunate_mod/runtime/entrypoint.sh
```

出荷前の基本確認:

```bash
make package-check
```

Android build:

```bash
cd android
./gradlew --no-daemon testDebugUnitTest assembleDebug
```

## トラブルシュート

`shogunate: command not found`

```bash
export PATH="$HOME/.local/bin:$PATH"
```

TUI に色が出ない場合:

```bash
echo "TERM=$TERM"
tput colors
printf '\033[31mRED\033[0m \033[32mGREEN\033[0m \033[34mBLUE\033[0m\n'
```

`tput colors` が `256` 未満なら、256色対応 terminal / tmux profile を使ってください。

Antigravity (`agy`) が毎回 login を求める場合:

```bash
bash ~/.shogunate/shogunate/shogunate_mod/cli/antigravity_keyring.sh
```

package install 後に generated instruction の警告が出る場合:

```bash
bash ~/.shogunate/shogunate/shogunate_mod/instructions/ensure_generated.sh
```

## release versioning

Shogunate は通常の version tag を使います。

```text
v5.0.0.0
v5.0.0.12
v5.2.0.1
v5.2.0.2
v5.2.0.3
v5.2.0.4
v5.2.0.5
v5.2.0.6
v5.2.0.7
v5.2.0.8
v5.2.0.9
v5.2.0.10
v5.2.0.11
v5.2.0.12
v5.2.0.13
```

各 release には必要に応じて以下を置きます。

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `shogunate-android-<version>.apk`

## License

MIT. See [LICENSE](LICENSE).
