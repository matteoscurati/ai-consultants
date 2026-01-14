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

# Generate critique of a response
# Usage: generate_critique <consultant> <response_content>
# Output: JSON with the critique
generate_critique() {
    local consultant="$1"
    local response="$2"

    local prompt="${CRITIQUE_PROMPT_TEMPLATE//%RESPONSE%/$response}"

    # Use the same consultant for the critique (self-reflection)
    case "$consultant" in
        Gemini)
            echo "$prompt" | "$GEMINI_CMD" -p - -m "$GEMINI_MODEL" 2>/dev/null
            ;;
        Codex)
            "$CODEX_CMD" exec --skip-git-repo-check "$prompt" 2>/dev/null
            ;;
        Mistral)
            "$MISTRAL_CMD" --prompt "$prompt" --auto-approve 2>/dev/null
            ;;
        Kilo)
            "$KILO_CMD" --auto --json "$prompt" 2>/dev/null
            ;;
        *)
            echo '{"critique": {"error": "Unknown consultant"}, "needs_refinement": false}'
            ;;
    esac
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

    case "$consultant" in
        Gemini)
            echo "$prompt" | "$GEMINI_CMD" -p - -m "$GEMINI_MODEL" 2>/dev/null
            ;;
        Codex)
            "$CODEX_CMD" exec --skip-git-repo-check "$prompt" 2>/dev/null
            ;;
        Mistral)
            "$MISTRAL_CMD" --prompt "$prompt" --auto-approve 2>/dev/null
            ;;
        Kilo)
            "$KILO_CMD" --auto --json "$prompt" 2>/dev/null
            ;;
    esac
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
            --argjson history "$(printf '%s\n' "${reflection_history[@]}" | jq -s '.')" \
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
