import base64
import json
import sys
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "shogunate_mod" / "manifest.yaml").is_file():
            return candidate
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())
sys.path.insert(0, str(ROOT))

from shogunate_mod.app import server as app_server


TOKEN = "unit-test-token"
PROJECT_ID = "battlefield-1"


class FakeRegistry:
    @staticmethod
    def load():
        return {"current": PROJECT_ID, "projects": [{"id": PROJECT_ID, "name": "fixture"}]}


def fake_api(transcript_messages=None):
    calls = []

    def command(name, payload):
        def run(args):
            calls.append((name, vars(args)))
            print(json.dumps(payload(args)))
            return 0

        return run

    project = lambda args: {"id": args.selector, "name": "fixture"}
    return SimpleNamespace(
        registry=FakeRegistry,
        calls=calls,
        cmd_capabilities=command("capabilities", lambda args: {"capabilities": {"battlefield": True}}),
        cmd_list=command("list", lambda args: {"current": PROJECT_ID, "projects": [{"id": PROJECT_ID}]}),
        cmd_status=command("status", project),
        cmd_start=command("start", lambda args: {"project": project(args), "new": args.new, "attach": args.attach}),
        cmd_stop=command("stop", lambda args: {"project": project(args), "stopped": []}),
        cmd_roles=command("roles", lambda args: {"project": project(args), "roles": []}),
        cmd_sessions=command("sessions", lambda args: {"project": project(args), "sessions": []}),
        cmd_session_create=command(
            "session-create", lambda args: {"project": project(args), "session": {"id": "chat-1", "mode": args.mode}}
        ),
        cmd_transcript=command(
            "transcript",
            lambda args: {
                "project": project(args),
                "session": args.session,
                "messages": transcript_messages or [{"id": "msg-1"}, {"id": "msg-2"}, {"id": "msg-3"}],
            },
        ),
        cmd_send=command(
            "send", lambda args: {"project": project(args), "role": args.role, "session": {"id": args.session}}
        ),
    )


@pytest.fixture
def bridge():
    api = fake_api()
    httpd = app_server.create_server("127.0.0.1", 0, TOKEN, api=api)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_port}", api
    finally:
        httpd.shutdown()
        thread.join(timeout=2)
        httpd.server_close()


def approval_message(request_id, *, session_id="chat-1", lifetime_seconds=240, nonce=None):
    issued = datetime.now(timezone.utc) - timedelta(seconds=1)
    expires = issued + timedelta(seconds=lifetime_seconds)
    request = {
        "version": 1,
        "requestId": request_id,
        "hostId": "host-1",
        "hostName": "Fixture PC",
        "user": "fixture-user",
        "runAs": "service-user",
        "sessionId": session_id,
        "action": "command.execute",
        "command": {"program": "tool", "args": ["check"], "cwd": "/work"},
        "reason": "unit test",
        "issuedAt": issued.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "expiresAt": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "nonce": nonce or base64.urlsafe_b64encode((request_id.encode() + b"\0" * 16)[:16]).rstrip(b"=").decode(),
    }
    raw = json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode()
    return {
        "id": f"event-{request_id}",
        "type": "approval_request",
        "approval": {"requestBytesBase64": base64.b64encode(raw).decode()},
    }


