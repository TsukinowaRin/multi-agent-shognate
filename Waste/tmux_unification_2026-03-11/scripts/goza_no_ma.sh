#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VIEW_SESSION="${VIEW_SESSION:-goza-no-ma}"
TMUX_VIEW_WIDTH="${TMUX_VIEW_WIDTH:-200}"
TMUX_VIEW_HEIGHT="${TMUX_VIEW_HEIGHT:-60}"
SETUP_ONLY=false
VIEW_ONLY=false
NO_ATTACH=false
VIEW_TEMPLATE="${VIEW_TEMPLATE:-}"
PASS_THROUGH=()
INBOX_PATH_HELPER_LOADED=false

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   バックエンドは setup-only で起動（CLI未起動）
  --view-only        バックエンド起動をスキップし、ビューのみ起動
  --no-attach        tmuxへattachせず、ビュー作成だけ行う
  --mux MODE         互換オプション。tmux 以外を指定しても tmux にフォールバック
  --ui MODE          互換オプション。tmux 以外を指定しても tmux にフォールバック
  --template NAME    表示テンプレート（shogun_only|goza_room）
  --session NAME     ビュー用 tmux セッション名（default: goza-no-ma）
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; shift ;;
    --view-only) VIEW_ONLY=true; shift ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --mux)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        if [[ "$2" != "tmux" ]]; then
          echo "[INFO] zellij backend は廃止されました。tmux を使用します。"
        fi
        shift 2
      else
        echo "[ERROR] --mux には値が必要です" >&2
        exit 1
      fi
      ;;
    --ui)
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        if [[ "$2" != "tmux" ]]; then
          echo "[INFO] zellij UI は廃止されました。tmux を使用します。"
        fi
        shift 2
      else
        echo "[ERROR] --ui には値が必要です" >&2
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
      while [[ $# -gt 0 ]]; do PASS_THROUGH+=("$1"); shift; done
      ;;
    -h|--help) usage; exit 0 ;;
    *) PASS_THROUGH+=("$1"); shift ;;
  esac
done

if [ -f "$ROOT_DIR/lib/inbox_path.sh" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/inbox_path.sh" || true
  INBOX_PATH_HELPER_LOADED=true
fi

sync_gemini_workspace_settings() {
  local sync_script="$ROOT_DIR/scripts/sync_gemini_settings.py"
  if [[ -x "$sync_script" ]]; then
    python3 "$sync_script" >/dev/null 2>&1 || echo "[WARN] Gemini workspace settings の同期に失敗しました" >&2
  fi
}

sync_opencode_like_workspace_settings() {
  local sync_script="$ROOT_DIR/scripts/sync_opencode_config.py"
  if [[ -x "$sync_script" ]]; then
    python3 "$sync_script" >/dev/null 2>&1 || echo "[WARN] OpenCode/Kilo project config の同期に失敗しました" >&2
  fi
}

sync_gemini_workspace_settings
sync_opencode_like_workspace_settings

if [[ -z "$VIEW_TEMPLATE" ]]; then
  VIEW_TEMPLATE="$(python3 - <<'PY'
from pathlib import Path
try:
    import yaml
except Exception:
    yaml = None

template = ""
if yaml:
    sp = Path("config/settings.yaml")
    if sp.exists():
        cfg = yaml.safe_load(sp.read_text(encoding="utf-8")) or {}
        template = str(((cfg.get("startup") or {}).get("template") or "")).strip()
    if not template:
        tp = Path("templates/multiplexer/tmux_templates.yaml")
        if tp.exists():
            tcfg = yaml.safe_load(tp.read_text(encoding="utf-8")) or {}
            template = str((tcfg.get("default") or "")).strip()
print(template or "shogun_only")
PY
)"
fi

if [[ "$VIEW_TEMPLATE" != "shogun_only" && "$VIEW_TEMPLATE" != "goza_room" ]]; then
  echo "[ERROR] --template は shogun_only または goza_room を指定してください（指定値: $VIEW_TEMPLATE）" >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

if [[ "$VIEW_ONLY" != true ]]; then
  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" = true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi
  set +e
  MAS_MULTIPLEXER=tmux MAS_CLI_READY_TIMEOUT="${MAS_CLI_READY_TIMEOUT:-12}" bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
  _rc=$?
  set -e
  if [[ "$_rc" -ne 0 ]]; then
    echo "[WARN] shutsujin_departure.sh exited with code $_rc (continuing to view setup)" >&2
  fi
fi

tmux_attach_session_cmd() {
  local session="$1"
  printf 'cd %q && TMUX= tmux attach-session -t %q || (echo %q; exec bash)' "$ROOT_DIR" "$session" "[WARN] attach失敗: $session"
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
  if [[ "$fallback_cols" -lt 20 ]]; then fallback_cols=20; fi
  tmux split-window -h -p 35 -t "$target" "$cmd" 2>/dev/null || tmux split-window -h -l "$fallback_cols" -t "$target" "$cmd"
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

if [[ "$VIEW_TEMPLATE" == "shogun_only" ]]; then
  tmux_target="shogun"
else
  if ! tmux has-session -t shogun 2>/dev/null || ! tmux has-session -t multiagent 2>/dev/null; then
    echo "[ERROR] shogun または multiagent セッションが存在しません。" >&2
    echo "        先に: bash shutsujin_departure.sh -s" >&2
    exit 1
  fi
  if ! tmux has-session -t "$VIEW_SESSION" 2>/dev/null; then
    tmux_new_view_session "$VIEW_SESSION" "overview" "$(tmux_attach_session_cmd shogun)"
    tmux_split_right_ratio_run "$VIEW_SESSION":overview "$(tmux_attach_session_cmd multiagent)"
    tmux select-layout -t "$VIEW_SESSION":overview main-vertical >/dev/null 2>&1 || true
    tmux set-window-option -t "$VIEW_SESSION":overview main-pane-width 65% >/dev/null 2>&1 || true
    tmux select-pane -t "$VIEW_SESSION":overview.0 -T "shogun" >/dev/null 2>&1 || true
    tmux select-pane -t "$VIEW_SESSION":overview.1 -T "multiagent" >/dev/null 2>&1 || true
    if tmux has-session -t gunshi 2>/dev/null; then
      tmux new-window -t "$VIEW_SESSION" -n "gunshi" "$(tmux_attach_session_cmd gunshi)" >/dev/null 2>&1 || true
    fi
    tmux select-window -t "$VIEW_SESSION":overview >/dev/null 2>&1 || true
  fi
  tmux_target="$VIEW_SESSION"
fi

tmux_focus_shogun_for_human "$VIEW_TEMPLATE" "$tmux_target"

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
