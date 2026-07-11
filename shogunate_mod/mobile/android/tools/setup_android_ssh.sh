#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="auto"
ASSUME_YES=0
PAIR_HOST_OVERRIDE="${SHOGUNATE_PAIR_HOST:-}"
ADB_BIN="${ADB:-adb}"
HOST_SSH_PORT="${HOST_SSH_PORT:-}"
ANDROID_USB_PORT="${ANDROID_USB_PORT:-2222}"
SSH_USER="${SSH_USER:-${USER:-}}"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR}"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

usage() {
  cat <<'USAGE'
Usage:
  bash android/tools/setup_android_ssh.sh [--pair|--pair-usb|--pair-wireless|--usb|--wireless|--auto] [--host <dns-url-or-ip>]

Options:
  --pair       Start unified Shogunate Pair.
  --pair-usb   Compatibility alias for --pair. USB is auto-detected.
  --pair-wireless
               Start Shogunate Pair for direct Tailscale/LAN SSH. No USB is
               required after the Android app can reach this host.
  --usb        USB debugging + adb reverse for Android -> host SSH.
  --wireless   Print LAN / Tailscale candidates for manual wireless SSH.
  --host       Kept for compatibility with older helpers. New Shogunate Pair
               reads the destination from the Android app.
  --yes        Kept for compatibility. Shogunate Pair always requires Password approval.
  --auto       Use USB when one adb device is visible; otherwise print wireless info.

Environment:
  ADB=/path/to/adb
  HOST_SSH_PORT=<override auto-detected host SSH port>
  ANDROID_USB_PORT=2222
  SSH_USER=<host ssh user>
  PROJECT_PATH=<remote Shogunate path>
  SHOGUNATE_PAIR_HOST=<dns-url-or-ip>  Same as --host.
  SHOGUNATE_QR=0  Disable terminal QR output.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --usb) MODE="usb"; shift ;;
    --wireless) MODE="wireless"; shift ;;
    --pair|--pair-usb) MODE="pair-usb"; shift ;;
    --pair-wireless) MODE="pair-wireless"; shift ;;
    --host)
      if [ $# -lt 2 ]; then
        echo "[ERROR] --host requires a value" >&2
        usage >&2
        exit 2
      fi
      PAIR_HOST_OVERRIDE="$2"
      shift 2
      ;;
    --yes|-y) ASSUME_YES=1; shift ;;
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

アプリ側では「設定」→「ワンタッチ接続」→「接続診断」で確認してください。
細かく直す場合だけ「マニュアルモード」を開いてください。
VALUES
}

unique_lines() {
  awk 'NF && !seen[$0]++'
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
  local key_path="${3:-}"
  local uri
  uri="$(printf 'shogunate://setup?host=%s&port=%s&user=%s&project=%s&shogun=%s&agents=%s' \
    "$(urlencode "$host")" \
    "$(urlencode "$port")" \
    "$(urlencode "$SSH_USER")" \
    "$(urlencode "$PROJECT_PATH")" \
    "$(urlencode "agent:shogun")" \
    "$(urlencode "shogunate:goza")")"
  if [ -n "$key_path" ]; then
    uri="${uri}&key=$(urlencode "$key_path")"
  fi
  printf '%s' "$uri"
}

print_setup_uri_block() {
  local host="$1"
  local port="$2"
  local key_path="${3:-}"
  local uri
  uri="$(setup_uri "$host" "$port" "$key_path")"
  echo "  ${host}: ${uri}"
}

print_setup_qr() {
  local uri="$1"
  if [ "${SHOGUNATE_QR:-1}" = "0" ] || ! command -v qrencode >/dev/null 2>&1; then
    return 0
  fi
  echo
  echo "[Setup QR]"
  printf '%s' "$uri" | qrencode -t ANSIUTF8
}

normalize_endpoint() {
  local input="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$input" <<'PY'
import sys
from urllib.parse import urlsplit

raw = sys.argv[1].strip()
if not raw:
    raise SystemExit(1)
parsed = urlsplit(raw if "://" in raw else f"ssh://{raw}")
host = parsed.hostname
if not host:
    raise SystemExit(1)
print(host)
print(parsed.port or "")
PY
    return $?
  fi

  local authority host port
  authority="${input#*://}"
  authority="${authority%%/*}"
  authority="${authority%%\?*}"
  authority="${authority%%#*}"
  authority="${authority##*@}"
  host="${authority%%:*}"
  port="${authority#*:}"
  [ "$port" != "$authority" ] || port=""
  host="${host#[}"
  host="${host%]}"
  [ -n "$host" ] || return 1
  printf '%s\n%s\n' "$host" "$port"
}

