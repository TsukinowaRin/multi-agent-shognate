"""Strict wire contract for host-signed, device-approved executions.

This module parses and binds bytes only.  It deliberately receives signature
verification as a callback so a missing crypto backend can never be mistaken
for successful verification.
"""

from __future__ import annotations

import base64
import binascii
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable, Mapping

from .registry import ALL_CAPABILITIES, RegistryValidationError


HOST_SIGNATURE_DOMAIN = b"shogunate-approval-host-v1\n"
DEVICE_SIGNATURE_DOMAIN = b"shogunate-approval-device-v1\n"
MAX_REQUEST_BYTES = 32 * 1024
MAX_ENVELOPE_BYTES = 48 * 1024
MAX_LIFETIME_SECONDS = 120
MAX_ARGV_ENTRIES = 256
MAX_ARG_BYTES = 4096
MAX_OUTPUT_BYTES = 16 * 1024 * 1024

REQUEST_KEYS = (
    "version",
    "requestId",
    "eventId",
    "sessionId",
    "hostId",
    "hostName",
    "source",
    "requiredCapabilities",
    "execution",
    "policy",
    "submitterExplanation",
    "issuedAt",
    "expiresAt",
    "nonce",
)
SOURCE_KEYS = ("kind", "clientId")
EXECUTION_KEYS = (
    "mode",
    "executable",
    "argvBase64Url",
    "cwd",
    "runAs",
    "environment",
    "timeoutSeconds",
    "outputLimitBytes",
)
EXECUTABLE_KEYS = ("path", "device", "inode", "size", "sha256Base64Url")
CWD_KEYS = ("path", "device", "inode")
RUN_AS_KEYS = ("uid", "gid", "supplementaryGids")
ENVIRONMENT_KEYS = ("profileId", "profileVersion", "sha256Base64Url")
POLICY_KEYS = ("id", "version")
ENVELOPE_KEYS = (
    "envelopeVersion",
    "algorithm",
    "keyId",
    "requestBytesBase64",
    "signatureBase64Url",
)
DECISION_KEYS = (
    "decisionVersion",
    "decision",
    "deviceId",
    "keyId",
    "hostEnvelopeBytesBase64",
    "signedAt",
    "signatureDerBase64",
)

_ID_RE = re.compile(r"[A-Za-z0-9._:-]{1,128}")
_UTC_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z")
_BIDI_CONTROLS = frozenset("\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069")

SignatureVerifier = Callable[[bytes, bytes], bool]


@dataclass(frozen=True)
class FrozenRequest:
    raw: bytes
    value: Mapping[str, Any]
    issued_at: datetime
    expires_at: datetime

    @property
    def request_id(self) -> str:
        return str(self.value["requestId"])

    @property
    def nonce(self) -> str:
        return str(self.value["nonce"])

    @property
    def required_capabilities(self) -> tuple[str, ...]:
        return tuple(self.value["requiredCapabilities"])


@dataclass(frozen=True)
class HostEnvelope:
    raw: bytes
    key_id: str
    request: FrozenRequest
    signature: bytes


@dataclass(frozen=True)
class UnverifiedHostEnvelope:
    """Structurally valid envelope whose host signature has not been trusted."""

    raw: bytes
    key_id: str
    request: FrozenRequest
    signature: bytes


@dataclass(frozen=True)
class DeviceDecision:
    raw: bytes
    device_id: str
    key_id: str
    host_envelope: HostEnvelope
    signed_at: datetime
    signature_der: bytes


