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

find_project_root() {
    local dir
    dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/scripts/build_instructions.sh" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

setup_file() {
    export PROJECT_ROOT="$(find_project_root)"
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
    PROJECT_ROOT="$(find_project_root)"
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

@test "build: OpenCode agent definitions are generated" {
    [ -f "$PROJECT_ROOT/.opencode/agents/shogun.md" ]
    [ -f "$PROJECT_ROOT/.opencode/agents/gunkan.md" ]
    [ -f "$PROJECT_ROOT/.opencode/agents/karo.md" ]
    [ -f "$PROJECT_ROOT/.opencode/agents/karo2.md" ]
    [ -f "$PROJECT_ROOT/.opencode/agents/ashigaru8.md" ]
    grep -q "mode: primary" "$PROJECT_ROOT/.opencode/agents/shogun.md"
    grep -q "Canonical agent_id: \`gunkan\`" "$PROJECT_ROOT/.opencode/agents/gunkan.md"
    grep -q "Canonical agent_id: \`ashigaru8\`" "$PROJECT_ROOT/.opencode/agents/ashigaru8.md"
}

@test "build: instruction source is MOD-owned with root compatibility fallback" {
    run bash "$BUILD_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Source directory: $PROJECT_ROOT/shogunate_mod/instructions/source"* ]]
    [[ "$output" == *"Auto-load source: $PROJECT_ROOT/shogunate_mod/instructions/autoload/CLAUDE.md"* ]]
    grep -q "shogunate_mod/instructions/source/roles/shogun_role.md" "$PROJECT_ROOT/.opencode/agents/shogun.md"
}

@test "build: generated instructions include MOD-owned role and CLI harnesses" {
    grep -q "Shogunate Role Harness" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "Optimization Advisory Harness" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "Role Harness: Gunkan" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "CLI Harness: Codex" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "CLI Harness: Claude" "$OUTPUT_DIR/gunkan.md"
    grep -q "CLI Harness: OpenCode" "$OUTPUT_DIR/opencode-karo.md"
    grep -q "CLI Harness: Antigravity" "$OUTPUT_DIR/antigravity-shogun.md"
    grep -q "CLI Harness: Cursor" "$OUTPUT_DIR/cursor-shogun.md"
    grep -q "CLI Harness: Copilot" "$OUTPUT_DIR/copilot-shogun.md"
    grep -q "CLI Harness: Kimi" "$OUTPUT_DIR/kimi-shogun.md"
    grep -q "CLI Harness: Kilo" "$OUTPUT_DIR/kilo-shogun.md"
    grep -q "CLI Harness: LocalAPI" "$OUTPUT_DIR/localapi-shogun.md"
    grep -q "Role Harness: Ashigaru" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Role Harness: Gunshi" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Role Harness: Karo" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Role Harness: Shogun" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Optimization Advisory Harness" "$PROJECT_ROOT/.opencode/agents/gunkan.md"
}

@test "build: role harnesses preserve samurai persona and packet discipline" {
    grep -q "Persona Preservation" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Harness Packet" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Command Packet" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Task Packet" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Report Packet" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Advice Packet" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Audit Packet" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "Speak as Shogun" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "Speak as Karo" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Speak as Ashigaru" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Speak as Gunshi" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Speak as Gunkan" "$OUTPUT_DIR/codex-gunkan.md"
}

