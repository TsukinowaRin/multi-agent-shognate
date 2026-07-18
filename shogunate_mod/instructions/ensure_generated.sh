#!/usr/bin/env bash
# Ensure instructions/generated/*.md are rebuilt when source docs change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/shogunate_mod/instructions/build.sh"
DEFAULT_SOURCE_DIR="${ROOT_DIR}/shogunate_mod/instructions/source"
FALLBACK_SOURCE_DIR="${ROOT_DIR}/instructions"
SOURCE_DIR="${SHOGUNATE_INSTRUCTIONS_SOURCE:-$DEFAULT_SOURCE_DIR}"
if [ ! -d "$SOURCE_DIR" ]; then
    SOURCE_DIR="$FALLBACK_SOURCE_DIR"
fi
DEFAULT_AUTOLOAD_DIR="${ROOT_DIR}/shogunate_mod/instructions/autoload"
AUTOLOAD_DIR="${SHOGUNATE_AUTOLOAD_SOURCE:-$DEFAULT_AUTOLOAD_DIR}"
AUTOLOAD_CLAUDE_MD="${AUTOLOAD_DIR}/CLAUDE.md"
if [ ! -f "$AUTOLOAD_CLAUDE_MD" ]; then
    AUTOLOAD_CLAUDE_MD="${ROOT_DIR}/CLAUDE.md"
fi

if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "[ERROR] build script not found: ${BUILD_SCRIPT}" >&2
    exit 1
fi

latest_source_mtime=0
while IFS= read -r src; do
    [ -f "$src" ] || continue
    src_mtime=$(stat -c '%Y' "$src" 2>/dev/null || echo 0)
    if [ "$src_mtime" -gt "$latest_source_mtime" ]; then
        latest_source_mtime="$src_mtime"
    fi
done < <(
    {
        find "${SOURCE_DIR}" -type f
        printf '%s\n' "${AUTOLOAD_CLAUDE_MD}"
        printf '%s\n' "${ROOT_DIR}/shogunate_mod/configure/opencode-permissions.yaml"
        printf '%s\n' "${ROOT_DIR}/shogunate_mod/instructions/build.sh"
        printf '%s\n' "${ROOT_DIR}/shogunate_mod/instructions/ensure_generated.sh"
    } | sort -u
)

targets=(
    "instructions/generated/shogun.md"
    "instructions/generated/karo.md"
    "instructions/generated/ashigaru.md"
    "instructions/generated/gunshi.md"
    "instructions/generated/gunkan.md"
    "instructions/generated/codex-shogun.md"
    "instructions/generated/codex-karo.md"
    "instructions/generated/codex-ashigaru.md"
    "instructions/generated/codex-gunshi.md"
    "instructions/generated/codex-gunkan.md"
    "instructions/generated/copilot-shogun.md"
    "instructions/generated/copilot-karo.md"
    "instructions/generated/copilot-ashigaru.md"
    "instructions/generated/copilot-gunshi.md"
    "instructions/generated/copilot-gunkan.md"
    "instructions/generated/kimi-shogun.md"
    "instructions/generated/kimi-karo.md"
    "instructions/generated/kimi-ashigaru.md"
    "instructions/generated/kimi-gunshi.md"
    "instructions/generated/kimi-gunkan.md"
    "instructions/generated/cursor-shogun.md"
    "instructions/generated/cursor-karo.md"
    "instructions/generated/cursor-ashigaru.md"
    "instructions/generated/cursor-gunshi.md"
    "instructions/generated/cursor-gunkan.md"
    "instructions/generated/antigravity-shogun.md"
    "instructions/generated/antigravity-karo.md"
    "instructions/generated/antigravity-ashigaru.md"
    "instructions/generated/antigravity-gunshi.md"
    "instructions/generated/antigravity-gunkan.md"
    "instructions/generated/localapi-shogun.md"
    "instructions/generated/localapi-karo.md"
    "instructions/generated/localapi-ashigaru.md"
    "instructions/generated/localapi-gunshi.md"
    "instructions/generated/localapi-gunkan.md"
    "instructions/generated/opencode-shogun.md"
    "instructions/generated/opencode-karo.md"
    "instructions/generated/opencode-ashigaru.md"
    "instructions/generated/opencode-gunshi.md"
    "instructions/generated/opencode-gunkan.md"
    "instructions/generated/kilo-shogun.md"
    "instructions/generated/kilo-karo.md"
    "instructions/generated/kilo-ashigaru.md"
    "instructions/generated/kilo-gunshi.md"
    "instructions/generated/kilo-gunkan.md"
    "instructions/generated/grok-shogun.md"
    "instructions/generated/grok-karo.md"
    "instructions/generated/grok-ashigaru.md"
    "instructions/generated/grok-gunshi.md"
    "instructions/generated/grok-gunkan.md"
    "AGENTS.md"
    ".github/copilot-instructions.md"
    "agents/default/system.md"
    "agents/default/agent.yaml"
    ".opencode/agents/shogun.md"
    ".opencode/agents/gunkan.md"
    ".opencode/agents/karo.md"
    ".opencode/agents/karo1.md"
    ".opencode/agents/karo2.md"
    ".opencode/agents/karo3.md"
    ".opencode/agents/gunshi.md"
    ".opencode/agents/ashigaru1.md"
    ".opencode/agents/ashigaru2.md"
    ".opencode/agents/ashigaru3.md"
    ".opencode/agents/ashigaru4.md"
    ".opencode/agents/ashigaru5.md"
    ".opencode/agents/ashigaru6.md"
    ".opencode/agents/ashigaru7.md"
    ".opencode/agents/ashigaru8.md"
)

needs_rebuild=false
for rel in "${targets[@]}"; do
    target="${ROOT_DIR}/${rel}"
    if [ ! -f "$target" ]; then
        needs_rebuild=true
        break
    fi
    target_mtime=$(stat -c '%Y' "$target" 2>/dev/null || echo 0)
    if [ "$target_mtime" -lt "$latest_source_mtime" ]; then
        needs_rebuild=true
        break
    fi
done

if [ "$needs_rebuild" = true ]; then
    echo "[INFO] instructions source changed. Rebuilding generated instruction files..."
    bash "$BUILD_SCRIPT"
else
    echo "[INFO] generated instruction files are up to date."
fi
