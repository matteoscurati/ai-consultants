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

# =============================================================================
# COST-AWARE ROUTING (v2.3)
# =============================================================================

# Ensure costs.sh is sourced (lazy loading helper)
_ensure_costs_sourced() {
    if ! type get_economic_model &>/dev/null; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "$script_dir/costs.sh" 2>/dev/null || true
    fi
}

# Select consultants based on cost efficiency
# Usage: select_consultants_cost_aware <category> <complexity> [min_affinity]
# Returns: list of consultants optimized for cost/quality balance
select_consultants_cost_aware() {
    local category="$1"
    local complexity="${2:-5}"
    local min_affinity="${3:-7}"

    # Check if cost-aware routing is enabled
    if [[ "${ENABLE_COST_AWARE_ROUTING:-false}" != "true" ]]; then
        # Fall back to standard selection
        select_consultants "$category" "$min_affinity"
        return
    fi

    _ensure_costs_sourced

    local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"
    local medium_threshold="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

    # Simple queries: only economic models, fewer consultants
    if [[ $complexity -le $simple_threshold ]]; then
        # For simple queries, use only 2 consultants with economic models
        select_consultants "$category" "$min_affinity" 2
        return
    fi

    # Medium complexity: balanced selection
    if [[ $complexity -le $medium_threshold ]]; then
        # Use standard selection but limit to 3-4 consultants
        select_consultants "$category" "$min_affinity" 4
        return
    fi

    # Complex queries: full selection
    select_consultants "$category" "$min_affinity"
}

# Get model override for cost-aware routing
# Usage: get_cost_aware_model <consultant> <complexity>
# Returns: model name to use, or empty for default
get_cost_aware_model() {
    local consultant="$1"
    local complexity="${2:-5}"

    # Check if cost-aware routing is enabled
    if [[ "${ENABLE_COST_AWARE_ROUTING:-false}" != "true" ]]; then
        echo ""
        return
    fi

    # Check if we should use economic models for simple queries
    if [[ "${USE_ECONOMIC_MODELS_FOR_SIMPLE:-true}" != "true" ]]; then
        echo ""
        return
    fi

    local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"

    # Simple queries: use economic model
    if [[ $complexity -le $simple_threshold ]]; then
        _ensure_costs_sourced
        local economic_model
        economic_model=$(get_economic_model "$consultant" 2>/dev/null || echo "")
        echo "$economic_model"
        return
    fi

    # Complex queries: use default model
    echo ""
}

# Check if cost-aware routing is enabled
# Usage: is_cost_aware_routing_enabled
is_cost_aware_routing_enabled() {
    [[ "${ENABLE_COST_AWARE_ROUTING:-false}" == "true" ]]
}

# Get routing summary for logging
# Usage: get_routing_summary <category> <complexity> <num_consultants>
get_routing_summary() {
    local category="$1"
    local complexity="${2:-5}"
    local num_consultants="${3:-5}"

    local mode="standard"
    if is_cost_aware_routing_enabled; then
        local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"
        local medium_threshold="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

        if [[ $complexity -le $simple_threshold ]]; then
            mode="economic"
        elif [[ $complexity -le $medium_threshold ]]; then
            mode="balanced"
        else
            mode="comprehensive"
        fi
    fi

    echo "{\"category\":\"$category\",\"complexity\":$complexity,\"mode\":\"$mode\",\"consultants\":$num_consultants}"
}

# =============================================================================
# FALLBACK ESCALATION (v2.3 Quality Review)
# =============================================================================

# Fallback escalation threshold - escalate to premium if confidence below this
FALLBACK_CONFIDENCE_THRESHOLD="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

# Check if response needs escalation based on confidence
# Usage: needs_escalation <response_file>
# Returns: 0 if escalation needed, 1 otherwise
needs_escalation() {
    local response_file="$1"

    if [[ ! -f "$response_file" || ! -s "$response_file" ]]; then
        return 0  # No response = needs escalation
    fi

    local confidence
    confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)

    if [[ ! "$confidence" =~ ^[0-9]+$ ]]; then
        confidence=5
    fi

    local threshold="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

    if [[ $confidence -lt $threshold ]]; then
        return 0  # Needs escalation
    fi

    return 1  # No escalation needed
}

# Get premium model for escalation
# Usage: get_premium_model <consultant>
get_premium_model() {
    local consultant="$1"
    consultant=$(echo "$consultant" | tr '[:upper:]' '[:lower:]')

    case "$consultant" in
        gemini)   echo "gemini-2.5-pro" ;;
        codex)    echo "gpt-4o" ;;
        mistral)  echo "mistral-large" ;;
        kilo)     echo "kilo" ;;
        cursor)   echo "cursor" ;;
        claude)   echo "claude-3-opus" ;;
        qwen3)    echo "qwen-max" ;;
        glm)      echo "glm-4" ;;
        grok)     echo "grok-2" ;;
        deepseek) echo "deepseek-coder" ;;
        *)        echo "" ;;
    esac
}

# Check if escalation is enabled
# Usage: is_escalation_enabled
is_escalation_enabled() {
    # Escalation is enabled when cost-aware routing is on
    [[ "${ENABLE_COST_AWARE_ROUTING:-false}" == "true" ]]
}

# Get escalation summary for a response
# Usage: get_escalation_summary <response_file> <consultant>
get_escalation_summary() {
    local response_file="$1"
    local consultant="$2"

    local needs_it="false"
    local confidence=0
    local threshold="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

    if [[ -f "$response_file" && -s "$response_file" ]]; then
        confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
        [[ ! "$confidence" =~ ^[0-9]+$ ]] && confidence=5
    fi

    if [[ $confidence -lt $threshold ]]; then
        needs_it="true"
    fi

    local premium_model
    premium_model=$(get_premium_model "$consultant")

    cat << EOF
{
  "consultant": "$consultant",
  "confidence": $confidence,
  "threshold": $threshold,
  "needs_escalation": $needs_it,
  "premium_model": "$premium_model"
}
EOF
}
