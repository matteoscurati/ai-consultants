#!/bin/bash
# synthesize.sh - Auto-synthesis engine for AI Consultants
#
# Analyzes responses from all consultants and generates an automatic synthesis
# with consensus score, weighted recommendation, and comparison table.
#
# Usage: ./synthesize.sh <responses_dir> <output_file>
#
# Requires: claude CLI for synthesis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# =============================================================================
# FALLBACK FUNCTION (defined before use)
# =============================================================================

generate_fallback_synthesis() {
    local responses_dir="$1"

    # Calculate basic statistics
    local total_confidence=0
    local count=0
    local consultants_json="[]"

    for f in "$responses_dir"/*.json; do
        if _is_successful_consultant_response_file "$f"; then
            local conf=$(jq -r '.confidence.score // 5' "$f" 2>/dev/null)
            local name=$(jq -r '.consultant // "unknown"' "$f" 2>/dev/null)
            total_confidence=$((total_confidence + conf))
            count=$((count + 1))
            consultants_json=$(echo "$consultants_json" | jq --arg n "$name" '. + [$n]')
        fi
    done

    local avg_confidence=5
    if [[ $count -gt 0 ]]; then
        avg_confidence=$((total_confidence / count))
    fi

    jq -n \
        --arg timestamp "$(date -Iseconds)" \
        --argjson count "$count" \
        --argjson avg_conf "$avg_confidence" \
        --argjson consultants "$consultants_json" \
        '{
            synthesis_version: "2.0-fallback",
            timestamp: $timestamp,
            consultants_analyzed: $count,
            consensus: {
                score: 50,
                level: "unknown",
                description: "Automatic synthesis not available - manual analysis required",
                agreed_points: [],
                disagreed_points: []
            },
            weighted_recommendation: {
                approach: "manual_review",
                summary: "Manual review of responses required",
                detailed: "Automatic synthesis was not possible. Please consult individual responses.",
                confidence_weighted_score: $avg_conf,
                supporting_consultants: $consultants,
                dissenting_consultants: [],
                incorporated_insights: []
            },
            comparison_table: [],
            risk_assessment: {
                overall_risk: "unknown",
                risks: []
            },
            action_items: [
                {
                    priority: 1,
                    action: "Manual review of responses",
                    rationale: "Automatic synthesis not available"
                }
            ],
            follow_up_questions: [],
            fallback: true
        }'
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

# --- Parameters ---
RESPONSES_DIR="${1:-}"
OUTPUT_FILE="${2:-/tmp/synthesis.json}"
ORIGINAL_QUESTION="${3:-}"

# --- Validation ---
if [[ -z "$RESPONSES_DIR" || ! -d "$RESPONSES_DIR" ]]; then
    log_error "Usage: $0 <responses_dir> <output_file> [original_question]"
    exit 1
fi

# --- Check for responses ---
RESPONSE_COUNT=$(find "$RESPONSES_DIR" -name "*.json" -type f 2>/dev/null | head -10 | wc -l)
if [[ "$RESPONSE_COUNT" -eq 0 ]]; then
    log_error "No JSON responses found in $RESPONSES_DIR"
    exit 1
fi

log_info "Starting automatic synthesis..."

# --- Collect all responses ---
COMBINED_RESPONSES=""
CONSULTANTS=()
CONFIDENCE_SCORES=()

# Use process substitution to handle filenames with spaces correctly.
# Cap at SYNTH_MAX *real* responses -- applied AFTER the metadata filter so
# pipeline metadata (voting/orchestration/stance_options...) can't steal a slot
# from a genuine consultant answer.
SYNTH_MAX="${SYNTH_MAX:-10}"
SYNTH_DETAIL_MAX_CHARS="${SYNTH_DETAIL_MAX_CHARS:-4000}"
if ! [[ "$SYNTH_DETAIL_MAX_CHARS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "SYNTH_DETAIL_MAX_CHARS must be a positive integer (got: $SYNTH_DETAIL_MAX_CHARS)"
    exit 1
fi
SYNTH_COLLECTED=0
while IFS= read -r response_file; do
    if _is_successful_consultant_response_file "$response_file"; then
        CONSULTANT=$(jq -r '.consultant // "unknown"' "$response_file" 2>/dev/null)
        CONFIDENCE=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)

        CONSULTANTS+=("$CONSULTANT")
        CONFIDENCE_SCORES+=("$CONFIDENCE")

        # Token optimization v2.1: Extract only essential fields instead of full JSON
        SYNTHESIS_EXTRACT_FIELDS="${SYNTHESIS_EXTRACT_FIELDS:-true}"
        if [[ "$SYNTHESIS_EXTRACT_FIELDS" == "true" ]]; then
            SUMMARY=$(jq -r '.response.summary // "N/A"' "$response_file" 2>/dev/null)
            APPROACH=$(jq -r '.response.approach // "N/A"' "$response_file" 2>/dev/null)
            PROS=$(jq -r '(.response.pros // []) | join("; ")' "$response_file" 2>/dev/null)
            CONS=$(jq -r '(.response.cons // []) | join("; ")' "$response_file" 2>/dev/null)
            CONF_REASONING=$(jq -r '.confidence.reasoning // "N/A"' "$response_file" 2>/dev/null)
            RESPONSE_QUALITY=$(jq -r '.metadata.response_quality // "unknown"' "$response_file" 2>/dev/null)
            DETAIL=$(jq -r '.response.detailed // ""' "$response_file" 2>/dev/null | cut -c1-"$SYNTH_DETAIL_MAX_CHARS")

            COMBINED_RESPONSES+="
**$CONSULTANT** (conf:$CONFIDENCE/10, approach:$APPROACH, quality:$RESPONSE_QUALITY)
Summary: $SUMMARY
Detail: $DETAIL
+: $PROS | -: $CONS
Reasoning: $CONF_REASONING
---
"
        else
            # Legacy mode: include full JSON
            COMBINED_RESPONSES+="
### $CONSULTANT (Confidence: $CONFIDENCE/10)
$(cat "$response_file")

---
"
        fi
        SYNTH_COLLECTED=$((SYNTH_COLLECTED + 1))
        [[ "$SYNTH_COLLECTED" -ge "$SYNTH_MAX" ]] && break
    fi
done < <(find "$RESPONSES_DIR" -name "*.json" -type f 2>/dev/null)

NUM_CONSULTANTS=${#CONSULTANTS[@]}
if [[ "$NUM_CONSULTANTS" -eq 0 ]]; then
    log_error "No successful consultant responses found in $RESPONSES_DIR"
    exit 1
fi
log_info "Found $NUM_CONSULTANTS responses to synthesize"

# --- Get synthesis strategy ---
# Default 'coverage': the panel's measured value is the UNION of distinct points across
# diverse models (it covers what one model misses), not a voted single recommendation.
SYNTHESIS_STRATEGY="${SYNTHESIS_STRATEGY:-coverage}"
log_info "Using synthesis strategy: $SYNTHESIS_STRATEGY"

# --- Strategy-specific instructions ---
get_strategy_instructions() {
    local strategy="$1"

    case "$strategy" in
        coverage|union)
            echo "STRATEGY: COVERAGE - Produce the COMPREHENSIVE UNION of every DISTINCT point, recommendation, risk, edge case, and consideration raised by ANY consultant. Deduplicate near-identical points but preserve every distinct one, and note which consultant(s) raised each. Do NOT collapse to a single 'winner' — the value is complete coverage of the solution/risk space, including points only one model raised. Enumerate the full distinct set in 'detailed'; 'summary' gives a coverage-oriented overview." ;;
        majority)
            echo "STRATEGY: MAJORITY - Synthesize a single blended recommendation, weighting all consultants equally." ;;
        risk_averse)
            echo "STRATEGY: RISK AVERSE - Prioritize safety, weight risk mentions higher, prefer established solutions, highlight risks" ;;
        security_first)
            echo "STRATEGY: SECURITY FIRST - Prioritize security, highlight vulnerabilities, reject insecure recommendations" ;;
        cost_capped)
            echo "STRATEGY: COST CAPPED - Prefer simpler solutions, minimize complexity, note cost implications" ;;
        compare_only)
            echo "STRATEGY: COMPARE ONLY - No recommendation, present objectively, set approach to 'user_decision_required'" ;;
        *)
            echo "STRATEGY: DEFAULT (COVERAGE) - Union of every distinct point across consultants" ;;
    esac
}

STRATEGY_INSTRUCTIONS=$(get_strategy_instructions "$SYNTHESIS_STRATEGY")

# --- Build synthesis prompt (token-optimized v2.2) ---
SYNTHESIS_PROMPT="You are an expert meta-analyst. Synthesize AI consultant responses.
Role context: Architect=scalability/design, Pragmatist=simplicity, Advocate=risks/edge-cases, Innovator=creativity.

## Synthesis Strategy
$STRATEGY_INSTRUCTIONS
"

if [[ -n "$ORIGINAL_QUESTION" ]]; then
    SYNTHESIS_PROMPT+="
## Original Question
$ORIGINAL_QUESTION

"
fi

SYNTHESIS_PROMPT+="
## Consultant Responses
$COMBINED_RESPONSES

## Instructions

Analyze carefully and produce ONLY valid JSON (no text before or after):

{
  \"synthesis_version\": \"2.2\",
  \"timestamp\": \"$(date -Iseconds)\",
  \"strategy\": \"$SYNTHESIS_STRATEGY\",
  \"consultants_analyzed\": $NUM_CONSULTANTS,
  \"consensus\": {
    \"score\": <0-100>,
    \"level\": \"<high|medium|low|none>\",
    \"description\": \"<description of consensus level>\",
    \"agreed_points\": [\"<points where >= 3 agree>\"],
    \"disagreed_points\": [
      {
        \"topic\": \"<topic>\",
        \"positions\": {
          \"<consultant_name>\": \"<position for each consultant that responded, or N/A if they did not address this topic>\"
        }
      }
    ]
  },
  \"weighted_recommendation\": {
    \"approach\": \"<recommended approach>\",
    \"summary\": \"<summary in 2-3 sentences>\",
    \"detailed\": \"<detailed explanation>\",
    \"confidence_weighted_score\": <1-10 weighted by confidence>,
    \"supporting_consultants\": [\"<who supports>\"],
    \"dissenting_consultants\": [\"<who dissents>\"],
    \"incorporated_insights\": [\"<insights from each consultant included>\"]
  },
  \"comparison_table\": [
    {
      \"aspect\": \"Approach\",
      \"<consultant_name>\": \"<value for each consultant that responded>\"
    },
    {
      \"aspect\": \"Complexity\",
      \"<consultant_name>\": \"<value for each consultant that responded>\"
    },
    {
      \"aspect\": \"Scalability\",
      \"<consultant_name>\": \"<value for each consultant that responded>\"
    },
    {
      \"aspect\": \"Risks\",
      \"<consultant_name>\": \"<value for each consultant that responded>\"
    }
  ],
  \"risk_assessment\": {
    \"overall_risk\": \"<low|medium|high>\",
    \"risks\": [
      {
        \"description\": \"<risk>\",
        \"severity\": \"<low|medium|high>\",
        \"mitigation\": \"<how to mitigate>\",
        \"identified_by\": [\"<who identified it>\"]
      }
    ]
  },
  \"action_items\": [
    {
      \"priority\": 1,
      \"action\": \"<what to do>\",
      \"rationale\": \"<why>\"
    }
  ],
  \"follow_up_questions\": [\"<questions for further clarification>\"],
  \"debate_evolution\": {
    \"initial_positions\": {},
    \"shifts\": [],
    \"final_stance\": \"<final stance of the panel>\"
  }
}

RULES:
- consensus.score: 100% = all agree, 75-99% = 3+ agree, 50-74% = 2v2, 25-49% = strong disagreement, 0-24% = no convergence
- confidence_weighted_score = weighted average by confidence of consultants supporting the approach
- Include ALL consultants that responded in comparison_table (use consultant name as key, \"N/A\" if no data)
- For disagreed_points, include all consultants that took a position on that topic
- Respond ONLY with valid JSON, no markdown or additional text
"

# --- Execute synthesis ---
TEMP_OUTPUT=$(mktemp)
SYNTHESIS_PAYLOAD_FILE="${TEMP_OUTPUT}.payload"

# Try the configured/selected synthesizer first, then the remaining ready
# families. A timeout or provider failure is unavailability, not a reason to
# discard nine valid consultant responses into a local placeholder.
synthesis_started_at=$(date +%s)
SELECTED_SYNTH_CLI=$(resolve_synthesis_cli 2>/dev/null || echo "")
SYNTH_CANDIDATES=()
SYNTH_CANDIDATE_NAMES=" "
if [[ -n "$SELECTED_SYNTH_CLI" ]]; then
    SYNTH_CANDIDATES+=("$SELECTED_SYNTH_CLI")
    SYNTH_CANDIDATE_NAMES+="$SELECTED_SYNTH_CLI "
fi
for candidate in gemini codex claude; do
    if [[ "$SYNTH_CANDIDATE_NAMES" != *" $candidate "* ]]; then
        SYNTH_CANDIDATES+=("$candidate")
        SYNTH_CANDIDATE_NAMES+="$candidate "
    fi
done

SYNTH_CLI=""
exit_code=1
avoid_synth=$(_consultant_to_cli "$(get_self_consultant_name)")
if ! [[ "${SYNTHESIS_TIMEOUT:-240}" =~ ^[1-9][0-9]*$ \
    && "${SYNTHESIS_TOTAL_TIMEOUT:-480}" =~ ^[1-9][0-9]*$ ]]; then
    log_error "SYNTHESIS_TIMEOUT and SYNTHESIS_TOTAL_TIMEOUT must be positive integers"
    exit 1
fi
for candidate in "${SYNTH_CANDIDATES[@]}"; do
    [[ "$candidate" == "$avoid_synth" ]] && continue
    if [[ "$candidate" != "$SELECTED_SYNTH_CLI" ]] && ! _synthesis_cli_ready "$candidate"; then
        continue
    fi

    : > "$TEMP_OUTPUT"
    rm -f "$SYNTHESIS_PAYLOAD_FILE"
    log_info "Running synthesis with $candidate..."
    if ! build_synthesis_args "$candidate" "$SYNTHESIS_PROMPT" "$SYNTHESIS_PAYLOAD_FILE"; then
        log_warn "Could not build synthesis invocation for $candidate"
        continue
    fi
    elapsed=$(( $(date +%s) - synthesis_started_at ))
    remaining=$(( SYNTHESIS_TOTAL_TIMEOUT - elapsed ))
    (( remaining > 0 )) || break
    provider_timeout="$SYNTHESIS_TIMEOUT"
    (( provider_timeout <= remaining )) || provider_timeout="$remaining"
    if printf '%s' "$SYNTHESIS_PROMPT" | run_with_timeout "$provider_timeout" \
            "${SYNTHESIS_ARGS[@]}" > "$TEMP_OUTPUT" 2>/dev/null; then
        exit_code=0
    else
        exit_code=$?
    fi
    if [[ "$candidate" == "codex" && $exit_code -eq 0 ]]; then
        if [[ -s "$SYNTHESIS_PAYLOAD_FILE" ]]; then
            cp "$SYNTHESIS_PAYLOAD_FILE" "$TEMP_OUTPUT"
        else
            exit_code=1
        fi
    fi
    if [[ $exit_code -eq 0 && -s "$TEMP_OUTPUT" ]]; then
        SYNTH_CLI="$candidate"
        break
    fi
    log_warn "Synthesis with $candidate failed (exit $exit_code); trying the next ready provider"
done

if [[ -z "$SYNTH_CLI" ]]; then
    log_warn "No synthesis CLI completed successfully, using local fallback"
    generate_fallback_synthesis "$RESPONSES_DIR" > "$TEMP_OUTPUT"
    SYNTH_CLI="local-fallback"
    exit_code=0
fi

# --- Post-processing ---
if [[ $exit_code -eq 0 && -f "$TEMP_OUTPUT" && -s "$TEMP_OUTPUT" ]]; then
    # Extract only JSON from response (remove any text before/after)
    RAW_OUTPUT=$(cat "$TEMP_OUTPUT")

    # Try to extract JSON
    if echo "$RAW_OUTPUT" | jq -e '.' > /dev/null 2>&1; then
        # It's already valid JSON
        cat "$TEMP_OUTPUT" > "$OUTPUT_FILE"
    else
        # Try to extract JSON from text using sed (portable across macOS/Linux)
        # This extracts from the first { to the last }
        JSON_EXTRACTED=$(echo "$RAW_OUTPUT" | sed -n '/{/,/}/p' | tr '\n' ' ' || echo "")
        if [[ -n "$JSON_EXTRACTED" ]] && echo "$JSON_EXTRACTED" | jq -e '.' > /dev/null 2>&1; then
            echo "$JSON_EXTRACTED" | jq '.' > "$OUTPUT_FILE"
        else
            # Fallback: create minimal structure
            generate_fallback_synthesis "$RESPONSES_DIR" > "$OUTPUT_FILE"
            SYNTH_CLI="local-fallback"
        fi
    fi

    annotated_output=$(mktemp)
    if jq --arg provider "$SYNTH_CLI" '.synthesis_provider = $provider' \
            "$OUTPUT_FILE" > "$annotated_output"; then
        mv "$annotated_output" "$OUTPUT_FILE"
    else
        rm -f "$annotated_output"
    fi

    log_success "Synthesis completed: $OUTPUT_FILE"
    rm -f "$TEMP_OUTPUT" "$SYNTHESIS_PAYLOAD_FILE"
    cat "$OUTPUT_FILE"
else
    log_error "Synthesis failed"
    generate_fallback_synthesis "$RESPONSES_DIR" > "$OUTPUT_FILE"
    rm -f "$TEMP_OUTPUT" "$SYNTHESIS_PAYLOAD_FILE"
    cat "$OUTPUT_FILE"
    exit 1
fi
