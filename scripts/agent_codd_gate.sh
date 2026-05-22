#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/agent_codd_gate.sh <agent_id> <task_or_cmd_id> [verify|build|audit|version]

Runs the integrated CoDD wrapper from an agent workflow and writes a durable
runtime report under queue/runtime/codd/.

Environment:
  CODD_AGENT_AUTO_INSTALL=1      Auto-install codd-dev through scripts/codd_check.sh
  CODD_AGENT_REPORT_DIR=...      Override report directory
  CODD_AGENT_LOG_DIR=...         Override log directory
  CODD_AGENT_RUNNER=...          Override runner for tests
EOF
}

yaml_quote() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

sanitize_id() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
        echo "Invalid ${label}: ${value}" >&2
        return 2
    fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage >&2
    exit 2
fi

AGENT_ID="$1"
TASK_ID="$2"
CODD_COMMAND="${3:-verify}"

sanitize_id "$AGENT_ID" "agent_id"
sanitize_id "$TASK_ID" "task_or_cmd_id"

case "$CODD_COMMAND" in
    verify|build|audit|version) ;;
    *)
        echo "Invalid CoDD command: ${CODD_COMMAND}" >&2
        exit 2
        ;;
esac

REPORT_DIR="${CODD_AGENT_REPORT_DIR:-${PROJECT_ROOT}/queue/runtime/codd}"
LOG_DIR="${CODD_AGENT_LOG_DIR:-${REPORT_DIR}/logs}"
RUNNER="${CODD_AGENT_RUNNER:-${PROJECT_ROOT}/scripts/codd_check.sh}"
AUTO_INSTALL="${CODD_AGENT_AUTO_INSTALL:-1}"
TIMESTAMP="$(date -Iseconds)"
REPORT_PATH="${REPORT_DIR}/${AGENT_ID}_${TASK_ID}_${CODD_COMMAND}.yaml"
LOG_PATH="${LOG_DIR}/${AGENT_ID}_${TASK_ID}_${CODD_COMMAND}.log"

mkdir -p "$REPORT_DIR" "$LOG_DIR"

set +e
CODD_AUTO_INSTALL="$AUTO_INSTALL" "$RUNNER" "$CODD_COMMAND" >"${LOG_PATH}.tmp" 2>&1
EXIT_CODE=$?
set -e
mv "${LOG_PATH}.tmp" "$LOG_PATH"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    STATUS="pass"
else
    STATUS="failed"
fi

{
    echo "agent_id: $(yaml_quote "$AGENT_ID")"
    echo "task_id: $(yaml_quote "$TASK_ID")"
    echo "timestamp: $(yaml_quote "$TIMESTAMP")"
    echo "status: $(yaml_quote "$STATUS")"
    echo "codd_command: $(yaml_quote "$CODD_COMMAND")"
    echo "exit_code: ${EXIT_CODE}"
    echo "cwd: $(yaml_quote "$PROJECT_ROOT")"
    echo "runner: $(yaml_quote "$RUNNER")"
    echo "log_path: $(yaml_quote "$LOG_PATH")"
    echo "summary: $(yaml_quote "CoDD ${CODD_COMMAND} exited ${EXIT_CODE}")"
} > "$REPORT_PATH"

echo "$REPORT_PATH"
exit "$EXIT_CODE"
