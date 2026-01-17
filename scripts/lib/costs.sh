#!/bin/bash
# costs.sh - Cost tracking and budget management for AI Consultants v2.0
#
# Tracks consultation costs based on estimated token usage
# and manages budget limits.

# =============================================================================
# COST RATES (USD per 1K tokens)
# =============================================================================
# Using case statements for bash 3.2 compatibility (no associative arrays)

# Get input token cost per 1K tokens
# Usage: get_input_cost_per_1k <model>
get_input_cost_per_1k() {
    local model="$1"
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
