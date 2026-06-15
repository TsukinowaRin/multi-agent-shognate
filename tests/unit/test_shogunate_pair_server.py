import base64
import importlib.util
import argparse
import tempfile
import unittest
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
            )
        )

        self.assertEqual(state.port_for_client("127.0.0.1", "127.0.0.1"), 2222)
        self.assertEqual(state.port_for_client("100.71.16.5", "100.71.16.10"), 2223)


if __name__ == "__main__":
    unittest.main()
