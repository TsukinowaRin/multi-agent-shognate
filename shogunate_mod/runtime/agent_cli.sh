#!/usr/bin/env bash

_emit_runtime_cli_entry() {
    local _agent="$1"
    local _cli_type="claude"
    if [ "$CLI_ADAPTER_LOADED" = true ]; then
        _cli_type=$(resolve_cli_type_for_agent "$_agent")
    fi
    printf "%s\t%s\n" "$_agent" "$_cli_type" >> "$SCRIPT_DIR/queue/runtime/agent_cli.tsv"
}
