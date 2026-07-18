"""Strict, host-owned registry for mobile approval devices.

The registry is deliberately independent from the app bridge.  A phone or the
relay may present enrollment material, but only a local privileged management
boundary is allowed to commit capability changes to this file.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
import re
import secrets
import stat
from dataclasses import dataclass, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Literal, TypeVar

try:
    import fcntl
except ImportError:  # Windows support is a separate plan; keep package imports safe there.
    fcntl = None  # type: ignore[assignment]


REGISTRY_SCHEMA_VERSION = 1
MAX_REGISTRY_BYTES = 1024 * 1024
T = TypeVar("T")

ApprovalCapability = Literal[
    "approve_pending",
    "submit_manual",
    "execute_unrestricted",
    "execute_shell",
]
ALL_CAPABILITIES: frozenset[str] = frozenset(
    {
        "approve_pending",
        "submit_manual",
        "execute_unrestricted",
        "execute_shell",
    }
)

DeviceState = Literal["active", "suspended", "revoked"]
ALL_STATES = frozenset({"active", "suspended", "revoked"})
ALL_SECURITY_LEVELS = frozenset({"STRONGBOX", "TEE"})
ALL_ATTESTATION_STATUSES = frozenset({"unverified", "verified"})

_DEVICE_ID_RE = re.compile(r"[A-Za-z0-9._:-]{1,128}")
_UTC_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z")
_BIDI_CONTROLS = frozenset(
    {
        "\u200e",
        "\u200f",
        "\u202a",
        "\u202b",
        "\u202c",
        "\u202d",
        "\u202e",
        "\u2066",
        "\u2067",
        "\u2068",
        "\u2069",
    }
)


class RegistryValidationError(ValueError):
    """Registry data is malformed or outside the accepted schema."""


class RegistryConflict(RegistryValidationError):
    """A mutation conflicts with current registry state or generation."""


class RegistrySecurityError(RegistryValidationError):
    """The registry path does not meet the local ownership boundary."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _validate_timestamp(value: Any, label: str) -> str:
    if not isinstance(value, str) or not _UTC_RE.fullmatch(value):
        raise RegistryValidationError(f"{label} must be a UTC timestamp")
    try:
        datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise RegistryValidationError(f"{label} must be a valid UTC timestamp") from exc
    return value


def _decode_canonical_base64(value: Any, label: str, minimum: int, maximum: int) -> bytes:
    if not isinstance(value, str) or not value or len(value) % 4:
        raise RegistryValidationError(f"{label} must be canonical base64")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RegistryValidationError(f"{label} must be canonical base64") from exc
    if not minimum <= len(decoded) <= maximum or base64.b64encode(decoded).decode("ascii") != value:
        raise RegistryValidationError(f"{label} must be canonical base64")
    return decoded


