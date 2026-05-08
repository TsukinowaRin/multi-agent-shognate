#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "CoDD config is tracked under .codd/codd.yaml" {
    [ -f "$PROJECT_ROOT/.codd/codd.yaml" ]
    grep -q 'codd_required_version: ">=1.34.0"' "$PROJECT_ROOT/.codd/codd.yaml"
    grep -q 'project_type: "cli"' "$PROJECT_ROOT/.codd/codd.yaml"
    grep -q 'enabled_checks:' "$PROJECT_ROOT/.codd/codd.yaml"
}

@test "CoDD wrapper supports install/build/verify/audit commands" {
    run bash -n "$PROJECT_ROOT/scripts/codd_check.sh"
    [ "$status" -eq 0 ]

    run bash "$PROJECT_ROOT/scripts/codd_check.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install        Install/update codd-dev"* ]]
    [[ "$output" == *"codd dag verify"* ]]
    [[ "$output" == *"CODD_AUTO_INSTALL=1"* ]]
    [[ "$output" == *"CODD_FALLBACK_VERSION"* ]]
}

@test "Makefile exposes integrated CoDD targets" {
    grep -q '^codd:' "$PROJECT_ROOT/Makefile"
    grep -q '^codd-install:' "$PROJECT_ROOT/Makefile"
    grep -q '^codd-verify:' "$PROJECT_ROOT/Makefile"
}

@test "GitHub Actions runs integrated CoDD by default" {
    grep -q "CoDD DAG verification" "$PROJECT_ROOT/.github/workflows/test.yml"
    ! grep -q "vars.ENABLE_CODD == 'true'" "$PROJECT_ROOT/.github/workflows/test.yml"
}

@test "Windows updater checks Python before integrated tool update" {
    grep -q "Python3 / python3-venv is not ready" "$PROJECT_ROOT/updater.bat"
    grep -q "Running updater and integrated tool updates" "$PROJECT_ROOT/updater.bat"
}
