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
    declare -A approach_counts

    for a in "${approaches[@]}"; do
        approach_counts[$a]=$((${approach_counts[$a]:-0} + 1))
        if [[ ${approach_counts[$a]} -gt $most_common_count ]]; then
            most_common_count=${approach_counts[$a]}
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

    declare -A approach_weights
    declare -A approach_supporters

    # Collect weights for each approach
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)
            local confidence=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)

            # Add weight
            approach_weights[$approach]=$((${approach_weights[$approach]:-0} + confidence))

            # Add supporter
            if [[ -z "${approach_supporters[$approach]}" ]]; then
                approach_supporters[$approach]="$consultant"
            else
                approach_supporters[$approach]="${approach_supporters[$approach]},$consultant"
            fi
        fi
    done

    # Find the approach with the highest weight
    local best_approach=""
    local best_weight=0
    local best_supporters=""

    for approach in "${!approach_weights[@]}"; do
        if [[ ${approach_weights[$approach]} -gt $best_weight ]]; then
            best_weight=${approach_weights[$approach]}
            best_approach="$approach"
            best_supporters="${approach_supporters[$approach]}"
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

    printf '%s\n' "${dissenters[@]}"
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
    declare -A votes

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)
            votes[$approach]=$((${votes[$approach]:-0} + 1))
        fi
    done

    local winner=""
    local max_votes=0

    for approach in "${!votes[@]}"; do
        if [[ ${votes[$approach]} -gt $max_votes ]]; then
            max_votes=${votes[$approach]}
            winner="$approach"
        fi
    done

    echo "$winner"
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
    local recommendation=$(calculate_weighted_recommendation "$responses_dir")
    local winning_approach=$(echo "$recommendation" | jq -r '.recommended_approach')
    local final_score=$(calculate_final_score "$responses_dir" "$winning_approach")

    jq -n \
        --argjson consensus_score "$consensus_score" \
        --arg consensus_level "$consensus_level" \
        --argjson avg_confidence "$avg_confidence" \
        --argjson recommendation "$recommendation" \
        --argjson final_score "$final_score" \
        '{
            voting_report: {
                consensus: {
                    score: $consensus_score,
                    level: $consensus_level
                },
                average_confidence: $avg_confidence,
                recommendation: $recommendation,
                final_weighted_score: $final_score
            }
        }'
}
