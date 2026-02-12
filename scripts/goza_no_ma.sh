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

if [[ "$VIEW_ONLY" != true ]]; then
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" = true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi

  MAS_MULTIPLEXER="$MUX_MODE" bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
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

mapfile -t AGENTS < <(python3 - << 'PY'
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
for x in active:
    if isinstance(x, int):
        if 1 <= x <= 8:
            normalized.append(f"ashigaru{x}")
        continue
    s = str(x).strip()
    if s.isdigit():
        i = int(s)
        if 1 <= i <= 8:
            normalized.append(f"ashigaru{i}")
    elif s.startswith("ashigaru") and s[8:].isdigit():
        i = int(s[8:])
        if 1 <= i <= 8:
            normalized.append(f"ashigaru{i}")

if not normalized:
    normalized = ["ashigaru1"]

agents = ["shogun", "karo"] + normalized
for a in agents:
    print(a)
PY
)

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
