<div align="center">

# Shogunate

**AI コーディング CLI を複数体で動かす、package install 対応の multi-agent runtime。**

将軍、家老、足軽、軍師、軍監を `tmux` 上に並べ、YAML queue と release package で運用します。

[![Release](https://img.shields.io/badge/release-v5.2.0.2-ff6600?style=flat-square)](https://github.com/TsukinowaRin/multi-agent-shognate/releases/tag/v5.2.0.2)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[English](README.md) | [日本語](README_ja.md)

</div>

<p align="center">
  <img src="images/screenshots/hero/latest-translucent-20260210-190453.png" alt="Shogunate tmux runtime" width="940">
</p>

## クイックスタート

固定 release package を cURL で入れます。

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.2/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.2
```

起動します。

```bash
shogunate
```

既定では runtime を `~/.shogunate/shogunate` に展開し、`~/.local/bin/shogunate` を登録します。

`shogunate` が見つからない場合は shell を開き直すか、PATH を追加してください。

```bash
export PATH="$HOME/.local/bin:$PATH"
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
shogunate                 # runtime 起動
shogunate clean           # clean start
shogunate resume          # 前回状態から resume
shogunate attach          # tmux session shogunate に attach
shogunate configure       # 役職ごとの CLI を選ぶ
shogunate status          # package/update metadata を表示
shogunate aliases         # shell alias の source コマンドを表示
shogunate help            # help
```

alias を読むと view 移動が短くなります。

```bash
source ~/.shogunate/shogunate/scripts/shell_aliases.sh

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
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.2/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.2 \
      --prefix "$HOME/.shogunate/shogunate" \
      --bin-dir "$HOME/.local/bin"
```

runtime の展開・更新だけ行い、初回 setup を走らせない場合:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/v5.2.0.2/scripts/shogunate_package_bootstrap.sh \
  | bash -s -- --version v5.2.0.2 --no-setup
```

インストール済み bootstrap から再実行する場合:

```bash
shogunate install --version v5.2.0.2 --no-setup
```

この branch が `main` に載った後の moving latest channel:

```bash
curl -fsSL https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main/scripts/shogunate_package_bootstrap.sh | bash
```

npm wrapper は同じ cURL bootstrap を呼ぶ薄い補助です。

```bash
npx @tsukinowarin/shogunate install -- --version v5.2.0.2
```

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
shogunate-android-v5.2.0.2.apk
```

Android app は SSH で host runtime へ接続し、既定では将軍 pane を対象にします。source checkout での pairing helper:

```bash
bash android/tools/setup_android_ssh.sh --pair-usb --yes
bash android/tools/setup_android_ssh.sh --wireless
```

runtime package archive には Android source は含めません。APK は release asset として配布します。

## 開発者向け checkout

Shogunate 自体を開発する場合だけ source checkout を使います。

```bash
git clone https://github.com/TsukinowaRin/multi-agent-shognate
cd multi-agent-shognate
bash first_setup.sh
bash shutsujin_departure.sh
```

出荷前の基本確認:

```bash
bash -n scripts/shogunate_package_bootstrap.sh shutsujin_departure.sh
python3 -m unittest tests.unit.test_package_distribution
git diff --check
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
bash ~/.shogunate/shogunate/scripts/ensure_antigravity_keyring.sh
```

package install 後に generated instruction の警告が出る場合:

```bash
bash ~/.shogunate/shogunate/scripts/ensure_generated_instructions.sh
```

## release versioning

Shogunate は通常の version tag を使います。

```text
v5.0.0.0
v5.0.0.12
v5.2.0.1
v5.2.0.2
v5.2.0.3
```

各 release には必要に応じて以下を置きます。

- `multi-agent-shognate-package.tar.gz`
- `multi-agent-shognate-package.zip`
- `shogunate-android-<version>.apk`

## License

MIT. See [LICENSE](LICENSE).
