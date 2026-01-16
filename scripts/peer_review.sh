#!/bin/bash
# peer_review.sh - Anonymous Peer Review for AI Consultants v2.2
#
# Implements blind peer review where consultants evaluate each other's
# responses without knowing the source, reducing bias and identifying
# the strongest arguments.
#
# Process:
#   1. Anonymize all responses (remove consultant names/identifiers)
#   2. Each consultant ranks and critiques top 2-3 responses
#   3. Aggregate peer scores to identify strongest arguments
#   4. De-anonymize in final report with peer scores
#
# Usage: ./peer_review.sh <responses_dir> <output_dir>
#
# Input: Directory containing consultant JSON responses
# Output: Directory with peer review results and aggregated scores

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Number of responses each consultant reviews (2-3 recommended)
REVIEWS_PER_CONSULTANT="${REVIEWS_PER_CONSULTANT:-3}"

# Minimum consultants needed for peer review
MIN_CONSULTANTS_FOR_REVIEW=3

# =============================================================================
# ANONYMIZATION
# =============================================================================

# Create anonymous ID from consultant name
# Uses a simple hash-like approach for deterministic but hidden IDs
generate_anonymous_id() {
    local consultant="$1"
    local index="$2"
    echo "Response_$(printf '%c' $((65 + index)))"  # A, B, C, D, etc.
}

# Anonymize a response by removing identifying information
# Usage: anonymize_response <response_file> <anonymous_id>
anonymize_response() {
    local response_file="$1"
    local anon_id="$2"

    # Remove consultant name and persona, keep the substance
    jq --arg anon_id "$anon_id" '
        del(.consultant, .persona, .model) |
        . + {anonymous_id: $anon_id}
    ' "$response_file" 2>/dev/null
}

# Create mapping file for de-anonymization later
# Usage: create_mapping <responses_dir> <output_file>
create_mapping() {
    local responses_dir="$1"
    local output_file="$2"

    local mapping="{}"
    local index=0

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" ]]; then
            local consultant
            consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            local anon_id
            anon_id=$(generate_anonymous_id "$consultant" "$index")

            mapping=$(echo "$mapping" | jq \
                --arg anon "$anon_id" \
                --arg real "$consultant" \
                --arg file "$(basename "$f")" \
                '. + {($anon): {consultant: $real, file: $file}}')

            ((index++))
        fi
    done

    echo "$mapping" > "$output_file"
}

# =============================================================================
# PEER REVIEW PROMPTS
# =============================================================================

# Generate the peer review prompt
generate_review_prompt() {
    local anonymous_responses="$1"

    cat << EOF
You are an expert peer reviewer evaluating anonymous responses to a coding question.
Review each response objectively without knowing who wrote it.

## Anonymous Responses to Review

$anonymous_responses

## Your Task

For each response, provide:
1. **Quality Score** (1-10): Overall quality of the response
2. **Strengths**: What the response does well (2-3 points)
3. **Weaknesses**: What could be improved (2-3 points)
4. **Ranking**: Rank all responses from best to worst

Respond ONLY with valid JSON:
{
  "reviews": [
    {
      "response_id": "Response_A",
      "quality_score": <1-10>,
      "strengths": ["<strength1>", "<strength2>"],
      "weaknesses": ["<weakness1>", "<weakness2>"],
      "key_insight": "<most valuable insight from this response>"
    }
  ],
  "ranking": ["Response_A", "Response_B", ...],
  "best_overall": "<response_id with best overall answer>",
  "reasoning": "<why you ranked them this way>"
}
EOF
}

# =============================================================================
# PEER REVIEW EXECUTION
# =============================================================================

# Run peer review for a single consultant
# Usage: run_consultant_review <consultant> <anonymous_file> <output_file>
run_consultant_review() {
    local consultant="$1"
    local anonymous_file="$2"
    local output_file="$3"

    local prompt
    prompt=$(generate_review_prompt "$(cat "$anonymous_file")")

    local timeout_var="${consultant^^}_TIMEOUT_SECONDS"
    local timeout="${!timeout_var:-180}"

    log_debug "Running peer review by $consultant..."

    case "$consultant" in
        Gemini)  echo "$prompt" | run_with_timeout "$timeout" "$GEMINI_CMD" -p - -m "$GEMINI_MODEL" ;;
        Codex)   run_with_timeout "$timeout" "$CODEX_CMD" exec --skip-git-repo-check "$prompt" ;;
        Mistral) run_with_timeout "$timeout" "$MISTRAL_CMD" --prompt "$prompt" --auto-approve ;;
        Kilo)    run_with_timeout "$timeout" "$KILO_CMD" --auto --json "$prompt" ;;
        Cursor)  run_with_timeout "$timeout" "$CURSOR_CMD" "$prompt" ;;
        *)
            echo '{"error": "Unknown consultant for peer review"}' > "$output_file"
            return 1
            ;;
    esac > "$output_file" 2>/dev/null
}

