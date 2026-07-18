#!/usr/bin/env bash
# ============================================================
# Instruction File Build System
# ============================================================
# Combines instruction parts into complete instruction files
# for each role and CLI combination.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_SOURCE_DIR="$ROOT_DIR/shogunate_mod/instructions/source"
FALLBACK_SOURCE_DIR="$ROOT_DIR/instructions"
PARTS_DIR="${SHOGUNATE_INSTRUCTIONS_SOURCE:-$DEFAULT_SOURCE_DIR}"
if [ ! -d "$PARTS_DIR" ]; then
    PARTS_DIR="$FALLBACK_SOURCE_DIR"
fi
DEFAULT_AUTOLOAD_DIR="$ROOT_DIR/shogunate_mod/instructions/autoload"
AUTOLOAD_DIR="${SHOGUNATE_AUTOLOAD_SOURCE:-$DEFAULT_AUTOLOAD_DIR}"
AUTOLOAD_CLAUDE_MD="$AUTOLOAD_DIR/CLAUDE.md"
if [ ! -f "$AUTOLOAD_CLAUDE_MD" ]; then
    AUTOLOAD_CLAUDE_MD="$ROOT_DIR/CLAUDE.md"
fi
OUTPUT_DIR="$ROOT_DIR/instructions/generated"

mkdir -p "$OUTPUT_DIR"

echo "=== Instruction File Build System ==="
echo "Building instruction files..."
echo "Source directory: $PARTS_DIR"
echo "Auto-load source: $AUTOLOAD_CLAUDE_MD"

opencode_build_python() {
    local candidate
    for candidate in "$ROOT_DIR/.venv/bin/python3" "$(command -v python3 2>/dev/null || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if "$candidate" -c 'import yaml' 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done

    echo "  ❌ PyYAML is required for OpenCode agent generation. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
    return 1
}

normalize_generated_markdown() {
    local output_path="$1"
    local tmp_path="${output_path}.tmp.$$"

    [ -f "$output_path" ] || return 0

    awk '{ sub(/\r$/, ""); sub(/[ \t]+$/, ""); print }' "$output_path" > "$tmp_path"
    mv "$tmp_path" "$output_path"
}

append_optional_section() {
    local output_path="$1"
    local section_path="$2"

    [ -f "$section_path" ] || return 0

    echo "" >> "$output_path"
    cat "$section_path" >> "$output_path"
}

append_harness_sections() {
    local output_path="$1"
    local cli_type="$2"
    local role="$3"
    local harness_dir="$PARTS_DIR/harnesses"

    [ -d "$harness_dir" ] || return 0

    append_optional_section "$output_path" "$harness_dir/common/role_best_practices.md"
    append_optional_section "$output_path" "$harness_dir/common/optimization_advisory.md"
    append_optional_section "$output_path" "$harness_dir/roles/${role}.md"
    append_optional_section "$output_path" "$harness_dir/cli/${cli_type}.md"
}

sync_root_instruction_compatibility_sources() {
    local source_path rel root_path

    [[ "$PARTS_DIR" == "$DEFAULT_SOURCE_DIR" ]] || return 0

    while IFS= read -r source_path; do
        rel="${source_path#$PARTS_DIR/}"
        root_path="$ROOT_DIR/instructions/$rel"
        mkdir -p "$(dirname "$root_path")"
        cp "$source_path" "$root_path"
    done < <(find "$PARTS_DIR" -type f -name '*.md' | sort)
}