def _decode_canonical_base64url(value: Any, label: str, size: int) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise RegistryValidationError(f"{label} must be canonical base64url")
    padded = value + "=" * ((4 - len(value) % 4) % 4)
    try:
        decoded = base64.b64decode(padded, altchars=b"-_", validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RegistryValidationError(f"{label} must be canonical base64url") from exc
    canonical = base64.urlsafe_b64encode(decoded).rstrip(b"=").decode("ascii")
    if len(decoded) != size or canonical != value:
        raise RegistryValidationError(f"{label} must be canonical base64url")
    return decoded


def _validate_display_name(value: Any) -> str:
    if not isinstance(value, str) or not 1 <= len(value) <= 80 or value != value.strip():
        raise RegistryValidationError("displayName must contain 1 to 80 visible characters")
    if any(ord(character) < 0x20 or ord(character) == 0x7F or character in _BIDI_CONTROLS for character in value):
        raise RegistryValidationError("displayName contains unsafe control characters")
    return value


def _validate_capabilities(values: Any) -> tuple[ApprovalCapability, ...]:
    if not isinstance(values, (list, tuple)) or any(not isinstance(value, str) for value in values):
        raise RegistryValidationError("capabilities must be a string array")
    if len(set(values)) != len(values) or not set(values).issubset(ALL_CAPABILITIES):
        raise RegistryValidationError("capabilities contain duplicates or unknown values")
    return tuple(sorted(values))  # type: ignore[return-value]


def _expect_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise RegistryValidationError(f"{label} fields do not match schema")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RegistryValidationError("registry JSON contains duplicate keys")
        result[key] = value
    return result


@dataclass(frozen=True)
class DeviceRecord:
    device_id: str
    display_name: str
    key_id: str
    public_key_spki_base64: str
    public_key_fingerprint: str
    security_level: str
    attestation_status: str
    state: DeviceState
    capabilities: tuple[ApprovalCapability, ...]
    generation: int
    enrolled_at: str
    updated_at: str
    last_seen_at: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "deviceId": self.device_id,
            "displayName": self.display_name,
            "keyId": self.key_id,
            "publicKeySpkiBase64": self.public_key_spki_base64,
            "publicKeyFingerprintSha256Base64Url": self.public_key_fingerprint,
            "securityLevel": self.security_level,
            "attestationStatus": self.attestation_status,
            "state": self.state,
            "capabilities": list(self.capabilities),
            "generation": self.generation,
            "enrolledAt": self.enrolled_at,
            "updatedAt": self.updated_at,
            "lastSeenAt": self.last_seen_at,
        }

    @classmethod
    def from_dict(cls, value: Any) -> DeviceRecord:
        if not isinstance(value, dict):
            raise RegistryValidationError("device must be an object")
        _expect_exact_keys(
            value,
            {
                "deviceId",
                "displayName",
                "keyId",
                "publicKeySpkiBase64",
                "publicKeyFingerprintSha256Base64Url",
                "securityLevel",
                "attestationStatus",
                "state",
                "capabilities",
                "generation",
                "enrolledAt",
                "updatedAt",
                "lastSeenAt",
            },
            "device",
        )
        device_id = value["deviceId"]
        if not isinstance(device_id, str) or not _DEVICE_ID_RE.fullmatch(device_id):
            raise RegistryValidationError("deviceId is invalid")
        display_name = _validate_display_name(value["displayName"])
        _decode_canonical_base64url(value["keyId"], "keyId", 32)
        public_key = _decode_canonical_base64(value["publicKeySpkiBase64"], "publicKeySpkiBase64", 64, 256)
        fingerprint = _decode_canonical_base64url(
            value["publicKeyFingerprintSha256Base64Url"],
            "publicKeyFingerprintSha256Base64Url",
            32,
        )
        expected_fingerprint = hashlib.sha256(public_key).digest()
        if fingerprint != expected_fingerprint:
            raise RegistryValidationError("public key fingerprint does not match publicKeySpkiBase64")
        if value["securityLevel"] not in ALL_SECURITY_LEVELS:
            raise RegistryValidationError("securityLevel must be STRONGBOX or TEE")
        if value["attestationStatus"] not in ALL_ATTESTATION_STATUSES:
            raise RegistryValidationError("attestationStatus is invalid")
        if value["state"] not in ALL_STATES:
            raise RegistryValidationError("state is invalid")
        generation = value["generation"]
        if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
            raise RegistryValidationError("device generation must be a positive integer")
        enrolled_at = _validate_timestamp(value["enrolledAt"], "enrolledAt")
        updated_at = _validate_timestamp(value["updatedAt"], "updatedAt")
        last_seen = value["lastSeenAt"]
        if last_seen is not None:
            last_seen = _validate_timestamp(last_seen, "lastSeenAt")
        capabilities = _validate_capabilities(value["capabilities"])
        if value["state"] == "revoked" and capabilities:
            raise RegistryValidationError("revoked device must not retain capabilities")
        return cls(
            device_id=device_id,
            display_name=display_name,
            key_id=value["keyId"],
            public_key_spki_base64=value["publicKeySpkiBase64"],
            public_key_fingerprint=value["publicKeyFingerprintSha256Base64Url"],
            security_level=value["securityLevel"],
            attestation_status=value["attestationStatus"],
            state=value["state"],
            capabilities=capabilities,
            generation=generation,
            enrolled_at=enrolled_at,
            updated_at=updated_at,
            last_seen_at=last_seen,
        )


