#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="auto"
ADB_BIN="${ADB:-adb}"
HOST_SSH_PORT="${HOST_SSH_PORT:-}"
ANDROID_USB_PORT="${ANDROID_USB_PORT:-2222}"
SSH_USER="${SSH_USER:-${USER:-}}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR}"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

usage() {
  cat <<'USAGE'
Usage:
  bash android/tools/setup_android_ssh.sh [--usb|--wireless|--auto]

Options:
  --usb       USB debugging + adb reverse for Android -> host SSH.
  --wireless  Print LAN / Tailscale candidates for wireless SSH.
  --auto      Use USB when one adb device is visible; otherwise print wireless info.

Environment:
  ADB=/path/to/adb
  HOST_SSH_PORT=<override auto-detected host SSH port>
  ANDROID_USB_PORT=2222
  SSH_USER=<host ssh user>
  PROJECT_PATH=<remote Shogunate path>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --usb) MODE="usb"; shift ;;
    --wireless) MODE="wireless"; shift ;;
    --auto) MODE="auto"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

has_adb_device() {
  command -v "$ADB_BIN" >/dev/null 2>&1 || return 1
  local count
  count="$("$ADB_BIN" devices 2>/dev/null | tr -d '\r' | awk '$2 == "device" {count++} END {print count + 0}')"
  [ "$count" = "1" ]
}

check_host_ssh_port() {
  [ -n "${HOST_SSH_PORT:-}" ] || return 1
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 127.0.0.1 "$HOST_SSH_PORT" >/dev/null 2>&1
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 2 bash -c "</dev/tcp/127.0.0.1/${HOST_SSH_PORT}" >/dev/null 2>&1
    return $?
  fi
  bash -c "</dev/tcp/127.0.0.1/${HOST_SSH_PORT}" >/dev/null 2>&1
}

port_is_open() {
  local port="$1"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 1 bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
    return $?
  fi
  bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1
}

port_is_ssh() {
  local port="$1"
  local output
  output="$(ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no 127.0.0.1 true 2>&1 || true)"
  case "$output" in
    *"Permission denied"*|*"Too many authentication failures"*|*"Host key verification failed"*|*"REMOTE HOST IDENTIFICATION HAS CHANGED"*)
      return 0
      ;;
  esac
  return 1
}

configured_ssh_ports() {
  local file
  for file in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$file" ] || continue
    awk 'tolower($1) == "port" && $2 ~ /^[0-9]+$/ {print $2}' "$file"
  done 2>/dev/null | awk '!seen[$0]++'
}

detect_host_ssh_port() {
  local port
  if [ -n "${HOST_SSH_PORT:-}" ]; then
    return 0
  fi
  for port in $(configured_ssh_ports) 22 2222 2223; do
    case "$port" in
      ''|*[!0-9]*) continue ;;
    esac
    if port_is_ssh "$port"; then
      HOST_SSH_PORT="$port"
      return 0
    fi
  done
  if command -v ss >/dev/null 2>&1; then
    HOST_SSH_PORT="$(ss -ltn 2>/dev/null | awk 'match($4, /:([0-9]+)$/, m) && m[1] ~ /^(22|2222|2223)$/ {print m[1]; exit}')"
  elif command -v netstat >/dev/null 2>&1; then
    HOST_SSH_PORT="$(netstat -ltn 2>/dev/null | awk 'match($4, /:([0-9]+)$/, m) && m[1] ~ /^(22|2222|2223)$/ {print m[1]; exit}')"
  elif command -v lsof >/dev/null 2>&1; then
    HOST_SSH_PORT="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '/sshd/ {sub(/^.*:/, "", $9); print $9; exit}')"
  fi
  HOST_SSH_PORT="${HOST_SSH_PORT:-22}"
}

print_app_values() {
  local host="$1"
  local port="$2"
  cat <<VALUES

[Android app settings]
  SSHホスト: ${host}
  SSHポート: ${port}
  SSHユーザー: ${SSH_USER}
  プロジェクトパス: ${PROJECT_PATH}
  将軍 tmux target: agent:shogun
  エージェント tmux target: shogunate:goza

アプリ側では「設定」→「USB接続」または「無線接続」→「標準値を入力」→「接続診断」の順で確認してください。
VALUES
}

