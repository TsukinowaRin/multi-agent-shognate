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
AGENT_CLI_COMMANDS = {
    "agy",
    "antigravity",
    "claude",
    "codex",
    "copilot",
    "cursor",
    "kilo",
    "kimi",
    "opencode",
}
SHELL_COMMANDS = {"bash", "dash", "fish", "sh", "tmux", "zsh"}


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


def process_table() -> dict[int, tuple[int, str]]:
    result = subprocess.run(
        ["ps", "-eo", "pid=,ppid=,args="],
        text=True,
        capture_output=True,
        check=False,
    )
    table: dict[int, tuple[int, str]] = {}
    if result.returncode != 0:
        return table
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
        except ValueError:
            continue
        table[pid] = (ppid, parts[2])
    return table


def command_basename(args: str) -> str:
    first = args.strip().split(None, 1)[0] if args.strip() else ""
    return Path(first).name


def descendant_process_args(root_pid: int, table: dict[int, tuple[int, str]]) -> list[str]:
    children: dict[int, list[int]] = {}
    for pid, (ppid, _) in table.items():
        children.setdefault(ppid, []).append(pid)
    found: list[str] = []
    stack = list(children.get(root_pid, []))
    while stack:
        pid = stack.pop()
        entry = table.get(pid)
        if not entry:
            continue
        found.append(entry[1])
        stack.extend(children.get(pid, []))
    return found


def active_pane_command(pane_pid: str, pane_current_command: str, table: dict[int, tuple[int, str]]) -> str:
    try:
        root_pid = int(pane_pid)
    except ValueError:
        return pane_current_command
    descendants = descendant_process_args(root_pid, table)
    for args in descendants:
        name = command_basename(args).lower()
        if name in AGENT_CLI_COMMANDS:
            return name
    for args in descendants:
        name = command_basename(args)
        if name and name.lower() not in SHELL_COMMANDS:
            return name
    return pane_current_command


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


def outbox_store(runtime: Path) -> Path:
    return runtime / APP_QUEUE / "outbox.json"


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


def load_outbox(runtime: Path) -> list[dict[str, Any]]:
    path = outbox_store(runtime)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []
    if not isinstance(data, dict):
        return []
    messages = data.get("pending")
    if not isinstance(messages, list):
        return []
    return [message for message in messages if isinstance(message, dict) and message.get("id")]


def save_outbox(runtime: Path, messages: list[dict[str, Any]]) -> None:
    path = outbox_store(runtime)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"pending": messages}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


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
        "pending_messages": len(load_outbox(runtime)),
    }


def append_transcript(runtime: Path, session_id: str, entry: dict[str, Any]) -> None:
    directory = session_dir(runtime, session_id)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "messages.jsonl"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def new_message_id() -> str:
    return f"msg-{time.time_ns()}"


def queue_message(runtime: Path, message: dict[str, Any]) -> None:
    pending = load_outbox(runtime)
    pending.append(message)
    save_outbox(runtime, pending)


def inbox_writer(runtime: Path) -> Path:
    return runtime / "shogunate_mod" / "inbox" / "write.sh"


def deliver_message(runtime: Path, message: dict[str, Any]) -> subprocess.CompletedProcess[str]:
    writer = inbox_writer(runtime)
    if not writer.exists():
        raise FileNotFoundError(str(writer))
    return subprocess.run(
        [
            "bash",
            str(writer),
            str(message["role"]),
            str(message["content"]),
            "user_message",
            "lord",
        ],
        cwd=runtime,
        text=True,
        capture_output=True,
        check=False,
    )


def wait_for_inbox_writer(runtime: Path, timeout_sec: float) -> bool:
    deadline = time.monotonic() + max(0.0, timeout_sec)
    while True:
        if inbox_writer(runtime).exists():
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.25)