# ============================================================
# Helper function: Build a complete instruction file
# ============================================================
build_instruction_file() {
    local cli_type="$1"
    local role="$2"
    local output_filename="$3"
    local output_path="$OUTPUT_DIR/$output_filename"
    local original_file="$PARTS_DIR/${role}.md"

    echo "Building: $output_filename (CLI: $cli_type, Role: $role)"

    # Extract YAML front matter from original file
    if [ -f "$original_file" ]; then
        awk '/^---$/{if(++n==2) {print "---"; exit} if(n==1) next} n==1' "$original_file" > "$output_path"
        echo "" >> "$output_path"
    else
        # Minimal YAML front matter
        cat > "$output_path" <<EOFYAML
---
role: $role
version: "3.0"
cli_type: $cli_type
---

EOFYAML
    fi

    # Append role-specific content
    cat "$PARTS_DIR/roles/${role}_role.md" >> "$output_path"

    # Append Shogunate MOD harnesses
    append_harness_sections "$output_path" "$cli_type" "$role"

    # Append common sections
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/protocol.md" >> "$output_path"
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/task_flow.md" >> "$output_path"
    echo "" >> "$output_path"
    cat "$PARTS_DIR/common/forbidden_actions.md" >> "$output_path"

    # Append CLI-specific tools section
    echo "" >> "$output_path"
    case "$cli_type" in
        claude)
            cat "$PARTS_DIR/cli_specific/claude_tools.md" >> "$output_path"
            ;;
        codex)
            cat "$PARTS_DIR/cli_specific/codex_tools.md" >> "$output_path"
            ;;
        copilot)
            cat "$PARTS_DIR/cli_specific/copilot_tools.md" >> "$output_path"
            ;;
        kimi)
            cat "$PARTS_DIR/cli_specific/kimi_tools.md" >> "$output_path"
            ;;
        cursor)
            cat "$PARTS_DIR/cli_specific/cursor_tools.md" >> "$output_path"
            ;;
        antigravity)
            cat "$PARTS_DIR/cli_specific/antigravity_tools.md" >> "$output_path"
            ;;
        localapi)
            cat "$PARTS_DIR/cli_specific/localapi_tools.md" >> "$output_path"
            ;;
        opencode)
            cat "$PARTS_DIR/cli_specific/opencode_tools.md" >> "$output_path"
            ;;
        kilo)
            cat "$PARTS_DIR/cli_specific/kilo_tools.md" >> "$output_path"
            ;;
        grok)
            cat "$PARTS_DIR/cli_specific/grok_tools.md" >> "$output_path"
            ;;
    esac

    normalize_generated_markdown "$output_path"

    echo "  ✅ Created: $output_filename"
}

sync_root_instruction_compatibility_sources

# Build Claude Code instruction files
build_instruction_file "claude" "shogun" "shogun.md"
build_instruction_file "claude" "karo" "karo.md"
build_instruction_file "claude" "ashigaru" "ashigaru.md"
build_instruction_file "claude" "gunshi" "gunshi.md"
build_instruction_file "claude" "gunkan" "gunkan.md"

# Claude Code agents read instructions/{role}.md (referenced from CLAUDE.md).
# Historically these were frozen v1 monoliths: they embedded Codex tool docs
# even for Claude agents, and gunshi/gunkan bodies were empty scaffolds.
# Serve the claude build output instead so Claude gets the same
# role + harness + common stack as every other CLI, with claude_tools.
# Must run after sync_root_instruction_compatibility_sources (which copies the
# legacy source monolith to the same path) so this final copy wins; the source
# monolith body remains only as the YAML front-matter donor.
for claude_role in shogun karo ashigaru gunshi gunkan; do
    cp "$OUTPUT_DIR/${claude_role}.md" "$ROOT_DIR/instructions/${claude_role}.md"
    echo "  ✅ Published: instructions/${claude_role}.md (claude build)"
done

# Build Codex instruction files
build_instruction_file "codex" "shogun" "codex-shogun.md"
build_instruction_file "codex" "karo" "codex-karo.md"
build_instruction_file "codex" "ashigaru" "codex-ashigaru.md"
build_instruction_file "codex" "gunshi" "codex-gunshi.md"
build_instruction_file "codex" "gunkan" "codex-gunkan.md"

# Build Copilot instruction files
build_instruction_file "copilot" "shogun" "copilot-shogun.md"
build_instruction_file "copilot" "karo" "copilot-karo.md"
build_instruction_file "copilot" "ashigaru" "copilot-ashigaru.md"
build_instruction_file "copilot" "gunshi" "copilot-gunshi.md"
build_instruction_file "copilot" "gunkan" "copilot-gunkan.md"

# Build Kimi K2 instruction files
build_instruction_file "kimi" "shogun" "kimi-shogun.md"
build_instruction_file "kimi" "karo" "kimi-karo.md"
build_instruction_file "kimi" "ashigaru" "kimi-ashigaru.md"
build_instruction_file "kimi" "gunshi" "kimi-gunshi.md"
build_instruction_file "kimi" "gunkan" "kimi-gunkan.md"

