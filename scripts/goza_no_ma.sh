#!/usr/bin/env bash
# WSL再起動後のワンコマンド起動 + 分割ビュー
# - バックエンド: tmux または zellij
# - 表示: tmux または zellij（zellij UI + tmux backend も対応）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIEW_SESSION="${VIEW_SESSION:-goza-no-ma}"
TMUX_VIEW_WIDTH="${TMUX_VIEW_WIDTH:-200}"
TMUX_VIEW_HEIGHT="${TMUX_VIEW_HEIGHT:-60}"
SETUP_ONLY=false
VIEW_ONLY=false
NO_ATTACH=false
MUX_MODE="${MUX_MODE:-zellij}"
UI_MODE="${UI_MODE:-}"
VIEW_TEMPLATE="${VIEW_TEMPLATE:-}"
PASS_THROUGH=()
CLI_ADAPTER_LOADED=false
INBOX_PATH_HELPER_LOADED=false
TOPOLOGY_ADAPTER_LOADED=false

usage() {
  cat << 'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   バックエンドは setup-only で起動（CLI未起動）
  --view-only        バックエンド起動をスキップし、ビューのみ起動
  --no-attach        tmuxへattachせず、ビュー作成だけ行う（検証向け）
  --mux MODE         バックエンド起動モード（zellij|tmux, default: zellij）
  --ui MODE          表示モード（zellij|tmux, default: muxと同じ）
  --template NAME    表示テンプレート（shogun_only|goza_room, default: settings）
  --session NAME     tmux ビューセッション名（default: goza-no-ma）
  -h, --help         このヘルプ

Examples:
  bash scripts/goza_no_ma.sh --mux zellij
  bash scripts/goza_no_ma.sh --mux tmux
  bash scripts/goza_no_ma.sh --mux tmux --ui zellij
  bash scripts/goza_no_ma.sh --template shogun_only
  bash scripts/goza_no_ma.sh --template goza_room
  bash scripts/goza_no_ma.sh -s --mux zellij
  bash scripts/goza_no_ma.sh -- --shogun-no-thinking
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only)
      SETUP_ONLY=true
      shift
      ;;
    --view-only)
      VIEW_ONLY=true
      shift
      ;;
    --no-attach)
      NO_ATTACH=true
      shift
      ;;
    --mux)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        MUX_MODE="$2"
        shift 2
      else
        echo "[ERROR] --mux には zellij または tmux を指定してください" >&2
        exit 1
      fi
      ;;
    --ui)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        UI_MODE="$2"
        shift 2
      else
        echo "[ERROR] --ui には zellij または tmux を指定してください" >&2
        exit 1
      fi
      ;;
    --template)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        VIEW_TEMPLATE="$2"
        shift 2
      else
        echo "[ERROR] --template には shogun_only または goza_room を指定してください" >&2
        exit 1
      fi
      ;;
    --session)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        VIEW_SESSION="$2"
        shift 2
      else
        echo "[ERROR] --session には名前を指定してください" >&2
        exit 1
      fi
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        PASS_THROUGH+=("$1")
        shift
      done
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      PASS_THROUGH+=("$1")
      shift
      ;;
  esac
done

if [ -f "$ROOT_DIR/lib/cli_adapter.sh" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/cli_adapter.sh" || true
  CLI_ADAPTER_LOADED=true
fi
if [ -f "$ROOT_DIR/lib/inbox_path.sh" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/inbox_path.sh" || true
  INBOX_PATH_HELPER_LOADED=true
fi
if [ -f "$ROOT_DIR/lib/topology_adapter.sh" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/topology_adapter.sh" || true
  TOPOLOGY_ADAPTER_LOADED=true
fi

sync_gemini_workspace_settings() {
  local sync_script="$ROOT_DIR/scripts/sync_gemini_settings.py"
  if [[ ! -x "$sync_script" ]]; then
    return 0
  fi
  if ! python3 "$sync_script" >/dev/null 2>&1; then
    echo "[WARN] Gemini workspace settings の同期に失敗しました。既存 .gemini/settings.json を使用して継続します" >&2
  fi
}

sync_opencode_like_workspace_settings() {
  local sync_script="$ROOT_DIR/scripts/sync_opencode_config.py"
  if [[ ! -x "$sync_script" ]]; then
    return 0
  fi
  if ! python3 "$sync_script" >/dev/null 2>&1; then
    echo "[WARN] OpenCode/Kilo project config の同期に失敗しました。既存 opencode.json を使用して継続します" >&2
  fi
}

sync_gemini_workspace_settings
sync_opencode_like_workspace_settings

if [[ "$MUX_MODE" != "zellij" && "$MUX_MODE" != "tmux" ]]; then
  echo "[ERROR] --mux は zellij または tmux を指定してください（指定値: $MUX_MODE）" >&2
  exit 1
fi

if [[ -z "$UI_MODE" ]]; then
  UI_MODE="$MUX_MODE"
fi
if [[ "$UI_MODE" != "zellij" && "$UI_MODE" != "tmux" ]]; then
  echo "[ERROR] --ui は zellij または tmux を指定してください（指定値: $UI_MODE）" >&2
  exit 1
fi

if [[ -z "$VIEW_TEMPLATE" ]]; then
  VIEW_TEMPLATE="$(python3 - "$MUX_MODE" << 'PY'
import sys
from pathlib import Path

mux = sys.argv[1]
template = ""

try:
    import yaml  # type: ignore
except Exception:
    yaml = None

if yaml:
    sp = Path("config/settings.yaml")
    if sp.exists():
        cfg = yaml.safe_load(sp.read_text(encoding="utf-8")) or {}
        template = str(((cfg.get("startup") or {}).get("template") or "")).strip()

    if not template:
        tp = Path(f"templates/multiplexer/{mux}_templates.yaml")
        if tp.exists():
            tcfg = yaml.safe_load(tp.read_text(encoding="utf-8")) or {}
            template = str((tcfg.get("default") or "")).strip()

if not template:
    template = "shogun_only"

print(template)
PY
)"
fi

if [[ "$VIEW_TEMPLATE" != "shogun_only" && "$VIEW_TEMPLATE" != "goza_room" ]]; then
  echo "[ERROR] --template は shogun_only または goza_room を指定してください（指定値: $VIEW_TEMPLATE）" >&2
  exit 1
fi

PURE_ZELLIJ_REQUESTED=0
if [[ "$MUX_MODE" == "zellij" && "$UI_MODE" == "zellij" && "$VIEW_TEMPLATE" == "goza_room" ]]; then
  PURE_ZELLIJ_REQUESTED=1
fi

if [[ "$PURE_ZELLIJ_REQUESTED" -eq 1 && "${MAS_ENABLE_PURE_ZELLIJ:-0}" != "1" ]]; then
  echo "[INFO] pure zellij goza_room は experimental のため、既定では zellij UI + tmux backend へフォールバックします。"
  MUX_MODE="tmux"
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。ビュー作成に tmux が必要です。" >&2
  exit 1
fi
if [[ "$MUX_MODE" == "zellij" || "$UI_MODE" == "zellij" ]] && ! command -v zellij >/dev/null 2>&1; then
  echo "[ERROR] zellij が見つかりません。zellij backend/UI では zellij が必要です。" >&2
  exit 1
fi

PURE_ZELLIJ_GOZA=0
if [[ "$MUX_MODE" == "zellij" && "$UI_MODE" == "zellij" && "$VIEW_TEMPLATE" == "goza_room" ]]; then
  PURE_ZELLIJ_GOZA=1
fi

if [[ "$VIEW_ONLY" != true ]]; then
  if [[ "$PURE_ZELLIJ_GOZA" -eq 1 ]]; then
    mkdir -p "$ROOT_DIR/queue/reports" "$ROOT_DIR/queue/tasks" "$ROOT_DIR/logs" "$ROOT_DIR/queue/runtime"
    if [[ "$INBOX_PATH_HELPER_LOADED" == "true" ]] && declare -F ensure_local_inbox_dir >/dev/null 2>&1; then
      ensure_local_inbox_dir "$ROOT_DIR/queue/inbox"
    else
      mkdir -p "$ROOT_DIR/queue/inbox"
    fi
  else
    START_ARGS=("${PASS_THROUGH[@]}")
    if [[ "$SETUP_ONLY" = true ]]; then
      START_ARGS=("-s" "${START_ARGS[@]}")
    fi
    # shutsujin_departure.sh は set -e で途中終了する場合があるが、
    # tmuxセッション自体は作成済みのため、ビュー作成・attachは続行する。
    set +e
    MAS_MULTIPLEXER="$MUX_MODE" MAS_CLI_READY_TIMEOUT="${MAS_CLI_READY_TIMEOUT:-12}" \
      bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
    _shutsujin_rc=$?
    set -e
    if [[ "$_shutsujin_rc" -ne 0 ]]; then
      echo "[WARN] shutsujin_departure.sh exited with code $_shutsujin_rc (continuing to view setup)" >&2
    fi
  fi
fi

tmux_attach_session_cmd() {
  local session="$1"
  printf 'cd %q && TMUX= tmux attach-session -t %q || (echo %q; exec bash)' \
    "$ROOT_DIR" "$session" "[WARN] attach失敗: $session"
}

kdl_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/ }"
  printf '%s' "$value"
}

