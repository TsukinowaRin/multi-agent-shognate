# 引き継ぎ: ブートストラップ注入の根本修正（2026-02-17）

作成日時: 2026-02-17
作成者: Claude Opus 4.6

## エグゼクティブサマリー

**現状**: Zellijモードでプロンプト注入の混線が依然として発生している。
- 症状: 家老に軍師のプロンプト、足軽に家老のプロンプトが注入される
- 原因: `zellij action write-chars` の並行実行による混線
- 対策済み: ファイルベース配信 + エージェント毎個別送信（コミット `39556af`）
- 効果: batsテスト200/200全パス、しかし実機では依然混入発生

**実機テスト結果（2026-02-17）**:
- テスト構成: 将軍=codex, 家老=codex, 軍師=gemini, 足軽=gemini
- 症状: 起動中にユーザーがZellijをポチポチすると、混線が発生
  - 家老に軍師のプロンプトが注入される
  - 将軍に別のプロンプトが注入される
- 原因推定: ユーザー操作によるフォーカス変更が、`write-chars`の送信先を誤認識させる可能性

**優先度**: 🔴 Critical（システムコア機能の不具合、全運用に影響）

**推奨即時対応**:
1. **検証**: 下記「デバッグコマンド」でブートストラップファイル生成を確認
2. **暫定対策**: 以下のいずれかを選択
   - A案: 順次起動方式（完全1エージェントずつ）
   - B案: インターバル延長（5秒→10秒）
   - C案: Claude限定で`-p`フラグ方式への移行
3. **恒久対策**: Zellij並行制御の仕組み見直し or tmux優先運用への回帰

---

## 1. 到達点（反映済みコミット）

### コミット `39556af` - ブートストラップ誤送信を根本修正（ファイルベース配信方式）

**変更内容**:
- `generate_bootstrap_file()`: 各エージェントのブートストラップを `queue/runtime/bootstrap_{agent_id}.md` に事前書き出し
- `deliver_bootstrap_zellij()`: セッション存在チェック + CLI readiness確認 + リトライ付き配信（`wait_for_cli_ready` 最大15秒）
- `deliver_bootstrap_tmux()`: ペイン存在チェック + ファイルから読み出し
- `send_line()`: zellij版にセッション存在チェック追加
- CLI起動前にブートストラップファイルを全エージェント分生成
- バッチ `sleep 2` を廃止、エージェント毎の個別配信に変更（1秒インターバル）
- localapi テストの期待値をモデル環境変数対応に更新

**ファイル**:
- `scripts/shutsujin_zellij.sh`
- `shutsujin_departure.sh`
- `tests/unit/test_cli_adapter.bats`

**テスト結果**: bats 200/200 PASS

---

## 2. 問題の詳細

### 2.1. 報告された症状

ユーザーが実機テスト（Zellij Pure Mode）で確認:
```
家老に軍師のプロンプトが注入される
足軽に家老のプロンプトが注入される
```

### 2.2. 根本原因の推定

`zellij action write-chars` を並行実行すると、内部バッファで混線する可能性:
```bash
# 現在の実装（scripts/shutsujin_zellij.sh:619-625）
for agent in "${AGENTS[@]}"; do
  deliver_bootstrap_zellij "$agent"
  sleep 1  # ← 1秒インターバルでは不十分
done
```

`deliver_bootstrap_zellij()` 内部:
```bash
wait_for_cli_ready "$agent" 15  # 画面ダンプでCLI起動確認
send_line "$agent" "$msg"       # write-chars送信
```

**問題点**:
1. `wait_for_cli_ready` は画面ダンプ（`dump-screen`）でCLI検出するが、バッファの完全な準備を保証しない
2. `send_line` の `write-chars` は非同期的で、送信完了を待たずに次のエージェントへ進む
3. 1秒インターバルが短すぎて、前のエージェントへの送信が完了する前に次が始まる

### 2.3. 既に試した対策とその限界

