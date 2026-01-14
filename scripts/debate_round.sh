#!/bin/bash
# debate_round.sh - Multi-Agent Debate (MAD) implementation for AI Consultants v2.0
#
# Implements deliberation rounds where consultants can see and
# respond to each other's responses.
#
# Usage: ./debate_round.sh <responses_dir> <round_number> <output_dir>
#
# Round 1: Initial responses (handled by consult_all.sh)
# Round 2: Cross-critique - each consultant sees other responses
# Round 3: Final stance - final position after seeing critiques

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Parameters ---
RESPONSES_DIR="${1:-}"
ROUND_NUMBER="${2:-2}"
OUTPUT_DIR="${3:-}"

if [[ -z "$RESPONSES_DIR" || ! -d "$RESPONSES_DIR" ]]; then
    log_error "Usage: $0 <responses_dir> <round_number> [output_dir]"
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$RESPONSES_DIR/round_${ROUND_NUMBER}"
fi

mkdir -p "$OUTPUT_DIR"

log_info "=== Multi-Agent Debate - Round $ROUND_NUMBER ==="

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Extract summary from a response for the debate prompt
extract_summary() {
    local response_file="$1"
    local consultant=$(jq -r '.consultant // "Unknown"' "$response_file" 2>/dev/null)
    local summary=$(jq -r '.response.summary // .response.detailed[:500] // "No summary"' "$response_file" 2>/dev/null)
    local approach=$(jq -r '.response.approach // "unknown"' "$response_file" 2>/dev/null)
    local confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)

    echo "**$consultant** (Approach: $approach, Confidence: $confidence/10):
$summary"
}

# Build prompt for debate round
build_debate_prompt() {
    local consultant="$1"
    local my_response_file="$2"
    local responses_dir="$3"

    local my_response=$(cat "$my_response_file" 2>/dev/null)
    local other_summaries=""

    # Collect summaries from other consultants
    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" ]]; then
            local other_consultant=$(jq -r '.consultant // "Unknown"' "$f" 2>/dev/null)
            if [[ "$other_consultant" != "$consultant" ]]; then
                other_summaries+="
$(extract_summary "$f")
---
"
            fi
        fi
    done

    cat << EOF
# Round $ROUND_NUMBER - Cross-Critique

## Your Previous Response (Round $((ROUND_NUMBER - 1)))
$(echo "$my_response" | jq -r '.response.summary // "No summary"')

Approach: $(echo "$my_response" | jq -r '.response.approach // "unknown"')
Confidence: $(echo "$my_response" | jq -r '.confidence.score // 5')/10

## Other Consultants' Responses
$other_summaries

## Instructions

After seeing the opinions of other consultants, respond in JSON:

{
  "debate": {
    "round": $ROUND_NUMBER,
    "position_changed": <true if you changed your mind, false otherwise>,
    "original_stance": "<your original position>",
    "updated_stance": "<your new position or confirmation of previous>",
    "confidence_delta": <confidence change: -3 to +3>,
    "critiques": [
      {
        "target": "<consultant name>",
        "critique": "<your critique>",
        "severity": "<minor|moderate|major>"
      }
    ],
    "incorporated_from": [
      {
        "source": "<consultant name>",
        "idea": "<what you incorporated>"
      }
    ],
    "areas_of_agreement": ["<points you agree with others on>"],
    "areas_of_disagreement": ["<points you disagree on>"]
  },
  "response": {
    "summary": "<updated summary if position_changed, otherwise confirmation>",
    "detailed": "<updated details>",
    "approach": "<updated or confirmed approach>",
    "pros": ["<updated pros>"],
    "cons": ["<updated cons>"]
  },
  "confidence": {
    "score": <new score 1-10>,
    "reasoning": "<why this confidence level after debate>"
  }
}

IMPORTANT: Respond ONLY with valid JSON. Be honest - if others have valid points, acknowledge them.
EOF
}

# =============================================================================
# MAIN DEBATE EXECUTION
# =============================================================================

