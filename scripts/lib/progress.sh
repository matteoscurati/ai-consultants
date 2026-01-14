#!/bin/bash
# progress.sh - Progress bars and interactive display for AI Consultants v2.0
#
# Shows progress bars for each consultant during consultations.

# =============================================================================
# CONFIGURATION
# =============================================================================

# Characters for progress bar
BAR_FILLED="█"
BAR_EMPTY="░"
BAR_WIDTH=20

# Status icons
declare -A STATUS_ICONS
STATUS_ICONS["starting"]="⏳"
STATUS_ICONS["running"]="🔄"
STATUS_ICONS["success"]="✅"
STATUS_ICONS["failed"]="❌"
STATUS_ICONS["timeout"]="⏰"
STATUS_ICONS["skipped"]="⏭️"

# Colors (ANSI)
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_DIM="\033[0;90m"

# =============================================================================
# PROGRESS STATE
# =============================================================================

declare -A PROGRESS_PERCENT
declare -A PROGRESS_STATUS
declare -A PROGRESS_START_TIME

# Initialize progress for a consultant
# Usage: init_progress <consultant>
init_progress() {
    local consultant="$1"
    PROGRESS_PERCENT[$consultant]=0
    PROGRESS_STATUS[$consultant]="starting"
    PROGRESS_START_TIME[$consultant]=$(date +%s)
}

# Update progress
# Usage: update_progress <consultant> <percent> [status]
update_progress() {
    local consultant="$1"
    local percent="$2"
    local status="${3:-running}"

    PROGRESS_PERCENT[$consultant]=$percent
    PROGRESS_STATUS[$consultant]="$status"
}

# =============================================================================
# DISPLAY FUNCTIONS
# =============================================================================

# Generate progress bar string
# Usage: generate_bar <percent>
generate_bar() {
    local percent=$1
    local filled=$((percent * BAR_WIDTH / 100))
    local empty=$((BAR_WIDTH - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="$BAR_FILLED"
    done
    for ((i=0; i<empty; i++)); do
        bar+="$BAR_EMPTY"
    done

    echo "$bar"
}

# Get status icon
# Usage: get_status_icon <status>
get_status_icon() {
    local status="$1"
    echo "${STATUS_ICONS[$status]:-❓}"
}

# Get color for status
# Usage: get_status_color <status>
get_status_color() {
    local status="$1"
    case "$status" in
        success)
            echo "$COLOR_GREEN"
            ;;
        failed|timeout)
            echo "$COLOR_RED"
            ;;
        running)
            echo "$COLOR_BLUE"
            ;;
        starting)
            echo "$COLOR_YELLOW"
            ;;
        *)
            echo "$COLOR_RESET"
            ;;
    esac
}

# Calculate elapsed time
# Usage: get_elapsed <consultant>
get_elapsed() {
    local consultant="$1"
    local start="${PROGRESS_START_TIME[$consultant]:-$(date +%s)}"
    local now=$(date +%s)
    local elapsed=$((now - start))
    echo "${elapsed}s"
}

# Render a single progress line
# Usage: render_progress_line <consultant>
render_progress_line() {
    local consultant="$1"
    local percent="${PROGRESS_PERCENT[$consultant]:-0}"
    local status="${PROGRESS_STATUS[$consultant]:-starting}"

    local bar=$(generate_bar "$percent")
    local icon=$(get_status_icon "$status")
    local color=$(get_status_color "$status")
    local elapsed=$(get_elapsed "$consultant")

    printf "  ${color}[%-8s]${COLOR_RESET} %s %3d%% %s ${COLOR_DIM}(%s)${COLOR_RESET}\n" \
        "$consultant" "$bar" "$percent" "$icon" "$elapsed"
}

# Render all progress bars
# Usage: render_all_progress
render_all_progress() {
    local consultants=("Gemini" "Codex" "Mistral" "Kilo")

    echo ""
    echo "  Progress:"
    echo ""

    for c in "${consultants[@]}"; do
        if [[ -n "${PROGRESS_STATUS[$c]}" ]]; then
            render_progress_line "$c"
        fi
    done

    echo ""
}

# Update display in-place (for terminals that support ANSI)
# Usage: update_display
update_display() {
    # Save cursor position, move up, render, restore
    local num_lines=6  # Header + 4 consultants + footer

    # Move cursor up
    printf "\033[${num_lines}A"

    # Clear lines and re-render
    for ((i=0; i<num_lines; i++)); do
        printf "\033[2K"  # Clear line
        printf "\033[1B"  # Move down
    done

    # Move back up
    printf "\033[${num_lines}A"

    # Render
    render_all_progress
}

# =============================================================================
# SPINNER
# =============================================================================

SPINNER_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
SPINNER_INDEX=0

# Advance spinner
spin() {
    SPINNER_INDEX=$(( (SPINNER_INDEX + 1) % ${#SPINNER_CHARS[@]} ))
    echo "${SPINNER_CHARS[$SPINNER_INDEX]}"
}

# Show spinner with message
# Usage: show_spinner <message>
show_spinner() {
    local message="$1"
    printf "\r  %s %s" "$(spin)" "$message"
}

# =============================================================================
# SUMMARY DISPLAY
# =============================================================================

# Show final summary
# Usage: show_summary <success_count> <total_count> <total_time>
show_summary() {
    local success="$1"
    local total="$2"
    local time="$3"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Consultation Summary                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  Consultants: ${COLOR_GREEN}%d${COLOR_RESET}/%d successful\n" "$success" "$total"
    printf "  Total time: ${COLOR_CYAN}%s${COLOR_RESET}\n" "$time"
    echo ""

    # Details per consultant
    for c in Gemini Codex Mistral Kilo; do
        if [[ -n "${PROGRESS_STATUS[$c]}" ]]; then
            local status="${PROGRESS_STATUS[$c]}"
            local icon=$(get_status_icon "$status")
            local elapsed=$(get_elapsed "$c")
            printf "  %s %-8s: %s (%s)\n" "$icon" "$c" "$status" "$elapsed"
        fi
    done

    echo ""
}

# =============================================================================
# INTERACTIVE MODE HELPERS
# =============================================================================

# Show header for interactive consultation
show_consultation_header() {
    local question="$1"
    local truncated="${question:0:60}"
    [[ ${#question} -gt 60 ]] && truncated+="..."

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           AI Consultants v2.0 - Live Consultation            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Query: $truncated"
    echo ""
}

# Show early termination option message
show_early_termination_hint() {
    echo ""
    echo "  ${COLOR_DIM}Press Ctrl+C to stop early with available responses${COLOR_RESET}"
    echo ""
}
