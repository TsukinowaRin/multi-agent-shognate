#!/usr/bin/env bash
# Ensure instructions/generated/*.md are rebuilt when source docs change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${ROOT_DIR}/scripts/build_instructions.sh"

if [ ! -x "$BUILD_SCRIPT" ]; then
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
        find "${ROOT_DIR}/instructions" -type f ! -path "${ROOT_DIR}/instructions/generated/*"
        printf '%s\n' "${ROOT_DIR}/CLAUDE.md"
        printf '%s\n' "${ROOT_DIR}/scripts/build_instructions.sh"
    } | sort -u
)

targets=(
    "instructions/generated/shogun.md"
    "instructions/generated/karo.md"
    "instructions/generated/ashigaru.md"
    "instructions/generated/codex-shogun.md"
    "instructions/generated/codex-karo.md"
    "instructions/generated/codex-ashigaru.md"
    "instructions/generated/copilot-shogun.md"
    "instructions/generated/copilot-karo.md"
    "instructions/generated/copilot-ashigaru.md"
    "instructions/generated/kimi-shogun.md"
    "instructions/generated/kimi-karo.md"
    "instructions/generated/kimi-ashigaru.md"
    "instructions/generated/gemini-shogun.md"
    "instructions/generated/gemini-karo.md"
    "instructions/generated/gemini-ashigaru.md"
    "instructions/generated/localapi-shogun.md"
    "instructions/generated/localapi-karo.md"
    "instructions/generated/localapi-ashigaru.md"
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
