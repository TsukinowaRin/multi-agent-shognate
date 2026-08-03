#!/usr/bin/env python3
"""Small sqlite3-shell compatibility helper for AGMSG tests.

Production AGMSG still requires the real sqlite3 executable. This helper only
lets the official AGMSG shell scripts exercise a real SQLite database in test
environments where Python 3.12 is present but the sqlite3 shell is not.
"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any


def readfile(path: str) -> bytes | None:
    try:
        return Path(path).read_bytes()
    except OSError:
        return None


def writefile(path: str, value: Any) -> int | None:
    try:
        data = value if isinstance(value, bytes) else str(value).encode("utf-8")
        Path(path).write_bytes(data)
        return len(data)
    except OSError:
        return None


def parse_args(argv: list[str]) -> tuple[str, str, list[str], str]:
    separator = "|"
    commands: list[str] = []
    mode = "plain"
    index = 0
    while index < len(argv):
        item = argv[index]
        if item == "-escape":
            index += 2
        elif item == "-cmd":
            commands.append(argv[index + 1])
            index += 2
        elif item == "-separator":
            separator = argv[index + 1]
            index += 2
        elif item == "-json":
            mode = "json"
            index += 1
        elif item in {"-batch", "-noheader"}:
            index += 1
        elif item.startswith("-"):
            raise ValueError(f"unsupported sqlite3 option: {item}")
        else:
            break
    if index >= len(argv):
        raise ValueError("database path is required")
    database = argv[index]
    sql = " ".join(argv[index + 1 :]) if index + 1 < len(argv) else sys.stdin.read()
    return database, sql, commands, separator if mode == "plain" else "json"


def statements(sql: str) -> list[str]:
    result: list[str] = []
    buffer = ""
    for char in sql:
        buffer += char
        if char == ";" and sqlite3.complete_statement(buffer):
            if buffer.strip():
                result.append(buffer.strip())
            buffer = ""
    if buffer.strip():
        result.append(buffer.strip())
    return result


def render(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def main(argv: list[str]) -> int:
    database, sql, commands, output_mode = parse_args(argv)
    connection = sqlite3.connect(database, timeout=5)
    connection.create_function("readfile", 1, readfile)
    connection.create_function("writefile", 2, writefile)
    try:
        for command in commands:
            if command.startswith(".timeout "):
                milliseconds = int(command.split(None, 1)[1])
                connection.execute(f"PRAGMA busy_timeout={milliseconds}")
            elif command.strip():
                raise ValueError(f"unsupported sqlite3 command: {command}")
        for statement in statements(sql):
            cursor = connection.execute(statement)
            if cursor.description is None:
                continue
            rows = cursor.fetchall()
            if output_mode == "json":
                columns = [item[0] for item in cursor.description]
                for row in rows:
                    print(
                        json.dumps(
                            dict(zip(columns, row, strict=True)),
                            ensure_ascii=False,
                            separators=(",", ":"),
                        )
                    )
            else:
                for row in rows:
                    print(output_mode.join(render(value) for value in row))
        connection.commit()
    finally:
        connection.close()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (ValueError, sqlite3.Error) as exc:
        print(f"sqlite3-python-cli: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