wireless_candidate_hosts() {
  {
    if command -v tailscale >/dev/null 2>&1; then
      tailscale ip -4 2>/dev/null || true
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "if (Get-Command tailscale -ErrorAction SilentlyContinue) { tailscale ip -4 }" 2>/dev/null \
        | tr -d '\r' || true
    fi

    if [[ "$OS_NAME" == "Darwin" ]]; then
      for iface in en0 en1 en2 bridge100; do
        ipconfig getifaddr "$iface" 2>/dev/null || true
      done
      if command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null \
          | awk '/^[a-zA-Z0-9]/ {iface=$1; sub(":", "", iface)} /inet / && $2 != "127.0.0.1" {print $2}' \
          || true
      fi
    elif command -v hostname >/dev/null 2>&1; then
      hostname -I 2>/dev/null | tr ' ' '\n' || true
    fi

    if command -v ip >/dev/null 2>&1; then
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") print $(i+1)}' || true
    fi
  } | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0 != "127.0.0.1"' | unique_lines
}

android_ipv4_addresses() {
  "$ADB_BIN" shell ip -4 addr show scope global 2>/dev/null \
    | tr -d '\r' \
    | sed -n 's/.*inet \([0-9][0-9.]*\)\/.*/\1/p' \
    | unique_lines
}

select_wireless_host() {
  local candidates="$1"
  local android_ips candidate android_ip

  android_ips="$(android_ipv4_addresses || true)"

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    while IFS= read -r android_ip; do
      [ -n "$android_ip" ] || continue
      if [ "$(printf '%s' "$candidate" | cut -d. -f1-3)" = "$(printf '%s' "$android_ip" | cut -d. -f1-3)" ]; then
        printf '%s' "$candidate"
        return 0
      fi
    done <<ANDROID_IPS
$android_ips
ANDROID_IPS
  done <<CANDIDATES
$candidates
CANDIDATES

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    case "$candidate" in
      100.*)
        while IFS= read -r android_ip; do
          case "$android_ip" in
            100.*)
              printf '%s' "$candidate"
              return 0
              ;;
          esac
        done <<ANDROID_IPS
$android_ips
ANDROID_IPS
        ;;
    esac
  done <<CANDIDATES
$candidates
CANDIDATES

  printf '%s\n' "$candidates" | head -n 1
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

adb_single_device_serial() {
  "$ADB_BIN" devices 2>/dev/null | tr -d '\r' | awk '$2 == "device" {print $1}'
}

require_usb_device() {
  if ! command -v "$ADB_BIN" >/dev/null 2>&1; then
    echo "[ERROR] adb が見つかりません。Android platform-tools を PATH に追加してください。" >&2
    exit 1
  fi
  if ! has_adb_device; then
    echo "[ERROR] USBデバッグ許可済み Android 端末が1台だけ接続されている状態にしてください。" >&2
    "$ADB_BIN" devices || true
    exit 1
  fi
}

confirm_pairing() {
  if [ "$ASSUME_YES" = "1" ]; then
    return 0
  fi
  cat <<CONFIRM

[PAIRING]
この操作は次を行います。
  1. Android app が自分の専用SSH鍵を app 内に作成または再利用
  2. 公開鍵を ${HOME}/.ssh/authorized_keys に追加
  3. Android app に接続設定を送信

秘密鍵はPCへ取り出しません。公開鍵だけをPCへ登録します。
古いdebug APKでは fallback としてPC生成鍵を app 専用領域へ転送します。
続行しますか？ [y/N]
CONFIRM
  local answer
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) echo "[CANCEL] pairing を中止しました。"; exit 1 ;;
  esac
}

install_public_key() {
  local public_key_file="$1"
  install_public_key_line "$(cat "$public_key_file")"
}

install_public_key_line() {
  local public_key="$1"
  local authorized_keys="${HOME}/.ssh/authorized_keys"
  install -d -m 700 "${HOME}/.ssh"
  touch "$authorized_keys"
  chmod 600 "$authorized_keys"
  if grep -qxF "$public_key" "$authorized_keys"; then
    echo "[OK] 公開鍵は既に authorized_keys に登録済みです。"
  else
    printf '%s\n' "$public_key" >> "$authorized_keys"
    echo "[OK] 公開鍵を authorized_keys に追加しました。"
  fi
}

query_android_pairing_profile() {
  local output
  output="$("$ADB_BIN" shell content query --uri content://com.shogun.android.pairing/profile 2>/dev/null | tr -d '\r' || true)"
  ANDROID_PAIR_PUBLIC_KEY="$(printf '%s\n' "$output" | sed -n 's/.*public_key=\(ssh-rsa [^,]*\), key_path=.*/\1/p' | head -n 1)"
  ANDROID_PAIR_KEY_PATH="$(printf '%s\n' "$output" | sed -n 's/.*key_path=\([^,]*\), device_label=.*/\1/p' | head -n 1)"
  ANDROID_PAIR_DEVICE_LABEL="$(printf '%s\n' "$output" | sed -n 's/.*device_label=\([^,]*\).*/\1/p' | head -n 1)"
  [ -n "$ANDROID_PAIR_PUBLIC_KEY" ] && [ -n "$ANDROID_PAIR_KEY_PATH" ]
}

