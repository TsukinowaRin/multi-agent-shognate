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
    mkdir -p "$ROOT_DIR/queue/reports" "$ROOT_DIR/queue/tasks" "$ROOT_DIR/queue/inbox" "$ROOT_DIR/logs" "$ROOT_DIR/queue/runtime"
  else
    START_ARGS=("${PASS_THROUGH[@]}")
    if [[ "$SETUP_ONLY" = true ]]; then
      START_ARGS=("-s" "${START_ARGS[@]}")
    fi
    MAS_MULTIPLEXER="$MUX_MODE" bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
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
        pane name="${pane_name_escaped}" {
            command "bash";
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

zellij_agent_pane_cmd() {
  local agent="$1"
  local cli_type="codex"
  local cli_cmd="codex --dangerously-bypass-approvals-and-sandbox --no-alt-screen"
  local startup_msg=""
  local startup_wait="3"
  local gemini_preflight_gate="0"
  local startup_msg_q=""

  if [[ "$CLI_ADAPTER_LOADED" == "true" ]]; then
    cli_type="$(resolve_cli_type_for_agent "$agent" 2>/dev/null || echo "codex")"
    cli_cmd="$(build_cli_command_with_type "$agent" "$cli_type" 2>/dev/null || echo "$cli_cmd")"
  fi

  if [[ "$SETUP_ONLY" == "true" ]]; then
    printf 'cd %q && export AGENT_ID=%q && export DISPLAY_MODE=%q && clear && exec bash' \
      "$ROOT_DIR" "$agent" "shout"
    return 0
  fi

  startup_msg="$(goza_startup_bootstrap_message "$agent" "$cli_type")"
  printf -v startup_msg_q '%q' "$startup_msg"
  case "$cli_type" in
    gemini) startup_wait="8" ;;
    codex) startup_wait="3" ;;
    claude) startup_wait="4" ;;
    *) startup_wait="4" ;;
  esac
  if [[ "$cli_type" == "gemini" && "$agent" == ashigaru* ]]; then
    gemini_preflight_gate="1"
  fi

  printf 'cd %q && export AGENT_ID=%q && export DISPLAY_MODE=%q && clear && bootstrap_line=%s && bootstrap_wait=%q && gemini_gate=%q && tty_path=\"$(tty)\" && (sleep \"$bootstrap_wait\"; if [[ \"$gemini_gate\" -eq 1 ]]; then printf \"1\\r\" > \"$tty_path\"; sleep 1; fi; printf \"%%s\\r\" \"$bootstrap_line\" > \"$tty_path\") >/dev/null 2>&1 & %s; echo %q; exec bash' \
    "$ROOT_DIR" "$agent" "shout" "$startup_msg_q" "$startup_wait" "$gemini_preflight_gate" "$cli_cmd" "[INFO] ${agent} pane ended. Waiting at shell."
}

zellij_collect_active_agents() {
  python3 - << 'PY'
from pathlib import Path

try:
    import yaml
except Exception:
    print("shogun")
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

agents = ["shogun", "karo"] + normalized
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
    karo)
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
    karo|ashigaru*)
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
    karo)
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
      karo) role_instruction_file="instructions/karo.md" ;;
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

zellij_bootstrap_pure_goza_background() {
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

  zellij_send_bootstrap_current_pane() {
    local _session="$1"
    local _agent="$2"
    local _cli_type="$3"
    local _wait="$4"
    local _startup_msg
    local _sent
    local _attempt

    sleep "$_wait"
    _startup_msg="$(goza_startup_bootstrap_message "$_agent" "$_cli_type")"
    _sent=0
    for _attempt in 1 2 3; do
      if zellij_send_line_to_session "$_session" "$_startup_msg"; then
        _sent=1
        break
      fi
      sleep 0.8
    done
    if [[ "$_sent" -ne 1 ]]; then
      echo "[WARN] pure zellij bootstrap send failed: ${_agent}" >&2
    fi
  }

  zellij_prepare_gemini_gate_current_pane() {
    local _session="$1"
    local _agent="$2"
    local _cli_type="$3"
    if [[ "$_cli_type" != "gemini" || "$_agent" != ashigaru* ]]; then
      return 0
    fi
    # 初回 trust / high-demand メニューに引っ掛かるケース向けに軽い先行入力を行う
    zellij_send_line_to_session "$_session" "1" >/dev/null 2>&1 || true
    sleep 0.8
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
    # CLI起動直後の入力取りこぼしを避ける
    sleep 8
    local idx
    local agent
    local cli_type
    local wait_sec
    local count="${#agents[@]}"
    local role_cli=()

    for idx in "${!agents[@]}"; do
      agent="${agents[$idx]}"
      cli_type="codex"
      if [[ "$CLI_ADAPTER_LOADED" == "true" ]]; then
        cli_type="$(resolve_cli_type_for_agent "$agent" 2>/dev/null || echo "codex")"
      fi
      role_cli[$idx]="$cli_type"
    done

    for idx in "${!agents[@]}"; do
      zellij_focus_agent_index "$session" "$idx" "$count"
      case "${role_cli[$idx]}" in
        gemini) wait_sec=7 ;;
        codex) wait_sec=2 ;;
        *) wait_sec=3 ;;
      esac
      zellij_prepare_gemini_gate_current_pane "$session" "${agents[$idx]}" "${role_cli[$idx]}"
      zellij_send_bootstrap_current_pane "$session" "${agents[$idx]}" "${role_cli[$idx]}" "$wait_sec"
    done

    # 最後に将軍ペインへフォーカスを戻す
    zellij_focus_shogun_anchor "$session"
  ) >/dev/null 2>&1 &
}

