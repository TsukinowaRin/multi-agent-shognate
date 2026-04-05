#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_RC="${1:-$HOME/.bashrc}"
BEGIN_MARK="# >>> multi-agent-shognate aliases >>>"
END_MARK="# <<< multi-agent-shognate aliases <<<"
SOURCE_LINE="source \"$ROOT_DIR/scripts/shell_aliases.sh\""

mkdir -p "$(dirname "$TARGET_RC")"
touch "$TARGET_RC"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  $0 == begin { skip = 1; next }
  $0 == end { skip = 0; next }
  $0 ~ /^alias (cgo|css|csg|csm|csst)=/ { next }
  !skip { print }
' "$TARGET_RC" > "$tmp_file"

{
  cat "$tmp_file"
  printf '\n%s\n%s\n%s\n' "$BEGIN_MARK" "$SOURCE_LINE" "$END_MARK"
} > "$TARGET_RC"

echo "[INFO] shell alias を更新しました: $TARGET_RC"
echo "[INFO] 現在のシェルへ即時反映するには次を実行してください:"
echo "       source \"$ROOT_DIR/scripts/shell_aliases.sh\""
