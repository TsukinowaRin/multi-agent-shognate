#!/usr/bin/env bash

bats_search() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -n -- "$pattern" "$@"
    else
        grep -nE -R -- "$pattern" "$@"
    fi
}

bats_search_fixed() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -nF -- "$pattern" "$@"
    else
        grep -nF -R -- "$pattern" "$@"
    fi
}
