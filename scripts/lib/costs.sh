#!/bin/bash
# costs.sh - Cost tracking and budget management for AI Consultants v2.0
#
# Tracks consultation costs based on estimated token usage
# and manages budget limits.

# =============================================================================
# EXTERNAL RATES FILE (v2.4)
# =============================================================================
# Path to external rates file for easy updates

# Get the script directory for relative path resolution
_COSTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COST_RATES_FILE="${COST_RATES_FILE:-$_COSTS_SCRIPT_DIR/../../docs/cost_rates.json}"

# Load rate from JSON file
# Usage: get_rate_from_file <model> <type: input|output>
# Returns: rate as string, or exits with 1 if not found
get_rate_from_file() {
    local model="$1"
    local type="$2"

    if [[ -f "$COST_RATES_FILE" ]]; then
        local rate
        rate=$(jq -r ".models[\"$model\"].$type // null" "$COST_RATES_FILE" 2>/dev/null)
        if [[ "$rate" != "null" && -n "$rate" ]]; then
            echo "$rate"
            return 0
        fi
    fi
    return 1
}

# Get fallback model for a consultant
# Usage: get_consultant_fallback_model <consultant>
# Returns: fallback model name (empty string if not found)
get_consultant_fallback_model() {
    local consultant="$1"
    consultant=$(echo "$consultant" | tr '[:upper:]' '[:lower:]')

    if [[ -f "$COST_RATES_FILE" ]]; then
        local fallback
        fallback=$(jq -r ".consultant_fallbacks[\"$consultant\"] // null" "$COST_RATES_FILE" 2>/dev/null)
        if [[ "$fallback" != "null" && -n "$fallback" ]]; then
            echo "$fallback"
        fi
    fi
}

# Resolve model name: use reported model if known, else fallback
# Usage: resolve_model_for_cost <reported_model> <consultant>
# Returns: resolved model name for cost calculation
resolve_model_for_cost() {
    local model="$1"
    local consultant="$2"

    # Fetch fallback once for reuse
    local fallback
    fallback=$(get_consultant_fallback_model "$consultant")

    # If model is "default", empty, or unknown, use fallback
    if [[ -z "$model" || "$model" == "default" ]]; then
        if [[ -n "$fallback" ]]; then
            type log_debug &>/dev/null && log_debug "Using fallback model '$fallback' for $consultant (reported: '$model')"
            echo "$fallback"
            return 0
        fi
    fi

    # Check if model exists in rates file
    if get_rate_from_file "$model" "input" >/dev/null 2>&1; then
        echo "$model"
        return 0
    fi

    # Model not in rates file, try fallback
    if [[ -n "$fallback" ]]; then
        type log_debug &>/dev/null && log_debug "Model '$model' not in rates, using fallback '$fallback' for $consultant"
        echo "$fallback"
        return 0
    fi

    # Return original (will use default rate)
    echo "$model"
}

# Get default rate from JSON file
# Usage: get_default_rate <type: input|output>
get_default_rate() {
    local type="$1"
    if [[ -f "$COST_RATES_FILE" ]]; then
        local rate
        rate=$(jq -r ".default_rate.$type // null" "$COST_RATES_FILE" 2>/dev/null)
        if [[ "$rate" != "null" && -n "$rate" ]]; then
            echo "$rate"
            return 0
        fi
    fi
    # Hardcoded fallback
    case "$type" in
        input)  echo "0.005" ;;
        output) echo "0.015" ;;
    esac
}

# =============================================================================
# COST RATES (USD per 1K tokens)
# =============================================================================
# Using case statements for bash 3.2 compatibility (no associative arrays)
# External JSON file is tried first, then fallback to hardcoded rates