# Build Antigravity instruction files
build_instruction_file "antigravity" "shogun" "antigravity-shogun.md"
build_instruction_file "antigravity" "karo" "antigravity-karo.md"
build_instruction_file "antigravity" "ashigaru" "antigravity-ashigaru.md"
build_instruction_file "antigravity" "gunshi" "antigravity-gunshi.md"
build_instruction_file "antigravity" "gunkan" "antigravity-gunkan.md"

# Build Cursor Agent instruction files
build_instruction_file "cursor" "shogun" "cursor-shogun.md"
build_instruction_file "cursor" "karo" "cursor-karo.md"
build_instruction_file "cursor" "ashigaru" "cursor-ashigaru.md"
build_instruction_file "cursor" "gunshi" "cursor-gunshi.md"
build_instruction_file "cursor" "gunkan" "cursor-gunkan.md"

# Build Local API instruction files
build_instruction_file "localapi" "shogun" "localapi-shogun.md"
build_instruction_file "localapi" "karo" "localapi-karo.md"
build_instruction_file "localapi" "ashigaru" "localapi-ashigaru.md"
build_instruction_file "localapi" "gunshi" "localapi-gunshi.md"
build_instruction_file "localapi" "gunkan" "localapi-gunkan.md"

# Build OpenCode instruction files
build_instruction_file "opencode" "shogun" "opencode-shogun.md"
build_instruction_file "opencode" "karo" "opencode-karo.md"
build_instruction_file "opencode" "ashigaru" "opencode-ashigaru.md"
build_instruction_file "opencode" "gunshi" "opencode-gunshi.md"
build_instruction_file "opencode" "gunkan" "opencode-gunkan.md"

# Build Kilo instruction files
build_instruction_file "kilo" "shogun" "kilo-shogun.md"
build_instruction_file "kilo" "karo" "kilo-karo.md"
build_instruction_file "kilo" "ashigaru" "kilo-ashigaru.md"
build_instruction_file "kilo" "gunshi" "kilo-gunshi.md"
build_instruction_file "kilo" "gunkan" "kilo-gunkan.md"

# Build Grok Build instruction files
# Grok Build (cli_type: grok, default model grok-4.5) was added in GB-002/GB-003A.
# Same 5-role mapping as the other MOD-owned CLIs so adapter.get_instruction_file
# resolves grok through instructions/generated/grok-<role>.md instead of the claude fallback.
build_instruction_file "grok" "shogun" "grok-shogun.md"
build_instruction_file "grok" "karo" "grok-karo.md"
build_instruction_file "grok" "ashigaru" "grok-ashigaru.md"
build_instruction_file "grok" "gunshi" "grok-gunshi.md"
build_instruction_file "grok" "gunkan" "grok-gunkan.md"

