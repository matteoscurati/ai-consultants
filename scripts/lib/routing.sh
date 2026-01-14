#!/bin/bash
# routing.sh - Smart consultant selection based on question type
#
# Selects the most suitable consultants based on the question category.

# =============================================================================
# AFFINITY MATRIX
# =============================================================================

# Affinity scores for each category-consultant combination
# Scale 1-10: 10 = perfect match, 1 = poor match

declare -A CONSULTANT_AFFINITY

# CODE_REVIEW: Codex and Kilo are the best for code review
CONSULTANT_AFFINITY["CODE_REVIEW:Gemini"]=7
CONSULTANT_AFFINITY["CODE_REVIEW:Codex"]=10
CONSULTANT_AFFINITY["CODE_REVIEW:Mistral"]=8   # Devil's advocate great for finding problems
CONSULTANT_AFFINITY["CODE_REVIEW:Kilo"]=9

# BUG_DEBUG: Codex excels at debugging
CONSULTANT_AFFINITY["BUG_DEBUG:Gemini"]=7
CONSULTANT_AFFINITY["BUG_DEBUG:Codex"]=10
CONSULTANT_AFFINITY["BUG_DEBUG:Mistral"]=9     # Finds edge cases
CONSULTANT_AFFINITY["BUG_DEBUG:Kilo"]=8

# ARCHITECTURE: Gemini is The Architect
CONSULTANT_AFFINITY["ARCHITECTURE:Gemini"]=10
CONSULTANT_AFFINITY["ARCHITECTURE:Codex"]=6
CONSULTANT_AFFINITY["ARCHITECTURE:Mistral"]=8  # Critiques architectures
CONSULTANT_AFFINITY["ARCHITECTURE:Kilo"]=9     # Innovative solutions

# ALGORITHM: All useful, Gemini for complexity
CONSULTANT_AFFINITY["ALGORITHM:Gemini"]=9
CONSULTANT_AFFINITY["ALGORITHM:Codex"]=8
CONSULTANT_AFFINITY["ALGORITHM:Mistral"]=7
CONSULTANT_AFFINITY["ALGORITHM:Kilo"]=8

# SECURITY: All important, Mistral essential
CONSULTANT_AFFINITY["SECURITY:Gemini"]=9
CONSULTANT_AFFINITY["SECURITY:Codex"]=9
CONSULTANT_AFFINITY["SECURITY:Mistral"]=10     # Devil's advocate for security
CONSULTANT_AFFINITY["SECURITY:Kilo"]=8

# QUICK_SYNTAX: Just one fast consultant needed
CONSULTANT_AFFINITY["QUICK_SYNTAX:Gemini"]=10
CONSULTANT_AFFINITY["QUICK_SYNTAX:Codex"]=8
CONSULTANT_AFFINITY["QUICK_SYNTAX:Mistral"]=5
CONSULTANT_AFFINITY["QUICK_SYNTAX:Kilo"]=6

# DATABASE: All useful
CONSULTANT_AFFINITY["DATABASE:Gemini"]=8
CONSULTANT_AFFINITY["DATABASE:Codex"]=9
CONSULTANT_AFFINITY["DATABASE:Mistral"]=7
CONSULTANT_AFFINITY["DATABASE:Kilo"]=7

# API_DESIGN: Gemini for design, Codex for practicality
CONSULTANT_AFFINITY["API_DESIGN:Gemini"]=10
CONSULTANT_AFFINITY["API_DESIGN:Codex"]=9
CONSULTANT_AFFINITY["API_DESIGN:Mistral"]=7
CONSULTANT_AFFINITY["API_DESIGN:Kilo"]=8

# TESTING: Codex and Mistral
CONSULTANT_AFFINITY["TESTING:Gemini"]=7
CONSULTANT_AFFINITY["TESTING:Codex"]=10
CONSULTANT_AFFINITY["TESTING:Mistral"]=9       # Finds untested cases
CONSULTANT_AFFINITY["TESTING:Kilo"]=7

# GENERAL: Balanced
CONSULTANT_AFFINITY["GENERAL:Gemini"]=8
CONSULTANT_AFFINITY["GENERAL:Codex"]=8
CONSULTANT_AFFINITY["GENERAL:Mistral"]=8
CONSULTANT_AFFINITY["GENERAL:Kilo"]=8

# =============================================================================
# SELECTION FUNCTIONS
# =============================================================================

# Get affinity for a category-consultant combination
# Usage: get_affinity <category> <consultant>
get_affinity() {
    local category="$1"
    local consultant="$2"
    local key="${category}:${consultant}"

    echo "${CONSULTANT_AFFINITY[$key]:-5}"
}

# Select the best consultants for a category
# Usage: select_consultants <category> [min_affinity] [max_consultants]
# Returns: list of consultants sorted by affinity
select_consultants() {
    local category="$1"
    local min_affinity="${2:-7}"
    local max_consultants="${3:-4}"

    local consultants=("Gemini" "Codex" "Mistral" "Kilo")
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
    for c in "${selected[@]}"; do
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
            echo 4
            ;;
        selective)
            echo 3
            ;;
        single)
            echo 1
            ;;
        *)
            echo 4
            ;;
    esac
}

# =============================================================================
# TIMEOUT ADJUSTMENTS
# =============================================================================

# Optimized timeouts by category
declare -A CATEGORY_TIMEOUTS
CATEGORY_TIMEOUTS["QUICK_SYNTAX"]=60
CATEGORY_TIMEOUTS["BUG_DEBUG"]=180
CATEGORY_TIMEOUTS["ARCHITECTURE"]=240
CATEGORY_TIMEOUTS["SECURITY"]=240
CATEGORY_TIMEOUTS["CODE_REVIEW"]=180
CATEGORY_TIMEOUTS["ALGORITHM"]=180
CATEGORY_TIMEOUTS["DATABASE"]=120
CATEGORY_TIMEOUTS["API_DESIGN"]=180
CATEGORY_TIMEOUTS["TESTING"]=120
CATEGORY_TIMEOUTS["GENERAL"]=180

# Get recommended timeout for a category
# Usage: get_category_timeout <category>
get_category_timeout() {
    local category="$1"
    echo "${CATEGORY_TIMEOUTS[$category]:-180}"
}
