# ExecPlan: Android app 接続セットアップ改善

作成日: 2026-05-30

## 目的

Android app の SSH 接続設定を、現行 Shogunate runtime に合わせやすくする。特に `shogunate:goza` のような tmux target を直接扱えるようにし、設定画面で接続診断を実行できる状態にする。

## 判断

- 初回は USB/Tailscale の完全自動 SSH provisioning までは入れない。端末側の SSH サーバーや鍵配布は OS/環境差が大きいため、まずアプリ内の設定・診断を確実にする。
- 既存互換のため、`shogun` のような session 名だけなら従来どおり `shogun:main`、`multiagent` なら `multiagent:0` に解決する。
- Shogunate 標準値は `shogunate:goza` を将軍 target / エージェント target の既定値とする。

## 手順

1. Android settings UI に Shogunate 推奨値ボタンと接続診断ボタンを追加する。
2. SettingsViewModel で SSH / tmux / project path / target / dashboard の診断を行う。
3. tmux target 解決を helper 化し、既存 session 名入力との互換性を保つ。
4. README と docs を更新する。
5. Android unit/build check を実行する。

## 検証

- `cd android && ./gradlew testDebugUnitTest`
- 可能なら `cd android && ./gradlew assembleDebug`
- `git diff --check`

## 結果

- `cd android && ./gradlew testDebugUnitTest assembleDebug`: PASS
- `git diff --check`: PASS
- 実機 adb install / launch: PASS
- 設定画面 smoke: `標準値を入力` / `接続診断` の表示と、SSH ユーザー未入力時の診断メッセージ表示を確認。

## 復旧

問題が出た場合は、Android app の設定 UI と tmux target helper の変更を戻せば既存挙動に戻る。SharedPreferences key は増やさず、既存ユーザー設定は破壊しない。
