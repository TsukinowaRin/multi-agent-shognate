#!/usr/bin/env bats
# test_build_system.bats — ビルドシステム（build_instructions.sh）ユニットテスト
# Phase 2+3 品質テスト基盤
#
# テスト構成:
#   - ビルド実行テスト: スクリプト正常終了、ディレクトリ生成
#   - ファイル生成テスト: claude/codex/copilot各ロールの生成確認
#   - 内容検証テスト: 空でないこと、ロール名・CLI固有セクション含有
#   - AGENTS.md / copilot-instructions.md 生成テスト
#   - 冪等性テスト: 2回ビルドで差分なし
#
# Phase 2+3未実装テストについて:
#   copilot生成、AGENTS.md、copilot-instructions.md のテストは
#   build_instructions.shが拡張されるまでFAILする（受入基準）。
#   SKIP は使用しない（SKIP=0ルール遵守）。

# --- セットアップ ---

setup_file() {
    export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_instructions.sh"
    export OUTPUT_DIR="$PROJECT_ROOT/instructions/generated"

    # パーツディレクトリの存在確認（前提条件）
    [ -d "$PROJECT_ROOT/instructions/roles" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/common" ] || return 1
    [ -d "$PROJECT_ROOT/instructions/cli_specific" ] || return 1

    # ビルド実行（全テストの前に1回のみ）
    bash "$BUILD_SCRIPT" > /dev/null 2>&1 || true
}

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    BUILD_SCRIPT="$PROJECT_ROOT/scripts/build_instructions.sh"
    OUTPUT_DIR="$PROJECT_ROOT/instructions/generated"
}

# =============================================================================
# ビルド実行テスト
# =============================================================================

@test "build: build_instructions.sh exits with status 0" {
    run bash "$BUILD_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "build: generated/ directory exists after build" {
    [ -d "$OUTPUT_DIR" ]
}

@test "build: generated/ contains at least 6 files" {
    local count
    count=$(find "$OUTPUT_DIR" -name "*.md" -type f | wc -l)
    [ "$count" -ge 6 ]
}

# =============================================================================
# ファイル生成テスト — Claude
# =============================================================================

@test "claude: shogun.md generated" {
    [ -f "$OUTPUT_DIR/shogun.md" ]
}

@test "claude: karo.md generated" {
    [ -f "$OUTPUT_DIR/karo.md" ]
}

@test "claude: ashigaru.md generated" {
    [ -f "$OUTPUT_DIR/ashigaru.md" ]
}

# =============================================================================
# ファイル生成テスト — Codex
# =============================================================================

@test "codex: codex-shogun.md generated" {
    [ -f "$OUTPUT_DIR/codex-shogun.md" ]
}

@test "codex: codex-karo.md generated" {
    [ -f "$OUTPUT_DIR/codex-karo.md" ]
}

@test "codex: codex-ashigaru.md generated" {
    [ -f "$OUTPUT_DIR/codex-ashigaru.md" ]
}

# =============================================================================
# ファイル生成テスト — Copilot (Phase 2+3 受入基準)
# =============================================================================

@test "copilot: copilot-shogun.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-shogun.md" ]
}

@test "copilot: copilot-karo.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-karo.md" ]
}

@test "copilot: copilot-ashigaru.md generated [Phase 2+3]" {
    [ -f "$OUTPUT_DIR/copilot-ashigaru.md" ]
}

# =============================================================================
# 内容検証テスト — 空でないこと
# =============================================================================

@test "content: shogun.md is not empty" {
    [ -s "$OUTPUT_DIR/shogun.md" ]
}

@test "content: karo.md is not empty" {
    [ -s "$OUTPUT_DIR/karo.md" ]
}

@test "content: ashigaru.md is not empty" {
    [ -s "$OUTPUT_DIR/ashigaru.md" ]
}

@test "content: codex-shogun.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-shogun.md" ]
}

@test "content: codex-karo.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-karo.md" ]
}

