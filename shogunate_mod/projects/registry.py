#!/usr/bin/env python3
"""Registered Shogunate project registry."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


def registry_path() -> Path:
    override = os.environ.get("SHOGUNATE_PROJECT_REGISTRY")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".shogunate" / "projects.json"


def stable_id(path: str) -> str:
    return hashlib.sha1(path.encode("utf-8")).hexdigest()[:12]


def normalize_path(path: str) -> str:
    if not path.strip():
        raise ValueError("project path is empty")
    project = Path(path).expanduser()
    if not project.is_dir():
        raise ValueError(f"project directory not found: {path}")
    return str(project.resolve())


def default_name(path: str) -> str:
    return Path(path).name or "project"


def load() -> dict[str, Any]:
    path = registry_path()
    if not path.exists():
        return {"current": "", "projects": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"current": "", "projects": []}
    if not isinstance(data, dict):
        return {"current": "", "projects": []}
    projects = data.get("projects")
    if not isinstance(projects, list):
        projects = []
    current = data.get("current")
    return {
        "current": current if isinstance(current, str) else "",
        "projects": [p for p in projects if isinstance(p, dict) and p.get("path")],
    }


def save(data: dict[str, Any]) -> None:
    path = registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def find_project(data: dict[str, Any], selector: str) -> dict[str, Any] | None:
    needle = selector.removeprefix("@").strip()
    if not needle:
        return None
    for project in data["projects"]:
        if needle in {
            str(project.get("id", "")),
            str(project.get("name", "")),
            str(project.get("path", "")),
        }:
            return project
    matches = [
        project
        for project in data["projects"]
        if str(project.get("name", "")).startswith(needle)
        or str(project.get("path", "")).endswith(needle)
    ]
    return matches[0] if len(matches) == 1 else None


def upsert(path: str, name: str = "", make_current: bool = False) -> dict[str, Any]:
    normalized = normalize_path(path)
    data = load()
    now = int(time.time())
    existing = next((p for p in data["projects"] if p.get("path") == normalized), None)
    project = {
        "id": existing.get("id") if existing else stable_id(normalized),
        "name": name.strip() or (existing.get("name") if existing else default_name(normalized)),
        "path": normalized,
        "last_opened_at": now,
    }
    data["projects"] = [p for p in data["projects"] if p.get("path") != normalized]
    data["projects"].insert(0, project)
    if make_current or not data.get("current"):
        data["current"] = project["id"]
    save(data)
    return project


def cmd_add(args: argparse.Namespace) -> int:
    project = upsert(args.path, args.name or "", make_current=args.select)
    print(f"registered {project['id']} {project['name']} {project['path']}")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    data = load()
    current = data.get("current", "")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
        return 0
    if not data["projects"]:
        print("No registered projects.")
        return 0
    for project in data["projects"]:
        marker = "*" if project.get("id") == current else " "
        print(f"{marker} {project.get('id')}  {project.get('name')}  {project.get('path')}")
    return 0


def cmd_select(args: argparse.Namespace) -> int:
    data = load()
    project = find_project(data, args.selector)
    if project is None:
        print(f"project not found: {args.selector}", file=sys.stderr)
        return 1
    data["current"] = project["id"]
    project["last_opened_at"] = int(time.time())
    data["projects"] = [p for p in data["projects"] if p.get("id") != project["id"]]
    data["projects"].insert(0, project)
    save(data)
    print(f"selected {project['id']} {project['name']} {project['path']}")
    return 0


def cmd_current(args: argparse.Namespace) -> int:
    data = load()
    project = find_project(data, data.get("current", ""))
    if project is None:
        return 1
    print(project["path"] if args.path else f"{project['id']} {project['name']} {project['path']}")
    return 0


def cmd_resolve(args: argparse.Namespace) -> int:
    data = load()
    selector = args.selector or data.get("current", "")
    project = find_project(data, selector)
    if project is None:
        return 1
    print(project["path"])
    return 0


def cmd_remove(args: argparse.Namespace) -> int:
    data = load()
    project = find_project(data, args.selector)
    if project is None:
        print(f"project not found: {args.selector}", file=sys.stderr)
        return 1
    data["projects"] = [p for p in data["projects"] if p.get("id") != project["id"]]
    if data.get("current") == project["id"]:
        data["current"] = data["projects"][0]["id"] if data["projects"] else ""
    save(data)
    print(f"removed {project['id']} {project['name']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command")

    add = sub.add_parser("add", help="register a project path")
    add.add_argument("path")
    add.add_argument("--name", default="")
    add.add_argument("--select", action="store_true")
    add.set_defaults(func=cmd_add)

    listing = sub.add_parser("list", help="list registered projects")
    listing.add_argument("--json", action="store_true")
    listing.set_defaults(func=cmd_list)

    select = sub.add_parser("select", help="select the current project")
    select.add_argument("selector")
    select.set_defaults(func=cmd_select)

    current = sub.add_parser("current", help="print the current registered project")
    current.add_argument("--path", action="store_true")
    current.set_defaults(func=cmd_current)

    resolve = sub.add_parser("resolve", help="print a registered project path")
    resolve.add_argument("selector", nargs="?")
    resolve.set_defaults(func=cmd_resolve)

    remove = sub.add_parser("remove", help="remove a registered project")
    remove.add_argument("selector")
    remove.set_defaults(func=cmd_remove)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        return cmd_list(argparse.Namespace(json=False))
    try:
        return args.func(args)
    except ValueError as exc:
        print(f"shogunate projects: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
