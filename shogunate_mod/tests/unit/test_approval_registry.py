import base64
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "package.json").is_file() and (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.approval.registry import (
    DeviceRegistry,
    RegistryConflict,
    RegistryFileStore,
    RegistrySecurityError,
    RegistryValidationError,
)
from shogunate_mod.approval import admin_cli


NOW = "2026-07-14T12:00:00.000Z"


def key_material(byte: bytes) -> tuple[str, str]:
    key_id = base64.urlsafe_b64encode(byte * 32).rstrip(b"=").decode()
    spki = base64.b64encode(byte * 91).decode()
    return key_id, spki


def enroll(registry: DeviceRegistry, device_id="device-1", byte=b"a"):
    key_id, spki = key_material(byte)
    return registry.enroll(
        device_id=device_id,
        display_name="OnePlus",
        key_id=key_id,
        public_key_spki_base64=spki,
        security_level="TEE",
        expected_generation=registry.generation,
        now=NOW,
    )


def test_enrollment_starts_with_minimum_capability_and_derived_fingerprint():
    registry = DeviceRegistry()
    device = enroll(registry)

    assert registry.generation == 1
    assert device.state == "active"
    assert device.capabilities == ("approve_pending",)
    assert device.attestation_status == "unverified"
    assert registry.require_authorized("device-1", "approve_pending") == device
    with pytest.raises(PermissionError):
        registry.require_authorized("device-1", "execute_unrestricted")

    serialized = registry.to_dict()
    assert DeviceRegistry.from_dict(serialized).to_dict() == serialized
    assert serialized["devices"][0]["publicKeyFingerprintSha256Base64Url"] != device.key_id


def test_capabilities_are_explicit_and_generation_blocks_lost_updates():
    registry = DeviceRegistry()
    enroll(registry)
    stale_generation = registry.generation
    device = registry.set_capabilities(
        "device-1",
        ["execute_shell", "submit_manual"],
        expected_generation=stale_generation,
        now="2026-07-14T12:01:00.000Z",
    )
    assert device.capabilities == ("execute_shell", "submit_manual")
    with pytest.raises(PermissionError):
        registry.require_authorized("device-1", "approve_pending")
    with pytest.raises(RegistryConflict, match="reload"):
        registry.rename("device-1", "Old write", expected_generation=stale_generation, now=NOW)


def test_suspend_and_terminal_revoke_fail_closed():
    registry = DeviceRegistry()
    enroll(registry)
    registry.set_capabilities(
        "device-1",
        ["approve_pending", "execute_unrestricted"],
        expected_generation=registry.generation,
        now=NOW,
    )
    suspended = registry.set_state(
        "device-1", "suspended", expected_generation=registry.generation, now=NOW
    )
    assert "execute_unrestricted" in suspended.capabilities
    with pytest.raises(PermissionError):
        registry.require_authorized("device-1", "execute_unrestricted")

    registry.set_state("device-1", "active", expected_generation=registry.generation, now=NOW)
    revoked = registry.set_state("device-1", "revoked", expected_generation=registry.generation, now=NOW)
    assert revoked.capabilities == ()
    with pytest.raises(RegistryConflict, match="cannot be modified"):
        registry.set_state("device-1", "active", expected_generation=registry.generation, now=NOW)


def test_duplicate_keys_unknown_fields_and_visual_controls_are_rejected():
    registry = DeviceRegistry()
    enroll(registry)
    key_id, spki = key_material(b"a")
    with pytest.raises(RegistryConflict, match="public key"):
        registry.enroll(
            device_id="device-2",
            display_name="Second",
            key_id=key_id,
            public_key_spki_base64=spki,
            security_level="TEE",
            expected_generation=registry.generation,
            now=NOW,
        )
    with pytest.raises(RegistryValidationError, match="control"):
        registry.rename("device-1", "Trusted\u202ePC", expected_generation=registry.generation, now=NOW)

    malformed = registry.to_dict()
    malformed["devices"][0]["unexpected"] = True
    with pytest.raises(RegistryValidationError, match="schema"):
        DeviceRegistry.from_dict(malformed)

    revoked_with_power = registry.to_dict()
    revoked_with_power["devices"][0]["state"] = "revoked"
    with pytest.raises(RegistryValidationError, match="must not retain"):
        DeviceRegistry.from_dict(revoked_with_power)

    rolled_back = registry.to_dict()
    rolled_back["generation"] = 0
    with pytest.raises(RegistryValidationError, match="older"):
        DeviceRegistry.from_dict(rolled_back)

    with pytest.raises(RegistryConflict, match="reload"):
        DeviceRegistry().enroll(
            device_id="device-bool-generation",
            display_name="Boolean generation",
            key_id=key_material(b"b")[0],
            public_key_spki_base64=key_material(b"b")[1],
            security_level="TEE",
            expected_generation=False,
            now=NOW,
        )


def test_file_store_is_atomic_private_and_rejects_duplicate_json(tmp_path: Path):
    os.chmod(tmp_path, 0o700)
    path = tmp_path / "approval-devices.json"
    store = RegistryFileStore(path)
    registry = DeviceRegistry()
    enroll(registry)

    store.save(registry)
    assert path.stat().st_mode & 0o777 == 0o600
    assert store.load().to_dict() == registry.to_dict()
    assert not list(tmp_path.glob(f".{path.name}.*"))

    path.write_text('{"schemaVersion":1,"schemaVersion":1,"generation":0,"devices":[]}', encoding="utf-8")
    os.chmod(path, 0o600)
    with pytest.raises(RegistryValidationError, match="duplicate"):
        store.load()


def test_file_store_rejects_public_or_symlinked_registry(tmp_path: Path):
    os.chmod(tmp_path, 0o700)
    path = tmp_path / "approval-devices.json"
    path.write_text(json.dumps(DeviceRegistry().to_dict()), encoding="utf-8")
    os.chmod(path, 0o644)
    with pytest.raises(RegistrySecurityError, match="accessible"):
        RegistryFileStore(path).load()

    path.unlink()
    target = tmp_path / "target.json"
    target.write_text(json.dumps(DeviceRegistry().to_dict()), encoding="utf-8")
    os.chmod(target, 0o600)
    path.symlink_to(target)
    with pytest.raises(RegistrySecurityError, match="safely open"):
        RegistryFileStore(path).load()


def test_file_store_update_serializes_management_mutation(tmp_path: Path):
    os.chmod(tmp_path, 0o700)
    path = tmp_path / "approval-devices.json"
    store = RegistryFileStore(path)
    registry = DeviceRegistry()
    enroll(registry)
    store.save(registry)

    updated = store.update(
        lambda current: current.set_capabilities(
            "device-1",
            ["submit_manual", "execute_unrestricted"],
            expected_generation=current.generation,
            now=NOW,
        )
    )
    assert updated.capabilities == ("execute_unrestricted", "submit_manual")
    assert store.load().generation == 2
    lock = tmp_path / f".{path.name}.lock"
    assert lock.stat().st_mode & 0o777 == 0o600


def test_local_admin_cli_lists_changes_and_revokes_devices(tmp_path: Path, capsys):
    os.chmod(tmp_path, 0o700)
    path = tmp_path / "approval-devices.json"
    store = RegistryFileStore(path)
    registry = DeviceRegistry()
    enroll(registry)
    store.save(registry)

    assert admin_cli.main(["--registry", str(path), "list"]) == 0
    listed = json.loads(capsys.readouterr().out)
    assert listed["devices"][0]["displayName"] == "OnePlus"
    assert "publicKeySpkiBase64" not in listed["devices"][0]

    assert admin_cli.main(
        [
            "--registry",
            str(path),
            "capabilities",
            "device-1",
            "approve_pending",
            "submit_manual",
            "execute_unrestricted",
        ]
    ) == 0
    changed = json.loads(capsys.readouterr().out)
    assert changed["capabilities"] == ["approve_pending", "execute_unrestricted", "submit_manual"]

    assert admin_cli.main(["--registry", str(path), "suspend", "device-1"]) == 0
    assert json.loads(capsys.readouterr().out)["state"] == "suspended"
    assert admin_cli.main(["--registry", str(path), "activate", "device-1"]) == 0
    capsys.readouterr()
    assert admin_cli.main(["--registry", str(path), "revoke", "device-1"]) == 0
    revoked = json.loads(capsys.readouterr().out)
    assert revoked["state"] == "revoked"
    assert revoked["capabilities"] == []

    assert admin_cli.main(["--registry", str(path), "activate", "device-1"]) == 2
    assert "cannot be modified" in json.loads(capsys.readouterr().err)["error"]


def test_npm_cli_dispatches_to_local_device_management(tmp_path: Path):
    os.chmod(tmp_path, 0o700)
    path = tmp_path / "approval-devices.json"
    store = RegistryFileStore(path)
    registry = DeviceRegistry()
    enroll(registry)
    store.save(registry)

    result = subprocess.run(
        [
            "node",
            "bin/shogunate.js",
            "approval-devices",
            "--registry",
            str(path),
            "list",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(result.stdout)
    assert payload["devices"][0]["deviceId"] == "device-1"
