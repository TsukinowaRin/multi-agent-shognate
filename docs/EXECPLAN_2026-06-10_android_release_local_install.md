# ExecPlan: Android APK release とローカル package install

## 目的

本家 `v5.2.0` 反映済みの Shogunate から Android APK と Shogunate package を同じ GitHub Release に固定し、このPCへ release package をインストールできることを確認する。

## 方針

- Android APK は package installer からも指定できる `v5.2.0.2` の release asset として配布する。
- Runtime package archive は Android app を含めない従来設計を維持する。
- ローカル導入先は既定の `~/.shogunate/shogunate`。
- 初回検証では `--no-setup` を使い、対話 setup や既存環境変更を避ける。

## 手順

1. Android version を `5.2.0.2` / `52002` に更新し、関連 docs を同期する。
2. Android unit/build check を実行する。
3. package distribution check と archive 作成を実行する。
4. GitHub release `v5.2.0.2` を作成し、APK と package archives をアップロードする。
5. cURL bootstrap を release tag 指定で実行し、このPCの `~/.shogunate/shogunate` に導入する。
6. インストール先で主要ファイル、version metadata、起動 script 構文を確認する。

## 検証

- `bash -n android/tools/setup_android_ssh.sh`
- `cd android && ./gradlew --no-daemon -Dkotlin.compiler.execution.strategy=in-process -Pkotlin.compiler.execution.strategy=in-process testDebugUnitTest assembleDebug`
- `python3 -m unittest tests/unit/test_package_distribution.py`
- `bash scripts/prepublish_check.sh`
- release asset download / install smoke

## 復旧

- 既存 install へ上書きする前に `~/.shogunate/shogunate` があれば timestamp backup へ退避する。
- GitHub release asset は tag 固定。差し替えが必要な場合は release の asset を削除して再アップロードする。
