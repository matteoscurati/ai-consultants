#!/bin/bash
# voting.sh - Confidence-weighted voting system for AI Consultants v2.0
#
# Implements weighted voting algorithms to calculate consensus
# and recommendations based on consultant confidence scores.

# =============================================================================
# CONFIDENCE-WEIGHTED VOTING
# =============================================================================

# Calculate the weighted average of confidence scores
# Usage: calculate_weighted_average <json_responses_dir>
calculate_weighted_average() {
    local responses_dir="$1"
    local total_weight=0
    local weighted_sum=0

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)
            weighted_sum=$((weighted_sum + confidence))
            total_weight=$((total_weight + 1))
        fi
    done

    if [[ $total_weight -gt 0 ]]; then
        echo $((weighted_sum / total_weight))
    else
        echo 5
    fi
}

# Calculate consensus score based on approach similarity
# Usage: calculate_consensus_score <json_responses_dir>
calculate_consensus_score() {
    local responses_dir="$1"
    local approaches=()

    # Clear any previous map state
    map_clear "CONSENSUS_COUNTS"

    # Collect all approaches
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            approaches+=("$approach")
        fi
    done

    local total=${#approaches[@]}
    if [[ $total -eq 0 ]]; then
        echo 0
        return
    fi

    # Count unique approaches and the frequency of the most common
    local most_common_count=0

    for a in "${approaches[@]}"; do
        local current_count
        current_count=$(map_get "CONSENSUS_COUNTS" "$a")
        current_count=$((${current_count:-0} + 1))
        map_set "CONSENSUS_COUNTS" "$a" "$current_count"
        if [[ $current_count -gt $most_common_count ]]; then
            most_common_count=$current_count
        fi
    done

    # Score = percentage that shares the most common approach
    local score=$((most_common_count * 100 / total))
    echo $score
}

# Determine the consensus level from a score
# Usage: get_consensus_level <score>
get_consensus_level() {
    local score=$1

    if [[ $score -ge 100 ]]; then
        echo "unanimous"
    elif [[ $score -ge 75 ]]; then
        echo "high"
    elif [[ $score -ge 50 ]]; then
        echo "medium"
    elif [[ $score -ge 25 ]]; then
        echo "low"
    else
        echo "none"
    fi
}

# Calculate the confidence-weighted recommendation
# Usage: calculate_weighted_recommendation <json_responses_dir>
# Output: JSON with the recommendation
calculate_weighted_recommendation() {
    local responses_dir="$1"

    # Clear any previous map state
    map_clear "APPROACH_WEIGHTS"
    map_clear "APPROACH_SUPPORTERS"

    # Collect weights for each approach
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local consultant approach confidence current_weight current_supporters
            consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)
            confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)

            # Add weight
            current_weight=$(map_get "APPROACH_WEIGHTS" "$approach")
            map_set "APPROACH_WEIGHTS" "$approach" "$((${current_weight:-0} + confidence))"

            # Add supporter
            current_supporters=$(map_get "APPROACH_SUPPORTERS" "$approach")
            if [[ -z "$current_supporters" ]]; then
                map_set "APPROACH_SUPPORTERS" "$approach" "$consultant"
            else
                map_set "APPROACH_SUPPORTERS" "$approach" "${current_supporters},$consultant"
            fi
        fi
    done

    # Find the approach with the highest weight using map_keys
    local best_approach=""
    local best_weight=0
    local best_supporters=""
    local approach weight

    for approach in $(map_keys "APPROACH_WEIGHTS"); do
        weight=$(map_get "APPROACH_WEIGHTS" "$approach")
        weight="${weight:-0}"
        if [[ $weight -gt $best_weight ]]; then
            best_weight=$weight
            best_approach="$approach"
            best_supporters=$(map_get "APPROACH_SUPPORTERS" "$approach")
        fi
    done

    # Output JSON
    jq -n \
        --arg approach "$best_approach" \
        --argjson weight "$best_weight" \
        --arg supporters "$best_supporters" \
        '{
            recommended_approach: $approach,
            total_weight: $weight,
            supporters: ($supporters | split(","))
        }'
}

