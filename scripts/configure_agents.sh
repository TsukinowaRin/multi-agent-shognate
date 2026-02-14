#!/usr/bin/env bash
# Multi Agents Shogunate CUI configurator
# - topology.active_ashigaru
# - cli.default / cli.agents
# - multiplexer.default / startup.template

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SETTINGS_PATH="$ROOT_DIR/config/settings.yaml"
TMP_PATH="$ROOT_DIR/config/settings.yaml.tmp"
OWNER_MAP_PATH="$ROOT_DIR/queue/runtime/ashigaru_owner.tsv"

TOPOLOGY_ADAPTER_LOADED=false
if [[ -f "$ROOT_DIR/lib/topology_adapter.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/topology_adapter.sh"
  TOPOLOGY_ADAPTER_LOADED=true
fi

read_current_value() {
  local key="$1"
  local fallback="$2"
  local v
  v="$(awk -F': ' -v k="$key" '$1==k{print $2; exit}' "$SETTINGS_PATH" 2>/dev/null | tr -d '"' || true)"
  if [[ -n "$v" ]]; then
    echo "$v"
  else
    echo "$fallback"
  fi
}

read_current_multiplexer() {
  local v
  v="$(awk '
    $0 ~ /^multiplexer:[[:space:]]*$/ {in_mux=1; next}
    in_mux && $0 ~ /^[^[:space:]]/ {in_mux=0}
    in_mux && $0 ~ /^[[:space:]]*default:[[:space:]]*/ {
      sub(/^[[:space:]]*default:[[:space:]]*/, "", $0); gsub(/"/, "", $0); print $0; exit
    }
  ' "$SETTINGS_PATH" 2>/dev/null || true)"
  echo "${v:-zellij}"
}

read_current_template() {
  local v
  v="$(awk '
    $0 ~ /^startup:[[:space:]]*$/ {in_s=1; next}
    in_s && $0 ~ /^[^[:space:]]/ {in_s=0}
    in_s && $0 ~ /^[[:space:]]*template:[[:space:]]*/ {
      sub(/^[[:space:]]*template:[[:space:]]*/, "", $0); gsub(/"/, "", $0); print $0; exit
    }
  ' "$SETTINGS_PATH" 2>/dev/null || true)"
  echo "${v:-goza_room}"
}

read_current_ashigaru_count() {
  local c
  c="$(awk '
    $0 ~ /^topology:[[:space:]]*$/ {in_t=1; next}
    in_t && $0 ~ /^[^[:space:]]/ {in_t=0}
    in_t && $0 ~ /^[[:space:]]*-[[:space:]]*ashigaru[1-9][0-9]*[[:space:]]*$/ {n++}
    END {print n+0}
  ' "$SETTINGS_PATH" 2>/dev/null || true)"
  if [[ "${c:-0}" -lt 1 ]]; then
    echo "1"
  else
    echo "$c"
  fi
}

prompt_choice() {
  local prompt="$1"
  local default="$2"
  shift 2
  local options=("$@")
  local input
  while true; do
    echo "" >&2
    echo "$prompt" >&2
    local idx=1
    local opt
    for opt in "${options[@]}"; do
      if [[ "$opt" == "$default" ]]; then
        echo "  $idx) $opt [default]" >&2
      else
        echo "  $idx) $opt" >&2
      fi
      idx=$((idx + 1))
    done
    read -r -p "> " input >&2
    if [[ -z "$input" ]]; then
      echo "$default"
      return 0
    fi
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 ]] && [[ "$input" -le "${#options[@]}" ]]; then
      echo "${options[$((input - 1))]}"
      return 0
    fi
    for opt in "${options[@]}"; do
      if [[ "$input" == "$opt" ]]; then
        echo "$opt"
        return 0
      fi
    done
    echo "入力エラー: 値を選択してください。" >&2
  done
}

prompt_model() {
  local role="$1"
  local cli="$2"
  local default_model="$3"
  local input
  echo "" >&2
  echo "${role} の model を入力してください（空なら自動）" >&2
  echo "  cli: ${cli}" >&2
  if [[ -n "$default_model" ]]; then
    echo "  default: ${default_model}" >&2
  fi
  read -r -p "> " input >&2
  if [[ -z "$input" ]]; then
    echo "$default_model"
  else
    echo "$input"
  fi
}

default_model_for_cli() {
  local cli="$1"
  case "$cli" in
    gemini) echo "auto" ;;
    kimi) echo "k2.5" ;;
    localapi) echo "local-model" ;;
    *) echo "" ;;
  esac
}

