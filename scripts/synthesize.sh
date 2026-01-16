#!/bin/bash
# synthesize.sh - Auto-synthesis engine for AI Consultants v2.0
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
        if [[ -f "$f" ]]; then
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

# Use process substitution to handle filenames with spaces correctly
while IFS= read -r response_file; do
    if [[ -f "$response_file" && -s "$response_file" ]]; then
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

            COMBINED_RESPONSES+="
**$CONSULTANT** (conf:$CONFIDENCE/10, approach:$APPROACH)
Summary: $SUMMARY
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
    fi
done < <(find "$RESPONSES_DIR" -name "*.json" -type f 2>/dev/null | head -10)

NUM_CONSULTANTS=${#CONSULTANTS[@]}
log_info "Found $NUM_CONSULTANTS responses to synthesize"

# --- Get synthesis strategy ---
SYNTHESIS_STRATEGY="${SYNTHESIS_STRATEGY:-majority}"
log_info "Using synthesis strategy: $SYNTHESIS_STRATEGY"

# --- Strategy-specific instructions ---
get_strategy_instructions() {
    local strategy="$1"

    case "$strategy" in
        majority)
            echo "STRATEGY: MAJORITY - Weight equally, most common wins, focus on consensus" ;;
        risk_averse)
            echo "STRATEGY: RISK AVERSE - Prioritize safety, weight risk mentions higher, prefer established solutions, highlight risks" ;;
        security_first)
            echo "STRATEGY: SECURITY FIRST - Prioritize security, highlight vulnerabilities, reject insecure recommendations" ;;
        cost_capped)
            echo "STRATEGY: COST CAPPED - Prefer simpler solutions, minimize complexity, note cost implications" ;;
        compare_only)
            echo "STRATEGY: COMPARE ONLY - No recommendation, present objectively, set approach to 'user_decision_required'" ;;
        *)
            echo "STRATEGY: DEFAULT (MAJORITY) - Weight equally, most common wins" ;;
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
          \"Gemini\": \"<position or N/A>\",
          \"Codex\": \"<position or N/A>\",
          \"Mistral\": \"<position or N/A>\",
          \"Kilo\": \"<position or N/A>\"
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
      \"Gemini\": \"<value>\",
      \"Codex\": \"<value>\",
      \"Mistral\": \"<value>\",
      \"Kilo\": \"<value>\"
    },
    {
      \"aspect\": \"Complexity\",
      \"Gemini\": \"<value>\",
      \"Codex\": \"<value>\",
      \"Mistral\": \"<value>\",
      \"Kilo\": \"<value>\"
    },
    {
      \"aspect\": \"Scalability\",
      \"Gemini\": \"<value>\",
      \"Codex\": \"<value>\",
      \"Mistral\": \"<value>\",
      \"Kilo\": \"<value>\"
    },
    {
      \"aspect\": \"Risks\",
      \"Gemini\": \"<value>\",
      \"Codex\": \"<value>\",
      \"Mistral\": \"<value>\",
      \"Kilo\": \"<value>\"
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
- Include ALL consultants in comparison_table even if response was empty (use \"N/A\")
- Respond ONLY with valid JSON, no markdown or additional text
"

# --- Execute synthesis ---
log_info "Running synthesis with Claude..."

TEMP_OUTPUT=$(mktemp)

# Try first with claude CLI
if command -v claude &> /dev/null; then
    echo "$SYNTHESIS_PROMPT" | claude --print > "$TEMP_OUTPUT" 2>/dev/null
    exit_code=$?
else
    log_warn "Claude CLI not found, using local fallback"
    # Fallback: generate basic synthesis without LLM
    generate_fallback_synthesis "$RESPONSES_DIR" > "$TEMP_OUTPUT"
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
        fi
    fi

    log_success "Synthesis completed: $OUTPUT_FILE"
    rm -f "$TEMP_OUTPUT"
    cat "$OUTPUT_FILE"
else
    log_error "Synthesis failed"
    generate_fallback_synthesis "$RESPONSES_DIR" > "$OUTPUT_FILE"
    rm -f "$TEMP_OUTPUT"
    cat "$OUTPUT_FILE"
    exit 1
fi
