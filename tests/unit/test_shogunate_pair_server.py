import base64
import importlib.util
import argparse
import json
import socket
import threading
import tempfile
import unittest
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "shogunate_pair_server.py"

spec = importlib.util.spec_from_file_location("shogunate_pair_server", SCRIPT)
pair_server = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(pair_server)


def sample_key(comment: str = "shogunate-test") -> str:
    blob = b"\x00\x00\x00\x07ssh-rsa\x00\x00\x00\x03\x01\x00\x01\x00\x00\x00\x01\x01"
    encoded = base64.b64encode(blob).decode("ascii")
    return f"ssh-rsa {encoded} {comment}"


class OneShotServer:
    def __init__(self, payload: bytes) -> None:
        self.payload = payload
        self.ready = threading.Event()
        self.done = threading.Event()
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.bind(("127.0.0.1", 0))
        self.socket.listen(1)
        self.port = self.socket.getsockname()[1]
        self.thread = threading.Thread(target=self._serve, daemon=True)

    def __enter__(self) -> "OneShotServer":
        self.thread.start()
        self.ready.wait(timeout=2)
        return self

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        try:
            self.done.wait(timeout=2)
        finally:
            self.socket.close()

    def _serve(self) -> None:
        self.ready.set()
        try:
            conn, _addr = self.socket.accept()
            with conn:
                if self.payload:
                    conn.sendall(self.payload)
        finally:
            self.done.set()
            self.socket.close()


class ShogunatePairServerTests(unittest.TestCase):
    def test_fingerprint_uses_openssh_sha256_format(self):
        fingerprint = pair_server.ssh_fingerprint(sample_key())

        self.assertTrue(fingerprint.startswith("SHA256:"))
        self.assertNotIn("=", fingerprint)

    def test_rejects_invalid_public_key(self):
        with self.assertRaises(ValueError):
            pair_server.normalize_public_key("not-a-key")

        with self.assertRaises(ValueError):
            pair_server.normalize_public_key("ssh-rsa !!! bad")

    def test_append_authorized_key_deduplicates(self):
        with tempfile.TemporaryDirectory() as tmp:
            authorized_keys = Path(tmp) / ".ssh" / "authorized_keys"
            key = sample_key()

            first = pair_server.append_authorized_key(key, authorized_keys)
            second = pair_server.append_authorized_key(key, authorized_keys)

            self.assertTrue(first)
            self.assertFalse(second)
            lines = authorized_keys.read_text(encoding="utf-8").splitlines()
            self.assertEqual(lines, [key])
            self.assertEqual(authorized_keys.stat().st_mode & 0o777, 0o600)
            self.assertEqual(authorized_keys.parent.stat().st_mode & 0o777, 0o700)

    def test_client_port_switches_between_usb_and_wireless(self):
        state = pair_server.PairingState(
            argparse.Namespace(
                host="0.0.0.0",
                port=8765,
                ssh_port=2223,
                client_ssh_port=None,
                usb_ready=True,
                adb="adb",
                usb_ssh_port=2222,
                project_root=str(ROOT),
                user="muro",
                shogun_target="agent:shogun",
                agents_target="shogunate:goza",
                authorized_keys="/tmp/authorized_keys",
                no_start_runtime=True,
                pair_password="",
                keep_running=False,
            )
        )

        self.assertEqual(state.port_for_client("127.0.0.1", "127.0.0.1"), 2222)
        self.assertEqual(state.port_for_client("100.71.16.5", "100.71.16.10"), 2223)

    def test_wireless_client_port_prefers_reachable_host_banner(self):
        state = pair_server.PairingState(
            argparse.Namespace(
                host="0.0.0.0",
                port=8765,
                ssh_port=22,
                client_ssh_port=None,
                usb_ready=True,
                adb="adb",
                usb_ssh_port=2222,
                project_root=str(ROOT),
                user="muro",
                shogun_target="agent:shogun",
                agents_target="shogunate:goza",
                authorized_keys="/tmp/authorized_keys",
                no_start_runtime=True,
                pair_password="",
                keep_running=False,
            )
        )
        original = pair_server.is_ssh_service
        try:
            pair_server.is_ssh_service = lambda host, port, timeout=0.75: host == "100.71.16.5" and port == 2223

            self.assertEqual(state.port_for_client("100.71.16.5", "100.113.76.83"), 2223)
        finally:
            pair_server.is_ssh_service = original

    def test_pairing_state_stops_after_one_success_by_default(self):
        state = pair_server.PairingState(
            argparse.Namespace(
                host="0.0.0.0",
                port=8765,
                ssh_port=2223,
                client_ssh_port=None,
                usb_ready=False,
                adb="adb",
                usb_ssh_port=2222,
                project_root=str(ROOT),
                user="muro",
                shogun_target="agent:shogun",
                agents_target="shogunate:goza",
                authorized_keys="/tmp/authorized_keys",
                no_start_runtime=True,
                pair_password="",
                keep_running=False,
            )
        )

        self.assertFalse(state.keep_running)
        self.assertFalse(state.completed)

    def test_pair_server_stops_after_success_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = pair_server.PairingState(
                argparse.Namespace(
                    host="127.0.0.1",
                    port=0,
                    ssh_port=2223,
                    client_ssh_port=2223,
                    usb_ready=False,
                    adb="adb",
                    usb_ssh_port=2222,
                    project_root=str(ROOT),
                    user="muro",
                    shogun_target="agent:shogun",
                    agents_target="shogunate:goza",
                    authorized_keys=str(Path(tmp) / ".ssh" / "authorized_keys"),
                    no_start_runtime=True,
                    pair_password="",
                    keep_running=False,
                )
            )
            server = pair_server.ThreadedPairingServer(("127.0.0.1", 0), pair_server.PairingHandler)
            server.pairing_state = state
            thread = threading.Thread(target=server.serve_forever)
            original_getpass = pair_server.getpass.getpass
            try:
                pair_server.getpass.getpass = lambda _prompt: "approve"
                thread.start()
                body = json.dumps(
                    {
                        "public_key": sample_key("android-test"),
                        "key_path": "/data/user/0/com.shogun.android/files/key.pem",
                        "device_label": "Test Phone",
                        "host": "127.0.0.1",
                    }
                ).encode("utf-8")
                request = urllib.request.Request(
                    f"http://127.0.0.1:{server.server_address[1]}/pair",
                    data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )

                with urllib.request.urlopen(request, timeout=5) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                thread.join(timeout=5)
            finally:
                pair_server.getpass.getpass = original_getpass
                server.server_close()

            self.assertTrue(payload["ok"])
            self.assertEqual(payload["device_label"], "Test Phone")
            self.assertTrue(state.completed)
            self.assertFalse(thread.is_alive())

    def test_detect_ssh_port_requires_ssh_banner(self):
        with OneShotServer(b"") as stale_proxy, OneShotServer(b"SSH-2.0-shogunate-test\r\n") as ssh:
            detected = pair_server.detect_ssh_port(candidates=(stale_proxy.port, ssh.port))

        self.assertEqual(detected, ssh.port)


if __name__ == "__main__":
    unittest.main()