class DeviceRegistry:
    def __init__(self, *, generation: int = 0, devices: Iterable[DeviceRecord] = ()) -> None:
        if not isinstance(generation, int) or isinstance(generation, bool) or generation < 0:
            raise RegistryValidationError("registry generation must be a non-negative integer")
        records = list(devices)
        if len(records) > 256:
            raise RegistryValidationError("registry contains too many devices")
        self._generation = generation
        self._devices = {record.device_id: record for record in records}
        if len(self._devices) != len(records):
            raise RegistryValidationError("registry contains duplicate device IDs")
        key_ids = [record.key_id for record in records]
        fingerprints = [record.public_key_fingerprint for record in records]
        if len(set(key_ids)) != len(key_ids) or len(set(fingerprints)) != len(fingerprints):
            raise RegistryValidationError("registry contains a public key assigned to multiple devices")
        if records and generation < max(record.generation for record in records):
            raise RegistryValidationError("registry generation is older than a device generation")

    @property
    def generation(self) -> int:
        return self._generation

    def list_devices(self) -> tuple[DeviceRecord, ...]:
        return tuple(sorted(self._devices.values(), key=lambda record: (record.display_name, record.device_id)))

    def get(self, device_id: str) -> DeviceRecord | None:
        return self._devices.get(device_id)

    def require_authorized(self, device_id: str, capability: ApprovalCapability) -> DeviceRecord:
        if capability not in ALL_CAPABILITIES:
            raise RegistryValidationError("unknown capability")
        device = self._devices.get(device_id)
        if device is None or device.state != "active" or capability not in device.capabilities:
            raise PermissionError("device is not authorized for this capability")
        return device

    def enroll(
        self,
        *,
        device_id: str,
        display_name: str,
        key_id: str,
        public_key_spki_base64: str,
        security_level: str,
        attestation_status: str = "unverified",
        expected_generation: int,
        now: str | None = None,
    ) -> DeviceRecord:
        self._check_generation(expected_generation)
        if len(self._devices) >= 256:
            raise RegistryConflict("registry device limit reached")
        if device_id in self._devices:
            raise RegistryConflict("deviceId is already registered")
        if not _DEVICE_ID_RE.fullmatch(device_id):
            raise RegistryValidationError("deviceId is invalid")
        display_name = _validate_display_name(display_name)
        _decode_canonical_base64url(key_id, "keyId", 32)
        public_key = _decode_canonical_base64(public_key_spki_base64, "publicKeySpkiBase64", 64, 256)
        fingerprint = base64.urlsafe_b64encode(hashlib.sha256(public_key).digest()).rstrip(b"=").decode("ascii")
        if any(record.key_id == key_id or record.public_key_fingerprint == fingerprint for record in self._devices.values()):
            raise RegistryConflict("public key is already assigned to another device")
        if security_level not in ALL_SECURITY_LEVELS:
            raise RegistryValidationError("securityLevel must be STRONGBOX or TEE")
        if attestation_status not in ALL_ATTESTATION_STATUSES:
            raise RegistryValidationError("attestationStatus is invalid")
        timestamp = _validate_timestamp(now, "now") if now is not None else _utc_now()
        record = DeviceRecord(
            device_id=device_id,
            display_name=display_name,
            key_id=key_id,
            public_key_spki_base64=public_key_spki_base64,
            public_key_fingerprint=fingerprint,
            security_level=security_level,
            attestation_status=attestation_status,
            state="active",
            # Enrollment never grants command submission or execution by itself.
            capabilities=("approve_pending",),
            generation=1,
            enrolled_at=timestamp,
            updated_at=timestamp,
            last_seen_at=None,
        )
        self._devices[device_id] = record
        self._generation += 1
        return record

    def set_capabilities(
        self,
        device_id: str,
        capabilities: Iterable[ApprovalCapability],
        *,
        expected_generation: int,
        now: str | None = None,
    ) -> DeviceRecord:
        self._check_generation(expected_generation)
        device = self._require_mutable(device_id)
        normalized = _validate_capabilities(list(capabilities))
        timestamp = _validate_timestamp(now, "now") if now is not None else _utc_now()
        return self._replace(device, capabilities=normalized, updated_at=timestamp)

    def set_state(
        self,
        device_id: str,
        state_value: DeviceState,
        *,
        expected_generation: int,
        now: str | None = None,
    ) -> DeviceRecord:
        self._check_generation(expected_generation)
        if state_value not in ALL_STATES:
            raise RegistryValidationError("state is invalid")
        device = self._require_mutable(device_id)
        timestamp = _validate_timestamp(now, "now") if now is not None else _utc_now()
        capabilities = () if state_value == "revoked" else device.capabilities
        return self._replace(device, state=state_value, capabilities=capabilities, updated_at=timestamp)

    def rename(
        self,
        device_id: str,
        display_name: str,
        *,
        expected_generation: int,
        now: str | None = None,
    ) -> DeviceRecord:
        self._check_generation(expected_generation)
        device = self._require_mutable(device_id)
        timestamp = _validate_timestamp(now, "now") if now is not None else _utc_now()
        return self._replace(device, display_name=_validate_display_name(display_name), updated_at=timestamp)

    def record_seen(
        self,
        device_id: str,
        *,
        expected_generation: int,
        now: str | None = None,
    ) -> DeviceRecord:
        self._check_generation(expected_generation)
        device = self._require_mutable(device_id)
        timestamp = _validate_timestamp(now, "now") if now is not None else _utc_now()
        return self._replace(device, last_seen_at=timestamp, updated_at=timestamp)

    def to_dict(self) -> dict[str, Any]:
        return {
            "schemaVersion": REGISTRY_SCHEMA_VERSION,
            "generation": self._generation,
            "devices": [record.to_dict() for record in self.list_devices()],
        }

    @classmethod
    def from_dict(cls, value: Any) -> DeviceRegistry:
        if not isinstance(value, dict):
            raise RegistryValidationError("registry must be an object")
        _expect_exact_keys(value, {"schemaVersion", "generation", "devices"}, "registry")
        if value["schemaVersion"] != REGISTRY_SCHEMA_VERSION:
            raise RegistryValidationError("unsupported registry schemaVersion")
        if not isinstance(value["devices"], list):
            raise RegistryValidationError("devices must be an array")
        return cls(
            generation=value["generation"],
            devices=(DeviceRecord.from_dict(item) for item in value["devices"]),
        )

    def _check_generation(self, expected_generation: int) -> None:
        if (
            not isinstance(expected_generation, int)
            or isinstance(expected_generation, bool)
            or expected_generation != self._generation
        ):
            raise RegistryConflict("registry generation changed; reload before mutating")

    def _require_mutable(self, device_id: str) -> DeviceRecord:
        device = self._devices.get(device_id)
        if device is None:
            raise RegistryConflict("device is not registered")
        if device.state == "revoked":
            # Revocation is terminal so an old key cannot be silently trusted again.
            raise RegistryConflict("revoked device cannot be modified; enroll a new key")
        return device

    def _replace(self, device: DeviceRecord, **changes: Any) -> DeviceRecord:
        updated = replace(device, generation=device.generation + 1, **changes)
        self._devices[device.device_id] = updated
        self._generation += 1
        return updated