def canonical_json_bytes(value: Mapping[str, Any]) -> bytes:
    """Serialize a validated mapping using the only accepted JSON encoding."""

    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def parse_frozen_request(raw: bytes, *, now: datetime | None = None) -> FrozenRequest:
    value = _decode_canonical_object(raw, REQUEST_KEYS, "request", MAX_REQUEST_BYTES)
    _expect(value["version"] == 2, "version must be 2")
    for key in ("requestId", "eventId", "sessionId", "hostId"):
        _validate_id(value[key], key)
    _validate_text(value["hostName"], "hostName", 1, 160)

    source = _expect_object(value["source"], SOURCE_KEYS, "source")
    _expect(source["kind"] in {"ai", "app", "ssh", "local"}, "source.kind is invalid")
    _validate_id(source["clientId"], "source.clientId")

    capabilities = value["requiredCapabilities"]
    _expect(isinstance(capabilities, list) and capabilities, "requiredCapabilities must be a non-empty array")
    _expect(
        all(isinstance(item, str) and item in ALL_CAPABILITIES for item in capabilities),
        "requiredCapabilities contains an unknown capability",
    )
    _expect(capabilities == sorted(set(capabilities)), "requiredCapabilities must be unique and sorted")
    if source["kind"] == "app":
        _expect("submit_manual" in capabilities, "app submissions require submit_manual")

    execution = _expect_object(value["execution"], EXECUTION_KEYS, "execution")
    _expect(execution["mode"] in {"argv", "shell"}, "execution.mode is invalid")
    if execution["mode"] == "shell":
        _expect("execute_shell" in capabilities, "shell mode requires execute_shell")

    executable = _expect_object(execution["executable"], EXECUTABLE_KEYS, "execution.executable")
    _validate_absolute_path(executable["path"], "execution.executable.path")
    for key in ("device", "inode", "size"):
        _validate_uint(executable[key], f"execution.executable.{key}", maximum=2**63 - 1)
    _decode_base64url(executable["sha256Base64Url"], "execution.executable.sha256Base64Url", 32, 32)

    argv = execution["argvBase64Url"]
    _expect(isinstance(argv, list) and 1 <= len(argv) <= MAX_ARGV_ENTRIES, "argvBase64Url is invalid")
    decoded_argv = [
        _decode_base64url(item, f"argvBase64Url[{index}]", 0, MAX_ARG_BYTES)
        for index, item in enumerate(argv)
    ]
    _expect(bool(decoded_argv[0]), "argvBase64Url[0] must not be empty")

    cwd = _expect_object(execution["cwd"], CWD_KEYS, "execution.cwd")
    _validate_absolute_path(cwd["path"], "execution.cwd.path")
    _validate_uint(cwd["device"], "execution.cwd.device", maximum=2**63 - 1)
    _validate_uint(cwd["inode"], "execution.cwd.inode", maximum=2**63 - 1)

    run_as = _expect_object(execution["runAs"], RUN_AS_KEYS, "execution.runAs")
    _validate_uint(run_as["uid"], "execution.runAs.uid", maximum=2**31 - 1)
    _validate_uint(run_as["gid"], "execution.runAs.gid", maximum=2**31 - 1)
    groups = run_as["supplementaryGids"]
    _expect(isinstance(groups, list) and len(groups) <= 256, "supplementaryGids is invalid")
    for index, group in enumerate(groups):
        _validate_uint(group, f"supplementaryGids[{index}]", maximum=2**31 - 1)
    _expect(groups == sorted(set(groups)), "supplementaryGids must be unique and sorted")

    environment = _expect_object(execution["environment"], ENVIRONMENT_KEYS, "execution.environment")
    _validate_id(environment["profileId"], "execution.environment.profileId")
    _validate_uint(environment["profileVersion"], "execution.environment.profileVersion", maximum=2**31 - 1)
    _decode_base64url(environment["sha256Base64Url"], "execution.environment.sha256Base64Url", 32, 32)
    _validate_uint(execution["timeoutSeconds"], "execution.timeoutSeconds", minimum=1, maximum=300)
    _validate_uint(
        execution["outputLimitBytes"],
        "execution.outputLimitBytes",
        minimum=1,
        maximum=MAX_OUTPUT_BYTES,
    )

    policy = _expect_object(value["policy"], POLICY_KEYS, "policy")
    _validate_id(policy["id"], "policy.id")
    _validate_uint(policy["version"], "policy.version", minimum=1, maximum=2**31 - 1)
    _validate_text(value["submitterExplanation"], "submitterExplanation", 0, 1000)

    issued_at = _parse_utc(value["issuedAt"], "issuedAt")
    expires_at = _parse_utc(value["expiresAt"], "expiresAt")
    lifetime = (expires_at - issued_at).total_seconds()
    _expect(0 < lifetime <= MAX_LIFETIME_SECONDS, "request lifetime is invalid")
    _decode_base64url(value["nonce"], "nonce", 16, 32)

    request = FrozenRequest(raw=raw, value=value, issued_at=issued_at, expires_at=expires_at)
    if now is not None:
        validate_request_time(request, now)
    return request