# Extract JSON from response (may have text wrapper)
extract_json_from_response() {
    local input="$1"

    # Try to extract JSON
    if echo "$input" | jq -e '.' > /dev/null 2>&1; then
        echo "$input"
        return 0
    fi

    # Try to extract from markdown code block
    local extracted
    extracted=$(echo "$input" | sed -n '/```json/,/```/p' | sed '1d;$d')
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e '.' > /dev/null 2>&1; then
        echo "$extracted"
        return 0
    fi

    # Try to find first { to last }
    extracted=$(echo "$input" | sed -n '/{/,/}/p')
    if [[ -n "$extracted" ]] && echo "$extracted" | jq -e '.' > /dev/null 2>&1; then
        echo "$extracted"
        return 0
    fi

    echo '{"error": "Could not extract JSON from response"}'
    return 1
}

# =============================================================================
# AGGREGATION
# =============================================================================

# Aggregate peer review scores
# Usage: aggregate_peer_scores <reviews_dir> <mapping_file> <output_file>
aggregate_peer_scores() {
    local reviews_dir="$1"
    local mapping_file="$2"
    local output_file="$3"

    local mapping
    mapping=$(cat "$mapping_file")

    # Initialize score tracking
    local aggregated='{}'

    # Process each review file
    for review_file in "$reviews_dir"/review_*.json; do
        if [[ ! -f "$review_file" ]]; then
            continue
        fi

        local reviewer
        reviewer=$(basename "$review_file" .json | sed 's/review_//')

        local review_content
        review_content=$(cat "$review_file")

        # Extract reviews array
        local reviews
        reviews=$(echo "$review_content" | jq -r '.reviews // []' 2>/dev/null)

        # Process each individual review
        echo "$reviews" | jq -c '.[]' 2>/dev/null | while read -r review; do
            local response_id score
            response_id=$(echo "$review" | jq -r '.response_id // ""')
            score=$(echo "$review" | jq -r '.quality_score // 5')

            if [[ -n "$response_id" ]]; then
                # Update aggregated scores
                aggregated=$(echo "$aggregated" | jq \
                    --arg id "$response_id" \
                    --argjson score "$score" \
                    --arg reviewer "$reviewer" \
                    '
                    if .[$id] then
                        .[$id].scores += [$score] |
                        .[$id].reviewers += [$reviewer] |
                        .[$id].total += $score |
                        .[$id].count += 1
                    else
                        .[$id] = {scores: [$score], reviewers: [$reviewer], total: $score, count: 1}
                    end
                    ')
            fi
        done
    done

    # Calculate averages and de-anonymize
    local final_results='[]'

    for anon_id in $(echo "$aggregated" | jq -r 'keys[]' 2>/dev/null); do
        local data
        data=$(echo "$aggregated" | jq --arg id "$anon_id" '.[$id]')

        local total count avg_score
        total=$(echo "$data" | jq -r '.total // 0')
        count=$(echo "$data" | jq -r '.count // 1')
        avg_score=$((total / count))

        # De-anonymize
        local real_consultant
        real_consultant=$(echo "$mapping" | jq -r --arg id "$anon_id" '.[$id].consultant // "unknown"')

        final_results=$(echo "$final_results" | jq \
            --arg anon "$anon_id" \
            --arg real "$real_consultant" \
            --argjson avg "$avg_score" \
            --argjson count "$count" \
            --argjson data "$data" \
            '. + [{
                anonymous_id: $anon,
                consultant: $real,
                average_peer_score: $avg,
                review_count: $count,
                individual_scores: $data.scores
            }]')
    done

    # Sort by average score descending
    echo "$final_results" | jq 'sort_by(-.average_peer_score)' > "$output_file"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local responses_dir="${1:-}"
    local output_dir="${2:-}"

    # Validate inputs
    if [[ -z "$responses_dir" || ! -d "$responses_dir" ]]; then
        log_error "Usage: $0 <responses_dir> <output_dir>"
        exit 1
    fi

    # Count available responses
    local response_count=0
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" && "$(basename "$f")" != "voting.json" && "$(basename "$f")" != "synthesis.json" ]]; then
            ((response_count++))
        fi
    done

    if [[ $response_count -lt $MIN_CONSULTANTS_FOR_REVIEW ]]; then
        log_warn "Peer review requires at least $MIN_CONSULTANTS_FOR_REVIEW responses (found $response_count)"
        log_info "Skipping peer review"
        exit 0
    fi

    # Setup output directory
    output_dir="${output_dir:-$responses_dir/peer_review}"
    mkdir -p "$output_dir"

    log_info "Starting anonymous peer review..."
    log_info "Responses to review: $response_count"

    # Step 1: Create anonymized versions and mapping
    log_info "Step 1: Anonymizing responses..."

    local mapping_file="$output_dir/mapping.json"
    local anonymous_dir="$output_dir/anonymous"
    mkdir -p "$anonymous_dir"

    create_mapping "$responses_dir" "$mapping_file"

    local index=0
    local anonymous_content=""

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" && "$(basename "$f")" != "voting.json" && "$(basename "$f")" != "synthesis.json" ]]; then
            local consultant
            consultant=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            local anon_id
            anon_id=$(generate_anonymous_id "$consultant" "$index")

            # Create anonymized file
            anonymize_response "$f" "$anon_id" > "$anonymous_dir/${anon_id}.json"

            # Build combined anonymous content for review
            local summary approach
            summary=$(jq -r '.response.summary // "No summary"' "$f" 2>/dev/null)
            approach=$(jq -r '.response.approach // "Unknown"' "$f" 2>/dev/null)

            anonymous_content+="
### $anon_id
**Approach**: $approach
**Summary**: $summary
---
"
            ((index++))
        fi
    done

    # Save combined anonymous responses
    echo "$anonymous_content" > "$output_dir/anonymous_responses.md"
    log_success "Created $index anonymous responses"

    # Step 2: Run peer reviews (excluding self-review)
    log_info "Step 2: Running peer reviews..."

    local reviews_dir="$output_dir/reviews"
    mkdir -p "$reviews_dir"

    # Determine which consultants can do reviews
    local reviewers=()
    [[ "$ENABLE_GEMINI" == "true" ]] && command -v "$GEMINI_CMD" &>/dev/null && reviewers+=("Gemini")
    [[ "$ENABLE_CODEX" == "true" ]] && command -v "$CODEX_CMD" &>/dev/null && reviewers+=("Codex")
    [[ "$ENABLE_MISTRAL" == "true" ]] && command -v "$MISTRAL_CMD" &>/dev/null && reviewers+=("Mistral")
    [[ "$ENABLE_KILO" == "true" ]] && command -v "$KILO_CMD" &>/dev/null && reviewers+=("Kilo")
    [[ "$ENABLE_CURSOR" == "true" ]] && command -v "$CURSOR_CMD" &>/dev/null && reviewers+=("Cursor")

    if [[ ${#reviewers[@]} -lt 2 ]]; then
        log_warn "Need at least 2 reviewers for peer review"
        exit 0
    fi

    # Run reviews in parallel
    local pids=()
    for reviewer in "${reviewers[@]}"; do
        local review_output="$reviews_dir/review_${reviewer}.json"
        run_consultant_review "$reviewer" "$output_dir/anonymous_responses.md" "$review_output" &
        pids+=($!)
        log_debug "Started review by $reviewer (PID: ${pids[-1]})"
    done

    # Wait for all reviews
    local success_count=0
    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}" 2>/dev/null; then
            local reviewer="${reviewers[$i]}"
            local review_file="$reviews_dir/review_${reviewer}.json"

            if [[ -s "$review_file" ]]; then
                # Try to extract and validate JSON
                local extracted
                extracted=$(extract_json_from_response "$(cat "$review_file")")
                echo "$extracted" > "$review_file"

                if echo "$extracted" | jq -e '.reviews' > /dev/null 2>&1; then
                    log_success "  $reviewer: review completed"
                    ((success_count++))
                else
                    log_warn "  $reviewer: invalid review format"
                fi
            fi
        else
            log_warn "  ${reviewers[$i]}: review failed"
        fi
    done

    if [[ $success_count -lt 2 ]]; then
        log_error "Not enough successful reviews for aggregation"
        exit 1
    fi

    # Step 3: Aggregate scores
    log_info "Step 3: Aggregating peer scores..."

    local aggregated_file="$output_dir/aggregated_scores.json"
    aggregate_peer_scores "$reviews_dir" "$mapping_file" "$aggregated_file"

    log_success "Peer review complete"

    # Step 4: Generate summary report
    log_info "Step 4: Generating summary..."

    local summary_file="$output_dir/peer_review_summary.json"
    jq -n \
        --argjson scores "$(cat "$aggregated_file")" \
        --argjson mapping "$(cat "$mapping_file")" \
        --argjson review_count "$success_count" \
        --argjson response_count "$response_count" \
        '{
            peer_review: {
                total_responses: $response_count,
                total_reviews: $review_count,
                results: $scores,
                best_rated: ($scores | first),
                mapping: $mapping
            }
        }' > "$summary_file"

    # Print results
    if [[ -s "$aggregated_file" ]]; then
        echo ""
        log_info "Peer Review Results (ranked by peer score):"
        echo ""
        jq -r '.[] | "  \(.consultant): \(.average_peer_score)/10 (reviewed by \(.review_count) peers)"' "$aggregated_file"
        echo ""
    fi

    log_info "Output directory: $output_dir"
    echo "$output_dir"
}

main "$@"
