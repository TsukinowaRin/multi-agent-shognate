#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GOZA_SESSION="${GOZA_SESSION_NAME:-goza-no-ma}"
GOZA_SIGNATURE_FILE="${GOZA_SIGNATURE_FILE:-$ROOT_DIR/queue/runtime/goza_signature.tsv}"
SETUP_ONLY=false
ENSURE_BACKEND=false
REFRESH=false
NO_ATTACH=false
PASS_THROUGH=()

if [ -f "$ROOT_DIR/lib/topology_adapter.sh" ]; then
  # shellcheck source=/dev/null
  source "$ROOT_DIR/lib/topology_adapter.sh"
fi

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/goza_no_ma.sh [options] [-- <shutsujin_departure.sh options>]

Options:
  -s, --setup-only   backend を setup-only で起動してから御座の間を開く
  --ensure-backend   御座の間 session が無ければ出陣してから開く
  --refresh          御座の間を再出陣して作り直す
  --no-attach        attach/switch せず存在確認だけ行う
  -h, --help         このヘルプ
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--setup-only) SETUP_ONLY=true; ENSURE_BACKEND=true; shift ;;
    --ensure-backend) ENSURE_BACKEND=true; shift ;;
    --view-only) shift ;;
    --refresh) REFRESH=true; ENSURE_BACKEND=true; shift ;;
    --no-attach) NO_ATTACH=true; shift ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do PASS_THROUGH+=("$1"); shift; done
      ;;
    -h|--help) usage; exit 0 ;;
    *) PASS_THROUGH+=("$1"); shift ;;
  esac
done

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux が見つかりません。" >&2
  exit 1
fi

compose_goza_signature() {
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "$@" | awk 'NF' | sort -V | paste -sd, -
}

desired_goza_signature() {
  local ashigaru=()
  local karos=()

  if declare -F topology_load_active_ashigaru >/dev/null 2>&1; then
    mapfile -t ashigaru < <(topology_load_active_ashigaru)
  fi
  if [ "${#ashigaru[@]}" -eq 0 ]; then
    mapfile -t ashigaru < <(python3 - <<'PY' 2>/dev/null || true
import yaml
from pathlib import Path
p = Path("config/settings.yaml")
cfg = yaml.safe_load(p.read_text(encoding="utf-8")) or {} if p.exists() else {}
active = ((cfg.get("topology") or {}).get("active_ashigaru") or [])
out = []
for item in active:
    s = str(item).strip()
    if s.isdigit() and int(s) >= 1:
        out.append(f"ashigaru{int(s)}")
    elif s.startswith("ashigaru") and s[8:].isdigit():
        out.append(s)
if not out:
    out = ["ashigaru1"]
for item in sorted(dict.fromkeys(out), key=lambda x: int(x[8:])):
    print(item)
PY
)
  fi
  if declare -F topology_resolve_karo_agents >/dev/null 2>&1; then
    mapfile -t karos < <(topology_resolve_karo_agents "${ashigaru[@]}")
  fi
  if [ "${#karos[@]}" -eq 0 ]; then
    karos=("karo")
  fi

  compose_goza_signature shogun "${karos[@]}" gunshi "${ashigaru[@]}"
}

current_goza_signature() {
  local pane_id=""
  local agent_id=""
  local agents=()

  tmux has-session -t "$GOZA_SESSION" 2>/dev/null || return 0
  while IFS= read -r pane_id; do
    [ -n "$pane_id" ] || continue
    agent_id="$(tmux show-options -p -t "$pane_id" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
    [ -n "$agent_id" ] || continue
    agents+=("$agent_id")
  done < <(tmux list-panes -s -t "$GOZA_SESSION" -F "#{pane_id}" 2>/dev/null || true)

  compose_goza_signature "${agents[@]}"
}

DESIRED_GOZA_SIGNATURE="$(desired_goza_signature)"

if [[ "$REFRESH" == true ]]; then
  tmux kill-session -t "$GOZA_SESSION" 2>/dev/null || true
fi

if tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  CURRENT_GOZA_SIGNATURE="$(current_goza_signature)"
  if [[ -n "$DESIRED_GOZA_SIGNATURE" && -n "$CURRENT_GOZA_SIGNATURE" && "$DESIRED_GOZA_SIGNATURE" != "$CURRENT_GOZA_SIGNATURE" ]]; then
    echo "[INFO] エージェント構成が変化したため、御座の間を再生成します。" >&2
    REFRESH=true
    ENSURE_BACKEND=true
    tmux kill-session -t "$GOZA_SESSION" 2>/dev/null || true
  fi
fi

if ! tmux has-session -t "$GOZA_SESSION" 2>/dev/null; then
  if [[ "$ENSURE_BACKEND" != true ]]; then
    echo "[ERROR] ${GOZA_SESSION} session が存在しません。" >&2
    echo "        先に: bash shutsujin_departure.sh" >&2
    echo "        あるいは: bash scripts/goza_no_ma.sh --ensure-backend" >&2
    exit 1
  fi

  START_ARGS=("${PASS_THROUGH[@]}")
  if [[ "$SETUP_ONLY" == true ]]; then
    START_ARGS=("-s" "${START_ARGS[@]}")
  fi
  bash "$ROOT_DIR/shutsujin_departure.sh" "${START_ARGS[@]}"
fi

if [[ "$NO_ATTACH" == true ]]; then
  echo "[INFO] 御座の間 session を確認しました: ${GOZA_SESSION}"
  echo "       attach: tmux attach -t ${GOZA_SESSION}"
  exit 0
fi

if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "$GOZA_SESSION"
else
  TMUX= tmux attach-session -t "$GOZA_SESSION"
fi
