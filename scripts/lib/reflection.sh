#!/bin/bash
# reflection.sh - Self-reflection (Reflexion pattern) for AI Consultants v2.0
#
# Implements the generate-critique-refine pattern to improve
# response quality through self-criticism.

# =============================================================================
# REFLECTION PROMPTS
# =============================================================================

# Prompt for self-critique
CRITIQUE_PROMPT_TEMPLATE='You provided this response to a programming question:

---
%RESPONSE%
---

Now critique your response. Consider:
1. **Correctness**: Are there logical or technical errors?
2. **Completeness**: Is anything important missing?
3. **Clarity**: Is it well explained?
4. **Edge cases**: Have you considered all edge cases?
5. **Alternatives**: Are there better approaches not mentioned?
6. **Risks**: Are there hidden potential problems?

Respond in JSON:
{
  "critique": {
    "strengths": ["<strengths of the response>"],
    "weaknesses": ["<weak points>"],
    "missing_aspects": ["<what is missing>"],
    "errors_found": ["<identified errors>"],
    "improvement_suggestions": ["<how to improve>"]
  },
  "overall_quality": <1-10>,
  "needs_refinement": <true if significant improvement is needed>
}'

# Prompt for refinement
REFINE_PROMPT_TEMPLATE='Your original response was:

---
%ORIGINAL%
---

Your self-critique identified:

---
%CRITIQUE%
---

Now produce an IMPROVED response that:
1. Corrects the identified errors
2. Adds the missing aspects
3. Strengthens the weak points
4. Maintains the strengths

Respond with the same JSON schema as the original response, but improved.'

# =============================================================================
# REFLECTION FUNCTIONS
# =============================================================================

# Helper: Execute prompt with a specific consultant
# Usage: _exec_consultant <consultant> <prompt>
_exec_consultant() {
    local consultant="$1"
    local prompt="$2"

    case "$consultant" in
        Gemini)  echo "$prompt" | "$GEMINI_CMD" -p - -m "$GEMINI_MODEL" 2>/dev/null ;;
        Codex)   "$CODEX_CMD" exec --skip-git-repo-check "$prompt" 2>/dev/null ;;
        Mistral) "$MISTRAL_CMD" --prompt "$prompt" --auto-approve 2>/dev/null ;;
        Kilo)    "$KILO_CMD" --auto --json "$prompt" 2>/dev/null ;;
        *)       return 1 ;;
    esac
}

# Generate critique of a response
# Usage: generate_critique <consultant> <response_content>
# Output: JSON with the critique
generate_critique() {
    local consultant="$1"
    local response="$2"
    local prompt="${CRITIQUE_PROMPT_TEMPLATE//%RESPONSE%/$response}"

    _exec_consultant "$consultant" "$prompt" || \
        echo '{"critique": {"error": "Unknown consultant"}, "needs_refinement": false}'
}

# Refine a response based on critique
# Usage: refine_response <consultant> <original_response> <critique>
# Output: refined response
refine_response() {
    local consultant="$1"
    local original="$2"
    local critique="$3"

    local prompt="${REFINE_PROMPT_TEMPLATE//%ORIGINAL%/$original}"
    prompt="${prompt//%CRITIQUE%/$critique}"

    _exec_consultant "$consultant" "$prompt"
}