urlencode() {
  local value="${1:-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
  else
    printf '%s' "$value" | sed 's/ /%20/g; s/:/%3A/g; s/\//%2F/g'
  fi
}

setup_uri() {
  local host="$1"
  local port="$2"
  printf 'shogunate://setup?host=%s&port=%s&user=%s&project=%s&shogun=%s&agents=%s' \
    "$(urlencode "$host")" \
    "$(urlencode "$port")" \
    "$(urlencode "$SSH_USER")" \
    "$(urlencode "$PROJECT_PATH")" \
    "$(urlencode "agent:shogun")" \
    "$(urlencode "shogunate:goza")"
}

remote_shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

push_android_settings() {
  local host="$1"
  local port="$2"
  local uri
  uri="$(setup_uri "$host" "$port")"
  if has_adb_device; then
    if "$ADB_BIN" shell "am start -a android.intent.action.VIEW -d $(remote_shell_quote "$uri") -p com.shogun.android" >/dev/null 2>&1; then
      echo "[OK] Android app に接続設定を送信しました。"
      return 0
    fi
    echo "[WARN] Android app への自動設定送信に失敗しました。アプリが未インストールの場合はAPKを入れてから再実行してください。" >&2
  fi
  echo "[Setup URI]"
  echo "  $uri"
}

setup_usb() {
  detect_host_ssh_port
  if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    echo "[ERROR] adb が見つかりません。Android platform-tools を PATH に追加してください。" >&2
    exit 1
  fi
  if ! has_adb_device; then
    echo "[ERROR] USBデバッグ許可済み Android 端末が1台だけ接続されている状態にしてください。" >&2
    "$ADB_BIN" devices || true
    exit 1
  fi
  if ! check_host_ssh_port; then
    echo "[WARN] 127.0.0.1:${HOST_SSH_PORT} にSSH接続できません。ホスト側のSSHサーバーを起動してください。" >&2
  fi

  "$ADB_BIN" reverse --remove "tcp:${ANDROID_USB_PORT}" >/dev/null 2>&1 || true
  "$ADB_BIN" reverse "tcp:${ANDROID_USB_PORT}" "tcp:${HOST_SSH_PORT}" >/dev/null

  echo "[OK] USB reverse を設定しました: Android 127.0.0.1:${ANDROID_USB_PORT} -> host 127.0.0.1:${HOST_SSH_PORT}"
  print_app_values "127.0.0.1" "$ANDROID_USB_PORT"
  push_android_settings "127.0.0.1" "$ANDROID_USB_PORT"
}

print_wireless_candidates() {
  detect_host_ssh_port
  echo "[Wireless SSH candidates]"
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | sed 's/^/  Tailscale: /' || true
  fi

  if [[ "$OS_NAME" == "Darwin" ]]; then
    for iface in en0 en1 en2 bridge100; do
      ipconfig getifaddr "$iface" 2>/dev/null | awk -v iface="$iface" 'NF {print "  " iface ": " $1}'
    done
    if command -v ifconfig >/dev/null 2>&1; then
      ifconfig 2>/dev/null \
        | awk '/^[a-zA-Z0-9]/ {iface=$1; sub(":", "", iface)} /inet / && $2 != "127.0.0.1" {print "  " iface ": " $2}' \
        | sort -u
    fi
  elif command -v hostname >/dev/null 2>&1; then
    hostname -I 2>/dev/null | tr ' ' '\n' | awk 'NF {print "  LAN: " $1}' || true
  fi

  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") print "  Default route: " $(i+1)}' || true
  fi
  print_app_values "<上のIPのいずれか>" "$HOST_SSH_PORT"
  echo
  echo "無線では上のIP候補から1つ選び、必要なら次の URI の host を差し替えてアプリへ取り込めます。"
  echo "  $(setup_uri "<上のIPのいずれか>" "$HOST_SSH_PORT")"
}

case "$MODE" in
  usb) setup_usb ;;
  wireless) print_wireless_candidates ;;
  auto)
    if has_adb_device; then
      setup_usb
    else
      print_wireless_candidates
    fi
    ;;
esac
