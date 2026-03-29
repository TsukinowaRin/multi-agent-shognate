# Portable Install / Uninstall / Release Notes (2026-03-29)

## 0. 目的
- 次エージェントが、portable installer / uninstaller / release 運用の直近変更点を短時間で把握できるようにする。
- 特に、**旧 uninstaller の危険な削除挙動**と、その修正内容・検証状況・使うべき release を明示する。

## 1. 結論
- 旧系統で安全性を確認した release は `android-v4.2.0.8`。
- **今後の release version は upstream 版に準拠し、現時点では `android-v4.4.1.N` 系で運用する。**
- `android-v4.2.0.8` は以下を含む。
  - uninstaller の危険な全削除挙動の修正
  - uninstaller 契約テスト追加
  - CI に Python unit test を追加
  - APK asset 名の重複 `android` を修正

## 2. 何が起きたか
### 2.1 事故
- 旧 `Shogunate-Uninstaller.bat` は、配置先フォルダ内を**ほぼ全面削除**する実装だった。
- そのため、Shogunate を既存 repo / project folder の中に置いていた場合、**unrelated files まで消える**事故が起きた。

### 2.2 原因
- 旧 cleanup は、以下のような広すぎる削除を行っていた。
  - `for /d %%D in ("%SCRIPT_DIR%\\*") do rmdir /s /q ...`
  - `del /f /q "%SCRIPT_DIR%\\*"`
- これは「Shogunate 管理対象だけ消す」実装になっていなかった。

## 3. 現在の安全仕様
`Shogunate-Uninstaller.bat` は次の前提で動く。

1. `.shogunate/install_manifest.json` が無ければ**実行拒否**
2. 削除対象は以下に限定
   - install manifest に入っている tracked file
   - 明示された local Shogunate data
     - `config/settings.yaml`
     - `dashboard.md`
     - `.claude/`
     - `.codex/`
     - `.shogunate/`
     - `projects/`
     - `context/local/`
     - `instructions/local/`
     - `skills/local/`
     - `queue/`
     - `logs/`
3. **同じフォルダ内の unrelated files は消さない**
4. 親フォルダは残す
5. preserve を選んだ場合は、userdata backup を install 外へ退避してから削除

## 4. Release installer の現状
- public release asset は installer 一本化した。
- updater は public release asset から外した。
- 運用:
  - 空フォルダに installer を置いて実行 → fresh install
  - 既存 portable install の同じフォルダで新しい installer を再実行 → in-place update
- release install 判定は `.shogunate/install_state.json` を優先する。
- legacy portable install でも
  - `first_setup.sh`
  - `config/settings.yaml`
  - no `.git`
  を満たせば release-update として扱う補強を入れている。

## 5. Asset naming の現状
### 正
- APK: `multi-agent-shognate-android-v4.4.1.0.apk` のように upstream 版へ準拠させる
- installer: `multi-agent-shognate-installer-v4.4.1.0.bat` のように version 部だけを使う

### 旧問題
- 一時期 APK asset 名が `multi-agent-shognate-android-android-v4.2.0.8.apk` になっていた。
- workflow 修正後、`android-v4.2.0.8` release は置換済み。

## 6. テスト状況
### 6.1 ローカルで通したもの
- `python3 -m unittest tests.unit.test_uninstaller_contract tests.unit.test_update_manager`
- `bash scripts/prepublish_check.sh`
- `cd android && ... ./gradlew --no-daemon assembleRelease`

### 6.2 CI
- `.github/workflows/test.yml` に Python unit test step を追加済み。
- 新規テスト:
  - `tests/unit/test_uninstaller_contract.py`
- 見ていること:
  - manifest 必須
  - 広域削除パターン不在
  - manifest ベース cleanup
  - 「unrelated files は残す」文言

## 7. 復旧メモ
- 事故発生後、`Windows File Recovery` で
  - `Reference` 狙い
  - `Human-Emulator` 広域
  の回収を試した。
- ただし、この turn では実回収物は確認できなかった。
- `.git` が残っていた repo は `git restore --source=HEAD --worktree -- .` で tracked file を戻せる。
- 旧 uninstaller が作った userdata backup は、**Shogunate local data only** であり、unrelated project files までは含まれない。

## 8. 次エージェントへの注意
1. uninstaller 関連の変更を入れる時は、**フォルダ全体削除へ戻さないこと**。
2. 既存 repo / project folder へ portable install するユーザーがいる前提で考えること。
3. release tag を付け替える場合、workflow は既存 assets を削除してから再公開するので、release object 自体の asset 名も置換される。
4. user 向け案内では、旧 `4.2.0.x` 系を固定値として案内せず、upstream 版準拠の tag を使うこと。

## 9. 関連ファイル
- `Shogunate-Uninstaller.bat`
- `install.bat`
- `scripts/update_manager.py`
- `tests/unit/test_uninstaller_contract.py`
- `tests/unit/test_update_manager.py`
- `.github/workflows/android-release.yml`
- `.github/workflows/test.yml`
- `README.md`
- `README_ja.md`
- `android/release/README.md`