# Execute complete reflection cycle
# Usage: run_reflection_cycle <consultant> <query> <output_file> [cycles]
run_reflection_cycle() {
    local consultant="$1"
    local query="$2"
    local output_file="$3"
    local cycles="${4:-1}"

    local current_response=""
    local reflection_history=()

    # Step 1: Get initial response (already done externally)
    if [[ -f "$output_file" && -s "$output_file" ]]; then
        current_response=$(cat "$output_file")
    else
        log_warn "No initial response found for reflection"
        return 1
    fi

    # Reflection cycles
    for ((cycle=1; cycle<=cycles; cycle++)); do
        log_debug "[$consultant] Reflection cycle $cycle/$cycles"

        # Step 2: Self-critique
        local critique=$(generate_critique "$consultant" "$current_response")

        # Check if refinement is needed
        local needs_refinement=$(echo "$critique" | jq -r '.needs_refinement // false' 2>/dev/null)

        if [[ "$needs_refinement" == "false" && $cycle -gt 1 ]]; then
            log_debug "[$consultant] No refinement needed, stopping at cycle $cycle"
            break
        fi

        # Save to history
        reflection_history+=("$critique")

        # Step 3: Refine
        local refined=$(refine_response "$consultant" "$current_response" "$critique")

        if [[ -n "$refined" ]]; then
            current_response="$refined"
        else
            log_warn "[$consultant] Refinement failed, keeping previous response"
            break
        fi
    done

    # Add reflection metadata to final result
    if echo "$current_response" | jq -e '.' > /dev/null 2>&1; then
        echo "$current_response" | jq \
            --argjson cycles "$cycles" \
            --argjson history "$(printf '%s\n' ${reflection_history[@]+"${reflection_history[@]}"} | jq -s '.')" \
            '. + {reflection: {cycles_completed: $cycles, history: $history}}' \
            > "$output_file"
    else
        echo "$current_response" > "$output_file"
    fi
}

# =============================================================================
# QUALITY ASSESSMENT
# =============================================================================

# Evaluate if a response would benefit from reflection
# Usage: should_reflect <response_json>
# Returns: 0 if yes, 1 if no
should_reflect() {
    local response="$1"

    # Check confidence score
    local confidence=$(echo "$response" | jq -r '.confidence.score // 5' 2>/dev/null)

    # If confidence is low, reflect
    if [[ $confidence -lt 6 ]]; then
        return 0
    fi

    # Check if there are many caveats
    local caveats_count=$(echo "$response" | jq -r '.response.caveats | length // 0' 2>/dev/null)
    if [[ $caveats_count -gt 3 ]]; then
        return 0
    fi

    # Check uncertainty factors
    local uncertainty_count=$(echo "$response" | jq -r '.confidence.uncertainty_factors | length // 0' 2>/dev/null)
    if [[ $uncertainty_count -gt 2 ]]; then
        return 0
    fi

    return 1
}

# Calculate quality score of a response
# Usage: calculate_quality_score <response_json>
calculate_quality_score() {
    local response="$1"

    local confidence=$(echo "$response" | jq -r '.confidence.score // 5' 2>/dev/null)
    local has_code=$(echo "$response" | jq -r '.response.code_snippets | length > 0' 2>/dev/null)
    local has_pros=$(echo "$response" | jq -r '.response.pros | length > 0' 2>/dev/null)
    local has_cons=$(echo "$response" | jq -r '.response.cons | length > 0' 2>/dev/null)

    local score=$confidence

    # Bonus for completeness
    [[ "$has_code" == "true" ]] && score=$((score + 1))
    [[ "$has_pros" == "true" ]] && score=$((score + 1))
    [[ "$has_cons" == "true" ]] && score=$((score + 1))

    # Cap at 10
    if [[ $score -gt 10 ]]; then
        score=10
    fi

    echo $score
}

# =============================================================================
# JUDGE STEP - OVERCONFIDENCE DETECTION (v2.2)
# =============================================================================

# Prompt template for the judge evaluation
JUDGE_PROMPT_TEMPLATE='You are an expert meta-evaluator. Your job is to detect OVERCONFIDENCE in AI responses.

Analyze this response for overconfidence signals:

---
CONSULTANT: %CONSULTANT%
CONFIDENCE SCORE: %CONFIDENCE%/10

SUMMARY:
%SUMMARY%

DETAILED RESPONSE:
%DETAILED%

REASONING FOR CONFIDENCE:
%REASONING%
---

Evaluate for overconfidence by checking:

