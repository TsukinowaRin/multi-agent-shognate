build_ashigaru_grid() {
    local pane_target="$1"
    local start_index="$2"
    local pane_count="$3"
    local depth="${4:-0}"
    local split_pane="" first_count=0 second_count=0

    if [ "$pane_count" -le 1 ]; then
        ASHIGARU_PANES["$start_index"]="$pane_target"
        return 0
    fi

    first_count=$(( (pane_count + 1) / 2 ))
    second_count=$(( pane_count - first_count ))

    if [ "$second_count" -le 0 ]; then
        ASHIGARU_PANES["$start_index"]="$pane_target"
        return 0
    fi

    if [ $(( depth % 2 )) -eq 0 ]; then
        split_pane="$(tmux split-window -v -t "$pane_target" -P -F '#{pane_id}')"
    else
        split_pane="$(tmux split-window -h -t "$pane_target" -P -F '#{pane_id}')"
    fi

    build_ashigaru_grid "$pane_target" "$start_index" "$first_count" $((depth + 1))
    build_ashigaru_grid "$split_pane" $((start_index + first_count)) "$second_count" $((depth + 1))
}

build_karo_grid() {
    local pane_target="$1"
    local start_index="$2"
    local pane_count="$3"
    local depth="${4:-0}"
    local split_pane="" first_count=0 second_count=0

    if [ "$pane_count" -le 1 ]; then
        KARO_PANES["$start_index"]="$pane_target"
        return 0
    fi

    first_count=$(( (pane_count + 1) / 2 ))
    second_count=$(( pane_count - first_count ))

    if [ "$second_count" -le 0 ]; then
        KARO_PANES["$start_index"]="$pane_target"
        return 0
    fi

    if [ $(( depth % 2 )) -eq 0 ]; then
        split_pane="$(tmux split-window -v -t "$pane_target" -P -F '#{pane_id}')"
    else
        split_pane="$(tmux split-window -h -t "$pane_target" -P -F '#{pane_id}')"
    fi

    build_karo_grid "$pane_target" "$start_index" "$first_count" $((depth + 1))
    build_karo_grid "$split_pane" $((start_index + first_count)) "$second_count" $((depth + 1))
}

start_goza_layout_autosave() {
    local session="$1"
    local autosave_script="$SCRIPT_DIR/shogunate_mod/view/goza_layout_autosave.sh"
    [ -x "$autosave_script" ] || return 0
    mkdir -p "$SCRIPT_DIR/logs"
    pkill -f "$autosave_script ${session} " >/dev/null 2>&1 || true
    nohup env GOZA_SIGNATURE_FILE="$GOZA_SIGNATURE_FILE" bash "$autosave_script" "$session" "$GOZA_LAYOUT_FILE" \
        9>&- \
        >> "$SCRIPT_DIR/logs/goza_layout_autosave.log" 2>&1 &
    disown
}

compose_goza_signature_from_agents() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    printf '%s\n' "$@" | awk 'NF' | sort -V | paste -sd, -
}

collect_goza_session_signature() {
    local session="$1"
    local pane_id=""
    local agent_id=""
    local agents=()

    tmux has-session -t "$session" 2>/dev/null || return 0
    while IFS= read -r pane_id; do
        [ -n "$pane_id" ] || continue
        agent_id="$(tmux show-options -p -t "$pane_id" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
        [ -n "$agent_id" ] || continue
        agents+=("$agent_id")
    done < <(tmux list-panes -s -t "$session" -F "#{pane_id}" 2>/dev/null || true)

    compose_goza_signature_from_agents "${agents[@]}"
}

write_goza_signature_file() {
    local signature="$1"
    mkdir -p "$(dirname "$GOZA_SIGNATURE_FILE")"
    printf '%s\n' "$signature" > "$GOZA_SIGNATURE_FILE"
}

