#!/usr/bin/env bash

shogunate_mod_source_runtime_file() {
    local runtime_file="$1"
    local path="$SCRIPT_DIR/shogunate_mod/runtime/$runtime_file"
    [ -f "$path" ] && . "$path"
}

shogunate_mod_source_runtime_file env.sh
shogunate_mod_source_runtime_file startup.sh
shogunate_mod_source_runtime_file options.sh
shogunate_mod_source_runtime_file banner.sh
shogunate_mod_source_runtime_file topology.sh
shogunate_mod_source_runtime_file daemon.sh
shogunate_mod_source_runtime_file state.sh
shogunate_mod_source_runtime_file agent_cli.sh
shogunate_mod_source_runtime_file directives.sh
shogunate_mod_source_runtime_file goza.sh
shogunate_mod_source_runtime_file launch.sh
shogunate_mod_source_runtime_file lifecycle.sh
shogunate_mod_source_runtime_file blocker.sh
shogunate_mod_source_runtime_file prompts.sh
shogunate_mod_source_runtime_file bootstrap.sh
shogunate_mod_source_runtime_file android_compat.sh
shogunate_mod_source_runtime_file summary.sh
shogunate_mod_source_runtime_file departure.sh