default_language="$(read_current_value "language" "ja")"
default_shell="$(read_current_value "shell" "bash")"
default_mux="$(read_current_multiplexer)"
default_template="$(read_current_template)"
default_cli="$(awk '
  $0 ~ /^cli:[[:space:]]*$/ {in_cli=1; next}
  in_cli && $0 ~ /^[^[:space:]]/ {in_cli=0}
  in_cli && $0 ~ /^[[:space:]]*default:[[:space:]]*/ {
    sub(/^[[:space:]]*default:[[:space:]]*/, "", $0); gsub(/"/, "", $0); print $0; exit
  }
' "$SETTINGS_PATH" 2>/dev/null || true)"
default_cli="${default_cli:-codex}"
default_count="$(read_current_ashigaru_count)"

echo "=== Multi Agents Shogunate 設定 CUI ===" >&2
echo "設定ファイル: $SETTINGS_PATH" >&2

mux="$(prompt_choice "multiplexer.default を選択" "$default_mux" "zellij" "tmux")"
template="$(prompt_choice "startup.template を選択" "$default_template" "shogun_only" "goza_room")"
cli_default="$(prompt_choice "cli.default を選択" "$default_cli" "codex" "gemini" "claude" "localapi" "kimi" "copilot")"

echo "" >&2
read -r -p "足軽人数を入力 (1以上) [default: $default_count]: " count_input
ashigaru_count="${count_input:-$default_count}"
if ! [[ "$ashigaru_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "入力エラー: 足軽人数は 1以上の整数で指定してください。" >&2
  exit 1
fi

shogun_cli="$(prompt_choice "shogun の CLI を選択" "$cli_default" "codex" "gemini" "claude" "localapi" "kimi" "copilot")"
shogun_model="$(prompt_model "shogun" "$shogun_cli" "$(default_model_for_cli "$shogun_cli")")"
karo_cli="$(prompt_choice "karo の CLI を選択" "$cli_default" "codex" "gemini" "claude" "localapi" "kimi" "copilot")"
karo_model="$(prompt_model "karo" "$karo_cli" "$(default_model_for_cli "$karo_cli")")"

declare -a ASHI_CLI
declare -a ASHI_MODEL
for ((i=1; i<=ashigaru_count; i++)); do
  role="ashigaru${i}"
  ASHI_CLI[$i]="$(prompt_choice "${role} の CLI を選択" "$cli_default" "codex" "gemini" "claude" "localapi" "kimi" "copilot")"
  ASHI_MODEL[$i]="$(prompt_model "${role}" "${ASHI_CLI[$i]}" "$(default_model_for_cli "${ASHI_CLI[$i]}")")"
done

{
  echo "language: $default_language"
  echo "shell: $default_shell"
  echo "multiplexer:"
  echo "  default: $mux"
  echo "startup:"
  echo "  template: $template"
  echo "topology:"
  echo "  active_ashigaru:"
  for ((i=1; i<=ashigaru_count; i++)); do
    echo "    - ashigaru${i}"
  done
  echo "cli:"
  echo "  default: $cli_default"
  echo "  agents:"
  echo "    shogun:"
  echo "      type: $shogun_cli"
  if [[ -n "$shogun_model" ]]; then
    echo "      model: $shogun_model"
  fi
  echo "    karo:"
  echo "      type: $karo_cli"
  if [[ -n "$karo_model" ]]; then
    echo "      model: $karo_model"
  fi
  for ((i=1; i<=ashigaru_count; i++)); do
    echo "    ashigaru${i}:"
    echo "      type: ${ASHI_CLI[$i]}"
    if [[ -n "${ASHI_MODEL[$i]}" ]]; then
      echo "      model: ${ASHI_MODEL[$i]}"
    fi
  done
  echo "  commands:"
  echo "    gemini: \"gemini --yolo\""
  echo "    localapi: \"python3 scripts/localapi_repl.py\""
} > "$TMP_PATH"

mv "$TMP_PATH" "$SETTINGS_PATH"
echo ""
echo "設定を更新しました: $SETTINGS_PATH"

if [[ "$TOPOLOGY_ADAPTER_LOADED" == true ]]; then
  mkdir -p "$ROOT_DIR/queue/runtime"
  declare -a PREVIEW_ASHIGARU=()
  for ((i=1; i<=ashigaru_count; i++)); do
    PREVIEW_ASHIGARU+=("ashigaru${i}")
  done
  build_even_ownership_map "$OWNER_MAP_PATH" "${PREVIEW_ASHIGARU[@]}"
  echo ""
  echo "割り振り確認（起動時固定 / round-robin）:"
  while IFS=$'\t' read -r karo_id karo_count; do
    if [[ -n "$karo_id" && -n "$karo_count" ]]; then
      echo "  - ${karo_id}: ${karo_count} 名"
    fi
  done < <(topology_print_owner_summary "$OWNER_MAP_PATH")
fi

echo "次の確認:"
echo "  cat config/settings.yaml"
echo "  bash scripts/goza_zellij.sh -s --no-attach"
