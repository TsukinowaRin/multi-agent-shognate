"""Host-owned approval trust and authorization primitives."""

from .registry import (
    ALL_CAPABILITIES,
    ApprovalCapability,
    DeviceRecord,
    DeviceRegistry,
    DeviceState,
    RegistryConflict,
    RegistryFileStore,
    RegistrySecurityError,
    RegistryValidationError,
)
from .protocol import DeviceDecision, FrozenRequest, HostEnvelope, UnverifiedHostEnvelope

__all__ = [
    "ALL_CAPABILITIES",
    "ApprovalCapability",
    "DeviceRecord",
    "DeviceRegistry",
    "DeviceState",
    "DeviceDecision",
    "FrozenRequest",
    "HostEnvelope",
    "UnverifiedHostEnvelope",
    "RegistryConflict",
    "RegistryFileStore",
    "RegistrySecurityError",
    "RegistryValidationError",
]