# Get input token cost per 1K tokens
# Usage: get_input_cost_per_1k <model>
get_input_cost_per_1k() {
    local model="$1"
    model=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    # Try external file first
    local rate
    if rate=$(get_rate_from_file "$model" "input" 2>/dev/null); then
        echo "$rate"
        return
    fi

    # Fallback to hardcoded rates for backwards compatibility
    case "$model" in
        gemini-2.5-pro)   echo "0.00125" ;;
        gemini-2.5-flash) echo "0.000075" ;;
        gemini-2.0-flash) echo "0.0001" ;;
        gpt-4)            echo "0.03" ;;
        gpt-4-turbo)      echo "0.01" ;;
        gpt-4o)           echo "0.005" ;;
        gpt-4o-mini)      echo "0.00015" ;;
        o1)               echo "0.015" ;;
        o3)               echo "0.015" ;;
        claude-3-opus)    echo "0.015" ;;
        claude-3-sonnet)  echo "0.003" ;;
        claude-3-haiku)   echo "0.00025" ;;
        mistral-large)    echo "0.004" ;;
        mistral-medium)   echo "0.0027" ;;
        mistral-small)    echo "0.001" ;;
        kilo)             echo "0.002" ;;
        cursor)           echo "0.005" ;;
        # Qwen3 models (Alibaba DashScope)
        qwen-max)         echo "0.004" ;;
        qwen-plus)        echo "0.002" ;;
        qwen-turbo)       echo "0.0008" ;;
        # GLM models (Zhipu AI)
        glm-4)            echo "0.003" ;;
        glm-3-turbo)      echo "0.001" ;;
        # Grok models (xAI)
        grok-beta)        echo "0.005" ;;
        grok-2)           echo "0.01" ;;
        # Default
        *)                echo "0.005" ;;
    esac
}

# Get output token cost per 1K tokens
# Usage: get_output_cost_per_1k <model>
get_output_cost_per_1k() {
    local model="$1"
    model=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    # Try external file first
    local rate
    if rate=$(get_rate_from_file "$model" "output" 2>/dev/null); then
        echo "$rate"
        return
    fi

    # Fallback to hardcoded rates for backwards compatibility
    case "$model" in
        gemini-2.5-pro)   echo "0.005" ;;
        gemini-2.5-flash) echo "0.0003" ;;
        gemini-2.0-flash) echo "0.0004" ;;
        gpt-4)            echo "0.06" ;;
        gpt-4-turbo)      echo "0.03" ;;
        gpt-4o)           echo "0.015" ;;
        gpt-4o-mini)      echo "0.0006" ;;
        o1)               echo "0.06" ;;
        o3)               echo "0.06" ;;
        claude-3-opus)    echo "0.075" ;;
        claude-3-sonnet)  echo "0.015" ;;
        claude-3-haiku)   echo "0.00125" ;;
        mistral-large)    echo "0.012" ;;
        mistral-medium)   echo "0.0081" ;;
        mistral-small)    echo "0.003" ;;
        kilo)             echo "0.006" ;;
        cursor)           echo "0.015" ;;
        # Qwen3 models (Alibaba DashScope)
        qwen-max)         echo "0.012" ;;
        qwen-plus)        echo "0.006" ;;
        qwen-turbo)       echo "0.002" ;;
        # GLM models (Zhipu AI)
        glm-4)            echo "0.009" ;;
        glm-3-turbo)      echo "0.003" ;;
        # Grok models (xAI)
        grok-beta)        echo "0.015" ;;
        grok-2)           echo "0.03" ;;
        # Default
        *)                echo "0.015" ;;
    esac
}

# =============================================================================
# COST CALCULATION
# =============================================================================

# Estimate cost for a query
# Usage: estimate_query_cost <model> <input_tokens> <output_tokens>
estimate_query_cost() {
    local model="$1"
    local input_tokens="${2:-1000}"
    local output_tokens="${3:-500}"

    # Normalize model name
    model=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    # Get rates using lookup functions
    local input_rate output_rate
    input_rate=$(get_input_cost_per_1k "$model")
    output_rate=$(get_output_cost_per_1k "$model")

    # Calculate cost
    local input_cost output_cost total_cost
    input_cost=$(echo "scale=6; $input_tokens / 1000 * $input_rate" | bc)
    output_cost=$(echo "scale=6; $output_tokens / 1000 * $output_rate" | bc)
    total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)

    echo "$total_cost"
}

# Calculate total session cost from responses
# Usage: calculate_session_cost <responses_dir>
calculate_session_cost() {
    local responses_dir="$1"
    local total_cost=0

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local model=$(jq -r '.model // "default"' "$f" 2>/dev/null)
            local tokens=$(jq -r '.metadata.tokens_used // 1000' "$f" 2>/dev/null)

            # Assume 60% input, 40% output
            local input_tokens=$((tokens * 60 / 100))
            local output_tokens=$((tokens * 40 / 100))

            local cost=$(estimate_query_cost "$model" "$input_tokens" "$output_tokens")
            total_cost=$(echo "scale=6; $total_cost + $cost" | bc)
        fi
    done

    echo "$total_cost"
}