# ============================================================
# AGENTS.md generation (Codex auto-load file)
# ============================================================
# Codex CLIはリポジトリルートのAGENTS.mdを自動読み込みする。
# MOD-owned CLAUDE.md sourceを正本とし、Claude固有部分をCodex固有に置換して生成。
generate_agents_md() {
    local output_path="$ROOT_DIR/AGENTS.md"
    local claude_md="$AUTOLOAD_CLAUDE_MD"

    echo "Generating: AGENTS.md (Codex auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping AGENTS.md generation."
        return 1
    fi

    # Normalize line endings to LF to keep tracked auto-load files stable across platforms.
    sed \
        -e 's|CLAUDE\.md|AGENTS.md|g' \
        -e 's|CLAUDE\.local\.md|AGENTS.override.md|g' \
        -e 's|instructions/shogun\.md|instructions/generated/codex-shogun.md|g' \
        -e 's|instructions/karo\.md|instructions/generated/codex-karo.md|g' \
        -e 's|instructions/ashigaru\.md|instructions/generated/codex-ashigaru.md|g' \
        -e 's|instructions/gunshi\.md|instructions/generated/codex-gunshi.md|g' \
        -e 's|instructions/gunkan\.md|instructions/generated/codex-gunkan.md|g' \
        -e 's|~/.claude/|~/.codex/|g' \
        -e 's|\.claude\.json|.codex/config.toml|g' \
        -e 's|\.mcp\.json|config.toml (mcp_servers section)|g' \
        -e 's|Claude Code|Codex CLI|g' \
        -e 's|## /clear Recovery|## /new Recovery|g' \
        -e 's|Forbidden after /clear|Forbidden after /new|g' \
        -e 's|pre-/clear memory|pre-/new memory|g' \
        -e 's|lost on /clear)|lost on /new)|g' \
        -e 's|(/new or /clear)|(`/new`)|g' \
        -e 's|sends `/clear` + Enter via send-keys|sends `/new` + Enter via send-keys（/clear→/new自動変換）|g' \
        -e 's|`/clear` sent (max once per 5 min)|スキップ（Codexは`/clear`不可）|g' \
        -e 's|escalation sends `/clear` (~4 min)|next nudge escalation or task reassignment|g' \
        -e 's|delivers `/clear` to the agent|delivers `/new` to the agent（/clear→/new自動変換）|g' \
        -e 's|`/clear` wipes old context|`/new` wipes old context|g' \
        "$claude_md" | tr -d '\r' > "$output_path"

    echo "  ✅ Created: AGENTS.md"
}

# ============================================================
# copilot-instructions.md generation (Copilot auto-load file)
# ============================================================
# GitHub Copilot CLIは .github/copilot-instructions.md を自動読み込みする。
# MOD-owned CLAUDE.md sourceを正本とし、Claude固有部分をCopilot固有に置換して生成。
generate_copilot_instructions() {
    local github_dir="$ROOT_DIR/.github"
    local output_path="$github_dir/copilot-instructions.md"
    local claude_md="$AUTOLOAD_CLAUDE_MD"

    echo "Generating: .github/copilot-instructions.md (Copilot auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping copilot-instructions.md generation."
        return 1
    fi

    mkdir -p "$github_dir"

    # Normalize line endings to LF to keep tracked auto-load files stable across platforms.
    sed \
        -e 's|CLAUDE\.md|copilot-instructions.md|g' \
        -e 's|CLAUDE\.local\.md|copilot-instructions.local.md|g' \
        -e 's|instructions/shogun\.md|instructions/generated/copilot-shogun.md|g' \
        -e 's|instructions/karo\.md|instructions/generated/copilot-karo.md|g' \
        -e 's|instructions/ashigaru\.md|instructions/generated/copilot-ashigaru.md|g' \
        -e 's|instructions/gunshi\.md|instructions/generated/copilot-gunshi.md|g' \
        -e 's|instructions/gunkan\.md|instructions/generated/copilot-gunkan.md|g' \
        -e 's|~/.claude/|~/.copilot/|g' \
        -e 's|\.claude\.json|.copilot/config.json|g' \
        -e 's|\.mcp\.json|.copilot/mcp-config.json|g' \
        -e 's|Claude Code|GitHub Copilot CLI|g' \
        "$claude_md" | tr -d '\r' > "$output_path"

    echo "  ✅ Created: .github/copilot-instructions.md"
}