zellij_pure_goza_layout_file() {
  local tab_title="$1"
  shift
  local agents=("$@")
  local layout_file="${TMPDIR:-/tmp}/zellij_pure_goza_${ZELLIJ_UI_SESSION}.kdl"
  local tab_title_escaped
  local shogun_agent="shogun"
  local karo_agent="karo"
  local ashigaru_agents=()
  local agent
  tab_title_escaped="$(kdl_escape "$tab_title")"

  for agent in "${agents[@]}"; do
    case "$agent" in
      shogun) shogun_agent="$agent" ;;
      karo) karo_agent="$agent" ;;
      ashigaru*) ashigaru_agents+=("$agent") ;;
    esac
  done
  if [[ ${#ashigaru_agents[@]} -eq 0 ]]; then
    ashigaru_agents=("ashigaru1")
  fi

  zellij_emit_agent_leaf() {
    local indent="$1"
    local target_agent="$2"
    local focus_attr="${3:-}"
    local pane_name_escaped
    local startup_cmd
    local startup_cmd_escaped
    pane_name_escaped="$(kdl_escape "$target_agent")"
    startup_cmd="$(zellij_agent_pane_cmd "$target_agent")"
    startup_cmd_escaped="$(kdl_escape "$startup_cmd")"
    if [[ -n "$focus_attr" ]]; then
      focus_attr=" focus=true"
    fi
    cat <<EOF
${indent}pane name="${pane_name_escaped}"${focus_attr} {
${indent}    command "bash";
${indent}    args "-lc" "${startup_cmd_escaped}";
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

  zellij_emit_ashigaru_grid() {
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
    zellij_emit_ashigaru_grid "${indent}    " "${local_agents[@]:0:4}"
    zellij_emit_ashigaru_grid "${indent}    " "${local_agents[@]:4}"
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
    echo "            pane split_direction=\"horizontal\" size=\"46%\" {"
    zellij_emit_agent_leaf "                " "$shogun_agent" "focus"
    echo "            }"
    echo "            pane split_direction=\"horizontal\" size=\"32%\" {"
    zellij_emit_agent_leaf "                " "$karo_agent"
    echo "            }"
    echo "            pane split_direction=\"horizontal\" size=\"22%\" {"
    zellij_emit_ashigaru_grid "                " "${ashigaru_agents[@]}"
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
  layout_file="$(zellij_pure_goza_layout_file "御座の間 (zellij-core)" "${agents[@]}")"

  zellij delete-session "$ZELLIJ_UI_SESSION" --force >/dev/null 2>&1 || \
    zellij kill-session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || true

  if [[ "$NO_ATTACH" = true ]]; then
    if zellij attach --create-background "$ZELLIJ_UI_SESSION" >/dev/null 2>&1 || \
       zellij attach --create-background --session "$ZELLIJ_UI_SESSION" >/dev/null 2>&1; then
      echo "[INFO] pure zellij goza session created: $ZELLIJ_UI_SESSION"
      echo "       attach: zellij attach $ZELLIJ_UI_SESSION"
      return 0
    fi
    echo "[ERROR] pure zellij goza session の背景起動に失敗しました: $ZELLIJ_UI_SESSION" >&2
    return 1
  fi
  # pure zellij では各pane内で自動初動送信する（足軽増員時の注入先ずれを回避）

  if zellij --new-session-with-layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  if zellij --layout "$layout_file" -s "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  if zellij --layout "$layout_file" attach -c "$ZELLIJ_UI_SESSION"; then
    return 0
  fi
  echo "[ERROR] pure zellij 御座の間起動に失敗しました（layout: $layout_file）" >&2
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
    tmux attach -t "$tmux_target"
  else
    tmux attach-session -t shogun
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
  tmux attach -t "$VIEW_SESSION"
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
tmux attach -t "$VIEW_SESSION"
