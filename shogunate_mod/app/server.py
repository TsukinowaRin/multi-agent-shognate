#!/usr/bin/env python3
"""HTTP JSON bridge for the app-facing battlefield API."""

from __future__ import annotations

import argparse
import base64
import binascii
import contextlib
import io
import ipaddress
import json
import os
import re
import secrets
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlsplit

from shogunate_mod.battlefield import api as battlefield_api
from shogunate_mod.approval.protocol import (
    MAX_ENVELOPE_BYTES,
    decode_host_envelope_unverified,
)
from shogunate_mod.approval.registry import RegistryValidationError


TOKEN_PATH = Path.home() / ".shogunate" / "app-server-token"
MAX_BODY_BYTES = 1024 * 1024
_COMMAND_LOCK = threading.Lock()
APPROVAL_CHALLENGE_TTL_SECONDS = 300
MAX_APPROVAL_REQUEST_BYTES = 16 * 1024
MAX_APPROVAL_STATE_ENTRIES = 256


class ApprovalConflict(ValueError):
    """A one-time approval resource was already consumed or collided."""


class ApprovalGone(ValueError):
    """An approval resource existed but has expired."""


def _iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _parse_utc(value: Any, label: str) -> datetime:
    if not isinstance(value, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z", value
    ):
        raise ValueError(f"{label} must be a UTC timestamp")
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError(f"{label} must be a valid UTC timestamp") from exc


def _exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise ValueError(f"{label} fields do not match the schema")


def _decode_base64(value: Any, label: str, minimum: int, maximum: int) -> bytes:
    if not isinstance(value, str) or not value or len(value) % 4:
        raise ValueError(f"{label} must be canonical base64")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError(f"{label} must be canonical base64") from exc
    if not minimum <= len(decoded) <= maximum or base64.b64encode(decoded).decode("ascii") != value:
        raise ValueError(f"{label} must be canonical base64")
    return decoded


