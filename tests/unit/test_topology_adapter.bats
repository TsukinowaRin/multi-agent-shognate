#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    ADAPTER_SCRIPT="$PROJECT_ROOT/lib/topology_adapter.sh"
    [ -f "$ADAPTER_SCRIPT" ] || return 1

    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/topology_adapter.XXXXXX")"
    SETTINGS_PATH="$TEST_TMPDIR/settings.yaml"
    RUNTIME_DIR="$TEST_TMPDIR/queue/runtime"
    OWNER_MAP="$RUNTIME_DIR/ashigaru_owner.tsv"
    mkdir -p "$RUNTIME_DIR"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

write_manual_settings() {
    local ashigaru_count="$1"
    shift
    local karos=("$@")
    {
        echo "topology:"
        echo "  active_ashigaru:"
        for ((i=1; i<=ashigaru_count; i++)); do
            echo "    - ashigaru${i}"
        done
        echo "  karo:"
        echo "    mode: manual"
        echo "    active_karo:"
        for k in "${karos[@]}"; do
            echo "      - ${k}"
        done
    } > "$SETTINGS_PATH"
}

generate_owner_map() {
    local count="$1"
    export TOPOLOGY_SETTINGS_PATH="$SETTINGS_PATH"
    export TOPOLOGY_RUNTIME_DIR="$RUNTIME_DIR"
    export TOPOLOGY_OWNER_MAP="$OWNER_MAP"

    # shellcheck source=/dev/null
    source "$ADAPTER_SCRIPT"

    local agents=()
    for ((i=1; i<=count; i++)); do
        agents+=("ashigaru${i}")
    done
    build_even_ownership_map "$OWNER_MAP" "${agents[@]}"
}

@test "M=10, N=2 のとき 5/5 で均等配分される" {
    write_manual_settings 10 karo1 karo2
    generate_owner_map 10

    run awk -F '\t' '$2=="karo1"{c++} END{print c+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]

    run awk -F '\t' '$2=="karo2"{c++} END{print c+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "M=17, N=3 のとき 6/6/5 で配分される" {
    write_manual_settings 17 karo1 karo2 karo3
    generate_owner_map 17

    run awk -F '\t' '$2=="karo1"{c++} END{print c+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "6" ]

    run awk -F '\t' '$2=="karo2"{c++} END{print c+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "6" ]

    run awk -F '\t' '$2=="karo3"{c++} END{print c+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "M=50, N=7 のとき人数差が最大1以内" {
    write_manual_settings 50 karo1 karo2 karo3 karo4 karo5 karo6 karo7
    generate_owner_map 50

    run awk -F '\t' '
        NF>=2 { c[$2]++ }
        END {
            min=-1; max=0
            for (k in c) {
                if (min < 0 || c[k] < min) min=c[k]
                if (c[k] > max) max=c[k]
            }
            print max-min
        }
    ' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" -le 1 ]
}

@test "N=1 のとき既存挙動（karo単独）を維持" {
    {
        echo "topology:"
        echo "  active_ashigaru:"
        echo "    - ashigaru1"
        echo "    - ashigaru2"
        echo "  karo:"
        echo "    mode: manual"
        echo "    active_karo:"
        echo "      - karo"
    } > "$SETTINGS_PATH"

    generate_owner_map 2

    run awk -F '\t' 'NF>=2 && $2!="karo"{bad=1} END{print bad+0}' "$OWNER_MAP"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}