# ============================================================
# Kimi K2 auto-load files generation
# ============================================================
# Kimi K2 CLIは agents/default/agent.yaml + system.md を自動読み込みする。
# MOD-owned CLAUDE.md sourceを正本とし、Claude固有部分をKimi固有に置換して生成。
generate_kimi_instructions() {
    local agents_dir="$ROOT_DIR/agents/default"
    local system_md_path="$agents_dir/system.md"
    local agent_yaml_path="$agents_dir/agent.yaml"
    local claude_md="$AUTOLOAD_CLAUDE_MD"

    echo "Generating: agents/default/system.md + agent.yaml (Kimi auto-load)"

    if [ ! -f "$claude_md" ]; then
        echo "  ⚠️  CLAUDE.md not found. Skipping Kimi auto-load generation."
        return 1
    fi

    mkdir -p "$agents_dir"

    # Generate system.md (CLAUDE.md → Kimi版)
    # Normalize line endings to LF to keep tracked auto-load files stable across platforms.
    sed \
        -e 's|CLAUDE\.md|agents/default/system.md|g' \
        -e 's|CLAUDE\.local\.md|agents/default/system.local.md|g' \
        -e 's|instructions/shogun\.md|instructions/generated/kimi-shogun.md|g' \
        -e 's|instructions/karo\.md|instructions/generated/kimi-karo.md|g' \
        -e 's|instructions/ashigaru\.md|instructions/generated/kimi-ashigaru.md|g' \
        -e 's|instructions/gunshi\.md|instructions/generated/kimi-gunshi.md|g' \
        -e 's|instructions/gunkan\.md|instructions/generated/kimi-gunkan.md|g' \
        -e 's|~/.claude/|~/.kimi/|g' \
        -e 's|\.claude\.json|.kimi/config.json|g' \
        -e 's|\.mcp\.json|.kimi/mcp.json|g' \
        -e 's|Claude Code|Kimi K2 CLI|g' \
        "$claude_md" | tr -d '\r' > "$system_md_path"

    echo "  ✅ Created: agents/default/system.md"

    # Generate agent.yaml (Kimi agent definition)
    cat > "$agent_yaml_path" <<'EOFYAML'
# Kimi K2 Agent Configuration
# Auto-generated by build_instructions.sh — do not edit manually
name: multi-agent-shogun
description: "Kimi K2 CLI agent for multi-agent-shogun system"
model: moonshot-k2.5
system_prompt_file: system.md
tools:
  - file_read
  - file_write
  - shell_exec
  - web_search
EOFYAML

    echo "  ✅ Created: agents/default/agent.yaml"
}

# ============================================================
# OpenCode agent definition files generation
# ============================================================
generate_opencode_agents() {
    local agents_dir="$ROOT_DIR/.opencode/agents"
    local permissions_file="${OPENCODE_PERMISSIONS_FILE:-$ROOT_DIR/shogunate_mod/configure/opencode-permissions.yaml}"
    local python_bin

    echo "Generating: .opencode/agents/*.md (OpenCode agent definitions)"

    if [ ! -f "$permissions_file" ] && [ -z "${OPENCODE_PERMISSIONS_FILE:-}" ]; then
        permissions_file="$ROOT_DIR/config/opencode-permissions.yaml"
    fi

    if [ ! -f "$permissions_file" ]; then
        echo "  ⚠️  OpenCode permissions matrix not found. Skipping OpenCode agent generation."
        echo "      Expected: shogunate_mod/configure/opencode-permissions.yaml"
        return 1
    fi

    mkdir -p "$agents_dir"

    python_bin=$(opencode_build_python) || return 1

    # Deterministic tracked output.  Include fork-only multi-karo and ashigaru8
    # surfaces so any role can be switched to OpenCode without a missing --agent.
    local agent_ids
    agent_ids="shogun gunkan karo karo1 karo2 karo3 gunshi ashigaru1 ashigaru2 ashigaru3 ashigaru4 ashigaru5 ashigaru6 ashigaru7 ashigaru8"

    for agent_id in $agent_ids; do
        local role=""
        local role_title=""
        case "$agent_id" in
            ashigaru*) role="ashigaru" ;;
            karo*)     role="karo" ;;
            *)         role="$agent_id" ;;
        esac

        case "$agent_id" in
            shogun)
                role_title="Shogun — strategic oversight and command issuance"
                ;;
            gunkan)
                role_title="Gunkan — independent audit and coherence review"
                ;;
            karo)
                role_title="Karo — task decomposition, assignment, and coordination"
                ;;
            karo*)
                role_title="Karo ${agent_id#karo} — task decomposition, assignment, and coordination"
                ;;
            gunshi)
                role_title="Gunshi — strategic analysis and quality control"
                ;;
            ashigaru*)
                role_title="Ashigaru ${agent_id#ashigaru} — front-line execution"
                ;;
        esac

        local permission_yaml
        if ! permission_yaml=$("$python_bin" - "$permissions_file" "$agent_id" <<'PYEOF'
import sys, yaml

permissions_file = sys.argv[1]
agent_id = sys.argv[2]

def role_for_agent(value: str) -> str:
    if value.startswith("ashigaru"):
        return "ashigaru"
    if value.startswith("karo"):
        return "karo"
    if value in {"shogun", "gunshi", "gunkan"}:
        return value
    return ""

def expand(pattern: str) -> str:
    return pattern.replace("{agent_id}", agent_id)

def build_rule(deny_patterns, allow_patterns):
    deny, allow, seen = [], [], set()
    for pattern in deny_patterns or []:
        expanded = expand(pattern)
        if expanded not in seen:
            seen.add(expanded)
            deny.append(expanded)
    for pattern in allow_patterns or []:
        expanded = expand(pattern)
        if expanded not in seen:
            seen.add(expanded)
            allow.append(expanded)
    rule = {}
    for pattern in deny:
        rule[pattern] = "deny"
    for pattern in allow:
        rule[pattern] = "allow"
    return rule

with open(permissions_file, encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}

role_cfg = (config.get("roles") or {}).get(role_for_agent(agent_id)) or {}
common_edit_deny = list((config.get("common") or {}).get("edit_deny") or [])
read_rule = build_rule(role_cfg.get("read_deny"), role_cfg.get("read_allow"))
edit_rule = build_rule(common_edit_deny + list(role_cfg.get("edit_deny") or []), role_cfg.get("edit_allow"))

permission = {
    "*": "allow",
    "question": role_cfg.get("question", "deny"),
    "read": read_rule,
    "edit": edit_rule,
    "write": edit_rule,
    "patch": edit_rule,
    "list": read_rule,
    "glob": read_rule,
}

print(yaml.dump({"permission": permission}, default_flow_style=False, allow_unicode=True).rstrip())
PYEOF
        ); then
            echo "  ❌ Failed to generate OpenCode permissions for ${agent_id}" >&2
            return 1
        fi

        local output_path="$agents_dir/${agent_id}.md"
        cat > "$output_path" <<FRONTMATTER
