#!/bin/bash
# costs.sh - Cost tracking and budget management for AI Consultants v2.0
#
# Tracks consultation costs based on estimated token usage
# and manages budget limits.

# =============================================================================
# COST RATES (USD per 1K tokens)
# =============================================================================

# Input token costs
declare -A INPUT_COST_PER_1K=(
    ["gemini-2.5-pro"]=0.00125
    ["gemini-2.5-flash"]=0.000075
    ["gemini-2.0-flash"]=0.0001
    ["gpt-4"]=0.03
    ["gpt-4-turbo"]=0.01
    ["gpt-4o"]=0.005
    ["gpt-4o-mini"]=0.00015
    ["o1"]=0.015
    ["o3"]=0.015
    ["claude-3-opus"]=0.015
    ["claude-3-sonnet"]=0.003
    ["claude-3-haiku"]=0.00025
    ["mistral-large"]=0.004
    ["mistral-medium"]=0.0027
    ["mistral-small"]=0.001
    ["kilo"]=0.002
    ["cursor"]=0.005
    ["default"]=0.005
)

# Output token costs (typically higher)
declare -A OUTPUT_COST_PER_1K=(
    ["gemini-2.5-pro"]=0.005
    ["gemini-2.5-flash"]=0.0003
    ["gemini-2.0-flash"]=0.0004
    ["gpt-4"]=0.06
    ["gpt-4-turbo"]=0.03
    ["gpt-4o"]=0.015
    ["gpt-4o-mini"]=0.0006
    ["o1"]=0.06
    ["o3"]=0.06
    ["claude-3-opus"]=0.075
    ["claude-3-sonnet"]=0.015
    ["claude-3-haiku"]=0.00125
    ["mistral-large"]=0.012
    ["mistral-medium"]=0.0081
    ["mistral-small"]=0.003
    ["kilo"]=0.006
    ["cursor"]=0.015
    ["default"]=0.015
)

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

    # Get rates (fallback to default)
    local input_rate="${INPUT_COST_PER_1K[$model]:-${INPUT_COST_PER_1K[default]}}"
    local output_rate="${OUTPUT_COST_PER_1K[$model]:-${OUTPUT_COST_PER_1K[default]}}"

    # Calculate cost
    local input_cost=$(echo "scale=6; $input_tokens / 1000 * $input_rate" | bc)
    local output_cost=$(echo "scale=6; $output_tokens / 1000 * $output_rate" | bc)
    local total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)

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
# Usage: estimate_consultation_cost <num_consultants> <context_size_chars>
estimate_consultation_cost() {
    local num_consultants="${1:-5}"
    local context_size="${2:-5000}"

    # Estimate tokens from context (approximately 4 chars per token)
    local estimated_input_tokens=$((context_size / 4))

    # Estimate output tokens (approximately 500-1000 per response)
    local estimated_output_tokens=750

    local total=0
    local models=("gemini-2.5-pro" "default" "mistral-large" "default" "cursor")

    for ((i=0; i<num_consultants && i<${#models[@]}; i++)); do
        local cost=$(estimate_query_cost "${models[$i]}" "$estimated_input_tokens" "$estimated_output_tokens")
        total=$(echo "scale=6; $total + $cost" | bc)
    done

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
