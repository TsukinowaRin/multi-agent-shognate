#!/usr/bin/env bash
# Multi Agents Shogunate CUI configurator
# - topology.active_ashigaru
# - cli.default / cli.agents
# - multiplexer.default / startup.template
# - gunshi / Codex reasoning / Gemini thinking

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

read_current_agent_field() {
  local agent_id="$1"
  local field="$2"
  local fallback="$3"
  python3 - "$SETTINGS_PATH" "$agent_id" "$field" "$fallback" <<'PY'
import sys, yaml
path, agent_id, field, fallback = sys.argv[1:5]
try:
    with open(path, encoding='utf-8') as fh:
        cfg = yaml.safe_load(fh) or {}
    cli = cfg.get('cli') or {}
    agents = cli.get('agents') or {}
    agent_cfg = agents.get(agent_id)
    if isinstance(agent_cfg, dict):
        value = agent_cfg.get(field, fallback)
    elif field == 'type' and isinstance(agent_cfg, str):
        value = agent_cfg
    else:
        value = fallback
except Exception:
    value = fallback
print('' if value is None else value)
PY
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

default_reasoning_for_role() {
  local role="$1"
  if [[ "$role" == "shogun" ]]; then
    echo "none"
  else
    echo "auto"
  fi
}

default_gemini_level_for_role() {
  local role="$1"
  local model="$2"
  local normalized_model
  normalized_model="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  if [[ "$role" != "shogun" ]]; then
    echo "auto"
    return 0
  fi
  case "$normalized_model" in
    gemini-3-flash*) echo "minimal" ;;
    gemini-3-pro*|auto|default|"") echo "low" ;;
    *) echo "auto" ;;
  esac
}

default_gemini_budget_for_role() {
  local role="$1"
  local model="$2"
  local normalized_model
  normalized_model="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  if [[ "$role" != "shogun" ]]; then
    echo ""
    return 0
  fi
  case "$normalized_model" in
    gemini-2.5-flash*|gemini-2.5-flash-lite*) echo "0" ;;
    gemini-2.5-pro*) echo "-1" ;;
    *) echo "" ;;
  esac
}

prompt_codex_reasoning() {
  local role="$1"
  local default_effort="${2:-auto}"
  prompt_choice "${role} の Codex reasoning_effort を選択" "${default_effort:-auto}" "auto" "none" "low" "medium" "high"
}

prompt_gemini_thinking_level() {
  local role="$1"
  local model="$2"
  local default_level="${3:-auto}"
  local normalized_model
  normalized_model="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_model" == gemini-2.5* ]]; then
    echo ""
    return 0
  fi
  if [[ "$normalized_model" == gemini-3-flash* ]]; then
    prompt_choice "${role} の Gemini thinking_level を選択" "${default_level:-auto}" "auto" "minimal" "low" "medium" "high"
    return 0
  fi
  prompt_choice "${role} の Gemini thinking_level を選択" "${default_level:-auto}" "auto" "low" "high" "minimal" "medium"
}

prompt_gemini_thinking_budget() {
  local role="$1"
  local model="$2"
  local default_budget="${3:-}"
  local normalized_model
  normalized_model="$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_model" != gemini-2.5* ]]; then
    echo ""
    return 0
  fi
  local input
  echo "" >&2
  echo "${role} の Gemini thinking_budget を入力してください（空なら自動 / -1=dynamic / 0=思考最小 / 正数=明示予算）" >&2
  if [[ -n "$default_budget" ]]; then
    echo "  default: ${default_budget}" >&2
  fi
  read -r -p "> " input >&2
  echo "${input:-$default_budget}"
}

