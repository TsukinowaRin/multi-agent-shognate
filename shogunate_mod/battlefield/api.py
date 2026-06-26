#!/usr/bin/env python3
"""App-facing Shogunate battlefield API.

This CLI is intentionally JSON-friendly. Mobile and desktop apps should use it
instead of guessing tmux session names or direct pane targets.
"""

from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from shogunate_mod.projects import registry  # noqa: E402

APP_QUEUE = Path("queue") / "app"


def now() -> int:
    return int(time.time())


def iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def json_print(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def fail(message: str, code: int = 1) -> int:
    print(f"shogunate battlefield: ERROR: {message}", file=sys.stderr)
    return code


def project_slug(path: str) -> str:
    base = Path(path).name.lower()
    slug = re.sub(r"[^a-z0-9_.-]+", "-", base)
    slug = re.sub(r"-+", "-", slug).strip("-")
    return (slug or "project")[:32]


def project_hash(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8")).hexdigest()[:8]


def workspace_home() -> Path:
    return Path(os.environ.get("SHOGUNATE_WORKSPACE_HOME", Path.home() / ".shogunate" / "workspaces")).expanduser()


def runtime_dir(project: dict[str, Any]) -> Path:
    path = str(project["path"])
    return workspace_home() / f"{project_slug(path)}-{project_hash(path)}"


def session_name(project: dict[str, Any]) -> str:
    path = str(project["path"])
    return f"shogunate-{project_slug(path)}-{project_hash(path)}"


def daemon_session_name(project: dict[str, Any]) -> str:
    return f"goza-runtime-{session_name(project)}"


def tmux(*args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["tmux", *args],
        text=True,
        capture_output=True,
        check=check,
    )


def tmux_available() -> bool:
    return shutil.which("tmux") is not None


def has_session(name: str) -> bool:
    if not tmux_available():
        return False
    return tmux("has-session", "-t", f"={name}").returncode == 0


def resolve_project(selector: str) -> dict[str, Any]:
    data = registry.load()
    project = registry.find_project(data, selector)
    if project is None:
        raise ValueError(f"project not found: {selector}")
    return project


def project_summary(project: dict[str, Any]) -> dict[str, Any]:
    runtime = runtime_dir(project)
    session = session_name(project)
    daemon = daemon_session_name(project)
    running = has_session(session)
    return {
        "id": project.get("id", ""),
        "name": project.get("name", ""),
        "path": project.get("path", ""),
        "last_opened_at": project.get("last_opened_at", 0),
        "runtime": {
            "status": "running" if running else "stopped",
            "session": session,
            "daemon_session": daemon,
            "workspace": str(runtime),
            "exists": runtime.exists(),
            "dashboard": str(runtime / "dashboard.md"),
        },
        "sessions": session_summary(runtime),
    }


def session_store(runtime: Path) -> Path:
    return runtime / APP_QUEUE / "sessions.json"


def session_dir(runtime: Path, session_id: str) -> Path:
    return runtime / APP_QUEUE / "sessions" / session_id


def load_sessions(runtime: Path) -> dict[str, Any]:
    path = session_store(runtime)
    if not path.exists():
        return {"current": "", "sessions": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"current": "", "sessions": []}
    if not isinstance(data, dict):
        return {"current": "", "sessions": []}
    sessions = data.get("sessions")
    current = data.get("current")
    return {
        "current": current if isinstance(current, str) else "",
        "sessions": [s for s in sessions if isinstance(s, dict) and s.get("id")] if isinstance(sessions, list) else [],
    }


def save_sessions(runtime: Path, data: dict[str, Any]) -> None:
    path = session_store(runtime)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def create_app_session(runtime: Path, mode: str, title: str = "") -> dict[str, Any]:
    data = load_sessions(runtime)
    session_id = f"chat-{time.strftime('%Y%m%d-%H%M%S')}"
    record = {
        "id": session_id,
        "title": title.strip() or ("新規チャット" if mode == "new" else "続きから"),
        "mode": mode,
        "created_at": now(),
        "updated_at": now(),
    }
    data["sessions"].insert(0, record)
    data["current"] = session_id
    save_sessions(runtime, data)
    session_dir(runtime, session_id).mkdir(parents=True, exist_ok=True)
    return record


def current_or_create_session(runtime: Path, mode: str = "resume") -> dict[str, Any]:
    data = load_sessions(runtime)
    current = data.get("current", "")
    for session in data["sessions"]:
        if session.get("id") == current:
            return session
    return create_app_session(runtime, mode=mode)


def session_summary(runtime: Path) -> dict[str, Any]:
    data = load_sessions(runtime)
    return {
        "current": data.get("current", ""),
        "count": len(data.get("sessions", [])),
    }


def append_transcript(runtime: Path, session_id: str, entry: dict[str, Any]) -> None:
    directory = session_dir(runtime, session_id)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "messages.jsonl"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def read_transcript(runtime: Path, session_id: str) -> list[dict[str, Any]]:
    path = session_dir(runtime, session_id) / "messages.jsonl"
    if not path.exists():
        return []
    messages = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict):
            messages.append(item)
    return messages


def roles_for_project(project: dict[str, Any]) -> list[dict[str, str]]:
    session = session_name(project)
    if not has_session(session):
        return []
    result = tmux(
        "list-panes",
        "-s",
        "-t",
        session,
        "-F",
        "#{pane_id}\t#{window_name}\t#{pane_index}\t#{@agent_id}\t#{@agent_cli}\t#{@model_name}\t#{pane_current_command}",
    )
    roles = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 7:
            continue
        pane_id, window, pane_index, agent_id, cli, model, current_command = parts[:7]
        if not agent_id:
            continue
        roles.append(
            {
                "role": agent_id,
                "pane": pane_id,
                "window": window,
                "pane_index": pane_index,
                "cli": cli,
                "model": model,
                "current_command": current_command,
            }
        )
    return roles


def host_info() -> dict[str, str]:
    return {
        "name": platform.node(),
        "user": getpass.getuser(),
        "platform": platform.platform(),
    }


def cmd_capabilities(args: argparse.Namespace) -> int:
    json_print(
        {
            "host": host_info(),
            "capabilities": {
                "projects": True,
                "battlefield": True,
                "start": True,
                "stop": True,
                "sessions": True,
                "role_chat": True,
            },
            "commands": [
                "shogunate projects --json",
                "shogunate battlefield list --json",
                "shogunate battlefield status <project> --json",
                "shogunate battlefield start <project> --resume",
                "shogunate battlefield start <project> --new",
                "shogunate battlefield stop <project>",
                "shogunate battlefield send <project> --role shogun <message>",
                "shogunate battlefield transcript <project> --json",
            ],
        }
    )
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    data = registry.load()
    projects = [project_summary(project) for project in data["projects"]]
    if args.json:
        json_print({"host": host_info(), "current": data.get("current", ""), "projects": projects})
        return 0
    if not projects:
        print("No registered battlefields.")
        return 0
    for project in projects:
        marker = "*" if project["id"] == data.get("current", "") else " "
        runtime = project["runtime"]
        print(f"{marker} {project['id']}  {runtime['status']:<8}  {project['name']}  {project['path']}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    summary = project_summary(project)
    summary["roles"] = roles_for_project(project)
    if args.json:
        json_print(summary)
        return 0
    runtime = summary["runtime"]
    print(f"{summary['name']} ({summary['id']})")
    print(f"  status:   {runtime['status']}")
    print(f"  project:  {summary['path']}")
    print(f"  runtime:  {runtime['workspace']}")
    print(f"  session:  {runtime['session']}")
    print(f"  roles:    {len(summary['roles'])}")
    return 0


def shogunate_command() -> str | None:
    command = os.environ.get("SHOGUNATE_COMMAND")
    if command:
        return command
    return shutil.which("shogunate")


def cmd_start(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    runtime = runtime_dir(project)
    mode = "clean" if args.new else "resume"
    chat_session = create_app_session(runtime, "new") if args.new else current_or_create_session(runtime, "resume")
    command = shogunate_command()
    if not command:
        return fail("shogunate command not found in PATH; set SHOGUNATE_COMMAND")
    launch_args = [command, "--project", f"@{project['id']}", mode]
    if not args.attach:
        launch_args.append("--no-attach")
    result = subprocess.run(launch_args, text=True, capture_output=True, check=False)
    payload = {
        "project": project_summary(project),
        "session": chat_session,
        "command": launch_args,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    if args.json:
        json_print(payload)
    else:
        print(result.stdout, end="")
        print(result.stderr, end="", file=sys.stderr)
    return result.returncode


def cmd_stop(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    session = session_name(project)
    daemon = daemon_session_name(project)
    stopped = []
    for name in (session, daemon):
        if has_session(name):
            result = tmux("kill-session", "-t", f"={name}")
            if result.returncode == 0:
                stopped.append(name)
    payload = {"project": project_summary(project), "stopped": stopped}
    if args.json:
        json_print(payload)
    else:
        print(f"stopped: {', '.join(stopped) if stopped else 'none'}")
    return 0


def valid_role(role: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]+", role):
        raise ValueError(f"invalid role: {role}")
    return role


def cmd_send(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    if not has_session(session_name(project)):
        return fail(f"battlefield is not running: {project.get('name')}")
    role = valid_role(args.role)
    runtime = runtime_dir(project)
    chat_session = current_or_create_session(runtime, "resume") if not args.session else {"id": args.session}
    entry = {
        "time": iso_now(),
        "from": "user",
        "to": role,
        "type": "user_message",
        "content": args.message,
    }
    append_transcript(runtime, chat_session["id"], entry)
    writer = runtime / "shogunate_mod" / "inbox" / "write.sh"
    if not writer.exists():
        return fail(f"inbox writer not found: {writer}")
    result = subprocess.run(
        ["bash", str(writer), role, args.message, "user_message", "lord"],
        cwd=runtime,
        text=True,
        capture_output=True,
        check=False,
    )
    payload = {
        "project": project_summary(project),
        "session": chat_session,
        "role": role,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
    }
    if args.json:
        json_print(payload)
    else:
        print("sent" if result.returncode == 0 else "send failed")
        if result.stderr:
            print(result.stderr, file=sys.stderr, end="")
    return result.returncode


def cmd_roles(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    roles = roles_for_project(project)
    if args.json:
        json_print({"project": project_summary(project), "roles": roles})
    else:
        if not roles:
            print("No running roles.")
        for role in roles:
            print(f"{role['role']:<12} {role['pane']:<8} {role['cli']} {role['model']}")
    return 0


def cmd_sessions(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    data = load_sessions(runtime_dir(project))
    if args.json:
        json_print({"project": project_summary(project), **data})
    else:
        if not data["sessions"]:
            print("No app sessions.")
        for session in data["sessions"]:
            marker = "*" if session.get("id") == data.get("current") else " "
            print(f"{marker} {session.get('id')}  {session.get('mode')}  {session.get('title')}")
    return 0


def cmd_session_create(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    session = create_app_session(runtime_dir(project), mode="new", title=args.title or "")
    if args.json:
        json_print({"project": project_summary(project), "session": session})
    else:
        print(f"created {session['id']} {session['title']}")
    return 0


def cmd_transcript(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    runtime = runtime_dir(project)
    data = load_sessions(runtime)
    session_id = args.session or data.get("current", "")
    if not session_id:
        messages: list[dict[str, Any]] = []
    else:
        messages = read_transcript(runtime, session_id)
    if args.json:
        json_print({"project": project_summary(project), "session": session_id, "messages": messages})
    else:
        for message in messages:
            print(f"[{message.get('time', '')}] {message.get('from')} -> {message.get('to')}: {message.get('content')}")
    return 0


def add_json_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--json", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")

    capabilities = sub.add_parser("capabilities", help="print app API capabilities")
    add_json_arg(capabilities)
    capabilities.set_defaults(func=cmd_capabilities)

    listing = sub.add_parser("list", help="list registered battlefields")
    add_json_arg(listing)
    listing.set_defaults(func=cmd_list)

    status = sub.add_parser("status", help="show one battlefield status")
    status.add_argument("selector")
    add_json_arg(status)
    status.set_defaults(func=cmd_status)

    start = sub.add_parser("start", help="start one battlefield")
    start.add_argument("selector")
    mode = start.add_mutually_exclusive_group()
    mode.add_argument("--resume", action="store_true", help="resume the current runtime state")
    mode.add_argument("--new", action="store_true", help="start a clean new Shogunate runtime")
    start.add_argument("--attach", action="store_true")
    start.add_argument("--json", action="store_true")
    start.set_defaults(func=cmd_start)

    stop = sub.add_parser("stop", help="stop one battlefield runtime")
    stop.add_argument("selector")
    add_json_arg(stop)
    stop.set_defaults(func=cmd_stop)

    roles = sub.add_parser("roles", help="list roles in a running battlefield")
    roles.add_argument("selector")
    add_json_arg(roles)
    roles.set_defaults(func=cmd_roles)

    send = sub.add_parser("send", help="send a message to a role")
    send.add_argument("selector")
    send.add_argument("message")
    send.add_argument("--role", default="shogun")
    send.add_argument("--session", default="")
    add_json_arg(send)
    send.set_defaults(func=cmd_send)

    sessions = sub.add_parser("sessions", help="list app chat sessions")
    sessions.add_argument("selector")
    add_json_arg(sessions)
    sessions.set_defaults(func=cmd_sessions)

    session_create = sub.add_parser("session-create", help="create a new app chat session")
    session_create.add_argument("selector")
    session_create.add_argument("--title", default="")
    add_json_arg(session_create)
    session_create.set_defaults(func=cmd_session_create)

    transcript = sub.add_parser("transcript", help="show app chat transcript")
    transcript.add_argument("selector")
    transcript.add_argument("--session", default="")
    add_json_arg(transcript)
    transcript.set_defaults(func=cmd_transcript)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        return cmd_list(argparse.Namespace(json=False))
    try:
        return args.func(args)
    except ValueError as exc:
        return fail(str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