run_debate_round() {
    local consultants=("Gemini" "Codex" "Mistral" "Kilo")
    local pids=()
    local output_files=()

    log_info "Starting debate round $ROUND_NUMBER for ${#consultants[@]} consultants..."

    for consultant in "${consultants[@]}"; do
        local response_file="$RESPONSES_DIR/${consultant,,}.json"

        # Skip if no previous round response
        if [[ ! -f "$response_file" || ! -s "$response_file" ]]; then
            log_warn "$consultant: no previous response, skipping"
            continue
        fi

        local output_file="$OUTPUT_DIR/${consultant,,}.json"
        output_files+=("$output_file")

        # Build debate prompt
        local debate_prompt=$(build_debate_prompt "$consultant" "$response_file" "$RESPONSES_DIR")

        # Execute query in background
        (
            local start_time=$(date +%s%3N 2>/dev/null || date +%s000)

            case "$consultant" in
                Gemini)
                    if [[ "$ENABLE_GEMINI" == "true" ]]; then
                        echo "$debate_prompt" | "$SCRIPT_DIR/query_gemini.sh" "" "" "$output_file" > /dev/null 2>&1
                    fi
                    ;;
                Codex)
                    if [[ "$ENABLE_CODEX" == "true" ]]; then
                        "$SCRIPT_DIR/query_codex.sh" "$debate_prompt" "" "$output_file" > /dev/null 2>&1
                    fi
                    ;;
                Mistral)
                    if [[ "$ENABLE_MISTRAL" == "true" ]]; then
                        "$SCRIPT_DIR/query_mistral.sh" "$debate_prompt" "" "$output_file" > /dev/null 2>&1
                    fi
                    ;;
                Kilo)
                    if [[ "$ENABLE_KILO" == "true" ]]; then
                        "$SCRIPT_DIR/query_kilo.sh" "$debate_prompt" "" "$output_file" > /dev/null 2>&1
                    fi
                    ;;
            esac

            local end_time=$(date +%s%3N 2>/dev/null || date +%s000)
            local latency=$((end_time - start_time))

            # Add debate metadata to result
            if [[ -f "$output_file" && -s "$output_file" ]]; then
                local temp_file=$(mktemp)
                jq --argjson round "$ROUND_NUMBER" \
                   --argjson latency "$latency" \
                   '. + {debate_round: $round, debate_latency_ms: $latency}' \
                   "$output_file" > "$temp_file" && mv "$temp_file" "$output_file"
            fi
        ) &

        pids+=($!)
    done

    # Wait for all jobs
    local success_count=0
    for i in "${!pids[@]}"; do
        if wait "${pids[$i]}" 2>/dev/null; then
            ((success_count++))
        fi
    done

    log_success "Debate round $ROUND_NUMBER completed: $success_count/${#pids[@]} responses"

    # Generate round summary
    generate_round_summary
}

# Generate debate round summary
generate_round_summary() {
    local summary_file="$OUTPUT_DIR/round_summary.json"

    local position_changes=0
    local total_critiques=0
    local consultants_responded=0

    for f in "$OUTPUT_DIR"/*.json; do
        if [[ -f "$f" && "$f" != *"summary"* ]]; then
            ((consultants_responded++))

            local changed=$(jq -r '.debate.position_changed // false' "$f" 2>/dev/null)
            if [[ "$changed" == "true" ]]; then
                ((position_changes++))
            fi

            local critiques=$(jq -r '.debate.critiques | length // 0' "$f" 2>/dev/null)
            total_critiques=$((total_critiques + critiques))
        fi
    done

    jq -n \
        --argjson round "$ROUND_NUMBER" \
        --argjson responded "$consultants_responded" \
        --argjson changes "$position_changes" \
        --argjson critiques "$total_critiques" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            round: $round,
            timestamp: $timestamp,
            consultants_responded: $responded,
            position_changes: $changes,
            total_critiques: $critiques,
            stability: (if $changes == 0 then "stable" elif $changes <= 1 then "mostly_stable" else "volatile" end)
        }' > "$summary_file"

    log_info "Round summary saved: $summary_file"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

run_debate_round
echo "$OUTPUT_DIR"