ZELLIJ_UI_SESSION="${ZELLIJ_UI_SESSION:-goza-no-ma-ui}"
GOZA_BOOTSTRAP_RUN_ID=""
GOZA_BOOTSTRAP_LOG=""

goza_bootstrap_log() {
  local message="$1"
  if [[ -z "${GOZA_BOOTSTRAP_LOG:-}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$GOZA_BOOTSTRAP_LOG")" 2>/dev/null || true
  printf "[%s] %s\n" "$(date -Iseconds)" "$message" >> "$GOZA_BOOTSTRAP_LOG"
}

goza_init_bootstrap_log() {
  if [[ -n "${GOZA_BOOTSTRAP_LOG:-}" ]]; then
    return 0
  fi
  GOZA_BOOTSTRAP_RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
  GOZA_BOOTSTRAP_LOG="$ROOT_DIR/queue/runtime/goza_bootstrap_${GOZA_BOOTSTRAP_RUN_ID}.log"
  mkdir -p "$(dirname "$GOZA_BOOTSTRAP_LOG")" 2>/dev/null || true
  goza_bootstrap_log "run start id=$GOZA_BOOTSTRAP_RUN_ID session=$ZELLIJ_UI_SESSION"
}

goza_agent_transcript_file() {
  local agent="$1"
  printf '%s' "$ROOT_DIR/queue/runtime/pure_zellij_${ZELLIJ_UI_SESSION}_${agent}.log"
}

goza_agent_bootstrap_file() {
  local agent="$1"
  printf '%s' "$ROOT_DIR/queue/runtime/pure_zellij_${ZELLIJ_UI_SESSION}_${agent}.bootstrap.txt"
}

prepare_pure_zellij_bootstrap_files() {
  local agents=("$@")
  local agent=""
  local cli_type=""
  local startup_msg=""
  local bootstrap_file=""

  mkdir -p "$ROOT_DIR/queue/runtime"
  for agent in "${agents[@]}"; do
    cli_type="$(zellij_resolve_cli_for_agent "$agent")"
    bootstrap_file="$(goza_agent_bootstrap_file "$agent")"
    startup_msg="$(goza_startup_bootstrap_message "$agent" "$cli_type" 2>/dev/null || true)"
    printf '%s\n' "$startup_msg" > "$bootstrap_file"
    goza_bootstrap_log "bootstrap prepared agent=$agent cli=$cli_type file=$(basename "$bootstrap_file")"
  done
}
zellij_ui_layout_file() {
  local tmux_target="$1"
  local tab_title="$2"
  local startup_cmd
  local startup_cmd_escaped
  local pane_name
  local pane_name_escaped
  local tab_title_escaped
  local layout_file="${TMPDIR:-/tmp}/zellij_ui_${ZELLIJ_UI_SESSION}.kdl"
  startup_cmd="$(tmux_attach_session_cmd "$tmux_target")"
  startup_cmd_escaped="$(kdl_escape "$startup_cmd")"
  pane_name="${tab_title}"
  pane_name_escaped="$(kdl_escape "$pane_name")"
  tab_title_escaped="$(kdl_escape "$tab_title")"
  cat > "$layout_file" <<EOF
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar";
        }
        children
        pane size=2 borderless=true {
            plugin location="zellij:status-bar";
        }
    }
    tab name="${tab_title_escaped}" {
        pane name="${pane_name_escaped}" command="bash" start_suspended=false {
            args "-lc" "${startup_cmd_escaped}";
        }
    }
}
EOF
  echo "$layout_file"
}

zellij_ui_attach_tmux_target() {
  local tmux_target="$1"
  local pane_title="$2"
  local layout_file

  if ! tmux has-session -t "$tmux_target" 2>/dev/null; then
    echo "[ERROR] tmux target session not found: $tmux_target" >&2
    return 1
  fi

  layout_file="$(zellij_ui_layout_file "$tmux_target" "$pane_title")"

  # 既存UIセッションは一旦削除して、毎回同じ構成で作り直す
  zellij delete-session "$ZELLIJ_UI_SESSION" --force >/dev/null 2>&1 || \
    zellij kill-session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || true

  if [[ "$NO_ATTACH" = true ]]; then
    # 非アタッチ時は従来どおり背景セッションだけ作成
    if zellij attach --create-background "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || \
       zellij attach --create-background --session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1; then
      echo "[INFO] zellij UI session created: $ZELLIJ_UI_SESSION"
      echo "       attach: zellij attach $ZELLIJ_UI_SESSION"
      return 0
    fi
    echo "[ERROR] zellij UI background session の作成に失敗しました: $ZELLIJ_UI_SESSION" >&2
    return 1
  fi

  # 0.41系では --new-session-with-layout が最も安定
  if zellij --new-session-with-layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  # 旧互換フォールバック
  if zellij --layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  if zellij --layout "$layout_file" attach -c "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  echo "[ERROR] zellij UI 起動に失敗しました（layout: $layout_file）" >&2
  return 1
}

