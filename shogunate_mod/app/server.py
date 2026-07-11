#!/usr/bin/env python3
"""HTTP JSON bridge for the app-facing battlefield API."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import secrets
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, unquote, urlsplit

from shogunate_mod.battlefield import api as battlefield_api


TOKEN_PATH = Path.home() / ".shogunate" / "app-server-token"
MAX_BODY_BYTES = 1024 * 1024
_COMMAND_LOCK = threading.Lock()


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


def make_handler(token: str, api: Any = battlefield_api) -> type[BaseHTTPRequestHandler]:
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
                body = json.loads(self.rfile.read(length).decode("utf-8"))
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
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                self._send_json(400, {"error": str(exc)})
            except Exception as exc:
                self._send_json(500, {"error": str(exc)})

        def log_message(self, format: str, *args: Any) -> None:
            print(f"shogunate app server: {self.address_string()} - {format % args}", file=sys.stderr)

    return AppRequestHandler


def create_server(bind: str, port: int, token: str, api: Any = battlefield_api) -> ThreadingHTTPServer:
    return ThreadingHTTPServer((bind, port), make_handler(token, api))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--bind", default="127.0.0.1")
    args = parser.parse_args(argv)
    token, created = load_or_create_token()
    if args.bind == "0.0.0.0":
        print("WARNING: app server is reachable from other hosts on 0.0.0.0", file=sys.stderr)
    print(f"shogunate app server token: {token}", file=sys.stderr)
    if created:
        print(f"created token file: {TOKEN_PATH}", file=sys.stderr)
    server = create_server(args.bind, args.port, token)
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