# Identify dissenters (those who do not support the winning approach)
# Usage: get_dissenters <json_responses_dir> <winning_approach>
get_dissenters() {
    local responses_dir="$1"
    local winning_approach="$2"
    local dissenters=()

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)

            if [[ "$approach" != "$winning_approach" ]]; then
                dissenters+=("$consultant")
            fi
        fi
    done

    printf '%s\n' ${dissenters[@]+"${dissenters[@]}"}
}

# Calculate confidence-weighted final score
# Usage: calculate_final_score <json_responses_dir> <winning_approach>
calculate_final_score() {
    local responses_dir="$1"
    local winning_approach="$2"

    local weighted_sum=0
    local total_confidence=0

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)
            local confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)

            total_confidence=$((total_confidence + confidence))

            # Full weight if supports, half if neutral, zero if dissents
            if [[ "$approach" == "$winning_approach" ]]; then
                weighted_sum=$((weighted_sum + confidence * 10))  # Full support
            else
                weighted_sum=$((weighted_sum + confidence * 2))   # Dissent but consider
            fi
        fi
    done

    if [[ $total_confidence -gt 0 ]]; then
        # Normalize to 1-10 scale
        local score=$((weighted_sum / total_confidence))
        if [[ $score -gt 10 ]]; then
            score=10
        fi
        echo $score
    else
        echo 5
    fi
}

# =============================================================================
# MAJORITY VOTING (simple)
# =============================================================================

# Simple majority vote (unweighted)
# Usage: simple_majority_vote <json_responses_dir>
simple_majority_vote() {
    local responses_dir="$1"

    # Clear any previous map state
    map_clear "MAJORITY_VOTES"

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local approach current_votes
            approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)
            current_votes=$(map_get "MAJORITY_VOTES" "$approach")
            map_set "MAJORITY_VOTES" "$approach" "$((${current_votes:-0} + 1))"
        fi
    done

    # Find approach with most votes using map_keys
    local winner=""
    local max_votes=0
    local approach votes

    for approach in $(map_keys "MAJORITY_VOTES"); do
        votes=$(map_get "MAJORITY_VOTES" "$approach")
        votes="${votes:-0}"
        if [[ $votes -gt $max_votes ]]; then
            max_votes=$votes
            winner="$approach"
        fi
    done

    echo "$winner"
}

# =============================================================================
# CONFIDENCE INTERVALS (v2.2)
# =============================================================================

# Calculate standard deviation of confidence scores
# Usage: calculate_confidence_stddev <json_responses_dir>
# Returns: Standard deviation value (integer, scaled by 10 for precision)
calculate_confidence_stddev() {
    local responses_dir="$1"
    local scores=()
    local sum=0
    local count=0

    # Collect all confidence scores
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local score=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)
            scores+=("$score")
            sum=$((sum + score))
            count=$((count + 1))
        fi
    done

    if [[ $count -lt 2 ]]; then
        echo 0
        return
    fi

    # Calculate mean (scaled by 10 for precision)
    local mean_scaled=$((sum * 10 / count))

    # Calculate variance
    local variance_sum=0
    for score in "${scores[@]}"; do
        local diff=$((score * 10 - mean_scaled))
        variance_sum=$((variance_sum + diff * diff))
    done
    local variance=$((variance_sum / count))

    # Approximate square root using Newton's method (integer math)
    # For small numbers, this gives reasonable results
    if [[ $variance -eq 0 ]]; then
        echo 0
        return
    fi

    local sqrt=$variance
    local prev=0
    for _ in {1..10}; do
        prev=$sqrt
        sqrt=$(( (sqrt + variance / sqrt) / 2 ))
        [[ $sqrt -eq $prev ]] && break
    done

    # Return scaled by 10 (so 15 means 1.5)
    echo $sqrt
}

