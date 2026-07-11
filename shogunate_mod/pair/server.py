#!/usr/bin/env python3
"""Temporary pairing server for Shogunate Android clients."""

from __future__ import annotations

import argparse
import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import getpass
import shutil
import socket
import socketserver
import stat
import subprocess
import sys
import threading
from typing import Any


ALLOWED_KEY_TYPES = {
    "ssh-rsa",
    "ssh-ed25519",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def parse_public_key(public_key: str) -> tuple[str, bytes, str]:
    parts = public_key.strip().split()
    if len(parts) < 2:
        raise ValueError("public_key must be an OpenSSH authorized_keys line")
    key_type = parts[0]
    if key_type not in ALLOWED_KEY_TYPES:
        raise ValueError(f"unsupported key type: {key_type}")
    try:
        blob = base64.b64decode(parts[1].encode("ascii"), validate=True)
    except Exception as exc:  # noqa: BLE001 - keep user-facing validation concise.
        raise ValueError("public_key is not valid base64") from exc
    if not blob:
        raise ValueError("public_key blob is empty")
    comment = " ".join(parts[2:])
    return key_type, blob, comment


def ssh_fingerprint(public_key: str) -> str:
    _key_type, blob, _comment = parse_public_key(public_key)
    digest = hashlib.sha256(blob).digest()
    return "SHA256:" + base64.b64encode(digest).decode("ascii").rstrip("=")


def normalize_public_key(public_key: str) -> str:
    key_type, blob, comment = parse_public_key(public_key)
    encoded = base64.b64encode(blob).decode("ascii")
    if comment:
        return f"{key_type} {encoded} {comment}"
    return f"{key_type} {encoded}"


def append_authorized_key(public_key: str, authorized_keys: Path) -> bool:
    normalized = normalize_public_key(public_key)
    authorized_keys.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(authorized_keys.parent, 0o700)
    existing = ""
    if authorized_keys.exists():
        existing = authorized_keys.read_text(encoding="utf-8", errors="replace")
        for line in existing.splitlines():
            if line.strip() == normalized:
                os.chmod(authorized_keys, 0o600)
                return False
    prefix = "" if not existing or existing.endswith("\n") else "\n"
    with authorized_keys.open("a", encoding="utf-8") as file:
        file.write(f"{prefix}{normalized}\n")
    os.chmod(authorized_keys, stat.S_IRUSR | stat.S_IWUSR)
    return True


def is_ssh_service(host: str, port: int, timeout: float = 0.75) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            banner = sock.recv(32)
    except OSError:
        return False
    return banner.startswith(b"SSH-")


def detect_ssh_port(candidates: tuple[int, ...] = (22, 2222, 2223)) -> int:
    env_value = os.environ.get("HOST_SSH_PORT")
    if env_value and env_value.isdigit():
        return int(env_value)
    for port in candidates:
        if is_ssh_service("127.0.0.1", port):
            return port
    return candidates[0] if candidates else 22


def env_int(name: str, default: int | None = None) -> int | None:
    value = os.environ.get(name, "")
    if not value:
        return default
    if not value.isdigit():
        raise ValueError(f"{name} must be an integer")
    return int(value)


def find_adb(adb: str) -> str:
    if "/" in adb or "\\" in adb:
        return adb
    return shutil.which(adb) or adb


def active_adb_devices(devices_stdout: str) -> list[str]:
    devices: list[str] = []
    for line in devices_stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] == "device":
            devices.append(fields[0])
    return devices


def is_wireless_adb_serial(serial: str) -> bool:
    return serial.startswith("adb-") or "._adb-tls-connect._tcp" in serial


def select_usb_adb_device(devices: list[str]) -> str:
    if len(devices) == 1:
        return devices[0]
    usb_candidates = [serial for serial in devices if not is_wireless_adb_serial(serial)]
    if len(usb_candidates) == 1:
        return usb_candidates[0]
    raise RuntimeError("USB debugging must show exactly one authorized Android device")