1. **Hedging vs Certainty Mismatch**: Does the text use hedging language ("might", "could", "possibly") but claim high confidence?
2. **Evidence Quality**: Is the confidence score justified by the evidence/reasoning provided?
3. **Complexity Acknowledgment**: Does a high confidence score acknowledge the complexity of the problem?
4. **Edge Cases**: Are edge cases mentioned? High confidence without edge case consideration is suspicious.
5. **Alternative Awareness**: Does the response acknowledge alternative approaches exist?

Respond ONLY with valid JSON:
{
  "consultant": "%CONSULTANT%",
  "original_confidence": %CONFIDENCE%,
  "overconfidence_detected": <true/false>,
  "adjusted_confidence": <1-10>,
  "analysis": {
    "hedging_language_count": <number of hedging phrases found>,
    "certainty_claims_count": <number of certainty claims>,
    "evidence_quality": "<weak|moderate|strong>",
    "complexity_acknowledged": <true/false>,
    "edge_cases_mentioned": <true/false>,
    "alternatives_acknowledged": <true/false>
  },
  "red_flags": ["<specific overconfidence indicators found>"],
  "recommendation": "<keep|adjust_down|flag_for_review>"
}'

# Run judge evaluation on a single response
# Usage: judge_response <response_file>
# Output: JSON with judge evaluation
judge_response() {
    local response_file="$1"

    if [[ ! -f "$response_file" || ! -s "$response_file" ]]; then
        echo '{"error": "Invalid response file"}'
        return 1
    fi

    local consultant confidence summary detailed reasoning
    consultant=$(jq -r '.consultant // "unknown"' "$response_file" 2>/dev/null)
    confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
    summary=$(jq -r '.response.summary // "No summary"' "$response_file" 2>/dev/null)
    detailed=$(jq -r '.response.detailed // "No details"' "$response_file" 2>/dev/null | head -c 2000)
    reasoning=$(jq -r '.confidence.reasoning // "No reasoning provided"' "$response_file" 2>/dev/null)

    local prompt="${JUDGE_PROMPT_TEMPLATE}"
    prompt="${prompt//%CONSULTANT%/$consultant}"
    prompt="${prompt//%CONFIDENCE%/$confidence}"
    prompt="${prompt//%SUMMARY%/$summary}"
    prompt="${prompt//%DETAILED%/$detailed}"
    prompt="${prompt//%REASONING%/$reasoning}"

    # Use Claude for judging (most reliable for meta-analysis)
    if command -v claude &> /dev/null; then
        echo "$prompt" | claude --print 2>/dev/null
    else
        # Fallback: heuristic-based detection
        heuristic_overconfidence_check "$response_file"
    fi
}