capture_agent_config() {
  local role="$1"
  local cli_fallback="$2"
  local type model reasoning level budget

  type="$(prompt_choice "${role} の CLI を選択" "$(read_current_agent_field "$role" "type" "$cli_fallback")" "codex" "gemini" "claude" "localapi" "kimi" "copilot")"
  model="$(prompt_model "$role" "$type" "$(read_current_agent_field "$role" "model" "$(default_model_for_cli "$type")")")"
  reasoning=""
  level=""
  budget=""

  case "$type" in
    codex)
      reasoning="$(prompt_codex_reasoning "$role" "$(read_current_agent_field "$role" "reasoning_effort" "$(default_reasoning_for_role "$role")")")"
      ;;
    gemini)
      level="$(prompt_gemini_thinking_level "$role" "$model" "$(read_current_agent_field "$role" "thinking_level" "$(default_gemini_level_for_role "$role" "$model")")")"
      budget="$(prompt_gemini_thinking_budget "$role" "$model" "$(read_current_agent_field "$role" "thinking_budget" "$(default_gemini_budget_for_role "$role" "$model")")")"
      ;;
  esac

  printf '%s\t%s\t%s\t%s\t%s\n' "$type" "$model" "$reasoning" "$level" "$budget"
}

emit_agent_yaml() {
  local role="$1"
  local type="$2"
  local model="$3"
  local reasoning="$4"
  local level="$5"
  local budget="$6"

  echo "    ${role}:"
  echo "      type: ${type}"
  if [[ -n "$model" ]]; then
    echo "      model: ${model}"
  fi
  if [[ -n "$reasoning" && "$reasoning" != "auto" ]]; then
    echo "      reasoning_effort: ${reasoning}"
  fi
  if [[ -n "$level" && "$level" != "auto" ]]; then
    echo "      thinking_level: ${level}"
  fi
  if [[ -n "$budget" ]]; then
    echo "      thinking_budget: ${budget}"
  fi
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

IFS=$'\t' read -r SHOGUN_CLI SHOGUN_MODEL SHOGUN_REASONING SHOGUN_GEMINI_LEVEL SHOGUN_GEMINI_BUDGET <<< "$(capture_agent_config "shogun" "$cli_default")"
IFS=$'\t' read -r GUNSHI_CLI GUNSHI_MODEL GUNSHI_REASONING GUNSHI_GEMINI_LEVEL GUNSHI_GEMINI_BUDGET <<< "$(capture_agent_config "gunshi" "$cli_default")"
IFS=$'\t' read -r KARO_CLI KARO_MODEL KARO_REASONING KARO_GEMINI_LEVEL KARO_GEMINI_BUDGET <<< "$(capture_agent_config "karo" "$cli_default")"

declare -a ASHI_CLI ASHI_MODEL ASHI_REASONING ASHI_GEMINI_LEVEL ASHI_GEMINI_BUDGET
for ((i=1; i<=ashigaru_count; i++)); do
  role="ashigaru${i}"
  IFS=$'\t' read -r ASHI_CLI[$i] ASHI_MODEL[$i] ASHI_REASONING[$i] ASHI_GEMINI_LEVEL[$i] ASHI_GEMINI_BUDGET[$i] <<< "$(capture_agent_config "$role" "$cli_default")"
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
  emit_agent_yaml "shogun" "$SHOGUN_CLI" "$SHOGUN_MODEL" "$SHOGUN_REASONING" "$SHOGUN_GEMINI_LEVEL" "$SHOGUN_GEMINI_BUDGET"
  emit_agent_yaml "gunshi" "$GUNSHI_CLI" "$GUNSHI_MODEL" "$GUNSHI_REASONING" "$GUNSHI_GEMINI_LEVEL" "$GUNSHI_GEMINI_BUDGET"
  emit_agent_yaml "karo" "$KARO_CLI" "$KARO_MODEL" "$KARO_REASONING" "$KARO_GEMINI_LEVEL" "$KARO_GEMINI_BUDGET"
  for ((i=1; i<=ashigaru_count; i++)); do
    emit_agent_yaml "ashigaru${i}" "${ASHI_CLI[$i]}" "${ASHI_MODEL[$i]}" "${ASHI_REASONING[$i]}" "${ASHI_GEMINI_LEVEL[$i]}" "${ASHI_GEMINI_BUDGET[$i]}"
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