def setup_usb_reverse(adb: str, pair_port: int, usb_ssh_port: int, host_ssh_port: int) -> None:
    adb_bin = find_adb(adb)
    devices = subprocess.run(
        [adb_bin, "devices", "-l"],
        check=False,
        capture_output=True,
        text=True,
    )
    if devices.returncode != 0:
        raise RuntimeError("adb devices failed; install adb and allow USB debugging")
    selected = select_usb_adb_device(active_adb_devices(devices.stdout))
    adb_target = [adb_bin, "-s", selected]
    subprocess.run([*adb_target, "reverse", "--remove", f"tcp:{pair_port}"], check=False)
    subprocess.run([*adb_target, "reverse", "--remove", f"tcp:{usb_ssh_port}"], check=False)
    subprocess.run([*adb_target, "reverse", f"tcp:{pair_port}", f"tcp:{pair_port}"], check=True)
    subprocess.run([*adb_target, "reverse", f"tcp:{usb_ssh_port}", f"tcp:{host_ssh_port}"], check=True)


def is_loopback_host(host: str, source: str) -> bool:
    normalized = host.strip().lower().strip("[]")
    return normalized in {"127.0.0.1", "localhost", "::1"} or source.startswith("127.") or source == "::1"


def start_runtime(project_root: Path, target_project: Path) -> tuple[bool, str]:
    runtime = project_root / "shogunate_mod" / "runtime" / "runtime_launcher.sh"
    if not runtime.is_file():
        return False, "shogunate_mod/runtime/runtime_launcher.sh not found"
    env = os.environ.copy()
    env["SHOGUNATE_PROJECT_DIR"] = str(target_project)
    try:
        subprocess.Popen(
            ["bash", str(runtime), "--resume", "--no-attach"],
            cwd=str(project_root),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        return False, str(exc)
    return True, "started"


def json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


class PairingState:
    def __init__(self, args: argparse.Namespace) -> None:
        self.host = args.host
        self.port = args.port
        self.host_ssh_port = args.ssh_port
        self.client_ssh_port = args.client_ssh_port
        self.usb_ready = args.usb_ready
        self.adb = args.adb
        self.usb_ssh_port = args.usb_ssh_port
        self.project_root = Path(args.project_root).expanduser().resolve()
        self.target_project = Path(args.target_project).expanduser().resolve()
        self.user = args.user
        self.shogun_target = args.shogun_target
        self.agents_target = args.agents_target
        self.authorized_keys = Path(args.authorized_keys).expanduser()
        self.start_runtime = not args.no_start_runtime
        self.pair_password = args.pair_password
        self.keep_running = args.keep_running
        self.completed = False
        self.prompt_lock = threading.Lock()

    def client_port_candidates(self) -> list[int]:
        candidates = [
            self.client_ssh_port,
            self.host_ssh_port,
            22,
            2222,
            2223,
            22220,
        ]
        result: list[int] = []
        for candidate in candidates:
            if candidate and candidate not in result:
                result.append(candidate)
        return result

    def port_for_client(self, requested_host: str, source: str) -> int:
        if self.client_ssh_port:
            return self.client_ssh_port
        if self.usb_ready and is_loopback_host(requested_host, source):
            return self.usb_ssh_port
        normalized_host = requested_host.strip().strip("[]")
        if normalized_host:
            for port in self.client_port_candidates():
                if is_ssh_service(normalized_host, port):
                    return port
        return self.host_ssh_port


class PairingHandler(http.server.BaseHTTPRequestHandler):
    server_version = "ShogunatePair/1.0"

    def do_GET(self) -> None:  # noqa: N802 - http.server API.
        if self.path != "/health":
            self.respond(404, {"ok": False, "error": "not found"})
            return
        state = self.pairing_state
        self.respond(
            200,
            {
                "ok": True,
                "service": "shogunate-pair",
                "ssh_port": state.host_ssh_port,
                "host_ssh_port": state.host_ssh_port,
                "usb_ssh_port": state.usb_ssh_port,
                "user": state.user,
                "project": str(state.project_root),
                "target_project": str(state.target_project),
                "pair_port": state.port,
                "usb_ready": state.usb_ready,
            },
        )

    def do_POST(self) -> None:  # noqa: N802 - http.server API.
        if self.path != "/pair":
            self.respond(404, {"ok": False, "error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length)
            payload = json.loads(raw_body.decode("utf-8"))
            response = self.handle_pair(payload)
        except ValueError as exc:
            self.respond(400, {"ok": False, "error": str(exc)})
            return
        except json.JSONDecodeError:
            self.respond(400, {"ok": False, "error": "request body must be JSON"})
            return
        except Exception as exc:  # noqa: BLE001 - keep server alive after one bad request.
            self.respond(500, {"ok": False, "error": str(exc)})
            return
        self.respond(200, response)
        if response.get("ok") and not self.pairing_state.keep_running:
            self.pairing_state.completed = True
            print("", flush=True)
            print("Pairing complete.", flush=True)
            print(f"  Device: {response.get('device_label', 'Android')}", flush=True)
            print(
                "  Android SSH: "
                f"{response.get('user', '')}@{response.get('host', '')}:{response.get('port', '')}",
                flush=True,
            )
            print("You can now use the Android app. Shogunate Pair will stop automatically.", flush=True)
            print("To pair another device later, run: shogunate pair", flush=True)
            threading.Thread(target=self.server.shutdown, daemon=True).start()

    def handle_pair(self, payload: dict[str, Any]) -> dict[str, Any]:
        state = self.pairing_state
        public_key = str(payload.get("public_key", "")).strip()
        if not public_key:
            raise ValueError("public_key is required")
        normalized_key = normalize_public_key(public_key)
        fingerprint = ssh_fingerprint(normalized_key)
        device_label = str(payload.get("device_label", "android")).strip() or "android"
        requested_host = str(payload.get("host", "")).strip()
        key_path = str(payload.get("key_path", "")).strip()
        source = self.client_address[0]

        with state.prompt_lock:
            print("", flush=True)
            print("Shogunate pairing request", flush=True)
            print(f"  device:      {device_label}", flush=True)
            print(f"  source:      {source}", flush=True)
            print(f"  host:        {requested_host or source}", flush=True)
            print(f"  fingerprint: {fingerprint}", flush=True)
            if state.pair_password:
                print("Approve this device by entering the Shogunate Pair Password.", flush=True)
            else:
                print("Approve this device by entering a non-empty local Password. Blank denies.", flush=True)
                print("Set SHOGUNATE_PAIR_PASSWORD to require a fixed approval password.", flush=True)
            answer = getpass.getpass("Password: ").strip()
            if not answer:
                return {"ok": False, "error": "pairing denied"}
            if state.pair_password and answer != state.pair_password:
                return {"ok": False, "error": "pairing password mismatch"}

        added = append_authorized_key(normalized_key, state.authorized_keys)
        runtime_started = False
        runtime_message = "skipped"
        if state.start_runtime:
            runtime_started, runtime_message = start_runtime(state.project_root, state.target_project)

        client_host = requested_host or source
        client_port = state.port_for_client(requested_host, source)
        print(
            f"Paired {device_label}; returning SSH destination: "
            f"{state.user}@{client_host}:{client_port}",
            flush=True,
        )
        if runtime_message != "started":
            print(f"Runtime start: {runtime_message}", flush=True)
        if not is_loopback_host(client_host, source) and not is_ssh_service(client_host, client_port):
            print(
                f"[WARN] {client_host}:{client_port} did not return an SSH banner from this host. "
                "If Android SSH fails, use USB/127.0.0.1 or set --client-ssh-port to a reachable forwarding port.",
                flush=True,
            )

        return {
            "ok": True,
            "message": "paired",
            "host": client_host,
            "port": str(client_port),
            "user": state.user,
            "project": str(state.project_root),
            "target_project": str(state.target_project),
            "shogun": state.shogun_target,
            "agents": state.agents_target,
            "key_path": key_path,
            "fingerprint": fingerprint,
            "device_label": device_label,
            "already_authorized": not added,
            "runtime_started": runtime_started,
            "runtime_message": runtime_message,
        }

    def respond(self, status: int, payload: dict[str, Any]) -> None:
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def pairing_state(self) -> PairingState:
        return self.server.pairing_state  # type: ignore[attr-defined]

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"[shogunate-pair] {self.address_string()} - {fmt % args}", flush=True)


class ThreadedPairingServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    pairing_state: PairingState


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Shogunate Android pairing server.")
    default_session = os.environ.get("GOZA_SESSION_NAME") or os.environ.get("SHOGUNATE_SESSION_NAME") or "shogunate"
    parser.add_argument("--host", default=os.environ.get("SHOGUNATE_PAIR_HOST", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("SHOGUNATE_PAIR_PORT", "8765")))
    parser.add_argument(
        "--ssh-port",
        type=int,
        default=detect_ssh_port(),
        help="Local SSH port on this computer/WSL. Auto-detected by SSH banner unless HOST_SSH_PORT is set.",
    )
    parser.add_argument(
        "--client-ssh-port",
        type=int,
        default=env_int("SHOGUNATE_CLIENT_SSH_PORT"),
        help="SSH port returned to wireless clients. Defaults to --ssh-port.",
    )
    parser.add_argument("--no-usb", action="store_true", help="Do not auto-configure adb reverse; wireless/LAN only.")
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"))
    parser.add_argument("--usb-ssh-port", type=int, default=int(os.environ.get("ANDROID_USB_PORT", "2222")))
    parser.add_argument("--project-root", default=str(repo_root()))
    parser.add_argument(
        "--target-project",
        default=os.environ.get("SHOGUNATE_PROJECT_DIR") or str(repo_root()),
        help="User project directory targeted by this Shogunate runtime.",
    )
    parser.add_argument("--user", default=os.environ.get("SSH_USER") or os.environ.get("USER") or "")
    parser.add_argument("--shogun-target", default=f"{default_session}:goza.0")
    parser.add_argument("--agents-target", default=f"{default_session}:goza")
    parser.add_argument("--authorized-keys", default=str(Path.home() / ".ssh" / "authorized_keys"))
    parser.add_argument("--pair-password", default=os.environ.get("SHOGUNATE_PAIR_PASSWORD", ""))
    parser.add_argument("--no-start-runtime", action="store_true")
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Keep the pairing server open after one successful device pairing.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if not args.user:
        print("ERROR: --user is required when SSH_USER/USER is empty", file=sys.stderr)
        return 64
    args.usb_ready = False
    if not args.no_usb:
        try:
            setup_usb_reverse(args.adb, args.port, args.usb_ssh_port, args.ssh_port)
            args.usb_ready = True
        except Exception as exc:  # noqa: BLE001 - USB is optional; wireless remains available.
            print(f"[WARN] USB pairing not ready: {exc}", flush=True)
            print("[WARN] Wireless/Tailscale pairing remains available.", flush=True)
    state = PairingState(args)
    server = ThreadedPairingServer((state.host, state.port), PairingHandler)
    server.pairing_state = state
    print(f"Shogunate pair listening on {state.host}:{state.port}", flush=True)
    if is_ssh_service("127.0.0.1", state.host_ssh_port):
        print(f"Detected local SSH service: 127.0.0.1:{state.host_ssh_port}", flush=True)
    else:
        print(
            f"[WARN] 127.0.0.1:{state.host_ssh_port} did not return an SSH banner. "
            "Pair can approve the key, but Android SSH may fail until sshd/port forwarding is fixed.",
            flush=True,
        )
    wireless_port = state.client_ssh_port or state.host_ssh_port
    print(f"Wireless SSH destination: {state.user}@<host>:{wireless_port}", flush=True)
    if state.usb_ready:
        print(
            f"USB reverse: Android 127.0.0.1:{state.port} -> pair, "
            f"127.0.0.1:{state.usb_ssh_port} -> SSH {state.host_ssh_port}",
            flush=True,
        )
    elif not args.no_usb:
        print("USB reverse: not ready. Connect over Tailscale/LAN, or plug in USB and restart pair.", flush=True)
    print(f"Project: {state.project_root}", flush=True)
    print(f"Target project: {state.target_project}", flush=True)
    if state.pair_password:
        print("Approval: fixed Shogunate Pair Password from SHOGUNATE_PAIR_PASSWORD/--pair-password.", flush=True)
    else:
        print("Approval: local Password prompt. Any non-empty input approves after checking the device name.", flush=True)
    print("Press Connect in the Android app. This will stop automatically after one successful pair.", flush=True)
    print("Use --keep-running only when pairing multiple devices.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShogunate pair stopped.", flush=True)
    finally:
        server.server_close()
    if state.completed:
        print("Shogunate pair stopped after successful setup.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