def _decode_base64url(value: Any, label: str, size: int) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError(f"{label} must be canonical base64url")
    padded = value + "=" * ((4 - len(value) % 4) % 4)
    try:
        decoded = base64.b64decode(padded, altchars=b"-_", validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError(f"{label} must be canonical base64url") from exc
    canonical = base64.urlsafe_b64encode(decoded).rstrip(b"=").decode("ascii")
    if len(decoded) != size or canonical != value:
        raise ValueError(f"{label} must be canonical base64url")
    return decoded


def _json_without_duplicate_keys(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_object_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("approval request bytes must contain UTF-8 JSON") from exc
    if not isinstance(value, dict):
        raise ValueError("approval request JSON must be an object")
    return value


def _reject_duplicate_object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("JSON contains duplicate object keys")
        result[key] = value
    return result


def _valid_der_ecdsa_signature(value: Any) -> None:
    signature = _decode_base64(value, "signatureDerBase64", 8, 80)
    if len(signature) < 8 or signature[0] != 0x30 or signature[1] != len(signature) - 2:
        raise ValueError("signatureDerBase64 must be a short-form DER ECDSA signature")
    offset = 2
    for _ in range(2):
        if offset + 2 > len(signature) or signature[offset] != 0x02:
            raise ValueError("signatureDerBase64 must contain two DER integers")
        length = signature[offset + 1]
        offset += 2
        if length < 1 or length > 33 or offset + length > len(signature):
            raise ValueError("signatureDerBase64 contains an invalid DER integer")
        integer = signature[offset : offset + length]
        if integer[0] & 0x80 or (length > 1 and integer[0] == 0 and not integer[1] & 0x80):
            raise ValueError("signatureDerBase64 contains a non-canonical DER integer")
        offset += length
    if offset != len(signature):
        raise ValueError("signatureDerBase64 has trailing data")


class ApprovalDevStore:
    """Loopback-only opaque relay state. It does not verify or authorize commands."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._challenges: dict[str, dict[str, Any]] = {}
        self._enrollments: dict[str, dict[str, Any]] = {}
        self._pending: dict[str, dict[str, Any]] = {}
        self._decisions: dict[str, dict[str, Any]] = {}
        self._collisions: set[str] = set()
        self._nonce_owners: dict[str, str] = {}
        self._replayed_nonces: set[str] = set()

    def _purge(self) -> None:
        monotonic_now = time.monotonic()
        utc_now = datetime.now(timezone.utc)
        self._challenges = {
            key: value for key, value in self._challenges.items() if value["deadline"] > monotonic_now
        }
        self._pending = {
            key: value for key, value in self._pending.items() if value["expires_at"] > utc_now
        }

    def create_challenge(self) -> dict[str, Any]:
        with self._lock:
            self._purge()
            if len(self._challenges) >= MAX_APPROVAL_STATE_ENTRIES:
                raise ApprovalConflict("too many active enrollment challenges")
            challenge_id = secrets.token_urlsafe(18)
            challenge = secrets.token_bytes(32)
            expires = datetime.now(timezone.utc).timestamp() + APPROVAL_CHALLENGE_TTL_SECONDS
            expires_at = datetime.fromtimestamp(expires, timezone.utc).isoformat(timespec="milliseconds").replace(
                "+00:00", "Z"
            )
            self._challenges[challenge_id] = {
                "deadline": time.monotonic() + APPROVAL_CHALLENGE_TTL_SECONDS,
                "challenge": challenge,
            }
            return {
                "challengeId": challenge_id,
                "challengeBase64": base64.b64encode(challenge).decode("ascii"),
                "expiresAt": expires_at,
            }

    def complete_enrollment(self, body: dict[str, Any]) -> dict[str, Any]:
        expected = {
            "challengeId",
            "algorithm",
            "keyId",
            "publicKeySpkiBase64",
            "attestationCertificateChainBase64",
            "securityLevel",
        }
        _exact_keys(body, expected, "enrollment")
        challenge_id = body["challengeId"]
        if not isinstance(challenge_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", challenge_id):
            raise ValueError("challengeId is invalid")
        if body["algorithm"] != "ES256" or body["securityLevel"] not in {"STRONGBOX", "TEE"}:
            raise ValueError("only hardware-backed ES256 enrollment is accepted")
        _decode_base64url(body["keyId"], "keyId", 32)
        _decode_base64(body["publicKeySpkiBase64"], "publicKeySpkiBase64", 64, 256)
        chain = body["attestationCertificateChainBase64"]
        if not isinstance(chain, list) or not 1 <= len(chain) <= 8:
            raise ValueError("attestationCertificateChainBase64 must contain 1 to 8 certificates")
        for certificate in chain:
            _decode_base64(certificate, "attestation certificate", 16, 8192)

        with self._lock:
            self._purge()
            challenge = self._challenges.pop(challenge_id, None)
            if challenge is None:
                raise ApprovalConflict("enrollment challenge is missing, expired, or already used")
            if len(self._enrollments) >= 16 and body["keyId"] not in self._enrollments:
                raise ApprovalConflict("too many development enrollments")
            # The bridge intentionally cannot prove that the certificate challenge matches.
            # It stores opaque public material for a later host verifier and never grants privilege.
            self._enrollments[body["keyId"]] = dict(body)
            return {
                "deviceId": f"dev-{body['keyId'][:12]}",
                "keyId": body["keyId"],
                "status": "unverified-development-only",
            }

    def observe_transcript(self, project_id: str, session_id: str, messages: list[Any]) -> None:
        with self._lock:
            self._purge()
            for message in messages:
                if not isinstance(message, dict) or message.get("type") != "approval_request":
                    continue
                approval = message.get("approval")
                if not isinstance(approval, dict):
                    continue
                try:
                    if set(approval) == {"requestBytesBase64"}:
                        request_bytes = _decode_base64(
                            approval["requestBytesBase64"],
                            "requestBytesBase64",
                            1,
                            MAX_APPROVAL_REQUEST_BYTES,
                        )
                        request = _json_without_duplicate_keys(request_bytes)
                        approval_bytes_base64 = approval["requestBytesBase64"]
                        protocol_version = 1
                    elif set(approval) == {"hostEnvelopeBytesBase64"}:
                        envelope_bytes = _decode_base64(
                            approval["hostEnvelopeBytesBase64"],
                            "hostEnvelopeBytesBase64",
                            1,
                            MAX_ENVELOPE_BYTES,
                        )
                        # The development bridge checks shape and lifetime only.  The
                        # root broker and Android pinned-key module remain the trust boundaries.
                        envelope = decode_host_envelope_unverified(
                            envelope_bytes,
                            now=datetime.now(timezone.utc),
                        )
                        request = dict(envelope.request.value)
                        approval_bytes_base64 = approval["hostEnvelopeBytesBase64"]
                        protocol_version = 2
                    else:
                        continue
                    request_id = request.get("requestId")
                    request_session = request.get("sessionId")
                    nonce = request.get("nonce")
                    issued_at = _parse_utc(request.get("issuedAt"), "issuedAt")
                    expires_at = _parse_utc(request.get("expiresAt"), "expiresAt")
                    if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", request_id):
                        continue
                    if not isinstance(nonce, str) or not re.fullmatch(r"[A-Za-z0-9_-]{22,256}", nonce):
                        continue
                    padded_nonce = nonce + "=" * ((4 - len(nonce) % 4) % 4)
                    nonce_bytes = base64.b64decode(padded_nonce, altchars=b"-_", validate=True)
                    if not 16 <= len(nonce_bytes) <= 192:
                        continue
                    if base64.urlsafe_b64encode(nonce_bytes).rstrip(b"=").decode("ascii") != nonce:
                        continue
                    if request_session != session_id or expires_at <= issued_at or expires_at <= datetime.now(timezone.utc):
                        continue
                    candidate = {
                        "project_id": project_id,
                        "session_id": session_id,
                        "approval_bytes_base64": approval_bytes_base64,
                        "protocol_version": protocol_version,
                        "nonce": nonce,
                        "issued_at": issued_at,
                        "expires_at": expires_at,
                    }
                except (ValueError, TypeError, binascii.Error, RegistryValidationError):
                    continue

                existing = self._pending.get(request_id)
                if existing and existing["approval_bytes_base64"] != candidate["approval_bytes_base64"]:
                    if len(self._collisions) < MAX_APPROVAL_STATE_ENTRIES:
                        self._collisions.add(request_id)
                    self._pending.pop(request_id, None)
                    continue
                nonce_owner = self._nonce_owners.get(candidate["nonce"])
                if candidate["nonce"] in self._replayed_nonces or (
                    nonce_owner is not None and nonce_owner != request_id
                ):
                    self._replayed_nonces.add(candidate["nonce"])
                    if nonce_owner is not None:
                        self._pending.pop(nonce_owner, None)
                        if len(self._collisions) < MAX_APPROVAL_STATE_ENTRIES:
                            self._collisions.add(nonce_owner)
                    self._pending.pop(request_id, None)
                    if len(self._collisions) < MAX_APPROVAL_STATE_ENTRIES:
                        self._collisions.add(request_id)
                    continue
                if nonce_owner is None:
                    if len(self._nonce_owners) >= MAX_APPROVAL_STATE_ENTRIES:
                        continue
                    self._nonce_owners[candidate["nonce"]] = request_id
                if request_id not in self._decisions and request_id not in self._collisions:
                    if len(self._pending) < MAX_APPROVAL_STATE_ENTRIES or request_id in self._pending:
                        self._pending[request_id] = candidate

    def submit_decision(self, request_id: str, body: dict[str, Any]) -> dict[str, Any]:
        if not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", request_id):
            raise ValueError("requestId is invalid")
        decision = body.get("decision")
        if decision == "denied":
            _exact_keys(body, {"decision"}, "denial")
        elif decision == "approved":
            if "decisionVersion" in body:
                _exact_keys(
                    body,
                    {
                        "decisionVersion",
                        "decision",
                        "deviceId",
                        "keyId",
                        "hostEnvelopeBytesBase64",
                        "signedAt",
                        "signatureDerBase64",
                    },
                    "v2 approval",
                )
                if body["decisionVersion"] != 1:
                    raise ValueError("decisionVersion must be 1")
                if not isinstance(body["deviceId"], str) or not re.fullmatch(
                    r"[A-Za-z0-9._:-]{1,128}", body["deviceId"]
                ):
                    raise ValueError("deviceId is invalid")
                envelope_bytes = _decode_base64(
                    body["hostEnvelopeBytesBase64"],
                    "hostEnvelopeBytesBase64",
                    1,
                    MAX_ENVELOPE_BYTES,
                )
                decode_host_envelope_unverified(envelope_bytes)
            else:
                _exact_keys(
                    body,
                    {
                        "decision",
                        "requestBytesBase64",
                        "algorithm",
                        "keyId",
                        "signatureDerBase64",
                        "signedAt",
                    },
                    "approval",
                )
                if body["algorithm"] != "ES256":
                    raise ValueError("algorithm must be ES256")
                _decode_base64(
                    body["requestBytesBase64"],
                    "requestBytesBase64",
                    1,
                    MAX_APPROVAL_REQUEST_BYTES,
                )
            _decode_base64url(body["keyId"], "keyId", 32)
            _valid_der_ecdsa_signature(body["signatureDerBase64"])
        else:
            raise ValueError("decision must be approved or denied")

        with self._lock:
            if request_id in self._collisions or request_id in self._decisions:
                raise ApprovalConflict("approval request collided or already has a decision")
            if len(self._decisions) >= MAX_APPROVAL_STATE_ENTRIES:
                raise ApprovalConflict("too many stored development decisions")
            pending = self._pending.get(request_id)
            if pending is None:
                raise LookupError(f"approval request not found: {request_id}")
            if pending["expires_at"] <= datetime.now(timezone.utc):
                self._pending.pop(request_id, None)
                raise ApprovalGone("approval request expired")
            if decision == "approved":
                if pending["protocol_version"] == 1:
                    if "requestBytesBase64" not in body:
                        raise ValueError("a v1 request requires a v1 decision")
                    if body["requestBytesBase64"] != pending["approval_bytes_base64"]:
                        raise ValueError("requestBytesBase64 does not match the pending request")
                else:
                    if "hostEnvelopeBytesBase64" not in body:
                        raise ValueError("a v2 request requires a v2 decision")
                    if body["hostEnvelopeBytesBase64"] != pending["approval_bytes_base64"]:
                        raise ValueError("hostEnvelopeBytesBase64 does not match the pending request")
                if body["keyId"] not in self._enrollments:
                    raise ValueError("keyId is not enrolled in this development bridge session")
                if "deviceId" in body and body["deviceId"] != f"dev-{body['keyId'][:12]}":
                    raise ValueError("deviceId does not match the enrolled development key")
                signed_at = _parse_utc(body["signedAt"], "signedAt")
                if not pending["issued_at"] <= signed_at < pending["expires_at"]:
                    raise ValueError("signedAt is outside the approval lifetime")
                if signed_at > datetime.now(timezone.utc).replace(microsecond=999999):
                    raise ValueError("signedAt is in the future")

            stored = {
                **body,
                "requestId": request_id,
                "projectId": pending["project_id"],
                "sessionId": pending["session_id"],
                "receivedAt": _iso_now(),
            }
            self._decisions[request_id] = stored
            self._pending.pop(request_id, None)
            return {"requestId": request_id, "status": "accepted"}


def load_or_create_token(path: Path = TOKEN_PATH) -> tuple[str, bool]:
    if path.exists():
        path.chmod(0o600)
        token = path.read_text(encoding="utf-8").strip()
        if not token:
            raise ValueError(f"token file is empty: {path}")
        return token, False

    path.parent.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(32)
    # 他ユーザーが読める瞬間を作らないため、生成時から 0600 を指定する。
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        handle.write(token + "\n")
    return token, True


def _run_command(func: Any, **kwargs: Any) -> tuple[int, dict[str, Any], str]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    # redirect_stdout は process-global なので、thread 間で JSON が混ざらないよう直列化する。
    with _COMMAND_LOCK, contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        code = func(argparse.Namespace(json=True, **kwargs))
    output = stdout.getvalue().strip()
    payload = json.loads(output) if output else {}
    if not isinstance(payload, dict):
        raise ValueError("battlefield API returned a non-object JSON response")
    return int(code), payload, stderr.getvalue().strip()


def make_handler(
    token: str,
    api: Any = battlefield_api,
    approval_store: ApprovalDevStore | None = None,
) -> type[BaseHTTPRequestHandler]:
    class AppRequestHandler(BaseHTTPRequestHandler):
        server_version = "ShogunateAppBridge/1"

        def _send_json(self, status: int, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        def _authorized(self) -> bool:
            header = self.headers.get("Authorization", "")
            prefix = "Bearer "
            supplied = header[len(prefix) :] if header.startswith(prefix) else ""
            return secrets.compare_digest(supplied, token)

        def _require_authorization(self) -> bool:
            if self._authorized():
                return True
            self._send_json(401, {"error": "unauthorized"})
            return False

        def _read_body(self) -> dict[str, Any]:
            raw_length = self.headers.get("Content-Length", "0")
            try:
                length = int(raw_length)
            except ValueError as exc:
                raise ValueError("invalid Content-Length") from exc
            if length < 0 or length > MAX_BODY_BYTES:
                raise ValueError("request body is too large")
            if length == 0:
                return {}
            try:
                body = json.loads(
                    self.rfile.read(length).decode("utf-8"),
                    object_pairs_hook=_reject_duplicate_object_pairs,
                )
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError("invalid JSON body") from exc
            if not isinstance(body, dict):
                raise ValueError("JSON body must be an object")
            return body

        def _project_id(self, value: str) -> str:
            project_id = unquote(value)
            projects = api.registry.load().get("projects", [])
            # selector の名前・path 解決を許さず、registry の id 完全一致だけを通す。
            if not any(isinstance(item, dict) and item.get("id") == project_id for item in projects):
                raise LookupError(f"battlefield not found: {project_id}")
            return project_id

        def _execute(self, func: Any, **kwargs: Any) -> None:
            code, payload, error = _run_command(func, **kwargs)
            if code != 0:
                self._send_json(500, {"error": error or f"battlefield command failed with exit {code}"})
                return
            self._send_json(200, payload)

        def do_OPTIONS(self) -> None:  # noqa: N802
            # CORS preflight はブラウザが Authorization を付けずに送るため認証しない。
            # レスポンスは許可ヘッダのみで情報を持たず、実 API は GET/POST 側で認証される。
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self) -> None:  # noqa: N802
            if not self._require_authorization():
                return
            try:
                parsed = urlsplit(self.path)
                parts = parsed.path.strip("/").split("/")
                if parts == ["api", "capabilities"]:
                    self._execute(api.cmd_capabilities)
                elif parts == ["api", "battlefields"]:
                    self._execute(api.cmd_list)
                elif len(parts) == 3 and parts[:2] == ["api", "battlefields"]:
                    self._execute(api.cmd_status, selector=self._project_id(parts[2]))
                elif len(parts) == 4 and parts[:2] == ["api", "battlefields"]:
                    project_id = self._project_id(parts[2])
                    if parts[3] == "roles":
                        self._execute(api.cmd_roles, selector=project_id)
                    elif parts[3] == "sessions":
                        self._execute(api.cmd_sessions, selector=project_id)
                    elif parts[3] == "transcript":
                        query = parse_qs(parsed.query, keep_blank_values=True)
                        session = query.get("session", [""])[0]
                        after = query.get("after", [""])[0]
                        code, payload, error = _run_command(api.cmd_transcript, selector=project_id, session=session)
                        if code != 0:
                            self._send_json(500, {"error": error or f"battlefield command failed with exit {code}"})
                            return
                        if approval_store is not None:
                            approval_store.observe_transcript(project_id, session, payload.get("messages", []))
                        if after:
                            messages = payload.get("messages", [])
                            index = next((i for i, item in enumerate(messages) if item.get("id") == after), None)
                            payload["messages"] = messages[index + 1 :] if index is not None else messages
                        self._send_json(200, payload)
                    else:
                        self._send_json(404, {"error": "not found"})
                else:
                    self._send_json(404, {"error": "not found"})
            except LookupError as exc:
                self._send_json(404, {"error": str(exc)})
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                self._send_json(400, {"error": str(exc)})
            except Exception as exc:  # HTTP 境界で例外を JSON に閉じ込め、server を継続する。
                self._send_json(500, {"error": str(exc)})

        def do_POST(self) -> None:  # noqa: N802
            if not self._require_authorization():
                return
            try:
                parts = urlsplit(self.path).path.strip("/").split("/")
                if parts == ["api", "approval-enrollment", "challenge"]:
                    if approval_store is None:
                        self._send_json(404, {"error": "not found"})
                        return
                    body = self._read_body()
                    _exact_keys(body, set(), "challenge request")
                    self._send_json(200, approval_store.create_challenge())
                    return
                if parts == ["api", "approval-enrollment", "complete"]:
                    if approval_store is None:
                        self._send_json(404, {"error": "not found"})
                        return
                    self._send_json(200, approval_store.complete_enrollment(self._read_body()))
                    return
                if len(parts) == 4 and parts[:2] == ["api", "approvals"] and parts[3] == "decision":
                    if approval_store is None:
                        self._send_json(404, {"error": "not found"})
                        return
                    request_id = unquote(parts[2])
                    self._send_json(200, approval_store.submit_decision(request_id, self._read_body()))
                    return
                if len(parts) != 4 or parts[:2] != ["api", "battlefields"]:
                    self._send_json(404, {"error": "not found"})
                    return
                project_id = self._project_id(parts[2])
                body = self._read_body()
                action = parts[3]
                if action == "start":
                    new = body.get("new", False)
                    if not isinstance(new, bool):
                        raise ValueError("new must be a boolean")
                    self._execute(
                        api.cmd_start,
                        selector=project_id,
                        new=new,
                        resume=not new,
                        attach=False,
                        launch_probe_timeout=1.0,
                        deliver_pending_timeout=15.0,
                    )
                elif action == "stop":
                    self._execute(api.cmd_stop, selector=project_id)
                elif action == "sessions":
                    mode = body.get("mode")
                    if mode not in {"new", "resume"}:
                        raise ValueError("mode must be 'new' or 'resume'")
                    self._execute(api.cmd_session_create, selector=project_id, title="", mode=mode)
                elif action == "send":
                    role = body.get("role")
                    session = body.get("session")
                    message = body.get("message")
                    if not all(isinstance(value, str) and value for value in (role, session, message)):
                        raise ValueError("role, session, and message must be non-empty strings")
                    self._execute(
                        api.cmd_send,
                        selector=project_id,
                        role=role,
                        session=session,
                        message=message,
                        start=False,
                        launch_probe_timeout=1.0,
                        deliver_pending_timeout=15.0,
                    )
                else:
                    self._send_json(404, {"error": "not found"})
            except LookupError as exc:
                self._send_json(404, {"error": str(exc)})
            except ApprovalConflict as exc:
                self._send_json(409, {"error": str(exc)})
            except ApprovalGone as exc:
                self._send_json(410, {"error": str(exc)})
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                self._send_json(400, {"error": str(exc)})
            except Exception as exc:
                self._send_json(500, {"error": str(exc)})

        def log_message(self, format: str, *args: Any) -> None:
            print(f"shogunate app server: {self.address_string()} - {format % args}", file=sys.stderr)

    return AppRequestHandler


def _is_loopback_bind(bind: str) -> bool:
    if bind == "localhost":
        return True
    try:
        return ipaddress.ip_address(bind).is_loopback
    except ValueError:
        return False


def create_server(
    bind: str,
    port: int,
    token: str,
    api: Any = battlefield_api,
    *,
    approval_dev: bool = False,
) -> ThreadingHTTPServer:
    if approval_dev and not _is_loopback_bind(bind):
        raise ValueError("--approval-dev requires a loopback bind address")
    approval_store = ApprovalDevStore() if approval_dev else None
    server = ThreadingHTTPServer((bind, port), make_handler(token, api, approval_store))
    server.approval_store = approval_store  # type: ignore[attr-defined]
    return server


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument(
        "--approval-dev",
        action="store_true",
        help="enable loopback-only opaque approval enrollment and decision relay endpoints",
    )
    args = parser.parse_args(argv)
    token, created = load_or_create_token()
    if args.bind == "0.0.0.0":
        print("WARNING: app server is reachable from other hosts on 0.0.0.0", file=sys.stderr)
    print(f"shogunate app server token: {token}", file=sys.stderr)
    if created:
        print(f"created token file: {TOKEN_PATH}", file=sys.stderr)
    server = create_server(args.bind, args.port, token, approval_dev=args.approval_dev)
    host, port = server.server_address[:2]
    print(f"shogunate app server listening on http://{host}:{port}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
