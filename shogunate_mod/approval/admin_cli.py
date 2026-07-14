"""Local-only management CLI for the host-owned approval device registry."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from .registry import (
    ALL_CAPABILITIES,
    DeviceRecord,
    RegistryConflict,
    RegistryFileStore,
    RegistrySecurityError,
    RegistryValidationError,
)


DEFAULT_REGISTRY_PATH = Path("/etc/shogunate/approval-devices.json")


def _device_summary(device: DeviceRecord) -> dict[str, Any]:
    # Public key bytes are not secret, but the management UI only needs a
    # stable fingerprint. Avoid copying bulky enrollment material into logs.
    return {
        "deviceId": device.device_id,
        "displayName": device.display_name,
        "keyId": device.key_id,
        "publicKeyFingerprintSha256Base64Url": device.public_key_fingerprint,
        "securityLevel": device.security_level,
        "attestationStatus": device.attestation_status,
        "state": device.state,
        "capabilities": list(device.capabilities),
        "generation": device.generation,
        "enrolledAt": device.enrolled_at,
        "updatedAt": device.updated_at,
        "lastSeenAt": device.last_seen_at,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY_PATH)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("list", help="list enrolled devices")

    show = subparsers.add_parser("show", help="show one device")
    show.add_argument("device_id")

    rename = subparsers.add_parser("rename", help="change a local device label")
    rename.add_argument("device_id")
    rename.add_argument("display_name")

    capabilities = subparsers.add_parser("capabilities", help="replace a device capability set")
    capabilities.add_argument("device_id")
    capabilities.add_argument("values", nargs="*", choices=sorted(ALL_CAPABILITIES))

    for name in ("activate", "suspend", "revoke"):
        state = subparsers.add_parser(name, help=f"set device state to {name}")
        state.add_argument("device_id")
    return parser


def _require_device(store: RegistryFileStore, device_id: str) -> DeviceRecord:
    device = store.load().get(device_id)
    if device is None:
        raise RegistryConflict("device is not registered")
    return device


def run(args: argparse.Namespace) -> dict[str, Any]:
    store = RegistryFileStore(args.registry)
    if args.command == "list":
        registry = store.load()
        return {
            "schemaVersion": 1,
            "registryGeneration": registry.generation,
            "devices": [_device_summary(device) for device in registry.list_devices()],
        }
    if args.command == "show":
        return _device_summary(_require_device(store, args.device_id))

    def mutate(registry):
        if args.command == "rename":
            return registry.rename(
                args.device_id,
                args.display_name,
                expected_generation=registry.generation,
            )
        if args.command == "capabilities":
            return registry.set_capabilities(
                args.device_id,
                args.values,
                expected_generation=registry.generation,
            )
        state = {"activate": "active", "suspend": "suspended", "revoke": "revoked"}[args.command]
        return registry.set_state(args.device_id, state, expected_generation=registry.generation)

    return _device_summary(store.update(mutate))


def main(argv: list[str] | None = None) -> int:
    try:
        args = _parser().parse_args(argv)
        print(json.dumps(run(args), ensure_ascii=False, separators=(",", ":")))
        return 0
    except PermissionError as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 3
    except (RegistrySecurityError, RegistryConflict, RegistryValidationError) as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