# Format cost for display
# Usage: format_cost <cost_usd>
format_cost() {
    local cost="$1"

    # Convert to cents if very small
    if (( $(echo "$cost < 0.01" | bc -l) )); then
        local cents=$(echo "scale=2; $cost * 100" | bc)
        echo "${cents}¢"
    else
        printf "\$%.4f" "$cost"
    fi
}

# =============================================================================
# BUDGET MANAGEMENT
# =============================================================================

# Check if cost exceeds budget
# Usage: check_budget <cost> <budget>
check_budget() {
    local cost="$1"
    local budget="${2:-${MAX_SESSION_COST:-1.00}}"

    if (( $(echo "$cost > $budget" | bc -l) )); then
        return 1  # Over budget
    fi
    return 0  # Within budget
}

# Check if we are close to warning threshold
# Usage: check_warning_threshold <cost>
check_warning_threshold() {
    local cost="$1"
    local threshold="${WARN_AT_COST:-0.50}"

    if (( $(echo "$cost > $threshold" | bc -l) )); then
        return 0  # Should warn
    fi
    return 1  # No warning needed
}

# Estimate pre-consultation cost (before executing)
# Usage: estimate_consultation_cost <num_consultants> <context_size_chars> [consultants_csv]
# The consultants_csv parameter is a comma-separated list of consultant names (e.g., "Gemini,Codex,Mistral")
estimate_consultation_cost() {
    local num_consultants="${1:-5}"
    local context_size="${2:-5000}"
    local consultants="${3:-}"

    # Estimate tokens from context (approximately 4 chars per token)
    local estimated_input_tokens=$((context_size / 4))

    # Estimate output tokens (approximately 500-1000 per response)
    local estimated_output_tokens=750

    local total=0

    if [[ -n "$consultants" ]]; then
        # Use provided consultant list with fallback models
        local IFS=','
        read -ra consultant_list <<< "$consultants"
        for consultant in "${consultant_list[@]}"; do
            local fallback_model
            fallback_model=$(get_consultant_fallback_model "$consultant")
            local model_to_use="${fallback_model:-default}"
            local cost=$(estimate_query_cost "$model_to_use" "$estimated_input_tokens" "$estimated_output_tokens")
            total=$(echo "scale=6; $total + $cost" | bc)
        done
    else
        # Fallback to generic estimate using default rate
        for ((i=0; i<num_consultants; i++)); do
            local default_input default_output
            default_input=$(get_default_rate "input")
            default_output=$(get_default_rate "output")
            local input_cost output_cost cost
            input_cost=$(echo "scale=6; $estimated_input_tokens / 1000 * $default_input" | bc)
            output_cost=$(echo "scale=6; $estimated_output_tokens / 1000 * $default_output" | bc)
            cost=$(echo "scale=6; $input_cost + $output_cost" | bc)
            total=$(echo "scale=6; $total + $cost" | bc)
        done
    fi

    echo "$total"
}

# =============================================================================
# COST TRACKING
# =============================================================================

# File for cumulative tracking
COST_TRACKING_FILE="${COST_TRACKING_FILE:-/tmp/ai_consultants_costs.json}"

# Record session cost
# Usage: track_session_cost <session_id> <cost>
track_session_cost() {
    local session_id="$1"
    local cost="$2"
    local timestamp=$(date -Iseconds)

    # Create file if it doesn't exist
    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo '{"sessions": [], "total_cost": 0}' > "$COST_TRACKING_FILE"
    fi

    # Add session and update total
    jq --arg id "$session_id" \
       --arg cost "$cost" \
       --arg ts "$timestamp" \
       '.sessions += [{id: $id, cost: ($cost | tonumber), timestamp: $ts}] | .total_cost += ($cost | tonumber)' \
       "$COST_TRACKING_FILE" > "${COST_TRACKING_FILE}.tmp" && \
       mv "${COST_TRACKING_FILE}.tmp" "$COST_TRACKING_FILE"
}

# Get total tracked cost
# Usage: get_total_tracked_cost
get_total_tracked_cost() {
    if [[ -f "$COST_TRACKING_FILE" ]]; then
        jq -r '.total_cost // 0' "$COST_TRACKING_FILE"
    else
        echo 0
    fi
}