def approval_v2_message(request_id, *, session_id="chat-1"):
    issued = datetime.now(timezone.utc) - timedelta(seconds=1)
    expires = issued + timedelta(seconds=120)
    b64url = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=").decode()
    request = {
        "version": 2,
        "requestId": request_id,
        "eventId": f"event-{request_id}",
        "sessionId": session_id,
        "hostId": "host-1",
        "hostName": "Fixture PC",
        "source": {"kind": "ssh", "clientId": "terminal-1"},
        "requiredCapabilities": ["execute_unrestricted"],
        "execution": {
            "mode": "argv",
            "executable": {
                "path": "/usr/bin/id",
                "device": 8,
                "inode": 123,
                "size": 48144,
                "sha256Base64Url": b64url(b"e" * 32),
            },
            "argvBase64Url": [b64url(b"/usr/bin/id"), b64url(b"-u")],
            "cwd": {"path": "/work", "device": 8, "inode": 456},
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
        "submitterExplanation": "unit test",
        "issuedAt": issued.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "expiresAt": expires.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "nonce": b64url(b"n" * 24),
    }
    request_bytes = json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode()
    envelope = {
        "envelopeVersion": 1,
        "algorithm": "Ed25519",
        "keyId": b64url(b"h" * 32),
        "requestBytesBase64": base64.b64encode(request_bytes).decode(),
        "signatureBase64Url": b64url(b"s" * 64),
    }
    envelope_bytes = json.dumps(envelope, ensure_ascii=False, separators=(",", ":")).encode()
    return {
        "id": f"event-{request_id}",
        "type": "approval_request",
        "approval": {"hostEnvelopeBytesBase64": base64.b64encode(envelope_bytes).decode()},
    }


@pytest.fixture
def approval_bridge():
    messages = [approval_message("request-1"), approval_message("request-2"), approval_v2_message("request-v2")]
    api = fake_api(messages)
    httpd = app_server.create_server("127.0.0.1", 0, TOKEN, api=api, approval_dev=True)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{httpd.server_port}", api, messages
    finally:
        httpd.shutdown()
        thread.join(timeout=2)
        httpd.server_close()


def request_json(base, path, *, method="GET", body=None, token=TOKEN):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = Request(base + path, data=data, headers=headers, method=method)
    with urlopen(request, timeout=2) as response:
        return response.status, response.headers, json.load(response)


def test_authentication_json_and_cors(bridge):
    base, _ = bridge
    with pytest.raises(HTTPError) as caught:
        request_json(base, "/api/capabilities", token="wrong")
    assert caught.value.code == 401
    assert json.load(caught.value) == {"error": "unauthorized"}
    assert caught.value.headers["Content-Type"] == "application/json; charset=utf-8"
    assert caught.value.headers["Access-Control-Allow-Origin"] == "*"

    status, headers, payload = request_json(base, "/api/capabilities")
    assert status == 200
    assert headers["Content-Type"] == "application/json; charset=utf-8"
    assert headers["Access-Control-Allow-Origin"] == "*"
    assert payload["capabilities"]["battlefield"] is True


def test_routes_call_existing_commands_and_filter_transcript(bridge):
    base, api = bridge
    assert request_json(base, "/api/battlefields")[2]["projects"] == [{"id": PROJECT_ID}]
    assert request_json(base, f"/api/battlefields/{PROJECT_ID}")[2]["id"] == PROJECT_ID
    assert request_json(base, f"/api/battlefields/{PROJECT_ID}/roles")[2]["roles"] == []
    assert request_json(base, f"/api/battlefields/{PROJECT_ID}/sessions")[2]["sessions"] == []

    transcript = request_json(
        base, f"/api/battlefields/{PROJECT_ID}/transcript?session=chat-1&after=msg-1"
    )[2]
    assert transcript["messages"] == [{"id": "msg-2"}, {"id": "msg-3"}]

    started = request_json(base, f"/api/battlefields/{PROJECT_ID}/start", method="POST", body={"new": True})[2]
    assert started["new"] is True
    assert started["attach"] is False
    session = request_json(
        base, f"/api/battlefields/{PROJECT_ID}/sessions", method="POST", body={"mode": "resume"}
    )[2]
    assert session["session"]["mode"] == "resume"
    sent = request_json(
        base,
        f"/api/battlefields/{PROJECT_ID}/send",
        method="POST",
        body={"role": "shogun", "session": "chat-1", "message": "hello"},
    )[2]
    assert sent["role"] == "shogun"
    assert request_json(base, f"/api/battlefields/{PROJECT_ID}/stop", method="POST", body={})[0] == 200
    assert {name for name, _ in api.calls} >= {
        "list", "status", "roles", "sessions", "transcript", "start", "session-create", "send", "stop"
    }


def test_unknown_id_bad_body_and_options(bridge):
    base, _ = bridge
    with pytest.raises(HTTPError) as missing:
        request_json(base, "/api/battlefields/not-registered")
    assert missing.value.code == 404

    with pytest.raises(HTTPError) as bad:
        request_json(base, f"/api/battlefields/{PROJECT_ID}/start", method="POST", body={"new": "yes"})
    assert bad.value.code == 400

    # ブラウザの CORS preflight は Authorization を送らないため、無認証で通ること。
    request = Request(base + "/api/battlefields", method="OPTIONS")
    with urlopen(request, timeout=2) as response:
        assert response.status == 204
        assert response.headers["Access-Control-Allow-Methods"] == "GET, POST, OPTIONS"


def test_token_file_is_created_with_private_permissions(tmp_path: Path):
    path = tmp_path / ".shogunate" / "app-server-token"
    token, created = app_server.load_or_create_token(path)
    assert created is True
    assert path.read_text().strip() == token
    assert path.stat().st_mode & 0o777 == 0o600
    path.chmod(0o644)
    assert app_server.load_or_create_token(path) == (token, False)
    assert path.stat().st_mode & 0o777 == 0o600


def test_approval_dev_endpoints_are_disabled_by_default_and_require_loopback(bridge):
    base, _ = bridge
    with pytest.raises(HTTPError) as disabled:
        request_json(base, "/api/approval-enrollment/challenge", method="POST", body={})
    assert disabled.value.code == 404
    with pytest.raises(ValueError, match="loopback"):
        app_server.create_server("0.0.0.0", 0, TOKEN, api=fake_api(), approval_dev=True)


def test_approval_dev_enrollment_is_hardware_only_and_challenge_is_single_use(approval_bridge):
    base, _, _ = approval_bridge
    challenge = request_json(base, "/api/approval-enrollment/challenge", method="POST", body={})[2]
    assert len(base64.b64decode(challenge["challengeBase64"], validate=True)) == 32
    key_id = base64.urlsafe_b64encode(b"k" * 32).rstrip(b"=").decode()
    enrollment = {
        "challengeId": challenge["challengeId"],
        "algorithm": "ES256",
        "keyId": key_id,
        "publicKeySpkiBase64": base64.b64encode(b"s" * 91).decode(),
        "attestationCertificateChainBase64": [base64.b64encode(b"c" * 64).decode()],
        "securityLevel": "SOFTWARE",
    }
    with pytest.raises(HTTPError) as software_key:
        request_json(base, "/api/approval-enrollment/complete", method="POST", body=enrollment)
    assert software_key.value.code == 400

    # 形式エラーでは challenge を消費せず、hardware-backed key で再試行できる。
    enrollment["securityLevel"] = "TEE"
    receipt = request_json(
        base, "/api/approval-enrollment/complete", method="POST", body=enrollment
    )[2]
    assert receipt == {
        "deviceId": f"dev-{key_id[:12]}",
        "keyId": key_id,
        "status": "unverified-development-only",
    }
    with pytest.raises(HTTPError) as replay:
        request_json(base, "/api/approval-enrollment/complete", method="POST", body=enrollment)
    assert replay.value.code == 409


def test_approval_dev_decision_matches_pending_bytes_and_is_single_use(approval_bridge):
    base, _, messages = approval_bridge
    request_json(base, f"/api/battlefields/{PROJECT_ID}/transcript?session=chat-1")
    key_id = base64.urlsafe_b64encode(b"k" * 32).rstrip(b"=").decode()
    challenge = request_json(base, "/api/approval-enrollment/challenge", method="POST", body={})[2]
    request_json(
        base,
        "/api/approval-enrollment/complete",
        method="POST",
        body={
            "challengeId": challenge["challengeId"],
            "algorithm": "ES256",
            "keyId": key_id,
            "publicKeySpkiBase64": base64.b64encode(b"s" * 91).decode(),
            "attestationCertificateChainBase64": [base64.b64encode(b"c" * 64).decode()],
            "securityLevel": "TEE",
        },
    )
    signature = base64.b64encode(bytes.fromhex("3006020101020101")).decode()
    approved = {
        "decision": "approved",
        "requestBytesBase64": messages[0]["approval"]["requestBytesBase64"],
        "algorithm": "ES256",
        "keyId": key_id,
        "signatureDerBase64": signature,
        "signedAt": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
    }
    wrong = {**approved, "requestBytesBase64": base64.b64encode(b"wrong").decode()}
    with pytest.raises(HTTPError) as mismatch:
        request_json(base, "/api/approvals/request-1/decision", method="POST", body=wrong)
    assert mismatch.value.code == 400

    duplicate_key_body = b'{"decision":"denied","decision":"approved"}'
    duplicate_key_request = Request(
        base + "/api/approvals/request-1/decision",
        data=duplicate_key_body,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method="POST",
    )
    with pytest.raises(HTTPError) as duplicate_key:
        urlopen(duplicate_key_request, timeout=2)
    assert duplicate_key.value.code == 400

    accepted = request_json(
        base, "/api/approvals/request-1/decision", method="POST", body=approved
    )[2]
    assert accepted == {"requestId": "request-1", "status": "accepted"}
    with pytest.raises(HTTPError) as duplicate:
        request_json(base, "/api/approvals/request-1/decision", method="POST", body=approved)
    assert duplicate.value.code == 409

    denied = request_json(
        base, "/api/approvals/request-2/decision", method="POST", body={"decision": "denied"}
    )[2]
    assert denied == {"requestId": "request-2", "status": "accepted"}

    original_nonce = json.loads(base64.b64decode(messages[0]["approval"]["requestBytesBase64"]))["nonce"]
    messages.append(approval_message("request-3", nonce=original_nonce))
    request_json(base, f"/api/battlefields/{PROJECT_ID}/transcript?session=chat-1")
    with pytest.raises(HTTPError) as replayed_nonce:
        request_json(
            base, "/api/approvals/request-3/decision", method="POST", body={"decision": "denied"}
        )
    assert replayed_nonce.value.code == 409


def test_approval_dev_relays_v2_envelope_without_claiming_signature_verification(approval_bridge):
    base, _, messages = approval_bridge
    request_json(base, f"/api/battlefields/{PROJECT_ID}/transcript?session=chat-1")
    key_id = base64.urlsafe_b64encode(b"v" * 32).rstrip(b"=").decode()
    challenge = request_json(base, "/api/approval-enrollment/challenge", method="POST", body={})[2]
    receipt = request_json(
        base,
        "/api/approval-enrollment/complete",
        method="POST",
        body={
            "challengeId": challenge["challengeId"],
            "algorithm": "ES256",
            "keyId": key_id,
            "publicKeySpkiBase64": base64.b64encode(b"p" * 91).decode(),
            "attestationCertificateChainBase64": [base64.b64encode(b"c" * 64).decode()],
            "securityLevel": "TEE",
        },
    )[2]
    signature = base64.b64encode(bytes.fromhex("3006020101020101")).decode()
    approved = {
        "decisionVersion": 1,
        "decision": "approved",
        "deviceId": receipt["deviceId"],
        "keyId": key_id,
        "hostEnvelopeBytesBase64": messages[2]["approval"]["hostEnvelopeBytesBase64"],
        "signedAt": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "signatureDerBase64": signature,
    }

    wrong_protocol = {
        "decision": "approved",
        "requestBytesBase64": base64.b64encode(b"wrong").decode(),
        "algorithm": "ES256",
        "keyId": key_id,
        "signatureDerBase64": signature,
        "signedAt": approved["signedAt"],
    }
    with pytest.raises(HTTPError) as v1_for_v2:
        request_json(base, "/api/approvals/request-v2/decision", method="POST", body=wrong_protocol)
    assert v1_for_v2.value.code == 400

    accepted = request_json(
        base, "/api/approvals/request-v2/decision", method="POST", body=approved
    )[2]
    assert accepted == {"requestId": "request-v2", "status": "accepted"}
