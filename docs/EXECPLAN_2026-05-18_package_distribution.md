# ExecPlan: Package Distribution

作成日: 2026-05-18

## 目的

OS 別 installer asset (`.bat` / `.sh` / `.command`) を廃止し、GitHub Release の version 固定 package と cURL bootstrap を標準配布導線にする。npm / npx は薄い wrapper として同じ bootstrap を呼ぶ。

## 方針

- Release asset は APK と package archive (`tar.gz` / `zip`) にする。
- package archive は Release tag の Git snapshot から作り、moving `main` へ依存しない。
- `scripts/shogunate_package_bootstrap.sh` は `curl | bash` で使える導入入口にする。
- npm package は `@tsukinowarin/shogunate` とし、`npx @tsukinowarin/shogunate install` で cURL bootstrap を呼ぶ。
- `Shogunate-Runtime.*` と `Shogunate-Configure-Roles.*` は installer ではなく launcher なので維持する。
- 旧 `install.bat` / `install.sh` / `install.command` / `Shogunate-Uninstaller.bat` と installer contract tests は削除する。

## 手順

1. 要件を `docs/REQS.md` に追加する。
2. cURL bootstrap script と npm wrapper を追加する。
3. release workflow を package archive 生成へ切り替える。
4. README / README_ja / android release docs を package distribution へ更新する。
5. installer / uninstaller files と古い tests を削除し、新しい package distribution contract test を追加する。
6. `.gitignore` と CI の unittest 対象を更新する。
7. shell / Python / Node / workflow text / docs grep を検証し、commit / push する。

## 検証

- `bash -n scripts/shogunate_package_bootstrap.sh first_setup.sh`
- `node bin/shogunate.js --help`
- `python3 -m unittest tests.unit.test_package_distribution tests.unit.test_update_manager`
- `git diff --check`
- `rg -n "multi-agent-shognate-installer|install\\.bat|install\\.sh|install\\.command|Shogunate-Uninstaller" README.md README_ja.md android/release/README.md .github/workflows/android-release.yml`

## 進捗

- [x] 2026-05-18: 要件と計画を作成。
- [x] bootstrap / npm wrapper を実装。
- [x] release workflow と tests を更新。
- [x] docs を更新。
- [x] 検証。
- [x] commit。
- [ ] push。

## 判断

- Decision: `.bat` installer は復活させず、Windows は WSL 上で curl bootstrap を使う。
  Rationale: この repo の runtime 自体が WSL / Linux / macOS + tmux 前提であり、Windows native installer は複雑さに対する効果が低い。
- Decision: npm package は当面 bootstrap wrapper とする。
  Rationale: Shogunate は tmux runtime と shell scripts を含むため、npm package 内から直接常用するより、固定 install directory に package snapshot を展開する方が運用しやすい。
