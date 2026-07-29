#!/usr/bin/env python3
"""Unit tests for runtime bootstrap / prompt / summary pure logic.

受け入れ条件 5, 6, 7 の pure logic を bash 関数として実装し、本 test はそれを
subprocess の bash へ source して stdin/argv 経由で呼び出す。tmux や filesystem
副作用に依存せず、判定関数の入出力だけを検証する。

* acceptance 5: should_embed_startup_prompt_in_cli_command (bootstrap.sh)
  - claude / codex は argv 直接 embed (起動argv へ初動命令を渡す)
  - opencode / antigravity 等は embed しない (外部file 権威要求なし)
* acceptance 6: opencode_project_modal_detected_in_text (prompts.sh)
  - 実modal だけ判定、idle placeholder `Ask anything... tech stack of this project?`
    は modal と誤認しない (前回 system matrix B の自動Enter 無限ループ原因)
* acceptance 7: compute_bootstrap_ready_state / format_departure_readiness_message
  (summary.sh) - ready 不足時は degraded / 「出陣準備未完了」とする
"""

from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    for path in [start, *start.parents]:
        if (path / "shogunate_mod" / "manifest.yaml").is_file() and (
            path / "shogunate_mod" / "runtime" / "bootstrap.sh"
        ).is_file():
            return path
    raise RuntimeError(f"repo root not found from {start}")


ROOT = find_repo_root(Path(__file__).resolve())

BOOTSTRAP_SH = ROOT / "shogunate_mod" / "runtime" / "bootstrap.sh"
PROMPTS_SH = ROOT / "shogunate_mod" / "runtime" / "prompts.sh"
SUMMARY_SH = ROOT / "shogunate_mod" / "runtime" / "summary.sh"
LAUNCH_SH = ROOT / "shogunate_mod" / "runtime" / "launch.sh"


def run_bash(source_files, body, env=None, args=None):
    """bash へ source_files を source し body を実行する。

    body は引数として1行の関数呼び出しを渡し、最後に `echo "__RC=$?"` を出力する
    慣例を取る。戻り値は stdout。終了コードは stdout 末尾の __RC= 行から復元する。
    """
    sources = "\n".join(
        f'source "{p}"' for p in source_files
    )
    script = sources + "\n" + body
    proc = subprocess.run(
        ["bash", "-c", script, "bash", *(args or [])],
        capture_output=True,
        text=True,
        env={**os.environ, **(env or {})},
        cwd=str(ROOT),
    )
    return proc


def call_fn(source_files, call, env=None, args=None):
    """単一関数呼び出しを実行し (rc, stdout) を返す。"""
    body = call + "\nRC=$?\nprintf '__RC=%s\\n' \"$RC\"\n"
    proc = run_bash(source_files, body, env=env, args=args)
    out = proc.stdout
    rc = None
    lines = out.splitlines()
    if lines and lines[-1].startswith("__RC="):
        rc = int(lines[-1][len("__RC="):])
        out = "\n".join(lines[:-1])
    return proc, rc, out


