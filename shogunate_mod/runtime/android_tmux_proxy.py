#!/usr/bin/env python3
"""Bridge legacy Android tmux sessions to Shogunate agent panes.

The Android app now prefers agent targets such as ``agent:shogun``.  This
proxy keeps older ``shogun`` / ``multiagent`` tmux targets useful when
``MAS_ENABLE_ANDROID_COMPAT=1`` by mirroring the real pane content and
forwarding line input to the pane with the matching ``@agent_id``.
"""

from __future__ import annotations

import argparse
import os
import select
import subprocess
import sys
import time


COMPAT_SESSIONS = {"shogun", "gunkan", "gunshi", "multiagent"}


def tmux(*args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["tmux", *args],
        text=True,
        capture_output=True,
        check=check,
    )


def resolve_agent_pane(agent_id: str) -> str:
    current_pane = os.environ.get("TMUX_PANE", "")
    preferred_sessions = [
        os.environ.get("GOZA_SESSION_NAME", ""),
        os.environ.get("SHOGUNATE_SESSION_NAME", ""),
        "shogunate",
    ]

    result = tmux("list-panes", "-a", "-F", "#{pane_id}\t#{session_name}\t#{@agent_id}")
    if result.returncode != 0:
        return ""

    candidates: list[tuple[int, str]] = []
    for line in result.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        pane_id, session_name, pane_agent = parts
        if pane_id == current_pane or pane_agent != agent_id:
            continue
        try:
            rank = preferred_sessions.index(session_name)
        except ValueError:
            rank = 100 if session_name not in COMPAT_SESSIONS else 200
        candidates.append((rank, pane_id))

    if not candidates:
        return ""
    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def capture_pane(target: str) -> str:
    result = tmux("capture-pane", "-e", "-p", "-S", "-120", "-t", target)
    if result.returncode != 0:
        return f"[Shogunate Android proxy] target unavailable: {target}\n{result.stderr.strip()}"
    return result.stdout.rstrip("\n")


def send_line(target: str, text: str) -> None:
    if text:
        tmux("send-keys", "-t", target, "-l", text)
    tmux("send-keys", "-t", target, "Enter")


def send_control(target: str, data: bytes) -> None:
    if data == b"\x03":
        tmux("send-keys", "-t", target, "C-c")
    elif data == b"\x04":
        tmux("send-keys", "-t", target, "C-d")


def render(agent_id: str, target: str) -> None:
    sys.stdout.write("\033[H\033[2J")
    sys.stdout.write(f"Shogunate Android compatibility proxy: {agent_id} -> {target or 'not found'}\n")
    sys.stdout.write("Input lines are forwarded to the real Shogunate pane.\n\n")
    if target:
        sys.stdout.write(capture_pane(target))
    else:
        sys.stdout.write(
            "No pane with the requested @agent_id was found.\n"
            "Start Shogunate runtime or use the Android app's Pair flow again."
        )
    sys.stdout.write("\n")
    sys.stdout.flush()


def run(agent_id: str, interval: float) -> int:
    buffer = bytearray()
    next_render = 0.0
    target = ""

    while True:
        now = time.monotonic()
        if now >= next_render:
            target = resolve_agent_pane(agent_id)
            render(agent_id, target)
            next_render = now + interval

        readable, _, _ = select.select([sys.stdin], [], [], 0.2)
        if not readable:
            continue
        data = os.read(sys.stdin.fileno(), 4096)
        if not data:
            return 0
        if data in (b"\x03", b"\x04"):
            if target:
                send_control(target, data)
            continue
        for byte in data:
            if byte in (10, 13):
                if target:
                    send_line(target, buffer.decode("utf-8", errors="replace"))
                buffer.clear()
            elif byte == 127:
                if buffer:
                    buffer.pop()
            elif byte >= 32:
                buffer.append(byte)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("agent_id", help="agent id to mirror, e.g. shogun or ashigaru1")
    parser.add_argument("--interval", type=float, default=1.0, help="refresh interval in seconds")
    args = parser.parse_args(argv)
    return run(args.agent_id, max(args.interval, 0.2))


if __name__ == "__main__":
    raise SystemExit(main())
