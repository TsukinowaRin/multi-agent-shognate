import json
import sys
import threading
from pathlib import Path
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "package.json").is_file() and (candidate / "shogunate_mod" / "manifest.yaml").is_file():
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


def fake_api():
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
                "messages": [{"id": "msg-1"}, {"id": "msg-2"}, {"id": "msg-3"}],
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