# Generate cost report
# Usage: generate_cost_report
generate_cost_report() {
    if [[ ! -f "$COST_TRACKING_FILE" ]]; then
        echo "No cost data available"
        return
    fi

    local total=$(jq -r '.total_cost // 0' "$COST_TRACKING_FILE")
    local sessions=$(jq -r '.sessions | length' "$COST_TRACKING_FILE")
    local avg=0
    if [[ $sessions -gt 0 ]]; then
        avg=$(echo "scale=6; $total / $sessions" | bc)
    fi

    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Cost Report                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Total sessions: $sessions"
    echo "  Total cost: $(format_cost $total)"
    echo "  Average per session: $(format_cost $avg)"
    echo ""

    # Last 5 sessions
    echo "  Recent sessions:"
    jq -r '.sessions | .[-5:] | .[] | "    \(.timestamp): \(.id) - $\(.cost)"' "$COST_TRACKING_FILE" 2>/dev/null || echo "    No sessions"
}

# =============================================================================
# UTILITY
# =============================================================================

# Convert tokens to estimated cost (quick helper)
# Usage: tokens_to_cost <tokens> [model]
tokens_to_cost() {
    local tokens="$1"
    local model="${2:-default}"

    # Assume 60/40 split
    local input=$((tokens * 60 / 100))
    local output=$((tokens * 40 / 100))

    estimate_query_cost "$model" "$input" "$output"
}

# =============================================================================
# RESPONSE LENGTH LIMITS (v2.3)
# =============================================================================

# Get max response tokens for a category
# Usage: get_max_response_tokens <category>
get_max_response_tokens() {
    local category="$1"
    local limits="${MAX_RESPONSE_TOKENS_BY_CATEGORY:-QUICK_SYNTAX:200,CODE_REVIEW:800,BUG_DEBUG:800,ARCHITECTURE:1000,SECURITY:1000,DATABASE:600,GENERAL:500}"

    # Search for category in the limits string
    local limit
    limit=$(echo "$limits" | tr ',' '\n' | grep -i "^${category}:" | cut -d: -f2 | head -1)

    # Return limit or default
    if [[ -n "$limit" && "$limit" =~ ^[0-9]+$ ]]; then
        echo "$limit"
    else
        echo "500"  # Default
    fi
}

# Check if response limits are enabled
# Usage: is_response_limits_enabled
is_response_limits_enabled() {
    [[ "${ENABLE_RESPONSE_LIMITS:-true}" == "true" ]]
}

# Get model tier (economy, standard, premium)
# Usage: get_model_tier <model>
get_model_tier() {
    local model="$1"
    model=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    case "$model" in
        # Economy tier - cheapest models
        gemini-2.5-flash|gemini-2.0-flash|gpt-4o-mini|claude-3-haiku|mistral-small|qwen-turbo|glm-3-turbo)
            echo "economy"
            ;;
        # Premium tier - most expensive models
        gpt-4|gpt-4-turbo|o1|o3|claude-3-opus|mistral-large|grok-2|qwen-max)
            echo "premium"
            ;;
        # Standard tier - default/mid-range
        *)
            echo "standard"
            ;;
    esac
}

# Get economic model for a consultant
# Usage: get_economic_model <consultant>
get_economic_model() {
    local consultant="$1"
    consultant=$(echo "$consultant" | tr '[:upper:]' '[:lower:]')

    case "$consultant" in
        gemini)   echo "gemini-2.5-flash" ;;
        codex)    echo "gpt-4o-mini" ;;
        mistral)  echo "mistral-small" ;;
        kilo)     echo "kilo" ;;           # No economy variant
        cursor)   echo "cursor" ;;          # No economy variant
        claude)   echo "claude-3-haiku" ;;
        qwen3)    echo "qwen-turbo" ;;
        glm)      echo "glm-3-turbo" ;;
        grok)     echo "grok-beta" ;;       # No economy variant
        deepseek) echo "deepseek-coder" ;;  # No economy variant
        *)        echo "" ;;
    esac
}