# Heuristic-based overconfidence detection (no LLM required)
# Usage: heuristic_overconfidence_check <response_file>
heuristic_overconfidence_check() {
    local response_file="$1"

    local consultant confidence text
    consultant=$(jq -r '.consultant // "unknown"' "$response_file" 2>/dev/null)
    confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
    text=$(jq -r '(.response.summary // "") + " " + (.response.detailed // "") + " " + (.confidence.reasoning // "")' "$response_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    # Count hedging language
    local hedging_words="might|could|possibly|perhaps|maybe|likely|probably|seems|appears|suggest"
    local hedging_count
    hedging_count=$(echo "$text" | grep -oiE "$hedging_words" | wc -l | tr -d ' ')

    # Count certainty language
    local certainty_words="definitely|certainly|absolutely|always|never|must|clearly|obviously|undoubtedly"
    local certainty_count
    certainty_count=$(echo "$text" | grep -oiE "$certainty_words" | wc -l | tr -d ' ')

    # Check for edge cases mention
    local edge_case_mentioned=false
    echo "$text" | grep -qiE "edge case|corner case|exception|special case" && edge_case_mentioned=true

    # Check for alternatives mention
    local alternatives_mentioned=false
    echo "$text" | grep -qiE "alternative|another approach|other option|could also|alternatively" && alternatives_mentioned=true

    # Calculate overconfidence indicators
    local red_flags=()
    local overconfidence=false
    local adjusted=$confidence

    # High confidence + lots of hedging = suspicious
    if [[ $confidence -ge 8 && $hedging_count -ge 3 ]]; then
        red_flags+=("High confidence with excessive hedging language")
        overconfidence=true
        adjusted=$((confidence - 2))
    fi

    # High confidence + no edge cases = suspicious
    if [[ $confidence -ge 8 && "$edge_case_mentioned" == "false" ]]; then
        red_flags+=("High confidence without edge case consideration")
        overconfidence=true
        adjusted=$((adjusted - 1))
    fi

    # Very high confidence is almost always overconfident
    if [[ $confidence -ge 9 ]]; then
        red_flags+=("Extremely high confidence (9-10) is rarely justified")
        overconfidence=true
        adjusted=$((adjusted - 1))
    fi

    # Clamp adjusted confidence
    [[ $adjusted -lt 1 ]] && adjusted=1
    [[ $adjusted -gt 10 ]] && adjusted=10

    local recommendation="keep"
    if [[ "$overconfidence" == "true" ]]; then
        if [[ $((confidence - adjusted)) -ge 2 ]]; then
            recommendation="adjust_down"
        else
            recommendation="flag_for_review"
        fi
    fi

    jq -n \
        --arg consultant "$consultant" \
        --argjson original "$confidence" \
        --argjson overconfidence "$overconfidence" \
        --argjson adjusted "$adjusted" \
        --argjson hedging "$hedging_count" \
        --argjson certainty "$certainty_count" \
        --argjson edge_cases "$edge_case_mentioned" \
        --argjson alternatives "$alternatives_mentioned" \
        --arg red_flags "$(IFS='|'; echo "${red_flags[*]:-}")" \
        --arg recommendation "$recommendation" \
        '{
            consultant: $consultant,
            original_confidence: $original,
            overconfidence_detected: $overconfidence,
            adjusted_confidence: $adjusted,
            analysis: {
                hedging_language_count: $hedging,
                certainty_claims_count: $certainty,
                evidence_quality: (if $hedging > $certainty then "weak" elif $hedging == $certainty then "moderate" else "strong" end),
                complexity_acknowledged: ($hedging > 0),
                edge_cases_mentioned: $edge_cases,
                alternatives_acknowledged: $alternatives
            },
            red_flags: ($red_flags | split("|") | map(select(. != ""))),
            recommendation: $recommendation
        }'
}

# Run judge evaluation on all responses in a directory
# Usage: judge_all_responses <responses_dir> <output_file>
judge_all_responses() {
    local responses_dir="$1"
    local output_file="$2"

    local results='[]'
    local overconfidence_count=0
    local total_count=0

    for f in "$responses_dir"/*.json; do
        if [[ -f "$f" && -s "$f" && "$(basename "$f")" != "voting.json" && "$(basename "$f")" != "synthesis.json" && "$(basename "$f")" != "judge_report.json" ]]; then
            local evaluation
            evaluation=$(judge_response "$f")

            if echo "$evaluation" | jq -e '.' > /dev/null 2>&1; then
                results=$(echo "$results" | jq --argjson eval "$evaluation" '. + [$eval]')

                local is_overconfident
                is_overconfident=$(echo "$evaluation" | jq -r '.overconfidence_detected // false')
                [[ "$is_overconfident" == "true" ]] && ((overconfidence_count++))
                ((total_count++))
            fi
        fi
    done

    # Generate summary
    jq -n \
        --argjson evaluations "$results" \
        --argjson overconfident "$overconfidence_count" \
        --argjson total "$total_count" \
        '{
            judge_report: {
                timestamp: (now | todate),
                total_evaluated: $total,
                overconfidence_detected: $overconfident,
                evaluations: $evaluations,
                summary: {
                    reliability: (if $overconfident == 0 then "high" elif ($overconfident / $total) < 0.3 then "medium" else "low" end),
                    action_required: ($overconfident > 0)
                }
            }
        }' > "$output_file"

    cat "$output_file"
}
