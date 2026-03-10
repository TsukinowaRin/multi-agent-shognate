#!/usr/bin/env python3
import argparse
import errno
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
import tty
from pathlib import Path


READY_PATTERNS = {
    "claude": re.compile(r"(claude code|claude|for shortcuts|/model)", re.I),
    "codex": re.compile(r"(openai codex|codex|for shortcuts|context left|/model)", re.I),
    "gemini": re.compile(r"(type your message|yolo mode|/model|@path/to/file)", re.I),
    "copilot": re.compile(r"(copilot|github copilot|for shortcuts|/model)", re.I),
    "kimi": re.compile(r"(kimi|moonshot|for shortcuts|/model)", re.I),
    "localapi": re.compile(r"(localapi|ready:|api)", re.I),
    "opencode": re.compile(r"(opencode|for shortcuts|/model|type your message)", re.I),
    "kilo": re.compile(r"(kilo|for shortcuts|/model|type your message)", re.I),
}

CODEX_UPDATE_PATTERN = re.compile(
    r"(update available|update now|skip until next version|press enter to continue)",
    re.I,
)
GEMINI_TRUST_PATTERN = re.compile(r"(trust this folder|trust parent folder|don.t trust)", re.I)
GEMINI_HIGH_DEMAND_PATTERN = re.compile(r"(high demand|keep trying)", re.I)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--agent", required=True)
    parser.add_argument("--cli", required=True)
    parser.add_argument("--command", required=True)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--meta", required=True)
    parser.add_argument("--bootstrap", required=True)
    return parser.parse_args()


def append_meta(meta_path: Path, message: str) -> None:
    with meta_path.open("a", encoding="utf-8") as fh:
        fh.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {message}\n")


def get_col_multiplier() -> int:
    raw = os.environ.get("MAS_CLI_COL_MULTIPLIER", "1").strip()
    try:
        value = int(raw)
    except ValueError:
        return 1
    return max(1, value)


def read_prompt(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8").strip()


def copy_winsize(from_fd: int, to_fd: int) -> None:
    try:
        rows, cols = termios.tcgetwinsize(from_fd)
        cols *= get_col_multiplier()
        termios.tcsetwinsize(to_fd, (rows, cols))
    except Exception:
        pass


def send_line(fd: int, text: str) -> None:
    os.write(fd, text.encode("utf-8", errors="ignore") + b"\r")


def send_text(fd: int, text: str) -> None:
    if not text:
        return
    os.write(fd, text.encode("utf-8", errors="ignore"))


def send_enter(fd: int) -> None:
    os.write(fd, b"\r")


def deliver_bootstrap(fd: int, text: str, meta_path: Path, agent: str, cli: str) -> None:
    send_text(fd, text)
    # TUI系CLIでは本文とEnterを同一writeにすると submit されず、
    # 入力欄への貼り付けだけで終わることがあるため分離する。
    time.sleep(0.2)
    send_enter(fd)
    append_meta(meta_path, f"bootstrap delivered agent={agent} cli={cli}")


def main() -> int:
    args = parse_args()
    root = Path(args.root)
    transcript_path = Path(args.transcript)
    meta_path = Path(args.meta)
    bootstrap_path = Path(args.bootstrap)
    startup_prompt = read_prompt(bootstrap_path)
    ready_pattern = READY_PATTERNS.get(args.cli, re.compile(r"ready:", re.I))

    transcript_path.parent.mkdir(parents=True, exist_ok=True)
    meta_path.parent.mkdir(parents=True, exist_ok=True)

    master_fd, slave_fd = pty.openpty()
    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()
    stdin_tty = os.isatty(stdin_fd)
    old_tty = None

    env = os.environ.copy()
    env.pop("COLUMNS", None)
    env.pop("LINES", None)

    def on_winch(_signum, _frame):
        copy_winsize(stdin_fd, slave_fd)

    if stdin_tty:
        copy_winsize(stdin_fd, slave_fd)
        try:
            old_tty = termios.tcgetattr(stdin_fd)
            tty.setraw(stdin_fd)
        except Exception:
            old_tty = None
        signal.signal(signal.SIGWINCH, on_winch)

    try:
        proc = subprocess.Popen(
            ["bash", "-lc", args.command],
            cwd=str(root),
            env=env,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            preexec_fn=os.setsid,
            close_fds=True,
        )
    finally:
        os.close(slave_fd)

    buffer = ""
    startup_sent = not bool(startup_prompt)
    codex_update_handled = False
    gemini_trust_handled = False
    gemini_retry_handled = False

    append_meta(meta_path, f"runner start agent={args.agent} cli={args.cli}")

    with transcript_path.open("ab") as transcript:
        while True:
            read_fds = [master_fd]
            if stdin_tty:
                read_fds.append(stdin_fd)

            try:
                ready, _, _ = select.select(read_fds, [], [], 0.1)
            except InterruptedError:
                continue

            if master_fd in ready:
                try:
                    chunk = os.read(master_fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        chunk = b""
                    else:
                        raise

                if chunk:
                    os.write(stdout_fd, chunk)
                    transcript.write(chunk)
                    transcript.flush()
                    decoded = chunk.decode("utf-8", errors="ignore")
                    buffer = (buffer + decoded)[-50000:]

                    if args.cli == "codex" and not codex_update_handled and CODEX_UPDATE_PATTERN.search(buffer):
                        send_line(master_fd, "2")
                        codex_update_handled = True
                        append_meta(meta_path, f"codex update skipped agent={args.agent}")
                        time.sleep(0.3)
                        continue

                    if args.cli == "gemini":
                        if not gemini_trust_handled and GEMINI_TRUST_PATTERN.search(buffer):
                            send_line(master_fd, "1")
                            gemini_trust_handled = True
                            append_meta(meta_path, f"gemini trust accepted agent={args.agent}")
                            time.sleep(0.3)
                            continue
                        if not gemini_retry_handled and GEMINI_HIGH_DEMAND_PATTERN.search(buffer):
                            send_line(master_fd, "1")
                            gemini_retry_handled = True
                            append_meta(meta_path, f"gemini keep_trying agent={args.agent}")
                            time.sleep(0.3)
                            continue

                    if not startup_sent and ready_pattern.search(buffer):
                        deliver_bootstrap(master_fd, startup_prompt, meta_path, args.agent, args.cli)
                        startup_sent = True
                        time.sleep(0.1)
                elif proc.poll() is not None:
                    break

            if stdin_tty and stdin_fd in ready:
                try:
                    user_data = os.read(stdin_fd, 1024)
                except OSError:
                    user_data = b""
                if user_data:
                    os.write(master_fd, user_data)

            if proc.poll() is not None:
                drained = False
                try:
                    more_ready, _, _ = select.select([master_fd], [], [], 0)
                    drained = not more_ready
                except Exception:
                    drained = True
                if drained:
                    break

    if old_tty is not None:
        try:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_tty)
        except Exception:
            pass

    append_meta(meta_path, f"runner exit agent={args.agent} cli={args.cli} rc={proc.returncode}")
    return int(proc.returncode or 0)


if __name__ == "__main__":
    raise SystemExit(main())