@test "build: role harnesses define workspace instruction priority" {
    grep -q "Instruction Scope and Priority" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "workspace instructions" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Never let a workspace \`AGENTS.md\` change your Shogunate role" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "keep the Shogunate role boundary and report the conflict" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "workspace \`AGENTS.md\` can refine repository conventions" "$OUTPUT_DIR/codex-shogun.md"
    grep -q "must not replace Shogunate role identity" "$OUTPUT_DIR/codex-shogun.md"
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

@test "claude: gunkan.md generated" {
    [ -f "$OUTPUT_DIR/gunkan.md" ]
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

@test "codex: codex-gunkan.md generated" {
    [ -f "$OUTPUT_DIR/codex-gunkan.md" ]
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

@test "content: codex-karo.md documents lead karo and coordination board" {
    grep -q "queue/runtime/lead_karo" "$OUTPUT_DIR/codex-karo.md"
    grep -q "queue/runtime/karo_coordination.yaml" "$OUTPUT_DIR/codex-karo.md"
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

@test "content: codex-gunkan.md defines independent event-driven audit role" {
    grep -q "Gunkan (軍監) Role Definition" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "将軍直属の独立監査役" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "queue/reports/gunkan_report.yaml" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "常時ポーリングや周期監視でトークンを使う" "$OUTPUT_DIR/codex-gunkan.md"
    grep -q "Event-Driven Activation" "$OUTPUT_DIR/codex-gunkan.md"
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

@test "content: codex-ashigaru.md requires exact contract match with sibling lane artifacts" {
    grep -q "If sibling-lane artifacts such as \`README.md\`, \`tests/test_app.py\`, or \`app.py\` already exist, re-read them and match their public identifiers exactly" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "Do not invent near-synonyms" "$OUTPUT_DIR/codex-ashigaru.md"
    grep -q "must use the exact same function names, exception names, CLI behavior, and JSON keys" "$OUTPUT_DIR/codex-ashigaru.md"
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
    grep -q "the first dispatch must use the active roster broadly" "$OUTPUT_DIR/codex-karo.md"
    grep -q "assign lanes across all useful active ashigaru in order, including \`ashigaru3+\` when present" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do \*\*not\*\* stop at \`ashigaru1\` / \`ashigaru2\` when \`ashigaru3+\` are active" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md tells karo when to use gunshi" {
    grep -q "## Gunshi Consultation Rule" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Assign a \`queue/tasks/gunshi.yaml\` analysis task" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do not wait for Gunshi before the first dispatch when obvious safe lanes already exist" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Gunshi does \*\*not\*\* implement files, manage ashigaru, update \`dashboard.md\`, or close the cmd" "$OUTPUT_DIR/codex-karo.md"
    grep -q "### Bloom Level → Agent Routing" "$OUTPUT_DIR/codex-karo.md"
    grep -q '"Investigating root cause/structure?" | L4 Analyze | \*\*Gunshi\*\*' "$OUTPUT_DIR/codex-karo.md"
    grep -q "## Quality Control Routing" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Route complex checks to Gunshi via \`queue/tasks/gunshi.yaml\`" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md runs proactive clarification and autonomous PDCA" {
    grep -q "## Proactive Clarification and Autonomous PDCA" "$OUTPUT_DIR/codex-karo.md"
    grep -q "High-impact ambiguity: ask Shogun for the lord's decision with 3-5 concrete questions" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Repeat up to 3 QC cycles" "$OUTPUT_DIR/codex-karo.md"
    grep -q "This PDCA loop must remain event-driven" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md allows greenfield split before files exist" {
    grep -q "\`target_path\` is the intended output path for the lane" "$OUTPUT_DIR/codex-karo.md"
    grep -q "For greenfield directories, you may split \`app.py\`, \`README.md\`, and \`tests/test_app.py\` in parallel" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do not treat the absence of those files at dispatch time as a reason to serialize the work" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-karo.md writes explicit shared contract into parallel app and README/tests lanes" {
    grep -q "When those parallel lanes must share a public contract, write the exact same contract into both task descriptions before dispatch" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Name the public function(s), exception type(s), CLI entrypoint behavior, and required output keys explicitly" "$OUTPUT_DIR/codex-karo.md"
    grep -q "Do not write vague instructions such as \"align with README/tests\"" "$OUTPUT_DIR/codex-karo.md"
    grep -q "For the common split of \`app.py\` vs \`README.md\` + \`tests/test_app.py\`" "$OUTPUT_DIR/codex-karo.md"
}

@test "content: codex-gunshi.md enforces event-driven standby after analysis" {
    grep -q "Gunshi must also remain event-driven" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "return to standby immediately" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "No sleep loop, no periodic re-analysis" "$OUTPUT_DIR/codex-gunshi.md"
}

@test "content: codex-gunshi.md keeps upstream strategist safeguards" {
    grep -q "## Forbidden Actions" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Manage ashigaru inboxes or assign work" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "## North Star Alignment" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "north_star_alignment" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "## Critical Thinking Protocol" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Confidence label" "$OUTPUT_DIR/codex-gunshi.md"
}

@test "content: codex-gunshi.md designs clarification and PDCA without taking over execution" {
    grep -q "## Proactive Clarification and Autonomous PDCA" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "return 3-5 concrete questions for Shogun / ntfy escalation" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "allow up to 3 QC cycles before escalation" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Gunshi may design the loop, critique outputs, and recommend redo / scale-out" "$OUTPUT_DIR/codex-gunshi.md"
    grep -q "Gunshi must not assign ashigaru" "$OUTPUT_DIR/codex-gunshi.md"
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
