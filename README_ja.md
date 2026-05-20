<div align="center">

# multi-agent-shognate

**tmux 運用と Android リモート操作に寄せた、portable な multi-agent-shogun fork。**

[![GitHub Stars](https://img.shields.io/github/stars/TsukinowaRin/multi-agent-shognate?style=social)](https://github.com/TsukinowaRin/multi-agent-shognate)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell%2FBash-100%25-green)]()

[English](README.md) | [日本語](README_ja.md)

</div>

<p align="center">
  <img src="images/screenshots/hero/latest-translucent-20260210-190453.png" alt="将軍ペインから複数エージェントを統率する様子" width="940">
</p>

## このリポジトリは何か

`multi-agent-shognate` は [`multi-agent-shogun`](https://github.com/yohey-w/multi-agent-shogun) を元にした fork で、upstream の発想は維持しつつ、実運用の前提をこのリポジトリ向けに変えています。

この fork が重視しているのは次です。

- `tmux` 中心の運用
- 固定ローカルディレクトリへ展開する package-based インストール
- fork 版 APK を使った Android リモート操作
- upstream より広い Multi-CLI 対応
- 保守寄りの既定構成: 全役職 `codex`、`config/settings.yaml` では model を pin しない、初期足軽は `ashigaru1` / `ashigaru2` の2名

要点だけ言うと、

- 将軍システムを使いたいフォルダに入れる
- `shutsujin_departure.sh` を起動する
- 将軍へ自然言語で命令する
- 家老が意図から人数配分と並列度を判断する

という運用です。

## upstream と何が違うか

| 項目 | upstream | この fork |
|---|---|---|
| runtime 構成 | split tmux session が主 | `goza-no-ma:overview` が runtime 正本。`shogun` / `gunshi` / `multiagent` は Android 互換 proxy として維持 |
| 初期足軽構成 | 歴史的に大きい編成を前提にした記述がある | 既定の現役足軽は `ashigaru1` と `ashigaru2` のみ |
| 既定 CLI | upstream 既定 | 全役職 `codex`、model 選択は pane-local CLI state に任せる |
| CLI 対応範囲 | upstream の中核 CLI | `Antigravity CLI`、`OpenCode`、`Kilo`、`localapi`、`Ollama` / `LM Studio` 連携を追加 |
| Android 配布 | upstream Android アプリ / APK | この repo の Releases にある fork 版 APK を正規配布物として扱う |
| 配布方式 | repo 前提の導線 | Release package (`tar.gz` / `zip`) + cURL bootstrap。npm / npx wrapper も用意 |
| 家老の動き | 指示に応じて分担 | この fork では、家老が意図から自律的に人数・分担・並列度を決めることを明示 |

## 基本モデル

指揮系統そのものは Shogun 方式です。

```text
あなた
 -> 将軍
 -> 家老
 -> 足軽 / 軍師
```

この fork で特に重要なのは次です。

- 現役兵力は `topology.active_ashigaru` を正本とする
- `ashigaru1..8` の歴史的記述は、そのまま現役人数とはみなさない
- 家老は、現在の active roster と命令内容から編成を適応的に決める

## 対応 CLI とベンダー

この fork は特定ベンダー前提ではありません。

### 対応している agent CLI type

| CLI type | 想定ベンダー / backend | 補足 |
|---|---|---|
| `codex` | OpenAI Codex CLI | この fork の既定 |
| `claude` | Anthropic Claude Code | upstream 同様に対応 |
| `copilot` | GitHub Copilot CLI | upstream 同様に対応 |
| `kimi` | Kimi Code | upstream 同様に対応 |
| `antigravity` | Google Antigravity CLI | この fork で明示対応。旧 `gemini` 設定はこの type に変換 |
| `opencode` | OpenCode CLI | この fork で追加 |
| `kilo` | Kilo CLI | この fork で追加 |
| `localapi` | OpenAI 互換 local endpoint | `Ollama` / `LM Studio` / llama.cpp server など向け |

### 既定の権限 / 承認方針

この fork では、全エージェントが既定で「承認確認を挟まない」側に寄るようにしてあります。

| CLI type | 既定の unattended 方針 |
|---|---|
| `claude` | `--dangerously-skip-permissions` |
| `codex` | `--sandbox danger-full-access --ask-for-approval never` |
| `copilot` | `--yolo` |
| `kimi` | `--yolo` |
| `antigravity` | `--dangerously-skip-permissions` |
| `opencode` | 生成される `opencode.json` に `permission: allow` を入れる |
| `kilo` | 生成される `opencode.json` に `permission: allow` を入れる |
| `localapi` | 別の承認レイヤーを持たず、local REPL を直接起動する |

OpenCode / Kilo は現行 CLI help 上で安定した `--yolo` flag を公開していないため、Shogunate では起動前に生成する project `opencode.json` の permission 設定を unattended mode の正本として扱います。

### runtime file watcher

inbox 配信は、使える場合は OS 標準に近い watcher を使います。

- Linux / WSL: `inotify-tools` の `inotifywait`
- macOS: Homebrew の `fswatch`
- fallback: 時間 polling。配信は維持しますが、未読検知まで watcher timeout 分だけ遅れることがあります

`first_setup.sh` は OS を見て推奨 watcher を確認・導入します。native watcher が無い環境でも、Shogunate は polling backend で起動を継続します。

### CLI state / ホスト認証

Shogunate runtime から起動する外部 CLI は、既知のログイン認証情報だけホスト PC / ユーザー home のものを使い、モデル設定・CLI 設定・履歴などは役職 / pane ごとに分離します。

- CLI 実行ファイル自体は、Shogunate 起動時の host shell / WSL 環境で解決されるものを使います。`HOME` 配下の一般的な Linux/WSL install path、`NVM_BIN`、`PNPM_HOME` を `PATH` より優先し、見つかった実行ファイルを絶対パス化して tmux pane へ渡します。これにより、native WSL CLI があるのに `/mnt/c/.../codex` のような Windows npm shim を誤って起動する事故を避けます。
- `Codex` は各役職を repo-local の別 `CODEX_HOME` で起動します。ホストの `~/.codex/auth.json` があれば role-local `auth.json` から symlink し、存在しない場合だけ従来の repo-local shared auth fallback を使います。model / `reasoning_effort` / 履歴 state は role-local に保ちます。
- Codex 起動は既定で通常の対話 TUI を優先します。Shogunate はまず `codex` を空で起動し、その後 tmux 経由で bootstrap prompt を配信します。従来の `codex <bootstrap prompt>` 起動へ戻したい場合だけ `MAS_CODEX_STARTUP_PROMPT_MODE=argv` を指定します。
- 入力欄の見た目、空入力時のサンプル文言、footer はインストール済み Codex CLI のバージョン側の表示です。Shogunate は Codex TUI を再装飾せず、起動状態を変えていた旧 positional bootstrap prompt だけを避けます。
- `Claude` / `Copilot` / `Kimi` / `Antigravity` / `OpenCode` / `Kilo` は、起動時に `HOME` と XDG paths を `.shogunate/cli-state/<cli>/agents/<agent>/home` 配下へ向けます。既知の host auth file だけ pane-local home へ symlink し、設定・モデル選択・cache・履歴は pane-local に保ちます。Antigravity は `agy` が使う host OAuth / account file を共有し、`.gemini/antigravity-cli/` 配下の auth file に加えて host の `.gemini/oauth_creds.json` / `.gemini/google_accounts.json` も再利用します。一方で settings と履歴は役職ごとに分離します。
- `OpenCode` / `Kilo` は既知の host `auth.json` だけを pane-local home へ symlink します。`model.json` は role-local file が未作成のときだけ host から初期コピーし、その後の model 選択は役職ごとに独立して保持します。一方で SQLite DB、prompt history、telemetry などの runtime file は pane-local に残します。古い DB / model / history symlink は起動時に外し、既存の role-local regular file は消しません。plugin manifest は未作成時だけ初期コピーし、`node_modules` は再インストールを避けるため host install を link できます。
- `localapi` は repo 内の local REPL なので、外部 CLI のログイン state 隔離対象ではありません。

この分離の目的は、再ログインの手間を避けつつ、Shogunate の役職別 model / reasoning / 履歴 state と、VSCode や別プロジェクトで使う同じ CLI の state を混ぜないことです。bootstrap は secrets の内容を読んだり表示したりせず、OpenCode / Kilo の provider database も既定では host からコピーしません。

### local provider 対応

`localapi` は、ローカルまたは self-hosted な provider を Shogunate に載せるための入口です。具体的には次を想定しています。

- `Ollama`
- `LM Studio`
- llama.cpp server
- OpenAI 互換 API を出す local endpoint

任意のローカルモデルを主目的で使うなら、まず `localapi` を使ってください。
この fork では、次の用途の主経路を `localapi` と位置付けます。

- LM Studio 上の独自 model ID をそのまま使いたい
- Ollama の local model を素直につなぎたい
- llama.cpp など OpenAI 互換 endpoint を直接叩きたい
- OpenCode / Kilo の内蔵 provider registry に載っていない backend を使いたい

`opencode` / `kilo` 自体は引き続き agent CLI として対応していますが、local provider 運用は best-effort です。backend 側では応答可能でも、CLI 側の provider/model registry によって model 名が弾かれることがあります。

### CoDD coherence gate

このリポジトリでは、[CoDD](https://github.com/yohey-w/codd-dev) を外部 coherence gate として標準統合しています。CoDD 本体は Shogunate に vendoring せず、`Update.bat` / `scripts/update_manager.py manual` / `make codd-install` が `codd-dev` を `.shogunate/codd-venv` へ導入・更新します。

```bash
make codd-install
make codd
# または一発:
CODD_AUTO_INSTALL=1 scripts/codd_check.sh verify
```

project config は `.codd/codd.yaml` です。install は基本的に PyPI の最新 `codd-dev` を取りに行きます。最新導入に失敗した場合は、開発時確認版の `CODD_FALLBACK_VERSION`（既定 `1.34.0`）へフォールバックします。WSL / Linux / macOS 側に `python3` / `python3-venv` が無い場合は、必要な install command を表示して停止します。CI でも `codd dag verify` を実行します。`scripts/codd_check.sh audit` も入口として用意していますが、CoDD 側の optional audit bridge がある環境向けです。

### 簡易 runtime 役職設定

通常はこちらを使います。役職ごとの大まかな CLI 種別と active Ashigaru 数だけを設定し、model / reasoning / thinking は tmux pane 内の各 CLI で手動設定して pane-local state に保持します。
対話入力の順番は `cli.default`、将軍、家老、軍師、足軽人数、active 足軽ごとの CLI です。

Linux / WSL terminal:

```bash
./Shogunate-Configure-Roles.sh
```

Windows Explorer:

```text
Shogunate-Configure-Roles.bat
```

macOS Finder / Terminal:

```bash
./Shogunate-Configure-Roles.command
```

macOS Shortcuts では、「Run Shell Script」アクションに次を指定します。

```bash
cd /path/to/multi-agent-shognate && ./Shogunate-Configure-Roles.sh
```

直接 Python で起動する場合はこちらです。

```bash
python3 scripts/configure_runtime_roles.py
```

非対話の例:

```bash
python3 scripts/configure_runtime_roles.py \
  --ashigaru-count 3 \
  --shogun antigravity \
  --karo codex \
  --gunshi codex \
  --ashigaru1 codex \
  --ashigaru2 opencode \
  --ashigaru3 opencode
```

### 詳細な役職ごとの CLI / model 設定

`config/settings.yaml` に model / reasoning / provider まで明示的に書きたい場合はこちらを使います。

```bash
bash scripts/configure_agents.sh
```

このスクリプトで設定できるもの:

- 役職ごとの CLI type
- 役職ごとの model
- Codex reasoning effort
- OpenCode / Kilo provider 設定
- active Ashigaru 数

## インストール方法

### 推奨: cURL package bootstrap

Release install は package 方式です。bootstrap が Release package をダウンロードし、固定ローカルディレクトリへ展開し、古い installer ファイルが残っていれば削除し、`first_setup.sh` を実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

version 固定で入れる場合:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v4.6.0.12 --prefix "$HOME/.shogunate/shogunate"
```

既定の導入先は `$SHOGUNATE_HOME` または `~/.shogunate/shogunate` です。

### npm / npx wrapper

npm package は同じ cURL bootstrap を呼ぶ薄い wrapper です。

```bash
npx @tsukinowarin/shogunate install
npx @tsukinowarin/shogunate install -- --version v4.6.0.12 --prefix "$HOME/.shogunate/shogunate"
```

Release asset:

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `multi-agent-shognate-package-<version>.tar.gz`
- `multi-agent-shognate-package-<version>.zip`

重要な挙動:

- package asset は対応する Release tag から作る
- `latest` は GitHub Releases の latest package asset を使い、OS 別 installer は使わない
- `--version` を指定すると、その Release tag に固定される
- `config/settings.yaml`、`queue/`、`logs/`、`.shogunate/` などの local state は package archive に含めない
- OS 別 installer asset は公開しない

### clone / ZIP 展開から手動インストール

repo を直接管理したい場合はこちらです。

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh
```

ZIP を使う場合も、展開後に同じように repo ルートで実行します。

### `first_setup.sh` がやること

`first_setup.sh` は、初回ローカル設定を作る前提のスクリプトです。

主な役割:

- `config/settings.yaml` のような local config 生成
- 依存関係チェック
- CLI bootstrap 補助
- tmux runtime の初期準備

この fork では `config/settings.yaml` は local-only で、公開 Git ツリーには含めません。

## アップデート

この fork では、更新経路を 2 つに分けています。

### 1. Git `main` で使う場合

`git clone` した repo をそのまま `main` で運用する場合は、rolling channel 扱いです。

- `shutsujin_departure.sh` の起動前に fast-forward 更新を確認する
- worktree が clean なら `origin/main` の最新へ追従する
- tracked な local 編集や local commit が衝突しそうなら、それを壊さない
- 代わりに `.shogunate/merge-candidates/` に incoming file を退避し、起動後に家老へマージ判断を依頼する

つまり、こちらが「常に最新コードへ寄せる」経路です。

さらに、元の upstream repo の最新内容を取り込み、衝突を Shogunate に整理させたい場合は次を使います。

```bash
bash scripts/upstream_sync.sh
```

適用前に何が変わるかだけ確認したいなら、次を使います。

```bash
bash scripts/upstream_sync.sh --dry-run
```

この導線では:

- `upstream/main` を fetch する
- local customization を壊さずに upstream snapshot を取り込む
- 衝突した incoming file を `.shogunate/merge-candidates/` に退避する
- `queue/shogun_to_karo.yaml` に pending cmd を追加する
- 起動後に家老が統合作業をさばく

`--dry-run` は add / update / remove / conflict の予定一覧を JSON で出し、worktree は変更しません。

### 2. Release package install の場合

cURL bootstrap または npm wrapper で入れたものは、stable release channel 扱いです。

Release version は本家 upstream version + fork revision にします。
先頭 3 つの数字は upstream Shogun の版を表し、
最後の 1 つはこの fork 側の配布・パッケージ改訂番号です。
現時点の upstream は `v4.6.0` なので、この repo の整列例は `v4.6.0.0` や `v4.6.0.12` です。
package asset 名も `android-` を含めず、同じ version 部を使います。

package asset の役割はこうです。

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `multi-agent-shognate-package-<version>.tar.gz`
- `multi-agent-shognate-package-<version>.zip`

cURL bootstrap は package を導入先へ展開して `first_setup.sh` を実行します。新しい version で再実行すると、local state を残しながら package install を更新します。`--version` を渡した場合は、その Release tag に固定されます。

Android アプリから SSH で接続している場合は、APK 側から **ホスト上の Shogunate 本体**の更新も実行できます。これは APK 自身の更新ではなく、ホストに入っている Shogunate の更新です。

### 何が保持されるか

アップデートでは、次のような local state / user-specific assets を残します。

- `config/settings.yaml`
- `.codex/`
- `.claude/`
- `projects/`
- `context/local/`
- `instructions/local/`
- `skills/local/`
- `queue/`, `logs/`, `dashboard.md` などの runtime state

tracked file が local 編集と衝突した場合は、package / 更新導線は local file を残したまま incoming version を次へ退避します。

- `.shogunate/merge-candidates/<batch>/incoming/...`

その後の起動で、家老にマージ処理を依頼する構成です。

## 初回起動

インストール後はこれです。

Linux / WSL terminal:

```bash
./Shogunate-Runtime.sh
```

Windows Explorer:

```text
Shogunate-Runtime.bat
```

macOS Finder / Terminal:

```bash
./Shogunate-Runtime.command
```

macOS Shortcuts では、「Run Shell Script」アクションに次を指定します。

```bash
cd /path/to/multi-agent-shognate && ./Shogunate-Runtime.sh
```

直接 shell で起動する導線も残しています。

```bash
bash shutsujin_departure.sh
```

launcher は既定で clean start し、`goza-no-ma` を作成したら起動中 window に先に attach します。Codex などのエージェント CLI は attach 後に裏の `overview` window で起動するため、Codex TUI は通常の手動起動に近い表示端末上で初期化されます。起動中 window はログ全文を追記表示し、AA も tmux の copy-mode で遡れます。起動完了後は自動で `overview` に切り替わります。ログインが必要な場合は、tmux 上で該当 pane の案内に従ってログインします。既存 state を保つ場合は `./Shogunate-Runtime.sh --resume`、attach しない場合は `./Shogunate-Runtime.sh --no-attach` を使います。

起動前の役職設定は、Windows では `Shogunate-Configure-Roles.bat`、Linux / WSL では `./Shogunate-Configure-Roles.sh`、macOS では `./Shogunate-Configure-Roles.command` から開けます。

## 最初の1案件／ソリューションを動かす

Shogunate は案件ごとに毎回インストールするのではなく、1つの Shogunate 環境から複数の作業対象 workspace を扱います。ここでいう「案件」は、Visual Studio のソリューションに近い粒度で、対象 repository や directory を指します。

1. まず役職設定を開きます。

   ```bash
   ./Shogunate-Configure-Roles.sh
   ```

   default CLI と足軽人数を選びます。ここでは厳密な model 名まで指定しなくて構いません。provider / model などの細かい設定は各 CLI pane 上で手動設定し、役職ごとに保持されます。

2. Shogunate を起動します。

   ```bash
   ./Shogunate-Runtime.sh
   ```

   既定の画面は `goza-no-ma:overview` です。通常の依頼先は将軍です。

3. 将軍に、作業対象 workspace と完了条件を伝えます。将軍 pane に直接入力しても、Android App で送信先を将軍にしたまま送っても構いません。

   例:

   ```text
   /home/me/projects/demo-api を対象にして。health-check endpoint を追加し、テストも更新して、最後に通ったテストコマンドを報告して。
   ```

   既存 repository なら絶対 path とユーザーから見える成果を伝えます。デモ作成なら `runtime_sandboxes/` 配下など、作成先 directory を明示します。

4. あとは将軍が家老へ命令を書き、家老が現役足軽へ分担します。設計、根本原因調査、複雑な品質確認が必要な場合は軍師へ回ります。

5. 進捗は `dashboard.md`、御座の間 pane、または Android App から確認します。完了報告は将軍へ戻り、家老が最終確認と dashboard 更新を担当します。

6. 同じ案件の runtime state を保って再開する場合:

   ```bash
   ./Shogunate-Runtime.sh --resume
   ```

   別案件へ切り替える場合は通常起動し、次の依頼で新しい workspace path を伝えます。Shogunate 側の役職設定や CLI 設定はこの install に残り、案件固有の source 変更は指定した workspace 側に残ります。

起動後に使う代表コマンド:

```bash
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/focus_agent_pane.sh gunshi
```

alias を使いたい場合:

```bash
source scripts/shell_aliases.sh
```

永続化したい場合:

```bash
bash scripts/install_shell_aliases.sh
source ~/.bashrc
```

### runtime 正本と互換 session

Android 連携に関わるので、ここは明示しておきます。

| session | 役割 |
|---|---|
| `goza-no-ma:overview` | この fork の runtime 正本 |
| `shogun:main` | Android 互換用の将軍 target |
| `gunshi:main` | Android 互換用の軍師 target |
| `multiagent:agents` | Android 互換用の家老 / 足軽 target |

## Android アプリと APK

この repo では **fork 版 Android アプリ**を配布しています。

upstream の APK は使いません。

### この fork で使う APK

この repo の **GitHub Releases** から取得してください。

asset 名は次のようなものです。

- `multi-agent-shognate-android-*.apk`

この fork では、この APK が正規配布物です。

### Android アプリは何をするか

APK は remote control / monitoring client です。

SSH でホストへ接続し、そこで次を読みます。

- `shogun` tmux session
- `multiagent` tmux session
- `dashboard.md`

必要なら将軍 pane に命令も送れます。新しい APK では将軍タブの送信先チップから、`@agent_id` ベースで将軍・家老・軍師・足軽へ送信先を切り替えられます。既定は将軍です。

さらに、この fork 版 APK からは **ホスト側 Shogunate の更新**も操作できます。

- 更新状態確認
- `upstream-sync --dry-run` の差分確認
- Shogunate を停止してから Release 更新
- Shogunate を停止してから upstream 取込

APK 自身の更新は行いません。Android アプリの更新は引き続き GitHub Releases から行います。

### Android の接続モデル

接続は SSH ベースです。特定の VPN 製品が必須というわけではなく、**スマホからホストへ SSH 到達できること**が条件です。

必要な設定:

- 到達可能な SSH ホスト名または IP
- SSH port
- ホスト側 Linux ユーザー名
- その Linux ユーザーの password または key
- ホスト側 project path
- session 名

この fork で典型的に使う値:

| 項目 | 値 |
|---|---|
| 将軍 session | `shogun` |
| エージェント session | `multiagent` |
| project path | ホスト上の repo ルート |

接続プロファイルを使う場合:

```bash
# Tailscale 経由の接続先を出力
scripts/android_pairing_profile.sh --mode tailscale --ssh-port 22

# USB adb reverse 経由の接続先を出力
scripts/android_pairing_profile.sh --mode usb --ssh-port 22 --android-port 2222
```

出力 JSON は Android 設定画面で取り込めます。password / private key / token は含めません。

補足:

- Android アプリの初期値は空欄または非識別的な placeholder にしてあります
- 個人の host 名、IP、topic は焼き込んでいません
- APK には app 側で `ntfy` を subscribe するための topic 欄もあります
- APK からの host 更新は、実行中の tmux runtime へ hot-apply せず、Shogunate 停止後に適用します

## 通知 (`ntfy`)

`ntfy` は使えますが、役割は分けて理解した方が安全です。

- サーバー側の将軍システム通知: `config/settings.yaml` などの local config を使う
- Android アプリ側通知: APK 自身が `ntfy` topic を subscribe できる

`ntfy_topic` のようなローカル値は private 扱いで、公開ツリーに載せない運用です。

## portable に別ワークスペースへ入れる使い方

このシステムは portable 運用を前提にできます。

別のワークスペースで使いたいなら、基本は次です。

- 対象フォルダを作る / 選ぶ
- cURL bootstrap に `--prefix <target-folder>` を渡す
- Release package を展開して `first_setup.sh` まで実行させる

こうすると、次の状態がそのワークスペースに閉じます。

- `queue/`
- `logs/`
- `dashboard.md`
- `config/settings.yaml`
- tmux runtime state

## この fork の既定値

現在の既定方針は次です。

- 全役職 `codex`
- `config/settings.yaml` では model を pin せず、各 CLI の pane-local / default model state に任せる
- 初期 active Ashigaru は `ashigaru1` と `ashigaru2`
- 家老1人が担当する足軽は最大6名。7名以上では `karo1`, `karo2` ... を自動作成して均等割り当てする
- 複数家老では `karo1` が筆頭家老として将軍報告を担う。家老間連携は自由な直接 inbox 会話ではなく `queue/runtime/karo_coordination.yaml` を使う

足軽数を増やしたい時は、歴史的な 1〜8 記述を信用するのではなく、active topology を変更します。

## よく使うコマンド

```bash
bash first_setup.sh
bash shutsujin_departure.sh
./Shogunate-Runtime.sh
./Shogunate-Configure-Roles.sh
python3 scripts/configure_runtime_roles.py
bash scripts/configure_agents.sh
bash scripts/goza_no_ma.sh
bash scripts/focus_agent_pane.sh shogun
bash scripts/focus_agent_pane.sh karo
bash scripts/prepublish_check.sh
```

## リポジトリ構成

```text
multi-agent-shognate/
├── android/                   # fork 版 Android アプリ
├── config/                    # local/runtime 設定テンプレート
├── docs/                      # 要件、計画、公開ポリシー
├── instructions/              # 共通と generated の CLI 指示書
├── lib/                       # shell helper library
├── scripts/                   # runtime / bootstrap / bridge / watcher
├── tests/                     # unit / smoke tests
├── bin/shogunate.js           # npm / npx wrapper for package bootstrap
├── Shogunate-Runtime.bat      # Windows runtime launcher
├── Shogunate-Runtime.sh       # Linux / WSL runtime launcher
├── Shogunate-Runtime.command  # macOS Finder runtime launcher
├── Shogunate-Configure-Roles.bat      # Windows WSL 役職設定 launcher
├── Shogunate-Configure-Roles.sh       # Linux / WSL 役職設定 launcher
├── Shogunate-Configure-Roles.command  # macOS Finder 役職設定 launcher
├── updater.bat                # 互換維持のため残している旧 Windows updater
├── first_setup.sh             # 初回セットアップ
└── shutsujin_departure.sh     # runtime 起動
```

## 公開時の衛生ルール

この fork では、次のようなものを local-only として扱います。

- `config/settings.yaml`
- runtime queue state
- local logs
- private notification topic
- 個人の host 名、path、IP

公開前はこれを実行してください。

```bash
bash scripts/prepublish_check.sh
```

## どんな人に向いているか

この fork が向いているのは次です。

- 好きなフォルダに portable に入れたい
- GitHub Releases から fork 版 APK を使いたい
- Antigravity / OpenCode / Kilo / localapi まで含めて使いたい
- `goza-no-ma` を runtime 正本として運用したい
- 保守寄りの既定値で安定運用したい

元のプロジェクトそのままの既定値や配布体系を求めるなら upstream を選ぶ方が自然です。

## 関連ドキュメント

- `android/README.md` - Android アプリの詳細
- `docs/REQS.md` - 正規化した現在要件
- `docs/PUBLISHING.md` - 公開前の privacy / cleanup ポリシー
- `docs/philosophy.md` - 設計思想