# Calculate query complexity score (1-10)
# Usage: calculate_query_complexity <query> <num_files> <category>
calculate_query_complexity() {
    local query="$1"
    local num_files="${2:-0}"
    local category="${3:-GENERAL}"

    local score=5  # Base score

    # Length factor
    local query_len=${#query}
    if [[ $query_len -gt 500 ]]; then
        score=$((score + 2))
    elif [[ $query_len -gt 200 ]]; then
        score=$((score + 1))
    elif [[ $query_len -lt 50 ]]; then
        score=$((score - 1))
    fi

    # File count factor
    if [[ $num_files -gt 5 ]]; then
        score=$((score + 2))
    elif [[ $num_files -gt 2 ]]; then
        score=$((score + 1))
    elif [[ $num_files -eq 0 ]]; then
        score=$((score - 1))
    fi

    # Category factor
    case "$category" in
        ARCHITECTURE|SECURITY)
            score=$((score + 2))
            ;;
        CODE_REVIEW|BUG_DEBUG)
            score=$((score + 1))
            ;;
        QUICK_SYNTAX)
            score=$((score - 2))
            ;;
    esac

    # Keyword complexity indicators
    if echo "$query" | grep -qiE "(architecture|design|scalab|security|performance|refactor|migrate)"; then
        score=$((score + 1))
    fi
    if echo "$query" | grep -qiE "(fix|bug|error|typo|rename)"; then
        score=$((score - 1))
    fi

    # Cap at 1-10
    [[ $score -gt 10 ]] && score=10
    [[ $score -lt 1 ]] && score=1

    echo "$score"
}

# Check if query is simple (should use economic models)
# Usage: is_simple_query <complexity_score>
is_simple_query() {
    local complexity="${1:-5}"
    local threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"

    [[ $complexity -le $threshold ]]
}

# Check if query is complex (should use premium models)
# Usage: is_complex_query <complexity_score>
is_complex_query() {
    local complexity="${1:-5}"
    local threshold="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

    [[ $complexity -gt $threshold ]]
}

# =============================================================================
# BUDGET ENFORCEMENT (v2.4)
# =============================================================================

# Check if budget enforcement is enabled
# Usage: is_budget_enabled
is_budget_enabled() {
    [[ "${ENABLE_BUDGET_LIMIT:-false}" == "true" ]]
}

# Get remaining budget
# Usage: get_remaining_budget <current_cost>
get_remaining_budget() {
    local current_cost="${1:-0}"
    local budget="${MAX_SESSION_COST:-1.00}"

    echo "scale=6; $budget - $current_cost" | bc
}

# Format budget status for display
# Usage: format_budget_status <current_cost> [budget]
format_budget_status() {
    local current_cost="${1:-0}"
    local budget="${2:-${MAX_SESSION_COST:-1.00}}"

    local remaining
    remaining=$(get_remaining_budget "$current_cost")
    local percent_used
    percent_used=$(echo "scale=1; $current_cost / $budget * 100" | bc 2>/dev/null || echo "0")

    echo "$(format_cost "$current_cost") / $(format_cost "$budget") (${percent_used}% used)"
}

# Enforce budget and take action based on BUDGET_ACTION
# Returns: 0 = proceed, 1 = stop
# Usage: enforce_budget <current_cost> <additional_estimate> <context_msg>
enforce_budget() {
    local current_cost="${1:-0}"
    local additional_estimate="${2:-0}"
    local context_msg="${3:-operation}"
    local budget="${MAX_SESSION_COST:-1.00}"
    local action="${BUDGET_ACTION:-warn}"

    # Skip if budget enforcement is disabled
    if ! is_budget_enabled; then
        return 0
    fi

    # Calculate projected cost
    local projected_cost
    projected_cost=$(echo "scale=6; $current_cost + $additional_estimate" | bc)

    # Check if projected cost exceeds budget
    if ! check_budget "$projected_cost" "$budget"; then
        local msg="Budget limit exceeded for $context_msg: projected $(format_cost "$projected_cost") > $(format_cost "$budget")"

        case "$action" in
            stop)
                log_error "$msg"
                log_error "Stopping consultation (BUDGET_ACTION=stop)"
                return 1
                ;;
            warn|*)
                log_warn "$msg"
                log_warn "Continuing despite budget limit (BUDGET_ACTION=warn)"
                return 0
                ;;
        esac
    fi

    return 0
}

# Estimate cost for a specific phase
# Usage: estimate_phase_cost <phase> <num_consultants> <context_size>
estimate_phase_cost() {
    local phase="$1"
    local num_consultants="${2:-4}"
    local context_size="${3:-5000}"

    case "$phase" in
        round1|consultation)
            # Initial consultation: all consultants
            estimate_consultation_cost "$num_consultants" "$context_size"
            ;;
        debate)
            # Debate round: ~50% of consultation cost per round
            local base
            base=$(estimate_consultation_cost "$num_consultants" "$context_size")
            echo "scale=6; $base * 0.5" | bc
            ;;
        synthesis)
            # Synthesis: single model, larger output
            estimate_query_cost "claude-3-sonnet" 2000 1500
            ;;
        *)
            echo "0"
            ;;
    esac
}
