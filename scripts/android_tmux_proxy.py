#!/usr/bin/env python3
import os
import select
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TMUX = os.environ.get("TMUX_BIN", "tmux")
SESSION = os.environ.get("GOZA_SESSION_NAME", "goza-no-ma")
WINDOW = os.environ.get("GOZA_WINDOW_NAME", "overview")
REFRESH = float(os.environ.get("ANDROID_PROXY_REFRESH", "0.8"))
TARGET_AGENT = sys.argv[1] if len(sys.argv) > 1 else ""


def run_tmux(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([TMUX, *args], text=True, capture_output=True)


def tmux_output(*args: str) -> str:
    proc = run_tmux(*args)
    if proc.returncode != 0:
        return ""
    return proc.stdout


def resolve_target(agent_id: str) -> str:
    out = tmux_output("list-panes", "-t", f"{SESSION}:{WINDOW}", "-F", "#{pane_id}")
    for pane_id in out.splitlines():
        pane_id = pane_id.strip()
        if not pane_id:
            continue
        current = tmux_output("show-options", "-p", "-t", pane_id, "-v", "@agent_id").strip()
        if current == agent_id:
            return pane_id
    return ""


def capture_target(target: str) -> str:
    if not target:
        return "[android-proxy] target unresolved\n"
    content = tmux_output("capture-pane", "-p", "-e", "-t", target, "-S", "-500")
    return content if content else "[android-proxy] target has no output\n"


def send_line(target: str, text: str) -> None:
    if not target:
        return
    if text:
        run_tmux("send-keys", "-l", "-t", target, text)
        time.sleep(0.3)
    run_tmux("send-keys", "-t", target, "Enter")


def redraw(content: str) -> None:
    sys.stdout.write("\033[H\033[2J")
    sys.stdout.write(content)
    if content and not content.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()


def main() -> int:
    if not TARGET_AGENT:
        sys.stderr.write("usage: android_tmux_proxy.py <agent_id>\n")
        return 1

    last = None
    while True:
        target = resolve_target(TARGET_AGENT)
        content = capture_target(target)
        if content != last:
            redraw(content)
            last = content

        readable, _, _ = select.select([sys.stdin], [], [], REFRESH)
        if sys.stdin in readable:
            line = sys.stdin.readline()
            if line == "":
                time.sleep(REFRESH)
                continue
            send_line(target, line.rstrip("\n"))
            updated = capture_target(resolve_target(TARGET_AGENT))
            if updated != last:
                redraw(updated)
                last = updated


if __name__ == "__main__":
    raise SystemExit(main())