goza_window_has_tiny_panes() {
    local window_target="$1"
    local width height

    while read -r width height; do
        [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || continue
        if (( width < GOZA_MIN_RESTORE_PANE_WIDTH || height < GOZA_MIN_RESTORE_PANE_HEIGHT )); then
            return 0
        fi
    done < <(tmux list-panes -t "$window_target" -F '#{pane_width} #{pane_height}' 2>/dev/null || true)

    return 1
}

goza_layout_saved_dimensions() {
    local layout="${1:-}"

    if [[ "$layout" =~ ^[^,]+,([0-9]+)x([0-9]+), ]]; then
        printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

goza_window_is_smaller_than_layout() {
    local window_target="$1"
    local layout="$2"
    local saved_width saved_height current_width current_height

    read -r saved_width saved_height < <(goza_layout_saved_dimensions "$layout") || return 1
    read -r current_width current_height < <(tmux display-message -p -t "$window_target" '#{window_width} #{window_height}' 2>/dev/null || true)
    [[ "$saved_width" =~ ^[0-9]+$ && "$saved_height" =~ ^[0-9]+$ ]] || return 1
    [[ "$current_width" =~ ^[0-9]+$ && "$current_height" =~ ^[0-9]+$ ]] || return 1

    (( current_width < saved_width || current_height < saved_height ))
}

save_goza_layout() {
    local session="$1"
    local window_target="${session}:${GOZA_WINDOW_NAME}"
    local pane_count layout signature

    tmux has-session -t "$session" 2>/dev/null || return 0
    if goza_window_has_tiny_panes "$window_target"; then
        return 0
    fi
    pane_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
    layout="$(tmux display-message -p -t "$window_target" "#{window_layout}" 2>/dev/null || true)"
    signature="$(collect_goza_session_signature "$session")"
    if [[ -n "$pane_count" && -n "$layout" ]]; then
        mkdir -p "$(dirname "$GOZA_LAYOUT_FILE")"
        printf '%s\t%s\t%s\n' "$pane_count" "$signature" "$layout" > "$GOZA_LAYOUT_FILE"
    fi
    if [[ -n "$signature" ]]; then
        write_goza_signature_file "$signature"
    fi
}

restore_goza_layout_if_available() {
    local session="$1"
    local expected_signature="$2"
    local window_target="${session}:${GOZA_WINDOW_NAME}"
    local current_count saved_count saved_signature saved_layout current_layout

    [[ -f "$GOZA_LAYOUT_FILE" ]] || return 0
    current_count="$(tmux list-panes -t "$window_target" 2>/dev/null | wc -l | tr -d '[:space:]')"
    IFS=$'\t' read -r saved_count saved_signature saved_layout < "$GOZA_LAYOUT_FILE" || return 0
    [[ -n "$saved_count" && -n "$saved_layout" ]] || return 0
    [[ "$saved_count" = "$current_count" ]] || return 0
    if [[ -n "$expected_signature" && -n "$saved_signature" && "$saved_signature" != "$expected_signature" ]]; then
        return 0
    fi
    current_layout="$(tmux display-message -p -t "$window_target" "#{window_layout}" 2>/dev/null || true)"
    tmux select-layout -t "$window_target" "$saved_layout" >/dev/null 2>&1 || return 0
    if goza_window_has_tiny_panes "$window_target"; then
        if goza_window_is_smaller_than_layout "$window_target" "$saved_layout"; then
            return 0
        fi
        if [[ -n "$current_layout" ]]; then
            tmux select-layout -t "$window_target" "$current_layout" >/dev/null 2>&1 || true
        fi
        log_info "⚠️  保存済み御座の間レイアウトは pane が小さすぎるため復元しません"
    fi
}

resolve_multiagent_pane_target() {
    resolve_agent_pane_target "$1"
}

list_backend_pane_targets() {
    if tmux has-session -t "$GOZA_SESSION_NAME" 2>/dev/null; then
        tmux list-panes -s -t "$GOZA_SESSION_NAME" -F "#{pane_id}" 2>/dev/null || true
        return 0
    fi
    if tmux has-session -t "shogun" 2>/dev/null; then
        tmux list-panes -t "shogun:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux has-session -t "gunkan" 2>/dev/null; then
        tmux list-panes -t "gunkan:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux has-session -t "gunshi" 2>/dev/null; then
        tmux list-panes -t "gunshi:main" -F "#{pane_id}" 2>/dev/null || true
    fi
    if tmux has-session -t "multiagent" 2>/dev/null; then
        tmux list-panes -t "multiagent:agents" -F "#{pane_id}" 2>/dev/null || true
    fi
}

resolve_agent_pane_target() {
    local agent_id="$1"
    local pane_target
    local pane_agent_id
    while IFS= read -r pane_target; do
        [ -n "$pane_target" ] || continue
        pane_agent_id="$(tmux show-options -p -t "$pane_target" -v @agent_id 2>/dev/null | tr -d '\r' | head -n1)"
        if [ "$pane_agent_id" = "$agent_id" ]; then
            printf '%s\n' "$pane_target"
            return 0
        fi
    done < <(list_backend_pane_targets)
    return 1
}

create_goza_runtime_session() {
    declare -ga MULTIAGENT_IDS
    declare -ga BACKEND_AGENT_IDS
    declare -gA AGENT_PANES
    declare -gA AGENT_PROMPT_LABELS
    declare -gA AGENT_PROMPT_COLORS

    MULTIAGENT_IDS=("${KARO_AGENTS[@]}" "${ACTIVE_ASHIGARU[@]}")
    MULTIAGENT_COUNT=${#MULTIAGENT_IDS[@]}

    log_war "🏯 御座の間を構築中（将軍・軍監・家老・軍師・足軽 ${ACTIVE_ASHIGARU_COUNT}名）..."

    if ! tmux new-session -d -x "$GOZA_VIEW_WIDTH" -y "$GOZA_VIEW_HEIGHT" -s "$GOZA_SESSION_NAME" -n "$GOZA_WINDOW_NAME" 2>/dev/null; then
        echo "[ERROR] tmux session '$GOZA_SESSION_NAME' の作成に失敗しました" >&2
        exit 1
    fi
    tmux set-option -t "$GOZA_SESSION_NAME" @shogunate_project_dir "$SHOGUNATE_PROJECT_DIR" >/dev/null 2>&1 || true
    tmux set-option -t "$GOZA_SESSION_NAME" @shogunate_runtime_dir "$SCRIPT_DIR" >/dev/null 2>&1 || true
    if [ -n "${MAS_LAUNCHER_RUN_ID:-}" ]; then
        tmux set-option -t "$GOZA_SESSION_NAME" @mas_launcher_run_id "$MAS_LAUNCHER_RUN_ID" >/dev/null 2>&1 || true
    fi
    create_goza_startup_window

    if [ "$SILENT_MODE" = true ]; then
        tmux set-environment -t "$GOZA_SESSION_NAME" DISPLAY_MODE "silent"
        echo "  📢 表示モード: サイレント（echo表示なし）"
    else
        tmux set-environment -t "$GOZA_SESSION_NAME" DISPLAY_MODE "shout"
    fi

    AGENT_PANES=()
    AGENT_PROMPT_LABELS=()
    AGENT_PROMPT_COLORS=()

    AGENT_PROMPT_LABELS["shogun"]="将軍"
    AGENT_PROMPT_COLORS["shogun"]="magenta"
    AGENT_PROMPT_LABELS["gunkan"]="軍監"
    AGENT_PROMPT_COLORS["gunkan"]="yellow"
    AGENT_PROMPT_LABELS["gunshi"]="軍師"
    AGENT_PROMPT_COLORS["gunshi"]="cyan"

    local _agent
    for _agent in "${MULTIAGENT_IDS[@]}"; do
        if [[ "$_agent" == karo* ]]; then
            AGENT_PROMPT_LABELS["$_agent"]="$_agent"
            AGENT_PROMPT_COLORS["$_agent"]="red"
        else
            AGENT_PROMPT_LABELS["$_agent"]="$_agent"
            AGENT_PROMPT_COLORS["$_agent"]="blue"
        fi
    done

    LEFT_MIN_WIDTH=36
    RIGHT_MIN_WIDTH=60
    if (( GOZA_VIEW_WIDTH < LEFT_MIN_WIDTH + RIGHT_MIN_WIDTH )); then
        LEFT_MIN_WIDTH=$(( GOZA_VIEW_WIDTH * 38 / 100 ))
        (( LEFT_MIN_WIDTH < 24 )) && LEFT_MIN_WIDTH=24
        RIGHT_MIN_WIDTH=$(( GOZA_VIEW_WIDTH - LEFT_MIN_WIDTH ))
    fi

    SHOGUN_WIDTH=$(( GOZA_VIEW_WIDTH * 38 / 100 ))
    (( SHOGUN_WIDTH < LEFT_MIN_WIDTH )) && SHOGUN_WIDTH=$LEFT_MIN_WIDTH
    RIGHT_WIDTH=$(( GOZA_VIEW_WIDTH - SHOGUN_WIDTH ))
    if (( RIGHT_WIDTH < RIGHT_MIN_WIDTH && GOZA_VIEW_WIDTH >= LEFT_MIN_WIDTH + RIGHT_MIN_WIDTH )); then
        RIGHT_WIDTH=$RIGHT_MIN_WIDTH
        SHOGUN_WIDTH=$(( GOZA_VIEW_WIDTH - RIGHT_WIDTH ))
    fi
    MAX_RIGHT_WIDTH=$(( GOZA_VIEW_WIDTH - LEFT_MIN_WIDTH ))
    (( RIGHT_WIDTH > MAX_RIGHT_WIDTH )) && RIGHT_WIDTH=$MAX_RIGHT_WIDTH
    (( RIGHT_WIDTH < 20 )) && RIGHT_WIDTH=20

    KARO_WIDTH=$(( RIGHT_WIDTH * 38 / 100 ))
    (( KARO_WIDTH < 24 )) && KARO_WIDTH=24
    MAX_KARO_WIDTH=$(( RIGHT_WIDTH - 32 ))
    if (( MAX_KARO_WIDTH < 24 )); then
        MAX_KARO_WIDTH=$(( RIGHT_WIDTH / 2 ))
    fi
    (( KARO_WIDTH > MAX_KARO_WIDTH )) && KARO_WIDTH=$MAX_KARO_WIDTH
    (( KARO_WIDTH < 12 )) && KARO_WIDTH=12

    RIGHT_COLUMN_WIDTH=$(( RIGHT_WIDTH - KARO_WIDTH ))
    (( RIGHT_COLUMN_WIDTH < 20 )) && RIGHT_COLUMN_WIDTH=20

    ASH_HEIGHT=$(( GOZA_VIEW_HEIGHT * 58 / 100 ))
    (( ASH_HEIGHT < 12 )) && ASH_HEIGHT=12
    GUNKAN_HEIGHT=$(( GOZA_VIEW_HEIGHT * 24 / 100 ))
    (( GUNKAN_HEIGHT < 8 )) && GUNKAN_HEIGHT=8

    ROOT_WINDOW="${GOZA_SESSION_NAME}:${GOZA_WINDOW_NAME}"
    SHOGUN_PANE="$(tmux display-message -p -t "$ROOT_WINDOW" "#{pane_id}")"
    RIGHT_COLUMN_PANE="$(tmux split-window -h -l "$RIGHT_WIDTH" -t "$SHOGUN_PANE" -P -F '#{pane_id}')"
    GUNKAN_PANE="$(tmux split-window -v -l "$GUNKAN_HEIGHT" -t "$SHOGUN_PANE" -P -F '#{pane_id}')"
    KARO_PANE="$RIGHT_COLUMN_PANE"
    GUNSHI_PANE="$(tmux split-window -h -l "$RIGHT_COLUMN_WIDTH" -t "$KARO_PANE" -P -F '#{pane_id}')"
    ASH_ROOT_PANE="$(tmux split-window -v -l "$ASH_HEIGHT" -t "$GUNSHI_PANE" -P -F '#{pane_id}')"

    AGENT_PANES["shogun"]="$SHOGUN_PANE"
    AGENT_PANES["gunkan"]="$GUNKAN_PANE"
    AGENT_PANES["gunshi"]="$GUNSHI_PANE"

    KARO_PANES=()
    build_karo_grid "$KARO_PANE" 0 "${#KARO_AGENTS[@]}" 0
    local _idx
    for _idx in "${!KARO_AGENTS[@]}"; do
        AGENT_PANES["${KARO_AGENTS[$_idx]}"]="${KARO_PANES[$_idx]}"
    done

    ASHIGARU_PANES=()
    build_ashigaru_grid "$ASH_ROOT_PANE" 0 "$ACTIVE_ASHIGARU_COUNT" 0
    for _idx in "${!ACTIVE_ASHIGARU[@]}"; do
        AGENT_PANES["${ACTIVE_ASHIGARU[$_idx]}"]="${ASHIGARU_PANES[$_idx]}"
    done

    BACKEND_AGENT_IDS=("shogun")
    BACKEND_AGENT_IDS+=("gunkan")
    BACKEND_AGENT_IDS+=("${KARO_AGENTS[@]}")
    BACKEND_AGENT_IDS+=("gunshi")
    BACKEND_AGENT_IDS+=("${ACTIVE_ASHIGARU[@]}")

    local _pane
    local _label
    local _color
    local _prompt
    for _agent in "${BACKEND_AGENT_IDS[@]}"; do
        _pane="${AGENT_PANES[$_agent]:-}"
        [ -n "$_pane" ] || continue
        _label="${AGENT_PROMPT_LABELS[$_agent]:-$_agent}"
        _color="${AGENT_PROMPT_COLORS[$_agent]:-white}"
        _prompt="$(generate_prompt "$_label" "$_color" "$SHELL_SETTING")"
        tmux set-option -p -t "$_pane" @agent_id "$_agent"
        tmux set-option -p -t "$_pane" @model_name "$(resolve_model_display_name "$_agent")"
        tmux set-option -p -t "$_pane" @current_task ""
        tmux select-pane -t "$_pane" -T "$_agent" >/dev/null 2>&1 || true
        tmux_send_text_and_enter_or_die "$_pane" "cd \"$(pwd)\" && export PS1='${_prompt}' && clear" "pane shell prep" "1"
        if [ "$CLI_ADAPTER_LOADED" = true ]; then
            tmux set-option -p -t "$_pane" @agent_cli "$(resolve_cli_type_for_agent "$_agent")"
        fi
    done

    tmux set-option -t "$GOZA_SESSION_NAME" -w pane-border-status top
    tmux set-option -t "$GOZA_SESSION_NAME" -w pane-border-format '#{?pane_active,#[reverse],}#[bold]#{@agent_id}#[default] (#{@model_name}) #{@current_task}'
    GOZA_SIGNATURE="$(compose_goza_signature_from_agents "${BACKEND_AGENT_IDS[@]}")"
    write_goza_signature_file "$GOZA_SIGNATURE"
    restore_goza_layout_if_available "$GOZA_SESSION_NAME" "$GOZA_SIGNATURE"
    start_goza_layout_autosave "$GOZA_SESSION_NAME"

    SHOGUN_TARGET="${AGENT_PANES[shogun]}"
    GUNKAN_TARGET="${AGENT_PANES[gunkan]}"
    GUNSHI_TARGET="${AGENT_PANES[gunshi]}"
    KARO_TARGET="${AGENT_PANES[${LEAD_KARO}]}"

    log_success "  └─ 御座の間、構築完了"
    echo ""
}