| 対策 | 実装箇所 | 効果 | 限界 |
|------|---------|------|------|
| ファイルベース事前生成 | `generate_bootstrap_file()` | ファイル内容の混入は防止 | `write-chars` の混線は防げない |
| セッション存在チェック | `send_line()` | 存在しないセッションへの誤送信防止 | 正しいセッションへの混線は防げない |
| CLI readiness確認 | `wait_for_cli_ready()` | 起動前送信を抑止 | バッファ準備完了は保証しない |
| エージェント毎個別配信 | for ループ + sleep 1 | バッチ送信より改善 | 1秒では不十分 |

---

## 3. 次のアクション候補（優先度順）

### 🔴 A案: ユーザー操作時の混線防止（実機テスト結果に基づく）【緊急】

**概要**: 起動中にユーザーがZellijを操作すると、フォーカス変更が`write-chars`の送信先を誤認識させる可能性があるため、対策を実装

**実装場所**: `scripts/shutsujin_zellij.sh`

**変更内容**:
```bash
# 起動中はユーザー操作を禁止する警告を追加
log_warn "⚠️  起動中はウィンドウ操作を禁止してください（混線防止のため）"

# send_line()でフォーカスチェックを追加
send_line() {
  local session="$1"
  local text="$2"
  if ! session_exists "$session"; then
    echo "[WARN] send_line: session '$session' does not exist, skipping" >&2
    return 1
  fi
  # フォーカスが正しいセッションにあるか確認
  if ! zellij -s "$session" list-sessions | grep -q "$session"; then
    echo "[WARN] send_line: session '$session' is not focused, skipping" >&2
    return 1
  fi
  zellij -s "$session" action write-chars "$text" >/dev/null 2>&1 || return 1
  if zellij -s "$session" action write 13 >/dev/null 2>&1; then
    sleep 0.5
    return 0
  fi
  if zellij -s "$session" action write 10 >/dev/null 2>&1; then
    sleep 0.5
    return 0
  fi
  zellij -s "$session" action write-chars $'\n' >/dev/null 2>&1 || return 1
  sleep 0.5
}
```

**メリット**:
- ユーザー操作による混線を防止
- フォーカスチェックで誤送信を防止

**デメリット**:
- ユーザー体験が悪化（起動中は操作禁止）

---

### 🟡 B案: 順次起動方式（完全1エージェントずつ）【推奨】

**概要**: CLI起動 → readiness確認 → ブートストラップ送信 → 次エージェントへ、を1サイクルとして順次実行

**実装場所**: `scripts/shutsujin_zellij.sh`

**変更内容**:
```bash
# Phase 1: ブートストラップファイル事前生成（現状維持）
for agent in "${AGENTS[@]}"; do
  cli_type=$(resolve_cli_type_for_agent "$agent")
  generate_bootstrap_file "$agent" "$cli_type"
  printf "%s\t%s\n" "$agent" "$cli_type" >> queue/runtime/agent_cli.tsv
done

# Phase 2+3 統合: CLI起動 → ブートストラップ送信を1エージェントずつ完結
for agent in "${AGENTS[@]}"; do
  cli_type="$(awk -F '\t' -v a="$agent" '$1==a{print $2}' queue/runtime/agent_cli.tsv | tail -n1)"
  cli_cmd=$(build_cli_command_with_type "$agent" "$cli_type")

  # CLI起動
  send_line "$agent" "$cli_cmd"
  log_info "  └─ $agent: $cli_type 起動中"

  # readiness確認（最大15秒）
  wait_for_cli_ready "$agent" 15

  # ブートストラップ送信
  deliver_bootstrap_zellij "$agent"
  log_info "  └─ $agent: 初動命令配信完了"

  # 次のエージェントへ進む前に2秒待機
  sleep 2
done
```

**メリット**:
- エージェント間の完全な分離を保証
- 混線リスクを最小化
- デバッグが容易（どのエージェントで失敗したかすぐ分かる）

**デメリット**:
- 起動時間が長くなる（エージェント数×17秒程度）
- 足軽が多いと体感遅延が大きい

**受け入れ条件**:
```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && \
bash scripts/goza_zellij.sh --clean
# 起動後、各エージェントが正しいプロンプトを受信していることを確認
```

---

### 🟡 B案: インターバル延長（5秒→10秒）【次善策】

**概要**: 現在の実装を維持し、エージェント間のインターバルを大幅延長