zellij_agent_boot_cmd() {
  local agent="$1"
  local cli_type="codex"
  local cli_cmd="codex --search --dangerously-bypass-approvals-and-sandbox --no-alt-screen"
  local transcript_file=""
  local transcript_dir=""
  local cli_cmd_quoted=""

  if [[ "$CLI_ADAPTER_LOADED" == "true" ]]; then
    cli_type="$(resolve_cli_type_for_agent "$agent" 2>/dev/null || echo "codex")"
    cli_cmd="$(build_cli_command_with_type "$agent" "$cli_type" 2>/dev/null || echo "$cli_cmd")"
  fi

  if [[ "$SETUP_ONLY" == "true" ]]; then
    printf 'cd %q && export AGENT_ID=%q && export DISPLAY_MODE=%q && clear && exec bash' \
      "$ROOT_DIR" "$agent" "shout"
    return 0
  fi

  transcript_file="$(goza_agent_transcript_file "$agent")"
  transcript_dir="$(dirname "$transcript_file")"
  printf -v cli_cmd_quoted '%q' "$cli_cmd"

  # pure zellij: shell pane に launch command を送って CLI を起動し、
  # 初動命令は外側のブートストラップで明示送信する。
  # transcript を agent ごとに分け、ready/trust/high-demand の判定を他ペインと混線させない。
  printf 'cd %q && export AGENT_ID=%q && export DISPLAY_MODE=%q && mkdir -p %q && : > %q && clear && if command -v script >/dev/null 2>&1; then script -qefc %s %q; else eval %s; fi; echo %q; exec bash' \
    "$ROOT_DIR" "$agent" "shout" "$transcript_dir" "$transcript_file" "$cli_cmd_quoted" "$transcript_file" "$cli_cmd_quoted" "[INFO] ${agent} pane ended. Waiting at shell."
}

zellij_collect_active_agents() {
  if [[ "$TOPOLOGY_ADAPTER_LOADED" == "true" ]] && declare -F topology_load_active_ashigaru >/dev/null 2>&1; then
    local active_agents=()
    local karo_agents=()
    mapfile -t active_agents < <(topology_load_active_ashigaru 2>/dev/null || true)
    if [[ ${#active_agents[@]} -eq 0 ]]; then
      active_agents=("ashigaru1")
    fi
    mapfile -t karo_agents < <(topology_resolve_karo_agents "${active_agents[@]}" 2>/dev/null || true)
    if [[ ${#karo_agents[@]} -eq 0 ]]; then
      karo_agents=("karo")
    fi

    echo "shogun"
    echo "gunshi"
    printf '%s\n' "${karo_agents[@]}"
    printf '%s\n' "${active_agents[@]}"
    return 0
  fi

  python3 - << 'PY'
from pathlib import Path

try:
    import yaml
except Exception:
    print("shogun")
    print("gunshi")
    print("karo")
    print("ashigaru1")
    raise SystemExit(0)

cfg = {}
p = Path("config/settings.yaml")
if p.exists():
    cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}

active = (cfg.get("topology") or {}).get("active_ashigaru") or ["ashigaru1"]
normalized = []
seen = set()
for x in active:
    if isinstance(x, int):
        if x >= 1:
            name = f"ashigaru{x}"
            if name not in seen:
                normalized.append(name)
                seen.add(name)
        continue
    s = str(x).strip()
    if s.isdigit():
        i = int(s)
        if i >= 1:
            name = f"ashigaru{i}"
            if name not in seen:
                normalized.append(name)
                seen.add(name)
    elif s.startswith("ashigaru") and s[8:].isdigit() and int(s[8:]) >= 1:
        if s not in seen:
            normalized.append(s)
            seen.add(s)

if not normalized:
    normalized = ["ashigaru1"]

agents = ["shogun", "gunshi", "karo"] + normalized
for a in agents:
    print(a)
PY
}

GOZA_LANG_SETTING="$(
python3 - << 'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    print("ja")
    raise SystemExit(0)
p = Path("config/settings.yaml")
if not p.exists():
    print("ja")
    raise SystemExit(0)
cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
lang = str(cfg.get("language") or "ja").strip() or "ja"
print(lang)
PY
)"

goza_role_linkage_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "連携順序: 殿の指示を受けたら、必ず『将軍→家老→足軽』で委譲せよ。家老への委譲は queue/shogun_to_karo.yaml 更新 + inbox通知を使い、足軽へ直接命令してはならない。"
      ;;
    gunshi)
      echo "連携順序: 家老から queue/tasks/gunshi.yaml 経由でタスクを受領し、分析・戦略立案後に queue/reports/gunshi_report.yaml を作成、inbox通知で家老へ返せ。将軍・足軽へ直接命令しない。"
      ;;
    karo|karo[1-9]*|karo_gashira)
      echo "連携順序: 将軍命令を受けたら、家老がサブタスク分解し queue/tasks/ashigaruN.yaml へ割当、inboxで該当足軽を起動せよ。人間へ直接報告せず、dashboardと既定フローを守れ。"
      ;;
    ashigaru*)
      echo "連携順序: 足軽は自分の task YAML のみ処理し、完了後は queue/reports/${agent_id}_report.yaml + inbox通知で家老へ報告せよ。将軍・人間への直接連絡は禁止。"
      ;;
    *)
      echo "連携順序: 将軍→家老→足軽の指揮系統を順守せよ。"
      ;;
  esac
}

goza_language_directive() {
  if [[ "${GOZA_LANG_SETTING:-ja}" == "ja" ]]; then
    echo "言語規則: 以後の応答は日本語（戦国口調）で統一せよ。"
  else
    echo "Language rule: Follow system language '${GOZA_LANG_SETTING}' for all outputs (include all agent communication)."
  fi
}

goza_event_driven_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "イベント駆動規則: 家老へ委譲したら即ターンを閉じ、殿の次入力を待て。自分で実装作業に入るな。"
      ;;
    gunshi)
      echo "イベント駆動規則: ポーリング禁止。家老からのinboxイベント起点で分析・戦略立案を行い、報告後は待機へ戻れ。"
      ;;
    karo|karo[1-9]*|karo_gashira|ashigaru*)
      echo "イベント駆動規則: ポーリング禁止。inboxイベント起点でタスク処理し、未読処理後は待機へ戻れ。"
      ;;
    *)
      echo "イベント駆動規則: inboxイベント起点で処理し、完了後は待機へ戻れ。"
      ;;
  esac
}

