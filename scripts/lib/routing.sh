#!/bin/bash
# routing.sh - Smart consultant selection based on question type
#
# Selects the most suitable consultants based on the question category.

# =============================================================================
# AFFINITY MATRIX
# =============================================================================
# Using case statements for bash 3.2 compatibility (no associative arrays)
# Affinity scores: 10 = perfect match, 1 = poor match

# =============================================================================
# SELECTION FUNCTIONS
# =============================================================================

# Get affinity for a category-consultant combination
# Usage: get_affinity <category> <consultant>
get_affinity() {
    local category="$1"
    local consultant="$2"

    case "$category" in
        CODE_REVIEW)
            case "$consultant" in
                Gemini)   echo 7 ;;
                Codex)    echo 10 ;;
                Mistral)  echo 8 ;;
                Kilo)     echo 9 ;;
                Cursor)   echo 9 ;;
                Aider)    echo 9 ;;
                Qwen3)    echo 8 ;;
                GLM)      echo 8 ;;
                Grok)     echo 7 ;;
                DeepSeek) echo 10 ;;
                *)        echo 5 ;;
            esac
            ;;
        BUG_DEBUG)
            case "$consultant" in
                Gemini)   echo 7 ;;
                Codex)    echo 10 ;;
                Mistral)  echo 9 ;;
                Kilo)     echo 8 ;;
                Cursor)   echo 9 ;;
                Aider)    echo 9 ;;
                Qwen3)    echo 8 ;;
                GLM)      echo 8 ;;
                Grok)     echo 7 ;;
                DeepSeek) echo 9 ;;
                *)        echo 5 ;;
            esac
            ;;
        ARCHITECTURE)
            case "$consultant" in
                Gemini)   echo 10 ;;
                Codex)    echo 6 ;;
                Mistral)  echo 8 ;;
                Kilo)     echo 9 ;;
                Cursor)   echo 8 ;;
                Aider)    echo 6 ;;
                Qwen3)    echo 7 ;;
                GLM)      echo 7 ;;
                Grok)     echo 9 ;;
                DeepSeek) echo 7 ;;
                *)        echo 5 ;;
            esac
            ;;
        ALGORITHM)
            case "$consultant" in
                Gemini)   echo 9 ;;
                Codex)    echo 8 ;;
                Mistral)  echo 7 ;;
                Kilo)     echo 8 ;;
                Cursor)   echo 7 ;;
                Aider)    echo 7 ;;
                Qwen3)    echo 9 ;;
                GLM)      echo 7 ;;
                Grok)     echo 8 ;;
                DeepSeek) echo 10 ;;
                *)        echo 5 ;;
            esac
            ;;
        SECURITY)
            case "$consultant" in
                Gemini)   echo 9 ;;
                Codex)    echo 9 ;;
                Mistral)  echo 10 ;;
                Kilo)     echo 8 ;;
                Cursor)   echo 8 ;;
                Aider)    echo 7 ;;
                Qwen3)    echo 7 ;;
                GLM)      echo 8 ;;
                Grok)     echo 8 ;;
                DeepSeek) echo 8 ;;
                *)        echo 5 ;;
            esac
            ;;
        QUICK_SYNTAX)
            case "$consultant" in
                Gemini)   echo 10 ;;
                Codex)    echo 8 ;;
                Mistral)  echo 5 ;;
                Kilo)     echo 6 ;;
                Cursor)   echo 7 ;;
                Aider)    echo 8 ;;
                Qwen3)    echo 7 ;;
                GLM)      echo 6 ;;
                Grok)     echo 5 ;;
                DeepSeek) echo 9 ;;
                *)        echo 5 ;;
            esac
            ;;
        DATABASE)
            case "$consultant" in
                Gemini)   echo 8 ;;
                Codex)    echo 9 ;;
                Mistral)  echo 7 ;;
                Kilo)     echo 7 ;;
                Cursor)   echo 8 ;;
                Aider)    echo 7 ;;
                Qwen3)    echo 9 ;;
                GLM)      echo 7 ;;
                Grok)     echo 6 ;;
                DeepSeek) echo 9 ;;
                *)        echo 5 ;;
            esac
            ;;
        API_DESIGN)
            case "$consultant" in
                Gemini)   echo 10 ;;
                Codex)    echo 9 ;;
                Mistral)  echo 7 ;;
                Kilo)     echo 8 ;;
                Cursor)   echo 9 ;;
                Aider)    echo 7 ;;
                Qwen3)    echo 7 ;;
                GLM)      echo 8 ;;
                Grok)     echo 8 ;;
                DeepSeek) echo 8 ;;
                *)        echo 5 ;;
            esac
            ;;
        TESTING)
            case "$consultant" in
                Gemini)   echo 7 ;;
                Codex)    echo 10 ;;
                Mistral)  echo 9 ;;
                Kilo)     echo 7 ;;
                Cursor)   echo 9 ;;
                Aider)    echo 9 ;;
                Qwen3)    echo 8 ;;
                GLM)      echo 10 ;;
                Grok)     echo 7 ;;
                DeepSeek) echo 8 ;;
                *)        echo 5 ;;
            esac
            ;;
        *)
            # GENERAL and unknown categories: all known consultants get score 8
            case "$consultant" in
                Gemini|Codex|Mistral|Kilo|Cursor|Aider|Qwen3|GLM|Grok|DeepSeek) echo 8 ;;
                *) echo 5 ;;
            esac
            ;;
    esac
}