def parse_host_envelope(
    raw: bytes,
    *,
    verify_signature: SignatureVerifier,
    now: datetime | None = None,
) -> HostEnvelope:
    unverified = decode_host_envelope_unverified(raw, now=now)
    _expect(
        verify_signature(HOST_SIGNATURE_DOMAIN + unverified.request.raw, unverified.signature) is True,
        "host signature verification failed",
    )
    return HostEnvelope(
        raw=unverified.raw,
        key_id=unverified.key_id,
        request=unverified.request,
        signature=unverified.signature,
    )


def decode_host_envelope_unverified(
    raw: bytes,
    *,
    now: datetime | None = None,
) -> UnverifiedHostEnvelope:
    """Decode an opaque relay payload without making a trust decision."""

    value = _decode_canonical_object(raw, ENVELOPE_KEYS, "host envelope", MAX_ENVELOPE_BYTES)
    _expect(value["envelopeVersion"] == 1, "envelopeVersion must be 1")
    _expect(value["algorithm"] == "Ed25519", "host envelope algorithm must be Ed25519")
    _decode_base64url(value["keyId"], "keyId", 32, 32)
    request_bytes = _decode_base64(value["requestBytesBase64"], "requestBytesBase64", 1, MAX_REQUEST_BYTES)
    signature = _decode_base64url(value["signatureBase64Url"], "signatureBase64Url", 64, 64)
    request = parse_frozen_request(request_bytes, now=now)
    return UnverifiedHostEnvelope(raw=raw, key_id=value["keyId"], request=request, signature=signature)


def parse_device_decision(
    raw: bytes,
    *,
    verify_host_signature: SignatureVerifier,
    verify_device_signature: SignatureVerifier,
    now: datetime | None = None,
) -> DeviceDecision:
    value = _decode_canonical_object(raw, DECISION_KEYS, "device decision", MAX_ENVELOPE_BYTES * 2)
    _expect(value["decisionVersion"] == 1, "decisionVersion must be 1")
    _expect(value["decision"] == "approved", "device decision must be approved")
    _validate_id(value["deviceId"], "deviceId")
    _decode_base64url(value["keyId"], "keyId", 32, 32)
    envelope_bytes = _decode_base64(
        value["hostEnvelopeBytesBase64"],
        "hostEnvelopeBytesBase64",
        1,
        MAX_ENVELOPE_BYTES,
    )
    signature_der = _decode_der_ecdsa(value["signatureDerBase64"])
    _expect(
        verify_device_signature(DEVICE_SIGNATURE_DOMAIN + envelope_bytes, signature_der) is True,
        "device signature verification failed",
    )
    envelope = parse_host_envelope(envelope_bytes, verify_signature=verify_host_signature, now=now)
    signed_at = _parse_utc(value["signedAt"], "signedAt")
    _expect(
        envelope.request.issued_at <= signed_at < envelope.request.expires_at,
        "signedAt is outside the request lifetime",
    )
    if now is not None:
        current = _as_utc(now)
        _expect(signed_at <= current, "signedAt is in the future")
    return DeviceDecision(
        raw=raw,
        device_id=value["deviceId"],
        key_id=value["keyId"],
        host_envelope=envelope,
        signed_at=signed_at,
        signature_der=signature_der,
    )


def validate_request_time(request: FrozenRequest, now: datetime) -> None:
    current = _as_utc(now)
    _expect(request.issued_at <= current, "request was issued in the future")
    _expect(current < request.expires_at, "request has expired")


