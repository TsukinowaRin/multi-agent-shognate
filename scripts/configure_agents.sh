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
CONFIG_CAPTURE_DELIM=$'\x1f'

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

read_current_opencode_like_field() {
  local field="$1"
  local fallback="$2"
  python3 - "$SETTINGS_PATH" "$field" "$fallback" <<'PY'
import sys, yaml
path, field, fallback = sys.argv[1:4]
try:
    with open(path, encoding='utf-8') as fh:
        cfg = yaml.safe_load(fh) or {}
    cli = cfg.get('cli') or {}
    section = cli.get('opencode_like') or cfg.get('opencode_like') or {}
    value = section.get(field, fallback) if isinstance(section, dict) else fallback
except Exception:
    value = fallback
print('' if value is None else value)
PY
}

read_current_opencode_like_instructions() {
  python3 - "$SETTINGS_PATH" <<'PY'
import sys, yaml
path = sys.argv[1]
try:
    with open(path, encoding='utf-8') as fh:
        cfg = yaml.safe_load(fh) or {}
    cli = cfg.get('cli') or {}
    section = cli.get('opencode_like') or cfg.get('opencode_like') or {}
    items = section.get('instructions') if isinstance(section, dict) else []
except Exception:
    items = []
if isinstance(items, list):
    print(','.join(str(x) for x in items if isinstance(x, str) and x.strip()))
else:
    print('')
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

prompt_line() {
  local prompt="$1"
  local default_value="${2:-}"
  local example="${3:-}"
  local input
  echo "" >&2
  echo "$prompt" >&2
  if [[ -n "$default_value" ]]; then
    echo "  default: ${default_value}" >&2
  fi
  if [[ -n "$example" ]]; then
    echo "  例: ${example}" >&2
  fi
  read -r -p "> " input >&2
  echo "${input:-$default_value}"
}

prompt_optional_line() {
  local prompt="$1"
  local default_value="${2:-}"
  local example="${3:-}"
  local input
  echo "" >&2
  echo "$prompt" >&2
  if [[ -n "$default_value" ]]; then
    echo "  default: ${default_value}" >&2
  fi
  if [[ -n "$example" ]]; then
    echo "  例: ${example}" >&2
  fi
  echo "  空入力で未設定" >&2
  read -r -p "> " input >&2
  if [[ -z "$input" ]]; then
    echo "$default_value"
  else
    echo "$input"
  fi
}

prompt_model() {
  local role="$1"
  local cli="$2"
  local default_model="$3"
  local input
  echo "" >&2
  echo "${role} の model を入力してください（空なら自動）" >&2
  echo "  cli: ${cli}" >&2
  if [[ "$cli" == "opencode" || "$cli" == "kilo" ]]; then
    echo "  例: ollama/qwen3-coder:30b, lmstudio/codellama-7b.Q4_0.gguf, openai/gpt-4.1" >&2
  fi
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
    opencode|kilo) echo "auto" ;;
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

default_opencode_like_base_url() {
  local provider="$1"
  case "$provider" in
    ollama) echo "http://127.0.0.1:11434/v1" ;;
    lmstudio|openai-compatible) echo "http://127.0.0.1:1234/v1" ;;
    *) echo "" ;;
  esac
}

default_opencode_like_api_key_env() {
  local provider="$1"
  case "$provider" in
    openai-compatible) echo "LOCALAI_API_KEY" ;;
    *) echo "" ;;
  esac
}

normalize_opencode_provider_choice() {
  local value="$1"
  case "$value" in
    ollama|lmstudio|openai-compatible) echo "$value" ;;
    custom) echo "custom" ;;
    *) echo "$value" ;;
  esac
}

uses_opencode_like_cli() {
  local cli_type="$1"
  [[ "$cli_type" == "opencode" || "$cli_type" == "kilo" ]]
}