**実装場所**: `scripts/shutsujin_zellij.sh:625`

**変更内容**:
```bash
for agent in "${AGENTS[@]}"; do
  deliver_bootstrap_zellij "$agent"
  sleep 10  # 1秒 → 10秒に延長
done
```

**メリット**:
- 変更が最小限
- 既存の流れを維持

**デメリット**:
- 根本解決ではない（10秒でも混線する可能性はゼロではない）
- 起動時間が長くなる（エージェント数×10秒程度）
- デバッグが難しい（どこで混線したか特定しづらい）

---

### 🟢 C案: Claude限定で`-p`フラグ方式への移行【理想的だが対応範囲限定】

**概要**: Claude Code CLIの`-p`フラグで起動時にプロンプトを渡す（`write-chars`を使わない）

**実装場所**: `lib/cli_adapter.sh` の `build_cli_command_with_type()`

**変更内容**:
```bash
claude)
    local prompt_file="$SCRIPT_DIR/queue/runtime/bootstrap_${agent_id}.md"
    if [ -f "$prompt_file" ]; then
        # プロンプトを起動時引数で渡す
        echo "claude --dangerously-skip-permissions -p \"\$(cat $prompt_file)\""
    else
        echo "claude --dangerously-skip-permissions"
    fi
    ;;
```

**メリット**:
- `write-chars` を使わないため混線リスクゼロ
- 起動時間の短縮（送信待機が不要）
- 確実性が高い

**デメリット**:
- **Claude Codeのみ対応**（Gemini/Codex/localapiは非対応）
- 他のCLIは依然として `write-chars` 方式のまま
- 部分的な解決に留まる

---

### 🔵 D案: Tmux優先運用への回帰【保守的】

**概要**: Zellijの並行制御問題を回避し、安定している tmux を優先運用とする

**実装場所**: ドキュメント + `config/settings.yaml` デフォルト変更

**変更内容**:
- `README.md` で tmux 推奨を明記
- `config/settings.yaml` の `startup.template` デフォルトを `shogun_only`（tmux前提）へ変更
- Zellij Pure Mode は「実験的機能」として位置づけ

**メリット**:
- 既に安定している tmux を活用
- Zellij問題の影響を最小化
- ユーザーの期待値調整

**デメリット**:
- Zellij対応の当初目的から後退
- Zellij好きなユーザーには不満

---

## 4. デバッグコマンド（コピペ用）

### 4.1. ブートストラップファイル生成確認

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && \
ls -la queue/runtime/bootstrap_*.md
```

**期待結果**: `bootstrap_shogun.md`, `bootstrap_gunshi.md`, `bootstrap_karo.md`, `bootstrap_ashigaru1.md` 等が存在

**内容確認**:
```bash
head -3 queue/runtime/bootstrap_shogun.md
head -3 queue/runtime/bootstrap_gunshi.md
head -3 queue/runtime/bootstrap_karo.md
```

### 4.2. Zellijセッション一覧確認

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && \
zellij list-sessions
```

**期待結果**: `shogun`, `gunshi`, `karo`, `ashigaru1`, ... のセッションが存在

### 4.3. 実行時ログ確認

```bash
cd /mnt/d/Git_WorkSpace/multi-agent-shognate/multi-agent-shognate && \
bash scripts/goza_zellij.sh --clean 2>&1 | tee /tmp/zellij_startup.log
```

**確認ポイント**:
- `📝 ブートストラップファイルを事前生成中` が表示されるか
- `📜 初動命令をエージェント毎に個別配信中` が表示されるか
- `CLI readiness確認付き` のログが各エージェントで表示されるか

### 4.4. CLI起動確認（各エージェント）

起動後、各セッションに入って確認:
```bash
zellij attach shogun   # 将軍のプロンプトが入っているか確認
zellij attach gunshi   # 軍師のプロンプトが入っているか確認
zellij attach karo     # 家老のプロンプトが入っているか確認
zellij attach ashigaru1  # 足軽のプロンプトが入っているか確認
```

---

## 5. 既知リスク

### 5.1. Zellij `write-chars` の仕様未確認

**リスク**: Zellijの内部バッファ仕様が不明で、`write-chars` の送信完了タイミングが保証されていない