# Select the best consultants for a category
# Usage: select_consultants <category> [min_affinity] [max_consultants]
# Returns: list of consultants sorted by affinity
select_consultants() {
    local category="$1"
    local min_affinity="${2:-7}"
    local max_consultants="${3:-8}"

    # Include all consultants (CLI-based and API-based)
    local consultants=("Gemini" "Codex" "Mistral" "Kilo" "Cursor" "Aider" "Qwen3" "GLM" "Grok" "DeepSeek")
    local selected=()
    local scores=()

    # Collect affinities
    for c in "${consultants[@]}"; do
        local score=$(get_affinity "$category" "$c")
        if [[ $score -ge $min_affinity ]]; then
            selected+=("$c")
            scores+=("$score")
        fi
    done

    # Sort by score (simple bubble sort)
    local n=${#selected[@]}
    for ((i=0; i<n-1; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            if [[ ${scores[$j]} -lt ${scores[$((j+1))]} ]]; then
                # Swap
                local tmp="${selected[$j]}"
                selected[$j]="${selected[$((j+1))]}"
                selected[$((j+1))]="$tmp"

                tmp="${scores[$j]}"
                scores[$j]="${scores[$((j+1))]}"
                scores[$((j+1))]="$tmp"
            fi
        done
    done

    # Limit to maximum requested
    local count=0
    for c in ${selected[@]+"${selected[@]}"}; do
        if [[ $count -ge $max_consultants ]]; then
            break
        fi
        echo "$c"
        ((count++))
    done
}

# Get the list of consultants as JSON
# Usage: get_selected_consultants_json <category> [min_affinity]
get_selected_consultants_json() {
    local category="$1"
    local min_affinity="${2:-7}"

    local consultants=$(select_consultants "$category" "$min_affinity")
    local json="["
    local first=true

    while IFS= read -r c; do
        if [[ -n "$c" ]]; then
            local score=$(get_affinity "$category" "$c")
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json+=","
            fi
            json+="{\"consultant\":\"$c\",\"affinity\":$score}"
        fi
    done <<< "$consultants"

    json+="]"
    echo "$json"
}

# Check if a consultant is recommended for a category
# Usage: is_recommended <category> <consultant> [min_affinity]
is_recommended() {
    local category="$1"
    local consultant="$2"
    local min_affinity="${3:-7}"

    local score=$(get_affinity "$category" "$consultant")
    if [[ $score -ge $min_affinity ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# SMART ROUTING MODES
# =============================================================================

# Determine the routing mode based on the category
# Usage: get_routing_mode <category>
# Returns: full|selective|single
get_routing_mode() {
    local category="$1"

    case "$category" in
        SECURITY)
            # Security: all consultants (important)
            echo "full"
            ;;
        QUICK_SYNTAX)
            # Syntax: just one needed
            echo "single"
            ;;
        CODE_REVIEW|BUG_DEBUG|ARCHITECTURE)
            # Important: at least 3
            echo "selective"
            ;;
        *)
            # Default: all
            echo "full"
            ;;
    esac
}

# Get the recommended number of consultants
# Usage: get_recommended_count <category>
get_recommended_count() {
    local category="$1"
    local mode=$(get_routing_mode "$category")

    case "$mode" in
        full)
            echo 10  # All consultants (CLI + API)
            ;;
        selective)
            echo 5  # Subset based on affinity
            ;;
        single)
            echo 1
            ;;
        *)
            echo 10
            ;;
    esac
}

# =============================================================================
# TIMEOUT ADJUSTMENTS
# =============================================================================

# Get recommended timeout for a category
# Usage: get_category_timeout <category>
get_category_timeout() {
    local category="$1"
    case "$category" in
        QUICK_SYNTAX)  echo 60 ;;
        BUG_DEBUG)     echo 180 ;;
        ARCHITECTURE)  echo 240 ;;
        SECURITY)      echo 240 ;;
        CODE_REVIEW)   echo 180 ;;
        ALGORITHM)     echo 180 ;;
        DATABASE)      echo 120 ;;
        API_DESIGN)    echo 180 ;;
        TESTING)       echo 120 ;;
        GENERAL|*)     echo 180 ;;
    esac
}