class StartupPromptEmbeddingTests(unittest.TestCase):
    """acceptance 5: Claude startup command argv 直接 embed。"""

    def _embed(self, cli_type, env=None):
        proc, rc, out = call_fn(
            [str(BOOTSTRAP_SH)],
            f'should_embed_startup_prompt_in_cli_command "{cli_type}"',
            env=env,
        )
        self.assertEqual(
            0, proc.returncode,
            f"bash failed: {proc.stderr}",
        )
        return rc == 0

    def test_claude_embeds_startup_prompt_in_argv(self):
        # acceptance 5: Claude は起動argv へ bootstrap 本文を直接渡す。
        # システム matrix B で Claude が外部 bootstrap を prompt injection として
        # 拒否した原因を回避するため、既定で argv embed を有効にする。
        self.assertTrue(self._embed("claude"))
        # 明示的に off にすれば埋め込まない (拡張点として残す)。
        self.assertFalse(self._embed("claude", env={"MAS_CLAUDE_STARTUP_PROMPT_MODE": "off"}))

    def test_codex_embeds_startup_prompt_in_argv(self):
        # codex は従来どおり argv (positional) embed。
        self.assertTrue(self._embed("codex"))
        self.assertFalse(self._embed("codex", env={"MAS_CODEX_STARTUP_PROMPT_MODE": "off"}))

    def test_opencode_and_antigravity_do_not_embed(self):
        # OpenCode / Antigravity 等は起動argv embed を行わず、外部fileを権威として
        # 読むよう求めない fallback / modal 経路で扱う。
        for cli in ("opencode", "antigravity", "cursor", "kimi", "kilo", "localapi", "copilot", ""):
            with self.subTest(cli=cli):
                self.assertFalse(self._embed(cli))

    def test_fallback_prompt_keeps_runtime_and_target_context(self):
        proc, rc, out = call_fn(
            [str(PROMPTS_SH)],
            'bootstrap_delivery_prompt_tmux "ashigaru1" "$SCRIPT_DIR/queue/runtime/bootstrap_ashigaru1.md"',
            env={
                "SCRIPT_DIR": "/runtime/shogunate",
                "SHOGUNATE_PROJECT_DIR": "/work/target-project",
            },
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("/runtime/shogunate", out)
        self.assertIn("/work/target-project", out)
        self.assertNotIn("ready:ashigaru1", out)

    def test_ready_instruction_does_not_echo_the_literal_ack_token(self):
        proc, rc, out = call_fn(
            [str(BOOTSTRAP_SH)],
            'bootstrap_ready_instruction_text "karo"',
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertEqual(0, rc)
        self.assertNotIn("ready:karo", out)
        self.assertIn("ready", out)
        self.assertIn("karo", out)

    def test_strict_marker_setup_fails_when_helper_is_missing(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            proc, rc, out = call_fn(
                [str(LAUNCH_SH)],
                'enable_report_provenance_strict_mode "$1"',
                args=[tmp],
            )
            self.assertEqual(0, proc.returncode, proc.stderr)
            self.assertNotEqual(0, rc)


class CliStartupScreenTests(unittest.TestCase):
    """CLIのgate画面と実入力画面を取り違えない。"""

    def _ready(self, cli_type, text):
        proc, rc, out = call_fn(
            [str(BOOTSTRAP_SH)],
            'cli_ready_screen_detected "$1" "$2"',
            args=[cli_type, text],
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        return rc == 0

    def _blocker(self, cli_type, text):
        proc, rc, out = call_fn(
            [str(PROMPTS_SH)],
            'cli_startup_blocker_kind "$1" "$2"',
            args=[cli_type, text],
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertEqual(0, rc)
        return out.strip()

    def test_grok_build_composer_is_ready(self):
        screen = "Grok Build Beta  0.2.114\n│ ❯\nGrok 4.5 (high)"
        self.assertTrue(self._ready("grok", screen))

    def test_grok_conversation_screen_remains_ready_after_banner_scrolls_out(self):
        screen = "ready:grok_probe\nWorked for 7.7s\n│ ❯\nShift+Tab:mode  │  Ctrl+x:shortcuts"
        self.assertTrue(self._ready("grok", screen))

    def test_antigravity_composer_is_ready(self):
        screen = "Antigravity CLI 1.1.8\n>\n? for shortcuts\nGemini 3.6 Flash"
        self.assertTrue(self._ready("antigravity", screen))

    def test_claude_composer_is_ready(self):
        screen = "Claude Code v2.1.220\n❯ Try edit <filepath>\nmanual mode on · ? for shortcuts"
        self.assertTrue(self._ready("claude", screen))

    def test_claude_compact_auto_mode_composer_is_ready(self):
        screen = "❯ Try refactor <filepath>\n⏵⏵ auto mode on (shift+tab to cycle) · ← for agents"
        self.assertTrue(self._ready("claude", screen))

    def test_workspace_trust_prompts_are_not_ready(self):
        agy = "Do you trust the contents of this project?\n> Yes, I trust this folder\nNo, exit"
        claude = "Quick safety check: Is this a project you created or one you trust?\n1. Yes, I trust this folder\nEnter to confirm"
        self.assertFalse(self._ready("antigravity", agy))
        self.assertFalse(self._ready("claude", claude))

    def test_unknown_cli_fails_closed(self):
        self.assertFalse(self._ready("future-cli", "ready and waiting for input"))

    def test_known_startup_blockers_are_classified(self):
        self.assertEqual(
            "auth-required",
            self._blocker("antigravity", "You are currently not signed in.\nSigning in..."),
        )
        self.assertEqual(
            "usage-limit",
            self._blocker("claude", "You're out of usage credits. Run /usage-credits"),
        )
        self.assertEqual(
            "external-import-approval-required",
            self._blocker("claude", "Allow external CLAUDE.md file imports?"),
        )
        self.assertEqual("", self._blocker("grok", "Grok Build Beta 0.2.114\n│ ❯"))

    def test_trust_auto_accept_requires_exact_target_project_path(self):
        for pane_path, target_path, expected in (
            ("/work/project", "/work/project", True),
            ("/work/other", "/work/project", False),
            ("", "/work/project", False),
            ("/work/project", "", False),
        ):
            with self.subTest(pane_path=pane_path, target_path=target_path):
                proc, rc, out = call_fn(
                    [str(PROMPTS_SH)],
                    'shogunate_target_project_path_matches "$1" "$2"',
                    args=[pane_path, target_path],
                )
                self.assertEqual(0, proc.returncode, proc.stderr)
                self.assertEqual(expected, rc == 0)


class BootstrapSubmissionEvidenceTests(unittest.TestCase):
    """send-keys成功とCLI処理開始を別々に判定する。"""

    def _active(self, cli_type, text, agent="ashigaru1"):
        proc, rc, out = call_fn(
            [str(PROMPTS_SH)],
            'cli_bootstrap_activity_detected_in_text "$1" "$2" "$3"',
            args=[cli_type, text, agent],
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        return rc == 0

    def test_antigravity_generation_is_submission_evidence(self):
        self.assertTrue(self._active("antigravity", "Generating...\nesc to cancel"))

    def test_grok_waiting_is_submission_evidence(self):
        self.assertTrue(self._active("grok", "Starting session…\nWaiting for response…\nEsc:cancel"))

    def test_claude_work_is_submission_evidence(self):
        self.assertTrue(self._active("claude", "✻ Worked for 0s"))

    def test_idle_composer_is_not_submission_evidence(self):
        self.assertFalse(self._active("grok", "Grok Build Beta 0.2.114\n│ ❯"))
        self.assertFalse(self._active("antigravity", "Antigravity CLI 1.1.8\n? for shortcuts"))

    def test_role_ready_ack_is_strongest_submission_evidence(self):
        self.assertTrue(self._active("grok", "ready:ashigaru1"))


class BootstrapAckParsingTests(unittest.TestCase):
    def _ack(self, text, agent="gunshi"):
        proc, rc, out = call_fn(
            [str(BOOTSTRAP_SH)],
            'bootstrap_acknowledged_tmux "" "$1" "$2"',
            args=[agent, text],
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        return rc == 0

    def test_plain_ack_is_detected(self):
        self.assertTrue(self._ack("ready:gunshi"))

    def test_grok_ack_with_timestamp_and_scrollbar_is_detected(self):
        self.assertTrue(self._ack("    ready:gunshi          4:32 AM  █"))

    def test_ack_token_inside_sentence_is_not_detected(self):
        self.assertFalse(self._ack("Please return ready:gunshi when done"))


class BootstrapDiagnosticRedactionTests(unittest.TestCase):
    def test_diagnostic_text_redacts_auth_shaped_values(self):
        screen = (
            "user@example.com\n"
            "Open https://auth.example.test/device?code=ABCD-EFGH\n"
            "token abcdefghijklmnopqrstuvwxyz0123456789\n"
            "Grok Build Beta 0.2.114\n"
        )
        proc, rc, out = call_fn(
            [str(BOOTSTRAP_SH)],
            'redact_bootstrap_diagnostic_text "$1"',
            args=[screen],
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertEqual(0, rc)
        self.assertNotIn("user@example.com", out)
        self.assertNotIn("https://", out)
        self.assertNotIn("abcdefghijklmnopqrstuvwxyz0123456789", out)
        self.assertIn("[redacted-email]", out)
        self.assertIn("[redacted-url]", out)
        self.assertIn("[redacted-long-token]", out)
        self.assertIn("Grok Build Beta 0.2.114", out)

    def test_new_bootstrap_clears_only_that_roles_stale_diagnostic(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            diagnostic_dir = Path(tmp) / "queue" / "runtime" / "bootstrap_diagnostics"
            diagnostic_dir.mkdir(parents=True)
            stale = diagnostic_dir / "gunshi.txt"
            other = diagnostic_dir / "gunkan.txt"
            stale.write_text("old gunshi failure", encoding="utf-8")
            other.write_text("keep other role", encoding="utf-8")
            proc, rc, out = call_fn(
                [str(BOOTSTRAP_SH)],
                'clear_bootstrap_diagnostic_for_agent "gunshi"',
                env={"SCRIPT_DIR": tmp},
            )
            self.assertEqual(0, proc.returncode, proc.stderr)
            self.assertEqual(0, rc)
            self.assertFalse(stale.exists())
            self.assertTrue(other.exists())


class OpenCodeModalDetectionTests(unittest.TestCase):
    """acceptance 6: idle placeholder を modal と誤認しない。"""

    def _modal(self, text, env=None):
        proc, rc, out = call_fn(
            [str(PROMPTS_SH)],
            f'opencode_project_modal_detected_in_text "$1"',
            env=env,
            args=[text],
        )
        self.assertEqual(0, proc.returncode, f"bash failed: {proc.stderr}")
        return rc == 0

    def test_real_modal_detected(self):
        # OpenCode が新規project で出す実modal の見出し。これらは modal と判定する。
        self.assertTrue(self._modal("What is this project?"))
        self.assertTrue(self._modal("  What is the project?"))
        self.assertTrue(self._modal("What is this project"))
        self.assertTrue(self._modal("Configure your project"))
        self.assertTrue(self._modal("Select a project"))

    def test_idle_placeholder_not_detected(self):
        # acceptance 6: idle placeholder `Ask anything... What is the tech stack
        # of this project?` を modal と誤認してはならない (自動Enter 無限ループ)。
        self.assertFalse(self._modal("Ask anything... What is the tech stack of this project?"))
        self.assertFalse(self._modal("Ask anything... What is the tech stack of this project?"))
        # 従来の緩い `project\\?"` が拾っていた末尾 `project?"` 単体も弾く。
        self.assertFalse(self._modal('some random text project?"'))
        self.assertFalse(self._modal(""))

    def test_modal_detector_runs_via_tmux_wrapper(self):
        # opencode_project_prompt_detected_tmux は tmux capture に依存する。tmux 未起動・
        # 存在しないpane では capture が空になり modal 検出は起きない (無限自動入力なし)。
        # ここでは純関数経路で false を返すことだけ副作用なしで確認する。
        proc, rc, out = call_fn(
            [str(PROMPTS_SH)],
            'opencode_project_prompt_detected_tmux "__nonexistent_pane__driver_test"',
            args=[],
        )
        if rc is not None:
            self.assertNotEqual(0, rc)


class BootstrapReadinessSummaryTests(unittest.TestCase):
    """acceptance 7: ready 不足時は degraded / 未完了 summary。"""

    def _state(self, ready, total, pending):
        proc, rc, out = call_fn(
            [str(SUMMARY_SH)],
            f'compute_bootstrap_ready_state "{ready}" "{total}" "{pending}"',
        )
        self.assertEqual(0, proc.returncode, f"bash failed: {proc.stderr}")
        return out.strip()

    def assertState(self, ready, total, pending, expected):
        self.assertEqual(expected, self._state(ready, total, pending))

    def test_all_ready_is_ready(self):
        self.assertState(4, 4, 0, "ready")

    def test_pending_is_degraded(self):
        # bootstrap pending が1件でもあれば ready 未完了扱い (false completion 防止)。
        self.assertState(4, 4, 1, "degraded")

    def test_partial_ready_is_degraded(self):
        self.assertState(2, 4, 0, "degraded")

    def test_summary_uses_actual_ready_ack_count_even_when_pending_is_zero(self):
        proc, rc, out = call_fn(
            [str(SUMMARY_SH)],
            'CURRENT_BOOTSTRAP_READY_COUNT=4 CURRENT_BOOTSTRAP_TOTAL_COUNT=6 CURRENT_BOOTSTRAP_PENDING_COUNT=0 current_bootstrap_ready_state',
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertEqual("degraded", out.strip())

    def test_zero_total_is_degraded(self):
        self.assertState(0, 0, 0, "degraded")

    def test_ready_message_when_ready(self):
        proc, rc, out = call_fn(
            [str(SUMMARY_SH)], 'format_departure_readiness_message "ready"',
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("出陣準備完了", out)

    def test_unready_message_when_degraded(self):
        proc, rc, out = call_fn(
            [str(SUMMARY_SH)], 'format_departure_readiness_message "degraded"',
        )
        self.assertEqual(0, proc.returncode, proc.stderr)
        self.assertIn("出陣準備未完了", out)

    def test_degraded_state_written_to_runtime_yaml(self):
        # acceptance 7: ready 不足時は runtime state file へ degraded を記録し、
        # summary が state を読んで false completion しない仕組みを提供する。
        import tempfile
        import yaml
        with tempfile.TemporaryDirectory() as tmp:
            runtime_dir = Path(tmp) / "rt"
            proc, rc, out = call_fn(
                [str(SUMMARY_SH)],
                f'write_bootstrap_ready_state "degraded" 2 4 {runtime_dir!s}',
            )
            self.assertEqual(0, proc.returncode, proc.stderr)
            state_file = runtime_dir / "bootstrap_ready_state.yaml"
            self.assertTrue(state_file.is_file())
            data = yaml.safe_load(state_file.read_text(encoding="utf-8"))
            self.assertEqual("degraded", data["state"])
            self.assertEqual(2, data["ready_count"])
            self.assertEqual(4, data["total_count"])


if __name__ == "__main__":
    unittest.main()
