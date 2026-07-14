import base64
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "package.json").is_file() and (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.approval.protocol import (
    DEVICE_SIGNATURE_DOMAIN,
    HOST_SIGNATURE_DOMAIN,
    canonical_json_bytes,
    parse_device_decision,
    parse_frozen_request,
    parse_host_envelope,
)
from shogunate_mod.approval.registry import RegistryValidationError


NOW = datetime(2026, 7, 14, 12, 1, tzinfo=timezone.utc)


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def request_value(*, source="ssh", mode="argv", capabilities=None):
    if capabilities is None:
        capabilities = ["execute_unrestricted"]
    return {
        "version": 2,
        "requestId": "request-001",
        "eventId": "event-001",
        "sessionId": "session-001",
        "hostId": "host-001",
        "hostName": "Workstation",
        "source": {"kind": source, "clientId": "client-001"},
        "requiredCapabilities": capabilities,
        "execution": {
            "mode": mode,
            "executable": {
                "path": "/usr/bin/id",
                "device": 8,
                "inode": 123,
                "size": 48144,
                "sha256Base64Url": b64url(b"e" * 32),
            },
            "argvBase64Url": [b64url(b"/usr/bin/id"), b64url(b"-u")],
            "cwd": {"path": "/home/user/project", "device": 8, "inode": 456},
            "runAs": {"uid": 0, "gid": 0, "supplementaryGids": []},
            "environment": {
                "profileId": "root-minimal",
                "profileVersion": 1,
                "sha256Base64Url": b64url(b"v" * 32),
            },
            "timeoutSeconds": 60,
            "outputLimitBytes": 1048576,
        },
        "policy": {"id": "unrestricted-v1", "version": 1},
        "submitterExplanation": "Show the effective user ID",
        "issuedAt": "2026-07-14T12:00:00.000Z",
        "expiresAt": "2026-07-14T12:02:00.000Z",
        "nonce": b64url(b"n" * 24),
    }


def envelope_bytes(request_bytes: bytes, signature=b"h" * 64) -> bytes:
    return canonical_json_bytes(
        {
            "envelopeVersion": 1,
            "algorithm": "Ed25519",
            "keyId": b64url(b"k" * 32),
            "requestBytesBase64": base64.b64encode(request_bytes).decode("ascii"),
            "signatureBase64Url": b64url(signature),
        }
    )


def decision_bytes(host_envelope_bytes: bytes) -> bytes:
    der = bytes.fromhex("3006020101020101")
    return canonical_json_bytes(
        {
            "decisionVersion": 1,
            "decision": "approved",
            "deviceId": "device-001",
            "keyId": b64url(b"d" * 32),
            "hostEnvelopeBytesBase64": base64.b64encode(host_envelope_bytes).decode("ascii"),
            "signedAt": "2026-07-14T12:01:00.000Z",
            "signatureDerBase64": base64.b64encode(der).decode("ascii"),
        }
    )


def test_canonical_request_accepts_exact_frozen_execution():
    raw = canonical_json_bytes(request_value())
    request = parse_frozen_request(raw, now=NOW)

    assert request.request_id == "request-001"
    assert request.required_capabilities == ("execute_unrestricted",)
    assert request.value["execution"]["argvBase64Url"][1] == b64url(b"-u")


def test_request_rejects_unknown_duplicate_and_reordered_fields():
    value = request_value()
    value["unexpected"] = True
    with pytest.raises(RegistryValidationError, match="fields or field order"):
        parse_frozen_request(canonical_json_bytes(value))

    duplicate = canonical_json_bytes(request_value()).replace(
        b'{"version":2,', b'{"version":2,"version":2,', 1
    )
    with pytest.raises(RegistryValidationError, match="duplicate"):
        parse_frozen_request(duplicate)

    value = request_value()
    reordered = {"requestId": value["requestId"], "version": value["version"], **dict(list(value.items())[2:])}
    with pytest.raises(RegistryValidationError, match="field order"):
        parse_frozen_request(canonical_json_bytes(reordered))


def test_request_capability_rules_fail_closed():
    with pytest.raises(RegistryValidationError, match="submit_manual"):
        parse_frozen_request(canonical_json_bytes(request_value(source="app")))

    with pytest.raises(RegistryValidationError, match="execute_shell"):
        parse_frozen_request(canonical_json_bytes(request_value(mode="shell")))

    approved = request_value(
        source="app",
        mode="shell",
        capabilities=["execute_shell", "execute_unrestricted", "submit_manual"],
    )
    assert parse_frozen_request(canonical_json_bytes(approved)).value["execution"]["mode"] == "shell"


def test_request_rejects_expiry_bidi_paths_and_boolean_ids():
    with pytest.raises(RegistryValidationError, match="expired"):
        parse_frozen_request(
            canonical_json_bytes(request_value()),
            now=datetime(2026, 7, 14, 12, 2, tzinfo=timezone.utc),
        )

    value = request_value()
    value["execution"]["cwd"]["path"] = "/safe/\u202eevil"
    with pytest.raises(RegistryValidationError, match="control"):
        parse_frozen_request(canonical_json_bytes(value))

    value = request_value()
    value["execution"]["runAs"]["uid"] = True
    with pytest.raises(RegistryValidationError, match="uid"):
        parse_frozen_request(canonical_json_bytes(value))


def test_host_envelope_verifies_domain_and_exact_request_bytes():
    request_bytes = canonical_json_bytes(request_value())
    raw = envelope_bytes(request_bytes)
    calls = []

    envelope = parse_host_envelope(
        raw,
        now=NOW,
        verify_signature=lambda message, signature: calls.append((message, signature)) is None,
    )

    assert envelope.request.raw == request_bytes
    assert calls == [(HOST_SIGNATURE_DOMAIN + request_bytes, b"h" * 64)]

    with pytest.raises(RegistryValidationError, match="host signature"):
        parse_host_envelope(raw, verify_signature=lambda _message, _signature: False)


def test_device_decision_binds_the_complete_host_envelope():
    request_bytes = canonical_json_bytes(request_value())
    host_bytes = envelope_bytes(request_bytes)
    raw = decision_bytes(host_bytes)
    device_calls = []

    decision = parse_device_decision(
        raw,
        now=NOW,
        verify_host_signature=lambda message, signature: (
            message == HOST_SIGNATURE_DOMAIN + request_bytes and signature == b"h" * 64
        ),
        verify_device_signature=lambda message, signature: device_calls.append((message, signature)) is None,
    )

    assert decision.device_id == "device-001"
    assert decision.host_envelope.request.request_id == "request-001"
    assert device_calls[0][0] == DEVICE_SIGNATURE_DOMAIN + host_bytes
    assert device_calls[0][1] == bytes.fromhex("3006020101020101")


def test_device_decision_rejects_bad_signature_and_signed_time():
    request_bytes = canonical_json_bytes(request_value())
    host_bytes = envelope_bytes(request_bytes)
    raw = decision_bytes(host_bytes)

    with pytest.raises(RegistryValidationError, match="device signature"):
        parse_device_decision(
            raw,
            verify_host_signature=lambda _message, _signature: True,
            verify_device_signature=lambda _message, _signature: False,
        )

    value = json.loads(raw)
    value["signedAt"] = "2026-07-14T12:02:00.000Z"
    with pytest.raises(RegistryValidationError, match="outside"):
        parse_device_decision(
            canonical_json_bytes(value),
            verify_host_signature=lambda _message, _signature: True,
            verify_device_signature=lambda _message, _signature: True,
        )