send_key_setup_to_android() {
  local host="$1"
  local port="$2"
  local key_path="$3"
  local uri
  uri="$(setup_uri "$host" "$port" "$key_path")"
  if "$ADB_BIN" shell "am start -a android.intent.action.VIEW -d $(remote_shell_quote "$uri") -p com.shogun.android" >/dev/null 2>&1; then
    echo "[OK] Android app に鍵認証つき接続設定を送信しました。"
  else
    echo "[WARN] Android app への自動設定送信に失敗しました。次の URI をアプリ設定画面で取り込んでください。" >&2
    echo "  $uri"
  fi
}

push_private_key_to_app() {
  local key_file="$1"
  local key_name="$2"
  local serial="$3"
  local app_home tmp_remote app_key_path
  app_home="$("$ADB_BIN" shell run-as com.shogun.android pwd 2>/dev/null | tr -d '\r')"
  if [ -z "$app_home" ]; then
    echo "[ERROR] Android app の run-as に失敗しました。debug APK をインストールしてから再実行してください。" >&2
    exit 1
  fi
  tmp_remote="/data/local/tmp/shogunate_${serial}_${key_name}"
  app_key_path="${app_home}/files/ssh_keys/${key_name}"

  "$ADB_BIN" push "$key_file" "$tmp_remote" >/dev/null 2>&1
  "$ADB_BIN" shell "cat '$tmp_remote' | run-as com.shogun.android sh -c 'mkdir -p files/ssh_keys && cat > files/ssh_keys/$key_name && chmod 600 files/ssh_keys/$key_name'" >/dev/null
  "$ADB_BIN" shell "rm -f '$tmp_remote'" >/dev/null 2>&1 || true
  echo "$app_key_path"
}

pair_usb() {
  detect_host_ssh_port
  echo "[PAIRING] Android app で USB を選ぶか Tailscale/LAN IP を入力し、接続を押してください。"
  echo "[PAIRING] USB が接続されていれば自動で adb reverse を設定します。"
  echo "[PAIRING] PC 側に表示される端末名を確認し、Password を入力すると公開鍵が登録されます。"
  exec python3 "$ROOT_DIR/shogunate_mod/pair/server.py" \
    --adb "$ADB_BIN" \
    --ssh-port "$HOST_SSH_PORT" \
    --usb-ssh-port "$ANDROID_USB_PORT" \
    --project-root "$PROJECT_PATH" \
    --user "$SSH_USER"
}

pair_wireless() {
  detect_host_ssh_port
  local candidates
  candidates="$(wireless_candidate_hosts)"
  echo "[Wireless pairing candidates]"
  if [ -n "$candidates" ]; then
    printf '%s\n' "$candidates" | sed 's/^/  /'
  else
    echo "  IP候補を自動検出できませんでした。Tailscale/LAN IP を Android app に手入力してください。"
  fi
  echo
  echo "[PAIRING] Android app で Tailscale/LAN IP を入力し、接続を押してください。"
  echo "[PAIRING] PC 側に表示される端末名を確認し、Password を入力すると公開鍵が登録されます。"
  exec python3 "$ROOT_DIR/shogunate_mod/pair/server.py" \
    --ssh-port "$HOST_SSH_PORT" \
    --project-root "$PROJECT_PATH" \
    --user "$SSH_USER"
}

print_wireless_candidates() {
  detect_host_ssh_port
  local candidates first_host first_uri
  echo "[Wireless SSH candidates]"
  if command -v tailscale >/dev/null 2>&1; then
    tailscale ip -4 2>/dev/null | sed 's/^/  Tailscale: /' || true
  fi

  candidates="$(wireless_candidate_hosts)"

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
    hostname -I 2>/dev/null | tr ' ' '\n' | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print "  LAN: " $1}' || true
  fi

  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") print "  Default route: " $(i+1)}' || true
  fi
  print_app_values "<上のIPのいずれか>" "$HOST_SSH_PORT"
  echo
  echo "[Setup URI candidates]"
  if [ -n "$candidates" ]; then
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ -z "${first_host:-}" ]; then
        first_host="$candidate"
      fi
      print_setup_uri_block "$candidate" "$HOST_SSH_PORT"
    done <<CANDIDATES
$candidates
CANDIDATES
    first_uri="$(setup_uri "$first_host" "$HOST_SSH_PORT")"
    print_setup_qr "$first_uri"
  else
    echo "  IP候補を自動検出できませんでした。Android app の設定画面で host を手入力してください。"
    echo "  $(setup_uri "<host>" "$HOST_SSH_PORT")"
  fi
}

case "$MODE" in
  usb) setup_usb ;;
  wireless) print_wireless_candidates ;;
  pair-usb) pair_usb ;;
  pair-wireless) pair_wireless ;;
  auto)
    if has_adb_device; then
      setup_usb
    else
      print_wireless_candidates
    fi
    ;;
esac