@test "content: codex-ashigaru.md is not empty" {
    [ -s "$OUTPUT_DIR/codex-ashigaru.md" ]
}

# =============================================================================
# 内容検証テスト — ロール名含有
# =============================================================================

@test "content: shogun.md contains shogun role reference" {
    grep -qi "shogun\|将軍" "$OUTPUT_DIR/shogun.md"
}

@test "content: karo.md contains karo role reference" {
    grep -qi "karo\|家老" "$OUTPUT_DIR/karo.md"
}

@test "content: ashigaru.md contains ashigaru role reference" {
    grep -qi "ashigaru\|足軽" "$OUTPUT_DIR/ashigaru.md"
}

@test "content: codex-shogun.md contains shogun role reference" {
    grep -qi "shogun\|将軍" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: codex-karo.md contains karo role reference" {
    grep -qi "karo\|家老" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md requires task_assigned to name task_id and queue/tasks path" {
    grep -q "task_id" "$OUTPUT_DIR/codex-karo.md"
    grep -q "queue/tasks/ashigaru1.yaml" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Bad:" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md uses active_ashigaru as force roster" {
    grep -q "topology.active_ashigaru" "$OUTPUT_DIR/codex-karo.md"
    grep -q "If only \`ashigaru1\` and \`ashigaru2\` are active, then the force size is two" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md does not hardcode ashigaru1-4/5-8 lanes" {
    ! grep -q "Ashigaru 1-4" "$OUTPUT_DIR/codex-karo.md"
    ! grep -q "Ashigaru 5-8" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-shogun.md uses active_ashigaru for current force recognition" {
    grep -q "topology.active_ashigaru" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "If only \`ashigaru1\` and \`ashigaru2\` are active, then \"all ashigaru\" means those two" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: codex-shogun.md enforces event-driven dispatch and cmd_done wakeups" {
    grep -q "event-driven dispatcher" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "\`type: cmd_done\`" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "\`type: runtime_blocked\`" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "No \`sleep\`, no background monitor, no periodic re-check while idle" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: codex-shogun.md keeps task_assigned on dispatch fast path only" {
    grep -q "Read only the minimum routing sources needed to create the cmd" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Do \*\*not\*\* open implementation targets such as \`app.py\`, test files, README files" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Do \*\*not\*\* run project tests, \`git status\`, or codebase-wide searches" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: codex-ashigaru.md contains ashigaru role reference" {
    grep -qi "ashigaru\|足軽" "$OUTPUT_DIR/codex-ashigaru.md"
}

@test "content: codex-ashigaru.md handles task_assigned by reading queue/tasks first" {
    grep -q "On \`task_assigned\` receipt" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "queue/tasks/ashigaru{N}.yaml" "$OUTPUT_DIR/codex-ashigaru.md"
}

@test "content: codex-ashigaru.md treats missing new target_path as normal greenfield work" {
    grep -q "If \`target_path\` points to a new deliverable that does not exist yet, treat that as normal" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Create the parent directory as needed and proceed with implementation" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "target_path\` is the intended output path" "$OUTPUT_DIR/codex-ashigaru.md"
}

@test "content: codex-ashigaru.md requires exact verification command and cwd before claiming pass" {
    grep -q "result.verification.command" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "result.verification.cwd" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Do not write \`pass\` unless the exact command really exited 0 in that exact directory" "$OUTPUT_DIR/codex-ashigaru.md"
}

@test "content: codex-ashigaru.md enforces event-driven standby after report" {
    grep -q "Ashigaru must work only from assigned events" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "return to standby immediately" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "No sleep loop, no periodic status re-check" "$OUTPUT_DIR/codex-ashigaru.md"
}

@test "content: codex-karo.md reruns reported verification before closing implementation cmd" {
    grep -q "rerun the exact \`result.verification.command\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "treat the report as incomplete and reassign instead of closing" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md enforces inbox-driven wakeups only" {
    grep -q "Karo must remain event-driven at all times" "$OUTPUT_DIR/codex-karo.md"
    grep -q "\`cmd_new\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "\`report_received\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do not run sleep loops, pane polling, or ad-hoc background monitors" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md dispatches cmd_new before broad reading" {
    grep -q "When \`queue/inbox/karo.yaml\` receives \`type: cmd_new\`, dispatch first and expand context later" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Mark the cmd \`status: in_progress\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Immediately send \`type: task_assigned\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do \*\*not\*\* inspect target code, README, test files, or broad repo state before the first dispatch" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md forces initial multi-ashigaru split when the cmd is naturally parallel" {
    grep -q "If two or more active ashigaru are available and the cmd naturally splits into independent early lanes" "$OUTPUT_DIR/codex-karo.md"
    grep -q "assign the first lane to \`ashigaru1\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "assign a complementary lane to \`ashigaru2\`" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do \*\*not\*\* leave \`ashigaru2\` idle" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md allows greenfield split before files exist" {
    grep -q "\`target_path\` is the intended output path for the lane" "$OUTPUT_DIR/codex-karo.md"
    grep -q "For greenfield directories, you may split \`app.py\`, \`README.md\`, and \`tests/test_app.py\` in parallel" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do not treat the absence of those files at dispatch time as a reason to serialize the work" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-gunshi.md enforces event-driven standby after analysis" {
    grep -q "Gunshi must also remain event-driven" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "return to standby immediately" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "No sleep loop, no periodic re-analysis" "$OUTPUT_DIR/codex-gunshi.md"
}

# =============================================================================
# 内容検証テスト — CLI固有セクション
# =============================================================================

@test "content: claude files contain Claude-specific tools" {
    # Claude Code固有ツール: Read, Write, Edit, Bash等
    grep -qi "claude\|Read\|Write\|Edit\|Bash" "$OUTPUT_DIR/shogun.md"
}

@test "content: codex files contain Codex-specific content" {
    grep -qi "codex\|AGENTS.md\|Codex" "$OUTPUT_DIR/codex-shogun.md"
}

@test "content: copilot files contain Copilot-specific content [Phase 2+3]" {
    grep -qi "copilot\|Copilot" "$OUTPUT_DIR/copilot-shogun.md"
}

# =============================================================================
# AGENTS.md 生成テスト (Phase 2+3 受入基準)
# =============================================================================

@test "agents: AGENTS.md generated [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ]
}

@test "agents: AGENTS.md contains Codex-specific content [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/AGENTS.md" ] && grep -qi "codex\|agent" "$PROJECT_ROOT/AGENTS.md"
}

@test "agents: AGENTS.md does not advertise fixed ashigaru1-8 roster" {
    ! grep -q "Ashigaru 1-8" "$PROJECT_ROOT/AGENTS.md"
    grep -q "Active Ashigaru" "$PROJECT_ROOT/AGENTS.md"
    grep -q "topology.active_ashigaru" "$PROJECT_ROOT/AGENTS.md"
}

# =============================================================================
# copilot-instructions.md 生成テスト (Phase 2+3 受入基準)
# =============================================================================

@test "copilot-inst: .github/copilot-instructions.md generated [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]
}

@test "copilot-inst: contains Copilot-specific content [Phase 2+3]" {
    [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ] && \
        grep -qi "copilot" "$PROJECT_ROOT/.github/copilot-instructions.md"
}

# =============================================================================
# 冪等性テスト
# =============================================================================

@test "idempotent: second build produces identical output" {
    # 1st build
    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    local checksums_first
    checksums_first=$(find "$OUTPUT_DIR" -name "*.md" -type f -exec md5sum {} \; | sort)

    # 2nd build
    bash "$BUILD_SCRIPT" > /dev/null 2>&1
    local checksums_second
    checksums_second=$(find "$OUTPUT_DIR" -name "*.md" -type f -exec md5sum {} \; | sort)

    [ "$checksums_first" = "$checksums_second" ]
}