# Calculate confidence interval
# Usage: calculate_confidence_interval <json_responses_dir>
# Output: JSON with mean, stddev, low, high bounds
calculate_confidence_interval() {
    local responses_dir="$1"

    local mean=$(calculate_weighted_average "$responses_dir")
    local stddev_scaled=$(calculate_confidence_stddev "$responses_dir")

    # Convert scaled stddev back to decimal format for display
    local stddev_int=$((stddev_scaled / 10))
    local stddev_dec=$((stddev_scaled % 10))

    # Calculate bounds (mean ± stddev)
    local low=$((mean * 10 - stddev_scaled))
    local high=$((mean * 10 + stddev_scaled))

    # Clamp to valid range [1, 10]
    [[ $low -lt 10 ]] && low=10
    [[ $high -gt 100 ]] && high=100

    local low_int=$((low / 10))
    local low_dec=$((low % 10))
    local high_int=$((high / 10))
    local high_dec=$((high % 10))

    jq -n \
        --argjson mean "$mean" \
        --arg stddev "${stddev_int}.${stddev_dec}" \
        --arg low "${low_int}.${low_dec}" \
        --arg high "${high_int}.${high_dec}" \
        --argjson variance_high "$([ $stddev_scaled -gt 20 ] && echo "true" || echo "false")" \
        '{
            mean: $mean,
            stddev: ($stddev | tonumber),
            interval: {
                low: ($low | tonumber),
                high: ($high | tonumber)
            },
            display: "\($mean) ± \($stddev)",
            high_variance: $variance_high
        }'
}

# Check if confidence scores have high variance (uncertainty indicator)
# Usage: has_high_confidence_variance <json_responses_dir>
# Returns: 0 (true) if variance is high, 1 (false) otherwise
has_high_confidence_variance() {
    local responses_dir="$1"
    local stddev_scaled=$(calculate_confidence_stddev "$responses_dir")

    # Consider variance "high" if stddev > 2.0 (scaled value > 20)
    [[ $stddev_scaled -gt 20 ]]
}

# Get confidence range as formatted string
# Usage: format_confidence_range <json_responses_dir>
# Output: "7 ± 1.5" or "7 (±1.5, high variance!)"
format_confidence_range() {
    local responses_dir="$1"
    local interval_json=$(calculate_confidence_interval "$responses_dir")

    local display=$(echo "$interval_json" | jq -r '.display')
    local high_variance=$(echo "$interval_json" | jq -r '.high_variance')

    if [[ "$high_variance" == "true" ]]; then
        echo "$display (high variance - uncertainty detected)"
    else
        echo "$display"
    fi
}

# =============================================================================
# UTILITY
# =============================================================================

# Generate complete voting report
# Usage: generate_voting_report <json_responses_dir>
generate_voting_report() {
    local responses_dir="$1"

    local consensus_score=$(calculate_consensus_score "$responses_dir")
    local consensus_level=$(get_consensus_level "$consensus_score")
    local avg_confidence=$(calculate_weighted_average "$responses_dir")
    local confidence_interval=$(calculate_confidence_interval "$responses_dir")
    local recommendation=$(calculate_weighted_recommendation "$responses_dir")
    local winning_approach=$(echo "$recommendation" | jq -r '.recommended_approach')
    local final_score=$(calculate_final_score "$responses_dir" "$winning_approach")

    jq -n \
        --argjson consensus_score "$consensus_score" \
        --arg consensus_level "$consensus_level" \
        --argjson avg_confidence "$avg_confidence" \
        --argjson confidence_interval "$confidence_interval" \
        --argjson recommendation "$recommendation" \
        --argjson final_score "$final_score" \
        '{
            voting_report: {
                consensus: {
                    score: $consensus_score,
                    level: $consensus_level
                },
                average_confidence: $avg_confidence,
                confidence_interval: $confidence_interval,
                recommendation: $recommendation,
                final_weighted_score: $final_score
            }
        }'
}