goza_reporting_chain_directive() {
  local agent_id="$1"
  case "$agent_id" in
    shogun)
      echo "報告規則: 家老の報告を受けて殿へ要約報告せよ。家老の問題を検知したら即改善指示を返せ。"
      ;;
    gunshi)
      echo "報告規則: 分析完了後は queue/reports/gunshi_report.yaml に結果を書き、inbox通知で家老へ返せ。将軍・人間へ直接報告しない。"
      ;;
    karo|karo[1-9]*|karo_gashira)
      echo "報告規則: タスク完了時は将軍へ要約を返し、人間へ直接報告しない。"
      ;;
    ashigaru*)
      echo "報告規則: 完了報告は必ず家老へ返す。将軍・人間へ直接報告しない。"
      ;;
    *)
      echo "報告規則: 指揮系統（将軍→家老→足軽）を守って報告せよ。"
      ;;
  esac
}

goza_startup_bootstrap_message() {
  local agent_id="$1"
  local cli_type="$2"
  local role_instruction_file=""
  local optimized_instruction_file=""
  local linkage_rule=""
  local lang_rule=""
  local event_rule=""
  local report_rule=""

  if [[ "$CLI_ADAPTER_LOADED" == "true" ]]; then
    role_instruction_file="$(get_role_instruction_file "$agent_id" 2>/dev/null || true)"
    optimized_instruction_file="$(get_instruction_file "$agent_id" "$cli_type" 2>/dev/null || true)"
  fi

  if [[ -z "$role_instruction_file" ]]; then
    case "$agent_id" in
      shogun) role_instruction_file="instructions/shogun.md" ;;
      gunshi) role_instruction_file="instructions/gunshi.md" ;;
      karo|karo[1-9]*|karo_gashira) role_instruction_file="instructions/karo.md" ;;
      ashigaru*) role_instruction_file="instructions/ashigaru.md" ;;
      *) role_instruction_file="AGENTS.md" ;;
    esac
  fi
  if [[ -z "$optimized_instruction_file" || ! -f "$ROOT_DIR/$optimized_instruction_file" ]]; then
    optimized_instruction_file="$role_instruction_file"
  fi

  linkage_rule="$(goza_role_linkage_directive "$agent_id")"
  lang_rule="$(goza_language_directive)"
  event_rule="$(goza_event_driven_directive "$agent_id")"
  report_rule="$(goza_reporting_chain_directive "$agent_id")"

  if [[ "$cli_type" == "gemini" ]]; then
    if [[ "$optimized_instruction_file" != "$role_instruction_file" ]]; then
      printf "【初動命令】あなたは%s。まず ready:%s を1行で即時送信せよ。次にこの順で読む: @AGENTS.md @%s @%s。3ファイルの要点を3行で要約し、その後は未読inbox監視へ戻れ。%s %s %s %s" \
        "$agent_id" "$agent_id" "$role_instruction_file" "$optimized_instruction_file" \
        "$lang_rule" "$event_rule" "$linkage_rule" "$report_rule"
    else
      printf "【初動命令】あなたは%s。まず ready:%s を1行で即時送信せよ。次にこの順で読む: @AGENTS.md @%s。2ファイルの要点を3行で要約し、その後は未読inbox監視へ戻れ。%s %s %s %s" \
        "$agent_id" "$agent_id" "$role_instruction_file" \
        "$lang_rule" "$event_rule" "$linkage_rule" "$report_rule"
    fi
    return 0
  fi

  if [[ "$optimized_instruction_file" != "$role_instruction_file" ]]; then
    printf "【初動命令】あなたは%s。まず 'ready:%s' を1行で即時送信し、次に AGENTS.md と %s を読み、続けて %s を読んで %s 向け差分を適用せよ。%s %s %s %s 準備が整ったら未読inbox監視へ戻れ。" \
      "$agent_id" "$agent_id" "$role_instruction_file" "$optimized_instruction_file" "$cli_type" \
      "$lang_rule" "$event_rule" "$linkage_rule" "$report_rule"
  else
    printf "【初動命令】あなたは%s。まず 'ready:%s' を1行で即時送信し、次に AGENTS.md と %s を読み、役割・口調・禁止事項を適用せよ。%s %s %s %s 準備が整ったら未読inbox監視へ戻れ。" \
      "$agent_id" "$agent_id" "$role_instruction_file" \
      "$lang_rule" "$event_rule" "$linkage_rule" "$report_rule"
  fi
}

zellij_send_line_to_session() {
  local session="$1"
  local text="$2"

  zellij -s "$session" action write-chars "$text" >/dev/null 2>&1 || return 1
  sleep 0.1
  if zellij -s "$session" action write 13 >/dev/null 2>&1; then
    return 0
  fi
  sleep 0.1
  if zellij -s "$session" action write 10 >/dev/null 2>&1; then
    return 0
  fi
  sleep 0.1
  zellij -s "$session" action write-chars $'\n' >/dev/null 2>&1 || return 1
}

zellij_agent_output_matches() {
  local session="$1"
  local agent="$2"
  local pattern="$3"
  local transcript_file=""
  local tmp_dump=""

  transcript_file="$(goza_agent_transcript_file "$agent")"
  if [[ -f "$transcript_file" ]] && grep -qiE "$pattern" "$transcript_file" 2>/dev/null; then
    return 0
  fi

  tmp_dump="${TMPDIR:-/tmp}/goza_ready_${agent}_$$.txt"
  if zellij -s "$session" action dump-screen "$tmp_dump" >/dev/null 2>&1; then
    if grep -qiE "$pattern" "$tmp_dump" 2>/dev/null; then
      rm -f "$tmp_dump"
      return 0
    fi
  fi
  rm -f "$tmp_dump"
  return 1
}

zellij_wait_agent_output() {
  local session="$1"
  local agent="$2"
  local pattern="$3"
  local max_wait="${4:-12}"
  local i

  if ! [[ "$max_wait" =~ ^[0-9]+$ ]]; then
    max_wait=12
  fi

  for ((i=0; i<max_wait; i++)); do
    if zellij_agent_output_matches "$session" "$agent" "$pattern"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

zellij_wait_ready_ack_current_pane() {
  local session="$1"
  local agent="$2"
  local max_wait="${3:-12}"
  zellij_wait_agent_output "$session" "$agent" "ready:${agent}" "$max_wait"
}

zellij_resolve_cli_for_agent() {
  local agent="$1"
  if [[ "$CLI_ADAPTER_LOADED" == "true" ]]; then
    resolve_cli_type_for_agent "$agent" 2>/dev/null || echo "codex"
    return 0
  fi
  echo "codex"
}

zellij_pure_ready_pattern() {
  case "${1:-codex}" in
    claude) echo '(claude code|claude|for shortcuts|/model)' ;;
    codex) echo '(openai codex|codex|for shortcuts|context left|/model)' ;;
    gemini) echo '(type your message|yolo mode|/model|@path/to/file)' ;;
    copilot) echo '(copilot|github copilot|for shortcuts|/model)' ;;
    kimi) echo '(kimi|moonshot|for shortcuts|/model)' ;;
    localapi) echo '(localapi|ready:|api)' ;;
    *) echo '(claude|codex|gemini|copilot|kimi|localapi|ready:)' ;;
  esac
}