**対策**: 公式ドキュメント確認 or Zellij開発者への問い合わせ

### 5.2. エージェント数増加時のスケーラビリティ

**リスク**: A案（順次起動）を採用すると、足軽10名で170秒（2分50秒）かかる

**対策**:
- 並行起動グループ化（将軍+軍師/家老/足軽で3グループに分けて並行実行）
- Tmux優先運用（D案）への回帰

### 5.3. 他のCLI（Gemini/Codex）の起動遅延

**リスク**: Gemini は trust prompt / high demand で追加待機が必要

**対策**: `wait_for_cli_ready()` のタイムアウトを動的調整（CLI種別で15秒/30秒/60秒）

---

## 6. 関連ドキュメント

- `docs/WORKLOG.md` - 実装詳細ログ
- `docs/REQS.md` - 受け入れ条件
- `scripts/shutsujin_zellij.sh` - Zellij起動スクリプト
- `shutsujin_departure.sh` - Tmux起動スクリプト
- `lib/cli_adapter.sh` - CLI抽象化レイヤー

---

## 7. 再開時チェックリスト

引き継ぎ者が作業を再開する際の確認事項:

- [x] デバッグコマンド4.1でブートストラップファイルが正しく生成されているか確認
- [x] デバッグコマンド4.3で起動ログを取得
- [x] デバッグコマンド4.4で各エージェントのプロンプト内容を確認
- [x] プロンプト混入が再現するか確認
- [x] 混入が再現する場合、どのエージェントに何のプロンプトが入ったか記録
  - **実機テスト結果**: 起動中にユーザーがZellijをポチポチすると、混線が発生
  - 家老に軍師のプロンプトが注入される
  - 将軍に別のプロンプトが注入される
- [ ] A案（ユーザー操作時の混線防止）を実装
- [ ] B案（順次起動方式）を採用するか決定
- [ ] 採用した案を実装
- [ ] batsテスト実行（`bats tests/ tests/unit/`）
- [ ] 実機テスト（Zellij Pure Mode）
- [ ] プロンプト混入が解消したことを確認
- [ ] コミット・プッシュ
- [ ] `docs/WORKLOG.md` に作業記録を追記
- [ ] `docs/REQS.md` に受け入れ条件を追記

---

## 8. 質問事項（ユーザーへの確認が必要）

1. **どのエージェントにどのプロンプトが入りましたか？**
   - 例: karo → 軍師のプロンプトが入った
   - 例: ashigaru1 → karoのプロンプトが入った

2. **複数回テストして、混入パターンは一定ですか？それともランダムですか？**
   - 一定の場合: 送信順序の問題の可能性
   - ランダムの場合: 並行実行の競合の可能性

3. **優先する運用スタイルはどれですか？**
   - A. Zellij Pure Modeを安定させたい（起動時間が多少長くても可）
   - B. Tmux優先運用に戻す（Zellijは実験的機能として位置づけ）
   - C. Claude限定で確実に動けばOK（他CLIは後回し）

---

## 9. コミット履歴

### コミット `39556af` (2026-02-17)

```
fix: ブートストラップ誤送信を根本修正（ファイルベース配信方式）

zellij/tmuxの初動命令（プロンプト注入）で、将軍に足軽の
プロンプトが注入されるなどの誤送信をファイルベース方式で解決。

変更内容:
- generate_bootstrap_file(): 各エージェントのブートストラップを
  queue/runtime/bootstrap_{agent_id}.md に事前書き出し
- deliver_bootstrap_zellij(): セッション存在チェック + CLI readiness
  確認 + リトライ付き配信（wait_for_cli_ready 最大15秒）
- deliver_bootstrap_tmux(): ペイン存在チェック + ファイルから読み出し
- send_line(): zellij版にセッション存在チェックを追加
- CLI起動前にブートストラップファイルを全エージェント分生成
- バッチ sleep 2 を廃止、エージェント毎の個別配信に変更
- localapi テストの期待値をモデル環境変数対応に更新

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**ファイル**: `scripts/shutsujin_zellij.sh`, `shutsujin_departure.sh`, `tests/unit/test_cli_adapter.bats`

---

**END OF HANDOVER**