def _decode_canonical_object(raw: bytes, keys: tuple[str, ...], label: str, maximum: int) -> dict[str, Any]:
    _expect(isinstance(raw, bytes) and 1 <= len(raw) <= maximum, f"{label} size is invalid")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RegistryValidationError(f"{label} must be UTF-8 JSON") from exc
    _expect(isinstance(value, dict), f"{label} must be a JSON object")
    _expect(tuple(value) == keys, f"{label} fields or field order do not match the schema")
    _expect(canonical_json_bytes(value) == raw, f"{label} is not canonical JSON")
    return value


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise RegistryValidationError("JSON contains duplicate keys")
        value[key] = item
    return value


def _expect_object(value: Any, keys: tuple[str, ...], label: str) -> dict[str, Any]:
    _expect(isinstance(value, dict) and tuple(value) == keys, f"{label} fields do not match the schema")
    return value


def _expect(condition: bool, message: str) -> None:
    if not condition:
        raise RegistryValidationError(message)


def _validate_id(value: Any, label: str) -> str:
    _expect(isinstance(value, str) and _ID_RE.fullmatch(value) is not None, f"{label} is invalid")
    return value


def _validate_text(value: Any, label: str, minimum: int, maximum: int) -> str:
    _expect(isinstance(value, str) and minimum <= len(value) <= maximum, f"{label} length is invalid")
    _expect(
        all(ord(character) >= 0x20 and ord(character) != 0x7F and character not in _BIDI_CONTROLS for character in value),
        f"{label} contains unsafe control characters",
    )
    return value


def _validate_absolute_path(value: Any, label: str) -> str:
    path = _validate_text(value, label, 1, 4096)
    _expect(path.startswith("/"), f"{label} must be absolute")
    return path


def _validate_uint(value: Any, label: str, *, minimum: int = 0, maximum: int) -> int:
    _expect(type(value) is int and minimum <= value <= maximum, f"{label} is invalid")
    return value


def _parse_utc(value: Any, label: str) -> datetime:
    _expect(isinstance(value, str) and _UTC_RE.fullmatch(value) is not None, f"{label} is invalid")
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise RegistryValidationError(f"{label} is invalid") from exc
    return parsed


def _as_utc(value: datetime) -> datetime:
    _expect(value.tzinfo is not None, "current time must be timezone-aware")
    return value.astimezone(timezone.utc)


def _decode_base64(value: Any, label: str, minimum: int, maximum: int) -> bytes:
    _expect(isinstance(value, str) and len(value) % 4 == 0, f"{label} must be canonical base64")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RegistryValidationError(f"{label} must be canonical base64") from exc
    _expect(
        minimum <= len(decoded) <= maximum and base64.b64encode(decoded).decode("ascii") == value,
        f"{label} must be canonical base64",
    )
    return decoded


def _decode_base64url(value: Any, label: str, minimum: int, maximum: int) -> bytes:
    _expect(
        isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_-]*", value) is not None,
        f"{label} must be canonical base64url",
    )
    padded = value + "=" * ((4 - len(value) % 4) % 4)
    try:
        decoded = base64.b64decode(padded, altchars=b"-_", validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RegistryValidationError(f"{label} must be canonical base64url") from exc
    canonical = base64.urlsafe_b64encode(decoded).rstrip(b"=").decode("ascii")
    _expect(minimum <= len(decoded) <= maximum and canonical == value, f"{label} must be canonical base64url")
    return decoded


def _decode_der_ecdsa(value: Any) -> bytes:
    signature = _decode_base64(value, "signatureDerBase64", 8, 80)
    _expect(signature[0] == 0x30 and signature[1] == len(signature) - 2, "ECDSA signature is not canonical DER")
    offset = 2
    for _ in range(2):
        _expect(offset + 2 <= len(signature) and signature[offset] == 0x02, "ECDSA signature is invalid")
        length = signature[offset + 1]
        offset += 2
        _expect(1 <= length <= 33 and offset + length <= len(signature), "ECDSA integer is invalid")
        integer = signature[offset : offset + length]
        _expect(not integer[0] & 0x80, "ECDSA integer must be positive")
        _expect(not (length > 1 and integer[0] == 0 and not integer[1] & 0x80), "ECDSA integer is padded")
        offset += length
    _expect(offset == len(signature), "ECDSA signature has trailing data")
    return signature