---
description: "${role_title}"
mode: primary
# Auto-generated by build_instructions.sh — do not edit manually.
# Source: shogunate_mod/instructions/source/roles/${role}_role.md + shogunate_mod/instructions/source/harnesses/* + shogunate_mod/instructions/source/common/* + shogunate_mod/instructions/source/cli_specific/opencode_tools.md
# grep intentionally inherits '*: allow'; OpenCode grep permission rules match the search regex, not file paths.
${permission_yaml}
---

FRONTMATTER

        {
            cat "$PARTS_DIR/roles/${role}_role.md"
            echo ""
            cat <<EOF
## Identity Anchor

This generated file belongs to exactly one agent.

- Canonical agent_id: \`${agent_id}\`
- Canonical tmux check: \`tmux display-message -t "\$TMUX_PANE" -p '#{@agent_id}'\`
- Proceed only if the tmux value matches the canonical agent_id.
- If you have not confirmed this yet, confirm it before reading inbox/task files.

EOF
        } >> "$output_path"

        append_harness_sections "$output_path" "opencode" "$role"

        {
            echo ""
            cat "$PARTS_DIR/common/protocol.md"
            echo ""
            cat "$PARTS_DIR/common/task_flow.md"
            echo ""
            cat "$PARTS_DIR/common/forbidden_actions.md"
            echo ""
            cat "$PARTS_DIR/cli_specific/opencode_tools.md"
        } >> "$output_path"

        normalize_generated_markdown "$output_path"

        local routing_yaml
        routing_yaml=$("$python_bin" - "$ROOT_DIR/config/settings.yaml" "$agent_id" <<'PYEOF'
import sys
from pathlib import Path
import yaml

settings_path = Path(sys.argv[1])
agent_id = sys.argv[2]

def normalize_opencode_model(model: str) -> str:
    if not model:
        return ""
    if "/" in model:
        return model
    if model in {"gpt-5.4-mini", "gpt-5.4", "gpt-5.3-codex", "gpt-5.3-codex-spark"} or model.startswith("gpt-5"):
        return f"openai/{model}"
    if model in {"claude-opus-4-6", "opus"}:
        return "anthropic/claude-opus-4-6"
    if model in {"claude-sonnet-4-6", "sonnet"}:
        return "anthropic/claude-sonnet-4-6"
    if model in {"claude-haiku-4-5-20251001", "haiku"}:
        return "anthropic/claude-haiku-4-5-20251001"
    if model in {"moonshot-k2.5", "k2.5"}:
        return "moonshot/kimi-k2.5"
    if model.startswith("kimi-"):
        return f"moonshot/kimi-{model.removeprefix('kimi-')}"
    return model

if not settings_path.exists():
    raise SystemExit(0)

settings = yaml.safe_load(settings_path.read_text(encoding="utf-8")) or {}
cli = settings.get("cli") or {}
default_cli = cli.get("default", "claude")
agents = cli.get("agents") or {}
agent_cfg = agents.get(agent_id)
if agent_cfg is None and agent_id.startswith("karo") and agent_id != "karo":
    agent_cfg = agents.get("karo")

agent_type = default_cli
model = None
variant = None
if isinstance(agent_cfg, str):
    agent_type = agent_cfg
elif isinstance(agent_cfg, dict):
    agent_type = agent_cfg.get("type") or default_cli
    model = agent_cfg.get("model")
    variant = agent_cfg.get("variant")

if agent_type != "opencode" or not variant:
    raise SystemExit(0)

frontmatter = {}
if model:
    frontmatter["model"] = normalize_opencode_model(str(model))
frontmatter["variant"] = str(variant)
print(yaml.safe_dump(frontmatter, allow_unicode=True, sort_keys=False).rstrip())
PYEOF
        )

        if [[ -n "$routing_yaml" ]]; then
            local runtime_path="$agents_dir/${agent_id}-runtime.md"
            ROUTING_YAML="$routing_yaml" "$python_bin" - "$output_path" "$runtime_path" <<'PYEOF'
import os, sys
from pathlib import Path
import yaml

source = Path(sys.argv[1])
dest = Path(sys.argv[2])
route = yaml.safe_load(os.environ.get("ROUTING_YAML", "")) or {}
text = source.read_text(encoding="utf-8")
if not text.startswith("---\n"):
    raise SystemExit(0)
parts = text.split("---", 2)
if len(parts) < 3:
    raise SystemExit(0)
route_lines = yaml.safe_dump(route, allow_unicode=True, sort_keys=False).splitlines()
frontmatter_lines = parts[1].lstrip("\n").splitlines()
new_lines = []
inserted = False
for line in frontmatter_lines:
    stripped = line.lstrip()
    indent = len(line) - len(stripped)
    if indent == 0 and (stripped.startswith("model:") or stripped.startswith("variant:")):
        continue
    if not inserted and indent == 0 and stripped.startswith("permission:"):
        new_lines.extend(route_lines)
        inserted = True
    new_lines.append(line)
if not inserted:
    new_lines.extend(route_lines)
dest.write_text(f"---\n{chr(10).join(new_lines).rstrip()}\n---{parts[2]}", encoding="utf-8")
PYEOF
            normalize_generated_markdown "$runtime_path"
            echo "  ✅ Created: .opencode/agents/${agent_id}-runtime.md (git-ignored runtime routing)"
        fi

        echo "  ✅ Created: .opencode/agents/${agent_id}.md"
    done
}

# Generate CLI auto-load files
generate_agents_md
generate_copilot_instructions
generate_kimi_instructions
generate_opencode_agents

echo ""
echo "=== Build Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "OpenCode agent definitions:"
ls -lh "$ROOT_DIR/.opencode/agents/"*.md 2>/dev/null || echo "  (none)"
echo ""
echo "Generated instruction files:"
ls -lh "$OUTPUT_DIR"/*.md
echo ""
echo "CLI auto-load files:"
[ -f "$ROOT_DIR/AGENTS.md" ] && ls -lh "$ROOT_DIR/AGENTS.md"
[ -f "$ROOT_DIR/.github/copilot-instructions.md" ] && ls -lh "$ROOT_DIR/.github/copilot-instructions.md"
[ -f "$ROOT_DIR/agents/default/system.md" ] && ls -lh "$ROOT_DIR/agents/default/system.md"
[ -f "$ROOT_DIR/agents/default/agent.yaml" ] && ls -lh "$ROOT_DIR/agents/default/agent.yaml"
