#!/usr/bin/env python3
"""Report provenance: pane-bound receipts and completion gate.

目的 (why this shape)
=====================
前回の system matrix で、別 role の pane が self-agent を名乗って Karo 内蔵
report だけで Shogun へ ``cmd_done`` を送る false completion が起きた。
本moduleは、reportを受領したinbox/write.sh経路とcompletion relayに対し、
「提出元paneがそのrole本人で、かつ現在のgeneration/CLI/report digestと一致
するか」を機械検出する境界を提供する。

暗号境界ではない (why not HMAC)
-------------------------------
同一ローカルユーザが悪意をもってruntime fileを直接偽造する攻撃は防げない。
HMACやsecretを導入してもローカルでのsecret管理が成立しにくく、複雑化するだけ
である。今回の事故は別role paneからの偶発的self-agent代用なので、
role/generation/pane/digest の一致確認で再現経路を止める十分な境界とする。

設計 (how it is structured)
----------------------------
全ての検証は pure function で、入力は明示的な dict/Path のみ。tmux や
filesystem の副作用は ``write_receipt`` / ``append_blocked_ledger`` /
``enable_strict_mode`` に限定し、それらも atomic replace で実装する。これに
より unit test は tmux を起動せずに acceptance 条件 1〜4 を検証できる。

strict gate は新runtimeが作る ``queue/runtime/report_provenance_required``
markerがある時だけ有効になる。marker がない既存runtimeは legacy 扱いとし、
更新後に再起動したruntimeから fail-closed に切り替わる。これにより、marker
未導入のruntimeを壊さずに段階的に境界を強制できる。
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Mapping, Optional

import yaml

# marker / ledger / receipt の配置は runtime queue の下に固定。
# 絶対pathでなくroot相対で持ち、呼び出し側がrootを渡す。
REPORT_RECEIPTS_REL = Path("queue/runtime/report_receipts")
STRICT_MARKER_REL = Path("queue/runtime/report_provenance_required")
BLOCKED_LEDGER_REL = Path("queue/runtime/report_provenance_blocked.yaml")

# provenance を要求する inbox message type。これ以外は従来どおり非report扱い。
PROVENANCE_REPORT_TYPES = frozenset({"report_received", "audit_report"})

# role_failover.py の status 語彙と同期。import 循環を避けるためここに再定義。
ROLE_STOPPED_STATUSES = frozenset({"stopped", "safe_stopped", "awaiting_handoff"})

_ROLE_RE = re.compile(r"^(shogun|gunkan|karo(?:[1-9][0-9]*)?|gunshi|ashigaru[1-9][0-9]*)$")
_ASHIGARU_RE = re.compile(r"^ashigaru[1-9][0-9]*$")
_KARO_RE = re.compile(r"^karo(?:[1-9][0-9]*)?$")

RECEIPT_SCHEMA_VERSION = 2


def is_role_name(value: Any) -> bool:
    return isinstance(value, str) and bool(_ROLE_RE.fullmatch(value))


def is_ashigaru(role: str) -> bool:
    return bool(_ASHIGARU_RE.fullmatch(role))


def expected_report_rel(role: str) -> Path:
    """role が提出すべき report file の root 相対path。

    report path は agent が自由に書けるため、provenance は「その role が本当に
    自分の report path を提出したか」をこの対応で検証する。一致しなければ
    別role の report を偽装した可能性とみなす。
    """
    if not is_role_name(role):
        raise ValueError(f"invalid role: {role!r}")
    if _ASHIGARU_RE.fullmatch(role):
        return Path("queue/reports") / f"{role}_report.yaml"
    if _KARO_RE.fullmatch(role):
        return Path("queue/reports") / "karo_report.yaml"
    if role == "gunkan":
        return Path("queue/reports") / "gunkan_report.yaml"
    if role == "gunshi":
        return Path("queue/reports") / "gunshi_report.yaml"
    if role == "shogun":
        return Path("queue/reports") / "shogun_report.yaml"
    return Path("queue/reports") / f"{role}_report.yaml"


def _normalize_report_path(report_path: Any, root: Optional[Path] = None) -> Optional[Path]:
    if report_path in (None, ""):
        return None
    p = Path(str(report_path))
    if root is not None:
        try:
            p = p.resolve() if p.is_absolute() else p
        except OSError:
            pass
    # 与えられたpathがroot相対として表現されている前提で、末尾の報告file名だけ比較。
    return p


def report_path_matches_role(role: str, report_path: Any) -> bool:
    """提出された report path が role の所期pathと一致するか。"""
    if not is_role_name(role) or report_path in (None, ""):
        return False
    expected = expected_report_rel(role)
    provided = Path(str(report_path))
    # filenameだけでは別directoryの同名fileを正規reportとして扱ってしまう。
    # root相対pathそのもの、または絶対path末尾の queue/reports/<name> 全体が
    # 一致する時だけ許可する。
    expected_parts = expected.parts
    provided_parts = provided.parts
    return len(provided_parts) >= len(expected_parts) and provided_parts[-len(expected_parts):] == expected_parts


def digest_report(report_bytes: bytes) -> str:
    """report 内容の SHA-256 hex digest。receipt 後の改変を検出する境界。"""
    if not isinstance(report_bytes, (bytes, bytearray)):
        raise TypeError("report content must be bytes")
    return hashlib.sha256(report_bytes).hexdigest()


def active_slot_cli(role_state: Optional[Mapping[str, Any]]) -> Optional[str]:
    """role_failover 状態から現slotのCLI typeを取り出す。

    primary_profile/fallback_profile には CLI type が埋まっている。provenance は
    pane metadata の @agent_cli と比較し、別CLIで動いているpaneの代用を検出する。
    """
    if not isinstance(role_state, Mapping):
        return None
    slot = role_state.get("active_slot", "primary")
    profile = role_state.get("fallback_profile") if slot == "fallback" else role_state.get("primary_profile")
    if isinstance(profile, Mapping):
        cli = profile.get("type")
        if isinstance(cli, str) and cli.strip():
            return cli.strip()
    return None


@dataclass(frozen=True)
class ProvenanceResult:
    ok: bool
    reason: str
    details: dict[str, Any] = field(default_factory=dict)

    def __bool__(self) -> bool:
        return self.ok


def verify_pane_identity(
    *,
    role: str,
    pane_meta: Mapping[str, Any],
    role_state: Optional[Mapping[str, Any]],
    report_path: Any = None,
    expected_generation: Optional[int] = None,
) -> ProvenanceResult:
    """提出元paneがそのrole本人かを検証するpure function。

    inbox/write.sh が tmux から ``@agent_id`` / ``@role_generation`` /
    ``@agent_cli_running`` / ``@agent_cli`` と ``$TMUX_PANE`` を集めて渡す。
    本関数はそれらと role_failover 状態を照合し、不一致なら理由を返す。

    検証項目 (acceptance 1):
      * pane 情報が存在する (missing_pane)
      * pane の @agent_id が role と一致 (wrong_role)
      * generation が failover 現generation と一致 (stale_generation)
      * role が停止状態でない (role_stopped)
      * CLI pane が running (cli_stopped)
      * CLI type が現slot と一致 (cli_mismatch)
      * report path が role の所期path (report_path_mismatch)
    """
    if not is_role_name(role):
        return ProvenanceResult(False, "invalid_role")
    if not isinstance(pane_meta, Mapping) or not pane_meta.get("pane"):
        return ProvenanceResult(False, "missing_pane")
    if str(pane_meta.get("agent_id", "")) != role:
        return ProvenanceResult(False, "wrong_role")

    if not isinstance(role_state, Mapping):
        return ProvenanceResult(False, "role_not_initialized")
    current_gen = role_state.get("generation")
    if not isinstance(current_gen, int) or isinstance(current_gen, bool):
        return ProvenanceResult(False, "role_not_initialized")
    pane_gen = pane_meta.get("role_generation")
    if not isinstance(pane_gen, int) or pane_gen != current_gen:
        return ProvenanceResult(False, "stale_generation")
    if expected_generation is not None and expected_generation != current_gen:
        return ProvenanceResult(False, "stale_generation")

    status = role_state.get("status")
    if status in ROLE_STOPPED_STATUSES:
        return ProvenanceResult(False, "role_stopped")

    running = str(pane_meta.get("agent_cli_running", "")).strip().lower()
    if running not in {"1", "true", "yes"}:
        return ProvenanceResult(False, "cli_stopped")

    pane_cli = pane_meta.get("agent_cli")
    expected_cli = active_slot_cli(role_state)
    if (
        isinstance(pane_cli, str)
        and pane_cli.strip()
        and isinstance(expected_cli, str)
        and pane_cli.strip() != expected_cli
    ):
        return ProvenanceResult(False, "cli_mismatch")

    if report_path is not None and str(report_path) != "":
        if not report_path_matches_role(role, report_path):
            return ProvenanceResult(False, "report_path_mismatch")

    return ProvenanceResult(
        True,
        "authorized",
        {"role": role, "generation": current_gen, "pane": pane_meta.get("pane")},
    )


def build_receipt(
    *,
    role: str,
    generation: int,
    pane: str,
    agent_cli: Optional[str],
    report_path: str,
    report_bytes: bytes,
    parent_cmd: str,
    task_id: Optional[str] = None,
) -> dict[str, Any]:
    """提出合格時に原子書き込みする receipt の中身を作るpure function。"""
    if not is_role_name(role):
        raise ValueError(f"invalid role: {role!r}")
    if not isinstance(generation, int) or isinstance(generation, bool) or generation < 1:
        raise ValueError("generation must be a positive integer")
    if not isinstance(report_bytes, (bytes, bytearray)):
        raise TypeError("report content must be bytes")
    if not bytes(report_bytes).strip():
        raise ValueError("report content must not be empty")
    parent_cmd = str(parent_cmd or "").strip()
    if not parent_cmd:
        raise ValueError("parent_cmd is required")
    normalized_task_id = str(task_id or "").strip()
    return {
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "role": role,
        "generation": generation,
        "pane": str(pane),
        "agent_cli": agent_cli,
        "report_path": str(report_path),
        "digest": digest_report(bytes(report_bytes)),
        "task_id": normalized_task_id or None,
        "parent_cmd": parent_cmd,
    }


def receipt_path(receipt_dir: Path, role: str) -> Path:
    return Path(receipt_dir) / f"{role}.yaml"


def write_receipt(receipt_dir: Path, role: str, receipt: Mapping[str, Any]) -> Path:
    """role ごとに最新report receiptを atomic replace で書く。

    同じ digest の再提出は上書きで冪等。異なる digest の再提出も最新で置き換わる
    が、completion relay 側で receipt 時点の digest とreport現内容を再照合する
    ため、receipt 後の改変は検出される (acceptance 2)。
    """
    if not is_role_name(role):
        raise ValueError(f"invalid role: {role!r}")
    if str(receipt.get("role")) != role:
        raise ValueError("receipt.role does not match target role")
    target = receipt_path(Path(receipt_dir), role)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(target.parent), suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.safe_dump(dict(receipt), fh, allow_unicode=True, sort_keys=False)
        os.replace(tmp_path, target)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        finally:
            raise
    return target


def load_receipt(receipt_dir: Path, role: str) -> Optional[dict[str, Any]]:
    path = receipt_path(Path(receipt_dir), role)
    if not path.exists():
        return None
    try:
        with path.open("r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except Exception:
        return None
    if not isinstance(data, Mapping):
        return None
    return dict(data)


def receipt_role(receipt: Optional[Mapping[str, Any]]) -> Optional[str]:
    if isinstance(receipt, Mapping):
        role = receipt.get("role")
        if isinstance(role, str) and is_role_name(role):
            return role
    return None


def receipt_generation(receipt: Optional[Mapping[str, Any]]) -> Optional[int]:
    if isinstance(receipt, Mapping):
        gen = receipt.get("generation")
        if isinstance(gen, int) and not isinstance(gen, bool) and gen > 0:
            return gen
    return None


def receipt_digest(receipt: Optional[Mapping[str, Any]]) -> Optional[str]:
    if isinstance(receipt, Mapping):
        digest = receipt.get("digest")
        if isinstance(digest, str) and digest:
            return digest
    return None


def verify_receipt_against_report(
    *,
    receipt: Optional[Mapping[str, Any]],
    role: str,
    report_bytes: bytes,
    current_generation: Optional[int],
    expected_task_id: Optional[str] = None,
    expected_parent_cmd: Optional[str] = None,
) -> ProvenanceResult:
    """completion relay が各 role の receipt と現report内容を照合する。

    acceptance 2: receipt 後に report を変更すると digest mismatch で拒否する。
    acceptance 1: receipt の role/generation が現状と一致することも確認する。
    """
    if receipt is None:
        return ProvenanceResult(False, "missing_receipt")
    if not isinstance(report_bytes, (bytes, bytearray)) or not bytes(report_bytes).strip():
        return ProvenanceResult(False, "missing_report")
    if receipt_role(receipt) != role:
        return ProvenanceResult(False, "receipt_role_mismatch")
    if receipt.get("schema_version") != RECEIPT_SCHEMA_VERSION:
        return ProvenanceResult(False, "receipt_schema_mismatch")
    if not report_path_matches_role(role, receipt.get("report_path")):
        return ProvenanceResult(False, "receipt_report_path_mismatch")
    gen = receipt_generation(receipt)
    if gen is None:
        return ProvenanceResult(False, "receipt_generation_invalid")
    if not isinstance(current_generation, int) or isinstance(current_generation, bool) or current_generation < 1:
        return ProvenanceResult(False, "current_generation_missing")
    if gen != current_generation:
        return ProvenanceResult(False, "stale_generation")
    actual_parent_cmd = str(receipt.get("parent_cmd") or "").strip()
    expected_parent_cmd = str(expected_parent_cmd or "").strip()
    if expected_parent_cmd and actual_parent_cmd != expected_parent_cmd:
        return ProvenanceResult(False, "parent_cmd_mismatch")
    expected_task_id = str(expected_task_id or "").strip()
    actual_task_id = str(receipt.get("task_id") or "").strip()
    if expected_task_id and actual_task_id != expected_task_id:
        return ProvenanceResult(False, "task_id_mismatch")
    expected_digest = receipt_digest(receipt)
    if not expected_digest:
        return ProvenanceResult(False, "receipt_digest_missing")
    if digest_report(bytes(report_bytes)) != expected_digest:
        return ProvenanceResult(False, "digest_mismatch")
    return ProvenanceResult(True, "verified")


def required_receipt_roles(cmd: Optional[Mapping[str, Any]], task_roles: Iterable[str]) -> set[str]:
    """cmd が完了に必要とする role を集める (acceptance 3)。

    ``audit_gate`` に列挙された role と、実際にcmdへ紐付くtask/reportを出した
    task_roles の和集合。全role分の receipt が揃わなければ完了できない。
    """
    roles: set[str] = set()
    if isinstance(cmd, Mapping):
        gate = cmd.get("audit_gate")
        if isinstance(gate, list):
            for r in gate:
                if isinstance(r, str) and is_role_name(r):
                    roles.add(r)
    for r in task_roles or ():
        if isinstance(r, str) and is_role_name(r):
            roles.add(r)
    return roles


@dataclass(frozen=True)
class CompletionResult:
    ok: bool
    reason: str
    missing_roles: set[str] = field(default_factory=set)
    invalid_roles: set[str] = field(default_factory=set)

    def __bool__(self) -> bool:
        return self.ok


def validate_completion(
    *,
    cmd: Optional[Mapping[str, Any]],
    task_roles: Iterable[str],
    receipts: Mapping[str, Optional[Mapping[str, Any]]],
    role_states: Mapping[str, Optional[Mapping[str, Any]]],
    report_bytes_by_role: Mapping[str, bytes],
    expected_context_by_role: Optional[Mapping[str, Mapping[str, Any]]] = None,
) -> CompletionResult:
    """全 required role の receipt と現reportを検証し、1件でも欠ければfail-closed。

    acceptance 3: 欠落・別role・stale・改変済み report なら cmd_done を送らず
    blocked ledger へ固定reasonを1件だけ記録するための理由を返す。
    acceptance 4 の strict 側呼び出し元が marker 有効時だけ本関数を使う。
    """
    required = required_receipt_roles(cmd, task_roles)
    if not required:
        return CompletionResult(False, "missing_required_roles")
    cmd_id = str(cmd.get("id") or "").strip() if isinstance(cmd, Mapping) else ""
    contexts = expected_context_by_role if isinstance(expected_context_by_role, Mapping) else {}
    missing: set[str] = set()
    invalid: set[str] = set()
    invalid_reasons: dict[str, str] = {}
    for role in sorted(required):
        receipt = receipts.get(role)
        if receipt is None:
            missing.add(role)
            continue
        rs = role_states.get(role)
        current_gen = None
        if isinstance(rs, Mapping):
            g = rs.get("generation")
            if isinstance(g, int) and not isinstance(g, bool):
                current_gen = g
        report_bytes = report_bytes_by_role.get(role, b"")
        context = contexts.get(role)
        if not isinstance(context, Mapping):
            context = {}
        result = verify_receipt_against_report(
            receipt=receipt,
            role=role,
            report_bytes=report_bytes,
            current_generation=current_gen,
            expected_task_id=context.get("task_id"),
            expected_parent_cmd=context.get("parent_cmd") or cmd_id,
        )
        if not result.ok:
            invalid.add(role)
            invalid_reasons[role] = result.reason
    if missing or invalid:
        if missing:
            reason = "missing_receipt"
        else:
            first_invalid = next(iter(sorted(invalid)))
            reason = invalid_reasons.get(first_invalid, "invalid_receipt")
        # 不合格時は代表reason1件。呼び出し側がこれをledgerへ1件だけ書く。
        return CompletionResult(False, reason, missing_roles=missing, invalid_roles=invalid)
    return CompletionResult(True, "all_receipts_verified")


# --- strict mode marker (acceptance 4) ---


def is_strict_mode(runtime_dir: Path) -> bool:
    """marker がある時だけ strict gate が有効。

    marker がない既存runtimeは legacy 扱いで、completion relay は従来挙動を
    保つ。launch.sh が新runtime起動時にmarkerを作ることで、更新再起動後に
    fail-closed に切り替わる。
    """
    return (Path(runtime_dir) / STRICT_MARKER_REL.name).exists()


def enable_strict_mode(runtime_dir: Path) -> Path:
    target = Path(runtime_dir) / STRICT_MARKER_REL.name
    target.parent.mkdir(parents=True, exist_ok=True)
    # marker は存在判定のみ。内容は空でよいが、冪等のため atomic write。
    fd, tmp_name = tempfile.mkstemp(dir=str(target.parent), suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("")
        os.replace(tmp_path, target)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        finally:
            raise
    return target


# --- blocked ledger (acceptance 3) ---


def blocked_ledger_entry(*, cmd_id: str, reason: str, missing_roles: Iterable[str] = (), invalid_roles: Iterable[str] = ()) -> dict[str, Any]:
    return {
        "cmd_id": str(cmd_id),
        "reason": str(reason),
        "missing_roles": sorted({r for r in missing_roles if is_role_name(r)}),
        "invalid_roles": sorted({r for r in invalid_roles if is_role_name(r)}),
    }


def _ledger_identity(entry: Mapping[str, Any]) -> str:
    return f"{entry.get('cmd_id')}|{entry.get('reason')}"


def append_blocked_ledger(ledger_path: Path, entry: Mapping[str, Any]) -> Path:
    """blocked ledger へ理由を1件だけ記録する。cmd_id+reason で重複抑止。

    acceptance 3: 不合格時 cmd YAML を自動書き戻さず、ledger と summary で
    明示する設計。Karoの編集中YAMLとの競合を避けるため、ここではcmdは触らない。
    """
    path = Path(ledger_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    existing: dict[str, dict[str, Any]] = {}
    if path.exists():
        try:
            with path.open("r", encoding="utf-8") as fh:
                raw = yaml.safe_load(fh)
        except Exception:
            raw = None
        if isinstance(raw, Mapping) and isinstance(raw.get("blocked"), list):
            for item in raw["blocked"]:
                if isinstance(item, Mapping):
                    existing[_ledger_identity(item)] = dict(item)
    identity = _ledger_identity(entry)
    existing[identity] = dict(entry)
    payload = {"blocked": list(existing.values())}
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            yaml.safe_dump(payload, fh, allow_unicode=True, sort_keys=False)
        os.replace(tmp_path, path)
    except Exception:
        try:
            tmp_path.unlink(missing_ok=True)
        finally:
            raise
    return path


def load_blocked_ledger(ledger_path: Path) -> list[dict[str, Any]]:
    path = Path(ledger_path)
    if not path.exists():
        return []
    try:
        with path.open("r", encoding="utf-8") as fh:
            raw = yaml.safe_load(fh)
    except Exception:
        return []
    if isinstance(raw, Mapping) and isinstance(raw.get("blocked"), list):
        return [dict(item) for item in raw["blocked"] if isinstance(item, Mapping)]
    return []