def flush_pending_messages(project: dict[str, Any], timeout_sec: float = 0.0) -> dict[str, Any]:
    runtime = runtime_dir(project)
    pending = load_outbox(runtime)
    if not pending:
        return {"attempted": 0, "delivered": 0, "remaining": 0, "errors": []}
    wait_for_inbox_writer(runtime, timeout_sec)
    remaining: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    delivered = 0
    for message in pending:
        try:
            result = deliver_message(runtime, message)
        except FileNotFoundError as exc:
            remaining.append(message)
            errors.append({"id": str(message.get("id", "")), "error": f"inbox writer not found: {exc}"})
            continue
        if result.returncode == 0:
            delivered += 1
            append_transcript(
                runtime,
                str(message.get("session", "")),
                {
                    "time": iso_now(),
                    "from": "system",
                    "to": str(message.get("role", "")),
                    "type": "delivery_status",
                    "message_id": str(message.get("id", "")),
                    "delivery": "delivered",
                },
            )
        else:
            remaining.append(message)
            errors.append(
                {
                    "id": str(message.get("id", "")),
                    "error": result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}",
                }
            )
    save_outbox(runtime, remaining)
    return {"attempted": len(pending), "delivered": delivered, "remaining": len(remaining), "errors": errors}


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
    proc_table = process_table()
    result = tmux(
        "list-panes",
        "-s",
        "-t",
        session,
        "-F",
        "#{pane_id}\t#{window_name}\t#{pane_index}\t#{@agent_id}\t#{@agent_cli}\t#{@model_name}\t#{pane_current_command}\t#{pane_pid}",
    )
    roles = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 8:
            continue
        pane_id, window, pane_index, agent_id, cli, model, pane_current_command, pane_pid = parts[:8]
        if not agent_id:
            continue
        current_command = active_pane_command(pane_pid, pane_current_command, proc_table)
        roles.append(
            {
                "role": agent_id,
                "pane": pane_id,
                "window": window,
                "pane_index": pane_index,
                "cli": cli,
                "model": model,
                "current_command": current_command,
                "pane_current_command": pane_current_command,
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
                "offline_history": True,
                "pending_messages": True,
                "send_start": True,
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
                "shogunate battlefield send <project> --role shogun --start <message>",
                "shogunate battlefield outbox <project> --json",
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


def launch_runtime(
    runtime: Path,
    launch_args: list[str],
    attach: bool = False,
    probe_timeout: float = 1.0,
) -> dict[str, Any]:
    if attach:
        result = subprocess.run(launch_args, text=True, capture_output=True, check=False)
        return {
            "command": launch_args,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "pid": None,
            "running": False,
            "log": "",
        }

    log = runtime / APP_QUEUE / f"launch-{time.strftime('%Y%m%d-%H%M%S')}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w", encoding="utf-8") as handle:
        process = subprocess.Popen(
            launch_args,
            text=True,
            stdout=handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + max(0.0, probe_timeout)
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.05)
        returncode = process.poll()
    try:
        stdout = log.read_text(encoding="utf-8")
    except OSError:
        stdout = ""
    return {
        "command": launch_args,
        "returncode": returncode,
        "stdout": stdout,
        "stderr": "",
        "pid": process.pid,
        "running": returncode is None,
        "log": str(log),
    }


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
    launch = launch_runtime(runtime, launch_args, attach=args.attach, probe_timeout=args.launch_probe_timeout)
    launch_ok = launch["returncode"] in (0, None)
    pending_delivery = (
        flush_pending_messages(project, timeout_sec=args.deliver_pending_timeout)
        if launch_ok
        else {"attempted": len(load_outbox(runtime)), "delivered": 0, "remaining": len(load_outbox(runtime)), "errors": []}
    )
    payload = {
        "project": project_summary(project),
        "session": chat_session,
        "pending_delivery": pending_delivery,
        **launch,
    }
    if args.json:
        json_print(payload)
    else:
        print(launch["stdout"], end="")
        print(launch["stderr"], end="", file=sys.stderr)
        if launch.get("running") and launch.get("log"):
            print(f"launch is still running; log: {launch['log']}")
    return 0 if launch_ok else int(launch["returncode"])


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
    role = valid_role(args.role)
    runtime = runtime_dir(project)
    chat_session = current_or_create_session(runtime, "resume") if not args.session else {"id": args.session}
    message_id = new_message_id()
    entry = {
        "id": message_id,
        "time": iso_now(),
        "from": "user",
        "to": role,
        "type": "user_message",
        "delivery": "pending",
        "content": args.message,
    }
    append_transcript(runtime, chat_session["id"], entry)

    start_payload: dict[str, Any] | None = None
    running = has_session(session_name(project))
    queued_message = {
        "id": message_id,
        "time": entry["time"],
        "session": chat_session["id"],
        "role": role,
        "content": args.message,
    }
    if not running and not args.start:
        queue_message(runtime, queued_message)
        payload = {
            "project": project_summary(project),
            "session": chat_session,
            "role": role,
            "queued": True,
            "start": start_payload,
            "returncode": 0,
            "stdout": "",
            "stderr": "",
        }
        if args.json:
            json_print(payload)
        else:
            print("queued; start Shogunate to deliver this message")
        return 0

    if args.start and not running:
        command = shogunate_command()
        if not command:
            return fail("shogunate command not found in PATH; set SHOGUNATE_COMMAND")
        launch_args = [command, "--project", f"@{project['id']}", "resume", "--no-attach"]
        start_payload = launch_runtime(runtime, launch_args, attach=False, probe_timeout=args.launch_probe_timeout)
        launch_ok = start_payload["returncode"] in (0, None)
        if not launch_ok:
            queue_message(runtime, queued_message)
            payload = {
                "project": project_summary(project),
                "session": chat_session,
                "role": role,
                "queued": True,
                "start": start_payload,
                "returncode": start_payload["returncode"],
                "stdout": start_payload["stdout"],
                "stderr": start_payload["stderr"],
            }
            if args.json:
                json_print(payload)
            else:
                print("queued; start failed")
                if start_payload["stderr"]:
                    print(start_payload["stderr"], file=sys.stderr, end="")
            return int(start_payload["returncode"])

    try:
        if args.start:
            wait_for_inbox_writer(runtime, args.deliver_pending_timeout)
        result = deliver_message(runtime, queued_message)
    except FileNotFoundError:
        queue_message(runtime, queued_message)
        payload = {
            "project": project_summary(project),
            "session": chat_session,
            "role": role,
            "queued": True,
            "start": start_payload,
            "returncode": 0,
            "stdout": "",
            "stderr": "",
        }
        if args.json:
            json_print(payload)
        else:
            print("queued; start Shogunate to deliver this message")
        return 0

    if result.returncode == 0:
        append_transcript(
            runtime,
            chat_session["id"],
            {
                "time": iso_now(),
                "from": "system",
                "to": role,
                "type": "delivery_status",
                "message_id": message_id,
                "delivery": "delivered",
            },
        )
    else:
        queue_message(runtime, queued_message)
    payload = {
        "project": project_summary(project),
        "session": chat_session,
        "role": role,
        "queued": result.returncode != 0,
        "start": start_payload,
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


def cmd_outbox(args: argparse.Namespace) -> int:
    project = resolve_project(args.selector)
    runtime = runtime_dir(project)
    pending = load_outbox(runtime)
    payload = {"project": project_summary(project), "pending": pending, "count": len(pending)}
    if args.json:
        json_print(payload)
    else:
        if not pending:
            print("No pending messages.")
        for message in pending:
            print(f"{message.get('id')}  {message.get('session')}  {message.get('role')}: {message.get('content')}")
    return 0


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
    start.add_argument("--launch-probe-timeout", type=float, default=1.0)
    start.add_argument("--deliver-pending-timeout", type=float, default=15.0)
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
    send.add_argument("--start", action="store_true", help="resume the battlefield before delivering")
    send.add_argument("--launch-probe-timeout", type=float, default=1.0)
    send.add_argument("--deliver-pending-timeout", type=float, default=15.0)
    add_json_arg(send)
    send.set_defaults(func=cmd_send)

    outbox = sub.add_parser("outbox", help="list messages queued while the battlefield is stopped")
    outbox.add_argument("selector")
    add_json_arg(outbox)
    outbox.set_defaults(func=cmd_outbox)

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