class RegistryFileStore:
    """Atomic JSON storage whose file is private to an expected local owner."""

    def __init__(self, path: Path, *, expected_uid: int | None = None) -> None:
        self.path = path
        self.expected_uid = getattr(os, "geteuid", lambda: -1)() if expected_uid is None else expected_uid

    def load(self) -> DeviceRegistry:
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(self.path, flags)
        except OSError as exc:
            raise RegistrySecurityError(f"cannot safely open registry: {self.path}") from exc
        try:
            metadata = os.fstat(descriptor)
            self._validate_file_metadata(metadata)
            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = os.read(descriptor, min(65536, MAX_REGISTRY_BYTES + 1 - total))
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > MAX_REGISTRY_BYTES:
                    raise RegistryValidationError("registry file is too large")
        finally:
            os.close(descriptor)
        try:
            value = json.loads(b"".join(chunks).decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise RegistryValidationError("registry file must contain UTF-8 JSON") from exc
        return DeviceRegistry.from_dict(value)

    def save(self, registry: DeviceRegistry) -> None:
        parent = self.path.parent
        self._validate_parent(parent)
        if self.path.exists() or self.path.is_symlink():
            # Refuse to replace a path that we would not trust for reads.
            self.load()

        payload = json.dumps(registry.to_dict(), ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        temporary = parent / f".{self.path.name}.{os.getpid()}.{secrets.token_hex(8)}"
        descriptor = -1
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            offset = 0
            while offset < len(payload):
                offset += os.write(descriptor, payload[offset:])
            os.fsync(descriptor)
            os.close(descriptor)
            descriptor = -1
            os.replace(temporary, self.path)
            directory_descriptor = os.open(parent, os.O_RDONLY)
            try:
                os.fsync(directory_descriptor)
            finally:
                os.close(directory_descriptor)
        except OSError as exc:
            raise RegistrySecurityError(f"cannot safely save registry: {self.path}") from exc
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass

    def update(self, mutation: Callable[[DeviceRegistry], T]) -> T:
        """Serialize a read-modify-write operation across local admin processes."""

        if fcntl is None:
            raise RegistrySecurityError("registry updates require the Linux/WSL file-lock boundary")
        parent = self.path.parent
        self._validate_parent(parent)
        lock_path = parent / f".{self.path.name}.lock"
        flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
        try:
            descriptor = os.open(lock_path, flags, 0o600)
        except OSError as exc:
            raise RegistrySecurityError("cannot safely open registry lock") from exc
        try:
            self._validate_file_metadata(os.fstat(descriptor))
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            registry = self.load()
            result = mutation(registry)
            self.save(registry)
            return result
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def _validate_file_metadata(self, metadata: os.stat_result) -> None:
        if not stat.S_ISREG(metadata.st_mode):
            raise RegistrySecurityError("registry must be a regular file")
        if metadata.st_uid != self.expected_uid:
            raise RegistrySecurityError("registry owner is not trusted")
        if metadata.st_mode & 0o077:
            raise RegistrySecurityError("registry must not be accessible by group or other users")

    def _validate_parent(self, parent: Path) -> None:
        try:
            parent_metadata = parent.stat(follow_symlinks=False)
        except OSError as exc:
            raise RegistrySecurityError(f"registry directory is unavailable: {parent}") from exc
        if not stat.S_ISDIR(parent_metadata.st_mode) or parent_metadata.st_uid != self.expected_uid:
            raise RegistrySecurityError("registry directory must be owned by the expected local user")
        if parent_metadata.st_mode & 0o022:
            raise RegistrySecurityError("registry directory must not be group/world writable")