emit_opencode_like_yaml() {
  local provider="$1"
  local base_url="$2"
  local api_key_env="$3"
  local instructions_csv="$4"
  local item

  if [[ -z "$provider" && -z "$base_url" && -z "$api_key_env" && -z "$instructions_csv" ]]; then
    return 0
  fi

  echo "  opencode_like:"
  if [[ -n "$provider" ]]; then
    echo "    provider: ${provider}"
  fi
  if [[ -n "$base_url" ]]; then
    echo "    base_url: ${base_url}"
  fi
  if [[ -n "$api_key_env" ]]; then
    echo "    api_key_env: ${api_key_env}"
  fi
  if [[ -n "$instructions_csv" ]]; then
    echo "    instructions:"
    IFS=',' read -r -a _opencode_instruction_items <<< "$instructions_csv"
    for item in "${_opencode_instruction_items[@]}"; do
      item="${item#"${item%%[![:space:]]*}"}"
      item="${item%"${item##*[![:space:]]}"}"
      if [[ -n "$item" ]]; then
        echo "      - ${item}"
      fi
    done
  fi
}

capture_agent_config() {
  local role="$1"
  local cli_fallback="$2"
  local type model reasoning level budget

  type="$(prompt_choice "${role} の CLI を選択" "$(read_current_agent_field "$role" "type" "$cli_fallback")" "codex" "gemini" "claude" "localapi" "opencode" "kilo" "kimi" "copilot")"
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

  printf '%s%s%s%s%s%s%s%s%s\n' \
    "$type" "$CONFIG_CAPTURE_DELIM" \
    "$model" "$CONFIG_CAPTURE_DELIM" \
    "$reasoning" "$CONFIG_CAPTURE_DELIM" \
    "$level" "$CONFIG_CAPTURE_DELIM" \
    "$budget"
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
cli_default="$(prompt_choice "cli.default を選択" "$default_cli" "codex" "gemini" "claude" "localapi" "opencode" "kilo" "kimi" "copilot")"

echo "" >&2
read -r -p "足軽人数を入力 (1以上) [default: $default_count]: " count_input
ashigaru_count="${count_input:-$default_count}"
if ! [[ "$ashigaru_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "入力エラー: 足軽人数は 1以上の整数で指定してください。" >&2
  exit 1
fi

IFS="$CONFIG_CAPTURE_DELIM" read -r SHOGUN_CLI SHOGUN_MODEL SHOGUN_REASONING SHOGUN_GEMINI_LEVEL SHOGUN_GEMINI_BUDGET <<< "$(capture_agent_config "shogun" "$cli_default")"
IFS="$CONFIG_CAPTURE_DELIM" read -r GUNSHI_CLI GUNSHI_MODEL GUNSHI_REASONING GUNSHI_GEMINI_LEVEL GUNSHI_GEMINI_BUDGET <<< "$(capture_agent_config "gunshi" "$cli_default")"
IFS="$CONFIG_CAPTURE_DELIM" read -r KARO_CLI KARO_MODEL KARO_REASONING KARO_GEMINI_LEVEL KARO_GEMINI_BUDGET <<< "$(capture_agent_config "karo" "$cli_default")"

declare -a ASHI_CLI ASHI_MODEL ASHI_REASONING ASHI_GEMINI_LEVEL ASHI_GEMINI_BUDGET
for ((i=1; i<=ashigaru_count; i++)); do
  role="ashigaru${i}"
  IFS="$CONFIG_CAPTURE_DELIM" read -r ASHI_CLI[$i] ASHI_MODEL[$i] ASHI_REASONING[$i] ASHI_GEMINI_LEVEL[$i] ASHI_GEMINI_BUDGET[$i] <<< "$(capture_agent_config "$role" "$cli_default")"
done

USES_OPENCODE_LIKE=false
if uses_opencode_like_cli "$cli_default" || \
   uses_opencode_like_cli "$SHOGUN_CLI" || \
   uses_opencode_like_cli "$GUNSHI_CLI" || \
   uses_opencode_like_cli "$KARO_CLI"; then
  USES_OPENCODE_LIKE=true
fi
if [[ "$USES_OPENCODE_LIKE" == false ]]; then
  for ((i=1; i<=ashigaru_count; i++)); do
    if uses_opencode_like_cli "${ASHI_CLI[$i]}"; then
      USES_OPENCODE_LIKE=true
      break
    fi
  done
fi

CURRENT_OPENCODE_PROVIDER="$(read_current_opencode_like_field "provider" "")"
CURRENT_OPENCODE_BASE_URL="$(read_current_opencode_like_field "base_url" "")"
CURRENT_OPENCODE_API_KEY_ENV="$(read_current_opencode_like_field "api_key_env" "")"
CURRENT_OPENCODE_INSTRUCTIONS="$(read_current_opencode_like_instructions)"

ENABLE_OPENCODE_PROVIDER_CONFIG="no"
OPENCODE_PROVIDER=""
OPENCODE_BASE_URL=""
OPENCODE_API_KEY_ENV=""
OPENCODE_INSTRUCTIONS=""

if [[ "$USES_OPENCODE_LIKE" == true || -n "$CURRENT_OPENCODE_PROVIDER$CURRENT_OPENCODE_BASE_URL$CURRENT_OPENCODE_API_KEY_ENV$CURRENT_OPENCODE_INSTRUCTIONS" ]]; then
  ENABLE_OPENCODE_PROVIDER_CONFIG="$(prompt_choice "OpenCode/Kilo の project provider 設定を保存するか" "$( [[ -n "$CURRENT_OPENCODE_PROVIDER$CURRENT_OPENCODE_BASE_URL$CURRENT_OPENCODE_API_KEY_ENV$CURRENT_OPENCODE_INSTRUCTIONS" ]] && echo yes || echo no )" "yes" "no")"
  if [[ "$ENABLE_OPENCODE_PROVIDER_CONFIG" == "yes" ]]; then
    provider_default="$(normalize_opencode_provider_choice "${CURRENT_OPENCODE_PROVIDER:-openai-compatible}")"
    case "$provider_default" in
      ollama|lmstudio|openai-compatible|custom) ;;
      *) provider_default="custom" ;;
    esac
    provider_choice="$(prompt_choice "provider を選択" "$provider_default" "ollama" "lmstudio" "openai-compatible" "custom")"
    if [[ "$provider_choice" == "custom" ]]; then
      OPENCODE_PROVIDER="$(prompt_line "custom provider ID を入力してください" "${CURRENT_OPENCODE_PROVIDER:-}" "my-provider")"
    else
      OPENCODE_PROVIDER="$provider_choice"
    fi
    OPENCODE_BASE_URL="$(prompt_optional_line "base_url を入力してください（空で provider 既定値）" "${CURRENT_OPENCODE_BASE_URL:-$(default_opencode_like_base_url "$OPENCODE_PROVIDER")}" "http://127.0.0.1:11434/v1")"
    OPENCODE_API_KEY_ENV="$(prompt_optional_line "api_key_env を入力してください（不要なら空）" "${CURRENT_OPENCODE_API_KEY_ENV:-$(default_opencode_like_api_key_env "$OPENCODE_PROVIDER")}" "LOCALAI_API_KEY")"
    OPENCODE_INSTRUCTIONS="$(prompt_optional_line "追加 instructions をカンマ区切りで入力してください（空で省略）" "${CURRENT_OPENCODE_INSTRUCTIONS:-AGENTS.md}" "AGENTS.md,instructions/shogun.md")"
  fi
fi

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
  echo "    opencode: \"opencode\""
  echo "    kilo: \"kilo\""
  emit_opencode_like_yaml "$OPENCODE_PROVIDER" "$OPENCODE_BASE_URL" "$OPENCODE_API_KEY_ENV" "$OPENCODE_INSTRUCTIONS"
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