zellij_bootstrap_delay_for_cli() {
  case "${1:-codex}" in
    claude) echo 5 ;;
    gemini) echo 4 ;;
    codex) echo 3 ;;
    *) echo 3 ;;
  esac
}

zellij_handle_codex_preflight_current_pane() {
  local session="$1"
  local agent="$2"
  local max_wait="${3:-20}"
  local i

  if ! [[ "$max_wait" =~ ^[0-9]+$ ]]; then
    max_wait=20
  fi

  for ((i=0; i<max_wait; i++)); do
    if zellij_agent_output_matches "$session" "$agent" '(openai codex|for shortcuts|context left|/model)'; then
      return 0
    fi
    if zellij_agent_output_matches "$session" "$agent" '(update available|update now|skip until next version|press enter to continue)'; then
      if zellij_send_line_to_session "$session" "2"; then
        goza_bootstrap_log "codex update skipped agent=$agent via numeric-select"
      fi
      sleep 2
      if zellij_agent_output_matches "$session" "$agent" '(update available|update now|skip until next version|press enter to continue)'; then
        zellij -s "$session" action write-chars $'\e[B' >/dev/null 2>&1 || true
        sleep 0.1
        zellij -s "$session" action write 13 >/dev/null 2>&1 || true
        goza_bootstrap_log "codex update skipped agent=$agent via down-enter"
        sleep 2
      fi
      continue
    fi
    sleep 1
  done

  return 1
}

zellij_handle_gemini_preflight_current_pane() {
  local session="$1"
  local agent="$2"
  local max_wait="${3:-20}"
  local i

  if ! [[ "$max_wait" =~ ^[0-9]+$ ]]; then
    max_wait=20
  fi

  for ((i=0; i<max_wait; i++)); do
    if zellij_agent_output_matches "$session" "$agent" '(type your message|yolo mode|/model|@path/to/file)'; then
      return 0
    fi
    if zellij_agent_output_matches "$session" "$agent" '(trust this folder|trust parent folder|don.t trust)'; then
      if zellij_send_line_to_session "$session" "1"; then
        goza_bootstrap_log "gemini trust accepted agent=$agent"
      fi
      sleep 2
      continue
    fi
    if zellij_agent_output_matches "$session" "$agent" '(high demand|keep trying)'; then
      if zellij_send_line_to_session "$session" "1"; then
        goza_bootstrap_log "gemini keep_trying agent=$agent"
      fi
      sleep 5
      continue
    fi
    sleep 1
  done

  return 1
}

zellij_resume_pure_goza_panes_background() {
  local session="$1"
  shift
  local agents=("$@")

  zellij_focus_direction() {
    local _session="$1"
    local _dir="$2"
    zellij -s "$_session" action move-focus "$_dir" >/dev/null 2>&1 && return 0
    zellij -s "$_session" action move-focus-or-tab "$_dir" >/dev/null 2>&1 && return 0
    return 1
  }

  zellij_focus_shogun_anchor() {
    local _session="$1"
    local _i
    for _i in {1..6}; do zellij_focus_direction "$_session" "left" || true; done
    for _i in {1..6}; do zellij_focus_direction "$_session" "up" || true; done
  }

  zellij_focus_agent_index() {
    local _session="$1"
    local _idx="$2"
    local _count="$3"
    local _step

    zellij_focus_shogun_anchor "$_session"

    case "$_idx" in
      0)
        return 0
        ;;
      1)
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        return 0
        ;;
      2)
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        return 0
        ;;
      3)
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        if [[ "$_count" -ge 4 ]]; then
          zellij_focus_direction "$_session" "down" || zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        fi
        return 0
        ;;
      *)
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        zellij_focus_direction "$_session" "down" || zellij_focus_direction "$_session" "right" || zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        for ((_step=4; _step<=_idx; _step++)); do
          zellij -s "$_session" action focus-next-pane >/dev/null 2>&1 || true
        done
        return 0
        ;;
    esac
  }

  (
    sleep 1
    local idx
    local count="${#agents[@]}"
    local agent
    local ack_timeout="${MAS_GOZA_READY_ACK_TIMEOUT:-12}"
    local ready_timeout="${MAS_GOZA_CLI_READY_TIMEOUT:-25}"
    local gemini_preflight_timeout="${MAS_GOZA_GEMINI_PREFLIGHT_TIMEOUT:-25}"
    local cli_type
    local startup_msg
    local ready_pattern
    local launch_delay
    local launch_cmd
    local retry_msg

    if ! [[ "$ack_timeout" =~ ^[0-9]+$ ]]; then
      ack_timeout=12
    fi

    goza_bootstrap_log "resume start session=$session agents=${agents[*]}"

    for idx in "${!agents[@]}"; do
      agent="${agents[$idx]}"
      zellij_focus_agent_index "$session" "$idx" "$count"
      launch_cmd="$(zellij_agent_boot_cmd "$agent")"
      if [[ -n "$launch_cmd" ]] && zellij_send_line_to_session "$session" "$launch_cmd"; then
        goza_bootstrap_log "launch command sent agent=$agent"
      else
        goza_bootstrap_log "launch command failed agent=$agent"
      fi

      cli_type="$(zellij_resolve_cli_for_agent "$agent")"
      launch_delay="$(zellij_bootstrap_delay_for_cli "$cli_type")"
      sleep "$launch_delay"

      if [[ "$cli_type" == "gemini" ]]; then
        if ! zellij_handle_gemini_preflight_current_pane "$session" "$agent" "$gemini_preflight_timeout"; then
          goza_bootstrap_log "gemini preflight unresolved agent=$agent timeout=${gemini_preflight_timeout}s"
        fi
      elif [[ "$cli_type" == "codex" ]]; then
        if ! zellij_handle_codex_preflight_current_pane "$session" "$agent" "$ready_timeout"; then
          goza_bootstrap_log "codex preflight unresolved agent=$agent timeout=${ready_timeout}s"
        fi
      else
        ready_pattern="$(zellij_pure_ready_pattern "$cli_type")"
        if ! zellij_wait_agent_output "$session" "$agent" "$ready_pattern" "$ready_timeout"; then
          goza_bootstrap_log "cli ready not detected agent=$agent cli=$cli_type timeout=${ready_timeout}s"
        fi
      fi

      startup_msg="$(goza_startup_bootstrap_message "$agent" "$cli_type" 2>/dev/null || true)"
      if [[ -n "$startup_msg" ]] && zellij_send_line_to_session "$session" "$startup_msg"; then
        goza_bootstrap_log "legacy send-line delivery agent=$agent cli=$cli_type"
      else
        goza_bootstrap_log "bootstrap send failed agent=$agent cli=$cli_type"
      fi

      if zellij_wait_ready_ack_current_pane "$session" "$agent" "$ack_timeout"; then
        goza_bootstrap_log "ready ack detected agent=$agent"
      else
        goza_bootstrap_log "ready ack missing first_try agent=$agent timeout=${ack_timeout}s"
        retry_msg="$(goza_startup_bootstrap_message "$agent" "$cli_type" 2>/dev/null || true)"
        if [[ -n "$retry_msg" ]] && zellij_send_line_to_session "$session" "$retry_msg"; then
          goza_bootstrap_log "bootstrap retry sent agent=$agent cli=$cli_type"
          if zellij_wait_ready_ack_current_pane "$session" "$agent" "$ack_timeout"; then
            goza_bootstrap_log "ready ack detected after_retry agent=$agent"
          else
            goza_bootstrap_log "ready ack missing after_retry agent=$agent timeout=${ack_timeout}s"
          fi
        else
          goza_bootstrap_log "bootstrap retry failed_to_send agent=$agent"
        fi
      fi

      sleep 0.4
    done

    # 最後に将軍ペインへフォーカスを戻す（人間が即対話しやすいように）
    zellij_focus_shogun_anchor "$session"
    goza_bootstrap_log "resume complete session=$session"
  ) >/dev/null 2>&1 &
}

zellij_pure_goza_layout_file() {
  local tab_title="$1"
  shift
  local agents=("$@")
  local layout_file="${TMPDIR:-/tmp}/zellij_pure_goza_${ZELLIJ_UI_SESSION}.kdl"
  local tab_title_escaped
  local shogun_agent="shogun"
  local gunshi_agent=""
  local karo_agents=()
  local ashigaru_agents=()
  local agent
  local left_width="${GOZA_PURE_LEFT_WIDTH:-40%}"
  local middle_width="${GOZA_PURE_MIDDLE_WIDTH:-24%}"
  local right_width="${GOZA_PURE_RIGHT_WIDTH:-36%}"
  tab_title_escaped="$(kdl_escape "$tab_title")"

  for agent in "${agents[@]}"; do
    case "$agent" in
      shogun) shogun_agent="$agent" ;;
      gunshi) gunshi_agent="$agent" ;;
      karo|karo[1-9]*|karo_gashira) karo_agents+=("$agent") ;;
      ashigaru*) ashigaru_agents+=("$agent") ;;
    esac
  done
  if [[ ${#karo_agents[@]} -eq 0 ]]; then
    karo_agents=("karo")
  fi
  if [[ ${#ashigaru_agents[@]} -eq 0 ]]; then
    ashigaru_agents=("ashigaru1")
  fi

  zellij_emit_agent_leaf() {
    local indent="$1"
    local target_agent="$2"
    local focus_attr="${3:-}"
    local pane_name_escaped
    local pane_cmd
    local pane_cmd_escaped
    pane_name_escaped="$(kdl_escape "$target_agent")"
    if [[ -n "$focus_attr" ]]; then
      focus_attr=" focus=true"
    fi
    pane_cmd="$(printf 'cd %q && export AGENT_ID=%q && export DISPLAY_MODE=%q && export ZELLIJ_UI_SESSION=%q && export GOZA_SETUP_ONLY=%q && exec bash %q %q %q' \
      "$ROOT_DIR" "$target_agent" "shout" "$ZELLIJ_UI_SESSION" "$SETUP_ONLY" "$ROOT_DIR/scripts/zellij_agent_bootstrap.sh" "$target_agent" "$ZELLIJ_UI_SESSION")"
    pane_cmd_escaped="$(kdl_escape "$pane_cmd")"
    cat <<EOF
${indent}pane name="${pane_name_escaped}"${focus_attr} command="bash" start_suspended=false {
${indent}    args "-lc" "${pane_cmd_escaped}";
${indent}}
EOF
  }

  zellij_emit_ashigaru_row() {
    local indent="$1"
    local left="$2"
    local right="${3:-}"
    if [[ -n "$right" ]]; then
      echo "${indent}pane split_direction=\"vertical\" {"
      zellij_emit_agent_leaf "${indent}    " "$left"
      zellij_emit_agent_leaf "${indent}    " "$right"
      echo "${indent}}"
    else
      zellij_emit_agent_leaf "$indent" "$left"
    fi
  }

  zellij_emit_agent_grid() {
    local indent="$1"
    shift
    local local_agents=("$@")
    local count="${#local_agents[@]}"
    if [[ "$count" -le 0 ]]; then
      return
    fi
    if [[ "$count" -eq 1 ]]; then
      zellij_emit_agent_leaf "$indent" "${local_agents[0]}"
      return
    fi
    if [[ "$count" -eq 2 ]]; then
      echo "${indent}pane split_direction=\"vertical\" {"
      zellij_emit_agent_leaf "${indent}    " "${local_agents[0]}"
      zellij_emit_agent_leaf "${indent}    " "${local_agents[1]}"
      echo "${indent}}"
      return
    fi
    if [[ "$count" -le 4 ]]; then
      echo "${indent}pane split_direction=\"horizontal\" {"
      zellij_emit_ashigaru_row "${indent}    " "${local_agents[0]}" "${local_agents[1]:-}"
      zellij_emit_ashigaru_row "${indent}    " "${local_agents[2]}" "${local_agents[3]:-}"
      echo "${indent}}"
      return
    fi
    echo "${indent}pane split_direction=\"horizontal\" {"
    zellij_emit_agent_grid "${indent}    " "${local_agents[@]:0:4}"
    zellij_emit_agent_grid "${indent}    " "${local_agents[@]:4}"
    echo "${indent}}"
  }

  {
    echo "layout {"
    echo "    default_tab_template {"
    echo "        pane size=1 borderless=true {"
    echo "            plugin location=\"zellij:tab-bar\";"
    echo "        }"
    echo "        children"
    echo "        pane size=2 borderless=true {"
    echo "            plugin location=\"zellij:status-bar\";"
    echo "        }"
    echo "    }"
    echo "    tab name=\"${tab_title_escaped}\" {"
    echo "        pane split_direction=\"vertical\" {"
    echo "            pane split_direction=\"horizontal\" size=\"${left_width}\" {"
    zellij_emit_agent_leaf "                " "$shogun_agent" "focus"
    if [[ -n "$gunshi_agent" ]]; then
      zellij_emit_agent_leaf "                " "$gunshi_agent"
    fi
    echo "            }"
    echo "            pane split_direction=\"horizontal\" size=\"${middle_width}\" {"
    zellij_emit_agent_grid "                " "${karo_agents[@]}"
    echo "            }"
    echo "            pane split_direction=\"horizontal\" size=\"${right_width}\" {"
    zellij_emit_agent_grid "                " "${ashigaru_agents[@]}"
    echo "            }"
    echo "        }"
    echo "    }"
    echo "}"
  } > "$layout_file"

  echo "$layout_file"
}

zellij_pure_attach_goza_room() {
  local agents=("$@")
  local layout_file

  goza_init_bootstrap_log
  prepare_pure_zellij_bootstrap_files "${agents[@]}"
  layout_file="$(zellij_pure_goza_layout_file "御座の間 (zellij-core)" "${agents[@]}")"
  goza_bootstrap_log "pure goza layout ready session=$ZELLIJ_UI_SESSION agents=${agents[*]}"

  zellij delete-session "$ZELLIJ_UI_SESSION" --force >/dev/null 2>&1 || \
    zellij kill-session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || true

  if [[ "$NO_ATTACH" = true ]]; then
    if zellij attach --create-background "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || \
       zellij attach --create-background --session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1; then
      echo "[INFO] pure zellij goza session created: $ZELLIJ_UI_SESSION"
      echo "       attach: zellij attach $ZELLIJ_UI_SESSION"
      goza_bootstrap_log "no_attach session created session=$ZELLIJ_UI_SESSION"
      return 0
    fi
    echo "[ERROR] pure zellij goza session の背景起動に失敗しました: $ZELLIJ_UI_SESSION" >&2
    goza_bootstrap_log "no_attach session create failed session=$ZELLIJ_UI_SESSION"
    return 1
  fi

  # pure zellij の初動は pane ごとの専用 runner が bootstrap file を読んで自律実行する。
  # 外側スクリプトによるアクティブペイン注入や focus 巡回は行わない。
  goza_bootstrap_log "attach attempt method=--new-session-with-layout session=$ZELLIJ_UI_SESSION"
  if zellij --new-session-with-layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  goza_bootstrap_log "attach attempt method=--layout -s session=$ZELLIJ_UI_SESSION"
  if zellij --layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  goza_bootstrap_log "attach attempt method=--layout attach -c session=$ZELLIJ_UI_SESSION"
  if zellij --layout "$layout_file" attach -c "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  echo "[ERROR] pure zellij 御座の間起動に失敗しました（layout: $layout_file）" >&2
  goza_bootstrap_log "attach failed session=$ZELLIJ_UI_SESSION layout=$layout_file"
  return 1
}

tmux_new_view_session() {
  local session="$1"
  local window="$2"
  local cmd="$3"
  tmux new-session -d -x "$TMUX_VIEW_WIDTH" -y "$TMUX_VIEW_HEIGHT" -s "$session" -n "$window" "$cmd"
}

tmux_split_right_ratio_run() {
  local target="$1"
  local cmd="$2"
  local fallback_cols
  fallback_cols=$(( TMUX_VIEW_WIDTH * 35 / 100 ))
  if [[ "$fallback_cols" -lt 20 ]]; then
    fallback_cols=20
  fi
  tmux split-window -h -p 35 -t "$target" "$cmd" 2>/dev/null || \
    tmux split-window -h -l "$fallback_cols" -t "$target" "$cmd"
}

tmux_split_right_ratio_pane() {
  local target="$1"
  local cmd="$2"
  local fallback_cols
  local pane
  fallback_cols=$(( TMUX_VIEW_WIDTH * 35 / 100 ))
  if [[ "$fallback_cols" -lt 20 ]]; then
    fallback_cols=20
  fi
  pane="$(tmux split-window -h -p 35 -P -F '#{pane_id}' -t "$target" "$cmd" 2>/dev/null || true)"
  if [[ -z "$pane" ]]; then
    pane="$(tmux split-window -h -l "$fallback_cols" -P -F '#{pane_id}' -t "$target" "$cmd" 2>/dev/null || true)"
  fi
  echo "$pane"
}

tmux_split_down_pane() {
  local target="$1"
  local cmd="$2"
  local fallback_rows
  local pane
  fallback_rows=$(( TMUX_VIEW_HEIGHT / 2 ))
  if [[ "$fallback_rows" -lt 10 ]]; then
    fallback_rows=10
  fi
  pane="$(tmux split-window -v -P -F '#{pane_id}' -t "$target" "$cmd" 2>/dev/null || true)"
  if [[ -z "$pane" ]]; then
    pane="$(tmux split-window -v -l "$fallback_rows" -P -F '#{pane_id}' -t "$target" "$cmd" 2>/dev/null || true)"
  fi
  echo "$pane"
}

tmux_focus_shogun_for_human() {
  local template="$1"
  local target="$2"
  if [[ "$template" == "goza_room" ]]; then
    tmux select-window -t "${target}:overview" >/dev/null 2>&1 || true
    tmux select-pane -t "${target}:overview.0" >/dev/null 2>&1 || true
    tmux set-option -t "${target}:overview" mouse on >/dev/null 2>&1 || true
  else
    tmux select-window -t "shogun:main" >/dev/null 2>&1 || true
    tmux select-pane -t "shogun:main.0" >/dev/null 2>&1 || true
  fi
}

if [[ "$MUX_MODE" == "tmux" ]]; then
  tmux_target=""

  if [[ "$VIEW_TEMPLATE" == "shogun_only" ]]; then
    tmux_target="shogun"
  else
    # template: goza_room
    if ! tmux has-session -t shogun 2>/dev/null || ! tmux has-session -t multiagent 2>/dev/null; then
      echo "[ERROR] shogun または multiagent セッションが存在しません。" >&2
      echo "        先に: bash shutsujin_departure.sh -s" >&2
      exit 1
    fi

    if ! tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
      tmux_new_view_session "$VIEW_SESSION" "overview" "$(tmux_attach_session_cmd shogun)"
      # 将軍を広く見せる（左65% / 右35%）
      tmux_split_right_ratio_run "$VIEW_SESSION":overview "$(tmux_attach_session_cmd multiagent)"
      tmux select-layout -t "$VIEW_SESSION":overview main-vertical >/dev/null 2>&1 || true
      tmux set-window-option -t "$VIEW_SESSION":overview main-pane-width 65% >/dev/null 2>&1 || true
      tmux select-pane -t "$VIEW_SESSION":overview.0 -T "shogun"
      tmux select-pane -t "$VIEW_SESSION":overview.1 -T "multiagent"
      # 軍師ウィンドウを別タブで追加（gunshi セッションが存在する場合）
      if tmux has-session -t gunshi 2>/dev/null; then
        tmux new-window -t "$VIEW_SESSION" -n "gunshi" "$(tmux_attach_session_cmd gunshi)" >/dev/null 2>&1 || true
      fi
      # 最初のウィンドウ（overview = 将軍）にフォーカスを戻す
      tmux select-window -t "$VIEW_SESSION":overview >/dev/null 2>&1 || true
    fi
    tmux_target="$VIEW_SESSION"
  fi

  tmux_focus_shogun_for_human "$VIEW_TEMPLATE" "$tmux_target"

  if [[ "$UI_MODE" == "zellij" ]]; then
    if [[ "$VIEW_TEMPLATE" == "goza_room" ]]; then
      echo "[INFO] zellij UI + tmux backend で表示します（tmux target: $tmux_target）。"
      zellij_ui_attach_tmux_target "$tmux_target" "御座の間 (tmux-core)"
    else
      echo "[INFO] zellij UI + tmux backend で表示します（tmux target: $tmux_target）。"
      zellij_ui_attach_tmux_target "$tmux_target" "将軍本陣 (tmux-core)"
    fi
    exit 0
  fi

  if [[ "$NO_ATTACH" = true ]]; then
    if [[ "$VIEW_TEMPLATE" == "goza_room" ]]; then
      echo "[INFO] tmux view session ready: $tmux_target"
      echo "       attach: tmux attach -t $tmux_target"
    else
      echo "[INFO] tmux mode started (template: shogun_only)."
      echo "       attach shogun: tmux attach-session -t shogun"
    fi
    exit 0
  fi
  if [[ "$VIEW_TEMPLATE" == "goza_room" ]]; then
    TMUX= tmux attach -t "$tmux_target"
  else
    TMUX= tmux attach-session -t shogun
  fi
  exit 0
fi

if [[ "$VIEW_TEMPLATE" == "shogun_only" ]]; then
  if ! zellij list-sessions -n 2>/dev/null | awk '{print $1}' | grep -qx "shogun"; then
    echo "[ERROR] shogun zellij session が見つかりませんでした。" >&2
    echo "        先に: bash shutsujin_departure.sh -s" >&2
    exit 1
  fi
  if [[ "$NO_ATTACH" = true ]]; then
    echo "[INFO] zellij mode started (template: shogun_only)."
    echo "       attach: zellij attach shogun"
    exit 0
  fi
  zellij attach shogun
  exit 0
fi

# pure zellij goza_room: agent sessions を複数ペインで一括表示する。
if [[ "$UI_MODE" == "zellij" ]]; then
  mapfile -t AGENTS < <(zellij_collect_active_agents)
  if [[ ${#AGENTS[@]} -eq 0 ]]; then
    echo "[ERROR] 表示対象エージェントを解決できませんでした。" >&2
    exit 1
  fi
  echo "[INFO] pure zellij 御座の間で起動します: ${AGENTS[*]}"
  zellij_pure_attach_goza_room "${AGENTS[@]}"
  exit 0
fi

echo "[INFO] zellij + goza_room は tmux ビューで表示します（バックエンドは zellij セッション）。"

role_border_color() {
  local role="$1"
  case "$role" in
    *shogun*) echo "colour54" ;;    # 紫
    *karo*) echo "colour19" ;;      # 紺
    *ashigaru*) echo "colour94" ;;  # 茶
    *) echo "colour248" ;;
  esac
}

apply_role_border_styles() {
  local pane
  local title
  local color

  tmux set-option -t "$VIEW_SESSION":agents pane-border-status top >/dev/null 2>&1 || true
  tmux set-option -t "$VIEW_SESSION":agents pane-border-style 'fg=colour240' >/dev/null 2>&1 || true
  tmux set-option -t "$VIEW_SESSION":agents pane-active-border-style 'fg=colour240' >/dev/null 2>&1 || true
  tmux set-option -t "$VIEW_SESSION":agents pane-border-format \
    '#{?#{m:*shogun*,#{pane_title}},#[fg=colour231#,bg=colour54#,bold] #{pane_index}:#{pane_title} #[default],#{?#{m:*karo*,#{pane_title}},#[fg=colour231#,bg=colour19#,bold] #{pane_index}:#{pane_title} #[default],#{?#{m:*ashigaru*,#{pane_title}},#[fg=colour231#,bg=colour94#,bold] #{pane_index}:#{pane_title} #[default],#{pane_index}:#{pane_title}}}' \
    >/dev/null 2>&1 || true

  while IFS= read -r pane; do
    title="$(tmux display-message -p -t "$pane" '#{pane_title}' 2>/dev/null || true)"
    color="$(role_border_color "$title")"
    tmux set-option -p -t "$pane" pane-border-style "fg=${color}" >/dev/null 2>&1 || true
    tmux set-option -p -t "$pane" pane-active-border-style "fg=${color}" >/dev/null 2>&1 || true
  done < <(tmux list-panes -t "$VIEW_SESSION":agents -F '#{pane_id}' 2>/dev/null || true)
}

mapfile -t AGENTS < <(zellij_collect_active_agents)

# 実在する zellij セッションのみ表示対象にする
zellij_sessions="$(zellij list-sessions -n 2>/dev/null || true)"
VISIBLE=()
for a in "${AGENTS[@]}"; do
  if echo "$zellij_sessions" | awk '{print $1}' | grep -qx "$a"; then
    VISIBLE+=("$a")
  fi
done

if [[ ${#VISIBLE[@]} -eq 0 ]]; then
  echo "[ERROR] attach可能な zellij session が見つかりませんでした。" >&2
  echo "        先に: bash shutsujin_departure.sh" >&2
  exit 1
fi

if tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
  # 既存ビューでも毎回スタイルを再適用する
  apply_role_border_styles
  if [[ "$NO_ATTACH" = true ]]; then
    echo "[INFO] tmux session already exists: $VIEW_SESSION"
    echo "       attach: tmux attach -t $VIEW_SESSION"
    exit 0
  fi
  TMUX= tmux attach -t "$VIEW_SESSION"
  exit 0
fi

attach_cmd() {
  local agent="$1"
  printf 'cd "%s" && zellij attach %q || (echo "[WARN] attach失敗: %s"; exec bash)' "$ROOT_DIR" "$agent" "$agent"
}

# 1ペイン目（将軍）
first="${VISIBLE[0]}"
tmux_new_view_session "$VIEW_SESSION" "agents" "$(attach_cmd "$first")"
tmux select-pane -t "$VIEW_SESSION":agents.0 -T "$first"

# 2ペイン目以降（将軍を大きく、残りを右側へ積む）
for i in "${!VISIBLE[@]}"; do
  if [[ "$i" -eq 0 ]]; then
    continue
  fi
  agent="${VISIBLE[$i]}"
  new_pane=""
  if [[ "$i" -eq 1 ]]; then
    new_pane="$(tmux_split_right_ratio_pane "$VIEW_SESSION":agents "$(attach_cmd "$agent")")"
  else
    new_pane="$(tmux_split_down_pane "$VIEW_SESSION":agents.1 "$(attach_cmd "$agent")")"
  fi
  tmux select-layout -t "$VIEW_SESSION":agents main-vertical >/dev/null 2>&1 || true
  tmux set-window-option -t "$VIEW_SESSION":agents main-pane-width 65% >/dev/null 2>&1 || true
  if [[ -n "$new_pane" ]]; then
    tmux select-pane -t "$new_pane" -T "$agent" >/dev/null 2>&1 || true
  fi
done

# 見やすさ調整
apply_role_border_styles

tmux display-message -t "$VIEW_SESSION":agents "Attached agents: ${VISIBLE[*]}"
if [[ "$NO_ATTACH" = true ]]; then
  echo "[INFO] view session created: $VIEW_SESSION"
  echo "       attach: tmux attach -t $VIEW_SESSION"
  exit 0
fi
TMUX= tmux attach -t "$VIEW_SESSION"
