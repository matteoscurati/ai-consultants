#!/bin/bash
# consult_all.sh - AI Consultants v2.0 - Main Orchestrator
#
# Complete workflow for multi-model AI consultation with:
# - Specialized personas for each consultant
# - Confidence scoring and weighted voting
# - Auto-synthesis of responses
# - Optional Multi-Agent Debate (MAD)
# - Smart routing based on question category
# - Session management for follow-up
# - Cost tracking
#
# Usage: ./consult_all.sh "Your question" [file1] [file2] ...
#
# Options (via environment variables):
#   ENABLE_SYNTHESIS=true    Enable automatic synthesis
#   ENABLE_DEBATE=true       Enable multi-round debate
#   DEBATE_ROUNDS=2          Number of debate rounds
#   ENABLE_SMART_ROUTING=true Select consultants based on question

set -euo pipefail

# --- Initial Setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/voting.sh"
source "$SCRIPT_DIR/lib/routing.sh"

# --- Custom API Agent Discovery ---
# Discovers custom API agents from environment variables
# Convention: ENABLE_AGENTNAME=true with AGENTNAME_API_URL set
_discover_custom_api_agents() {
    while IFS='=' read -r var value; do
        [[ "$var" != ENABLE_* ]] && continue
        [[ "$value" != "true" ]] && continue

        local agent_upper="${var#ENABLE_}"

        # Skip known agents (uses helper from common.sh)
        is_known_agent "$agent_upper" && continue

        # Check if it has an API URL configured (indicates it's an API agent)
        local url_var="${agent_upper}_API_URL"
        [[ -z "${!url_var:-}" ]] && continue

        # Add custom API agent with proper case
        local agent_name
        agent_name=$(to_title "$agent_upper")
        SELECTED_CONSULTANTS+=("$agent_name")
        log_debug "Discovered custom API agent: $agent_name"
    done < <(env)
}

# --- Input Validation ---
if [[ $# -eq 0 ]]; then
    log_error "Usage: $0 \"Your question\" [file1] [file2] ..."
    log_info "Example: $0 \"How to optimize this function?\" src/utils.py"
    exit 1
fi

QUERY="$1"
shift

# FILES array handling (compatible with set -u)
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    FILES=()
fi

if [[ -z "$QUERY" ]]; then
    log_error "The question cannot be empty"
    exit 1
fi

# --- Header ---
echo "" >&2
echo "╔══════════════════════════════════════════════════════════════╗" >&2
echo "║         AI Consultants v${AI_CONSULTANTS_VERSION} - Expert Panel                 ║" >&2
echo "╚══════════════════════════════════════════════════════════════╝" >&2
echo "" >&2

# --- Pre-flight Check (optional) ---
if [[ "$ENABLE_PREFLIGHT" == "true" ]]; then
    log_info "Running pre-flight check..."
    preflight_args=()
    [[ "$PREFLIGHT_QUICK" == "true" ]] && preflight_args+=("--quick")
    if ! "$SCRIPT_DIR/preflight_check.sh" ${preflight_args[@]+"${preflight_args[@]}"} > /dev/null 2>&1; then
        log_error "Pre-flight check failed. Run ./preflight_check.sh for details."
        exit 1
    fi
    log_success "Pre-flight check passed"
    echo "" >&2
fi

# --- Question Classification ---
QUESTION_CATEGORY="GENERAL"
if [[ "$ENABLE_CLASSIFICATION" == "true" ]]; then
    log_info "Classifying question..."
    QUESTION_CATEGORY=$("$SCRIPT_DIR/classify_question.sh" "$QUERY" 2>/dev/null || echo "GENERAL")
    log_info "Category: $QUESTION_CATEGORY"
fi

# --- Create Output Directory (with secure permissions) ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR_BASE}/${TIMESTAMP}"
# Create base directory with restricted permissions (owner only)
mkdir -p "$DEFAULT_OUTPUT_DIR_BASE"
chmod 700 "$DEFAULT_OUTPUT_DIR_BASE"
# Create session-specific directory
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

log_info "Output: $OUTPUT_DIR"
log_info "Question: ${QUERY:0:80}$([ ${#QUERY} -gt 80 ] && echo '...')"
if [[ ${#FILES[@]} -gt 0 ]]; then
    log_info "Files: ${FILES[*]}"
fi
echo "" >&2

# --- Automatic Context Creation ---
log_info "Building automatic context..."
CONTEXT_FILE="$OUTPUT_DIR/context.md"
if [[ ${#FILES[@]} -gt 0 ]]; then
    "$SCRIPT_DIR/build_context.sh" "$CONTEXT_FILE" "$QUERY" "${FILES[@]}" > /dev/null
else
    "$SCRIPT_DIR/build_context.sh" "$CONTEXT_FILE" "$QUERY" > /dev/null
fi
log_success "Context created: $CONTEXT_FILE ($(wc -l < "$CONTEXT_FILE" | tr -d ' ') lines)"

# --- Cost Estimation (optional) ---
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    CONTEXT_SIZE=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')
    ESTIMATED_COST=$(estimate_consultation_cost 4 "$CONTEXT_SIZE")
    log_info "Estimated cost: $(format_cost "$ESTIMATED_COST")"
fi
echo "" >&2

# --- Consultant Selection ---
declare -a SELECTED_CONSULTANTS=()

if [[ "$ENABLE_SMART_ROUTING" == "true" ]]; then
    log_info "Smart routing for category $QUESTION_CATEGORY..."
    while IFS= read -r c; do
        [[ -n "$c" ]] && SELECTED_CONSULTANTS+=("$c")
    done < <(select_consultants "$QUESTION_CATEGORY" "$MIN_AFFINITY")
    log_info "Selected consultants: ${SELECTED_CONSULTANTS[*]}"
else
    # All enabled consultants
    # CLI-based consultants
    [[ "$ENABLE_GEMINI" == "true" ]] && SELECTED_CONSULTANTS+=("Gemini")
    [[ "$ENABLE_CODEX" == "true" ]] && SELECTED_CONSULTANTS+=("Codex")
    [[ "$ENABLE_MISTRAL" == "true" ]] && SELECTED_CONSULTANTS+=("Mistral")
    [[ "$ENABLE_KILO" == "true" ]] && SELECTED_CONSULTANTS+=("Kilo")
    [[ "$ENABLE_CURSOR" == "true" ]] && SELECTED_CONSULTANTS+=("Cursor")
    [[ "$ENABLE_AIDER" == "true" ]] && SELECTED_CONSULTANTS+=("Aider")
    # API-based consultants (predefined)
    [[ "$ENABLE_QWEN3" == "true" ]] && SELECTED_CONSULTANTS+=("Qwen3")
    [[ "$ENABLE_GLM" == "true" ]] && SELECTED_CONSULTANTS+=("GLM")
    [[ "$ENABLE_GROK" == "true" ]] && SELECTED_CONSULTANTS+=("Grok")
    [[ "$ENABLE_DEEPSEEK" == "true" ]] && SELECTED_CONSULTANTS+=("DeepSeek")

    # Discover custom API agents from environment
    # Convention: ENABLE_AGENTNAME=true with AGENTNAME_API_URL set
    _discover_custom_api_agents
fi

if [[ ${#SELECTED_CONSULTANTS[@]} -eq 0 ]]; then
    log_error "No consultant enabled or selected"
    exit 1
fi

# Minimum 2 consultants required for meaningful comparison
if [[ ${#SELECTED_CONSULTANTS[@]} -lt 2 ]]; then
    log_error "At least 2 consultants required for meaningful comparison."
    log_error "Currently enabled: ${#SELECTED_CONSULTANTS[@]} (${SELECTED_CONSULTANTS[*]})"
    echo "" >&2
    log_info "Run ./scripts/setup_wizard.sh to configure additional consultants"
    log_info "Or manually enable more:"
    log_info "  ENABLE_GEMINI=true ENABLE_CODEX=true ./scripts/consult_all.sh \"query\""
    exit 1
fi

# --- Round 1: Parallel Consultation ---
log_info "Starting parallel consultation (Round 1)..."
echo "" >&2

declare -a PIDS=()
declare -a NAMES=()
declare -a OUTPUT_FILES=()

# Initialize progress for each consultant
for c in "${SELECTED_CONSULTANTS[@]}"; do
    init_progress "$c"
done

# Launch consultants in parallel
for consultant in "${SELECTED_CONSULTANTS[@]}"; do
    local_output_file="$OUTPUT_DIR/${consultant,,}.json"
    OUTPUT_FILES+=("$local_output_file")
    NAMES+=("$consultant")

    # Convention: query script is query_<lowercase_name>.sh
    local query_script="$SCRIPT_DIR/query_${consultant,,}.sh"

    if [[ -x "$query_script" ]]; then
        # Use dedicated query script
        "$query_script" "" "$CONTEXT_FILE" "$local_output_file" > /dev/null 2>&1 &
    else
        # Fallback: custom API agent via generic API query
        (
            source "$SCRIPT_DIR/lib/api_query.sh"
            run_api_consultant "$consultant" "" "$CONTEXT_FILE" "$local_output_file"
        ) > /dev/null 2>&1 &
    fi

    PIDS+=($!)
    update_progress "$consultant" 10 "running"
done

# --- Wait and Collect Results ---
log_info "Waiting for responses from ${#PIDS[@]} consultants..."

declare -a RESULTS=()
SUCCESS_COUNT=0

for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    name="${NAMES[$i]}"
    output_file="${OUTPUT_FILES[$i]}"

    if wait "$pid" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            RESULTS+=("$name:OK")
            ((SUCCESS_COUNT++))
            update_progress "$name" 100 "success"
        else
            log_warn "  $name: Empty response"
            RESULTS+=("$name:EMPTY")
            update_progress "$name" 100 "failed"
        fi
    else
        log_error "  $name: Failed"
        RESULTS+=("$name:FAILED")
        update_progress "$name" 100 "failed"
    fi
done

echo "" >&2

# --- Round 2+: Multi-Agent Debate (optional) ---
if [[ "$ENABLE_DEBATE" == "true" && $DEBATE_ROUNDS -gt 1 && $SUCCESS_COUNT -gt 1 ]]; then
    log_info "Starting Multi-Agent Debate (${DEBATE_ROUNDS} total rounds)..."

    for ((round=2; round<=DEBATE_ROUNDS; round++)); do
        log_info "  Round $round..."
        DEBATE_OUTPUT=$("$SCRIPT_DIR/debate_round.sh" "$OUTPUT_DIR" "$round" "$OUTPUT_DIR/round_$round")

        # Update responses with debate results
        if [[ -d "$OUTPUT_DIR/round_$round" ]]; then
            for f in "$OUTPUT_DIR/round_$round"/*.json; do
                if [[ -f "$f" && "$f" != *"summary"* ]]; then
                    consultant=$(basename "$f" .json)
                    # Merge debate data into main response
                    if [[ -f "$OUTPUT_DIR/${consultant}.json" ]]; then
                        jq -s '.[0] * {debate: .[1].debate}' \
                            "$OUTPUT_DIR/${consultant}.json" "$f" \
                            > "$OUTPUT_DIR/${consultant}.json.tmp" && \
                            mv "$OUTPUT_DIR/${consultant}.json.tmp" "$OUTPUT_DIR/${consultant}.json"
                    fi
                fi
            done
        fi
    done
    echo "" >&2
fi

# --- Voting and Consensus ---
log_info "Calculating consensus and voting..."
VOTING_REPORT=$(generate_voting_report "$OUTPUT_DIR")
echo "$VOTING_REPORT" > "$OUTPUT_DIR/voting.json"

CONSENSUS_SCORE=$(echo "$VOTING_REPORT" | jq -r '.voting_report.consensus.score // 50')
CONSENSUS_LEVEL=$(echo "$VOTING_REPORT" | jq -r '.voting_report.consensus.level // "unknown"')
log_info "  Consensus: ${CONSENSUS_SCORE}% ($CONSENSUS_LEVEL)"
echo "" >&2

# --- Auto-Synthesis (optional) ---
SYNTHESIS_FILE=""
if [[ "$ENABLE_SYNTHESIS" == "true" && $SUCCESS_COUNT -gt 0 ]]; then
    log_info "Generating automatic synthesis..."
    SYNTHESIS_FILE="$OUTPUT_DIR/synthesis.json"

    if "$SCRIPT_DIR/synthesize.sh" "$OUTPUT_DIR" "$SYNTHESIS_FILE" "$QUERY" > /dev/null 2>&1; then
        log_success "Synthesis generated: $SYNTHESIS_FILE"
    else
        log_warn "Synthesis failed, using fallback"
    fi
    echo "" >&2
fi

# --- Generate Combined Report ---
log_info "Generating combined report..."

REPORT_FILE="$OUTPUT_DIR/report.md"

{
    echo "# AI Consultation Report v2.0"
    echo ""
    echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**Directory**: $(pwd)"
    echo "**Version**: AI Consultants v${AI_CONSULTANTS_VERSION}"
    echo "**Category**: $QUESTION_CATEGORY"
    echo "**Successes**: $SUCCESS_COUNT/${#PIDS[@]} consultants"
    echo "**Consensus**: ${CONSENSUS_SCORE}% ($CONSENSUS_LEVEL)"
    echo ""
    echo "---"
    echo ""

    # Question
    echo "## Question"
    echo ""
    echo "$QUERY"
    echo ""

    # Included files
    if [[ ${#FILES[@]} -gt 0 ]]; then
        echo "## Analyzed Files"
        echo ""
        for f in "${FILES[@]}"; do
            echo "- \`$f\`"
        done
        echo ""
    fi

    echo "---"
    echo ""

    # Synthesis (if available)
    if [[ -n "$SYNTHESIS_FILE" && -f "$SYNTHESIS_FILE" ]]; then
        echo "## Automatic Synthesis"
        echo ""

        recommendation=$(jq -r '.weighted_recommendation.summary // "N/A"' "$SYNTHESIS_FILE" 2>/dev/null)
        approach=$(jq -r '.weighted_recommendation.approach // "N/A"' "$SYNTHESIS_FILE" 2>/dev/null)

        echo "**Recommended Approach**: $approach"
        echo ""
        echo "$recommendation"
        echo ""

        # Comparison table
        echo "### Consultant Comparison"
        echo ""
        echo "| Aspect | Gemini | Codex | Mistral | Kilo | Cursor |"
        echo "|---------|--------|-------|---------|------|--------|"

        jq -r '.comparison_table[]? | "| \(.aspect) | \(.Gemini // "N/A") | \(.Codex // "N/A") | \(.Mistral // "N/A") | \(.Kilo // "N/A") | \(.Cursor // "N/A") |"' \
            "$SYNTHESIS_FILE" 2>/dev/null || echo "| ... | ... | ... | ... | ... | ... |"

        echo ""

        # Risks
        echo "### Risk Assessment"
        echo ""
        overall_risk=$(jq -r '.risk_assessment.overall_risk // "unknown"' "$SYNTHESIS_FILE" 2>/dev/null)
        echo "**Overall Risk**: $overall_risk"
        echo ""

        jq -r '.risk_assessment.risks[]? | "- **\(.description)** (\(.severity)): \(.mitigation)"' \
            "$SYNTHESIS_FILE" 2>/dev/null || echo "- No significant risks identified"

        echo ""
        echo "---"
        echo ""
    fi

    echo "## Individual Responses"
    echo ""

    # Response from each consultant
    for i in "${!NAMES[@]}"; do
        name="${NAMES[$i]}"
        output_file="${OUTPUT_FILES[$i]}"
        result="${RESULTS[$i]}"

        echo "### $name"
        echo ""

        if [[ "$result" == *":OK" ]] && [[ -s "$output_file" ]]; then
            persona=$(jq -r '.persona // "N/A"' "$output_file" 2>/dev/null)
            confidence=$(jq -r '.confidence.score // "N/A"' "$output_file" 2>/dev/null)
            approach=$(jq -r '.response.approach // "N/A"' "$output_file" 2>/dev/null)
            summary=$(jq -r '.response.summary // "No summary"' "$output_file" 2>/dev/null)

            echo "**Persona**: $persona"
            echo "**Confidence**: $confidence/10"
            echo "**Approach**: $approach"
            echo ""
            echo "**Summary**: $summary"
            echo ""
            echo "<details>"
            echo "<summary>Full response</summary>"
            echo ""
            echo '```json'
            jq '.' "$output_file" 2>/dev/null | head -100
            if [[ $(wc -l < "$output_file") -gt 100 ]]; then
                echo ""
                echo "[... output truncated ...]"
            fi
            echo '```'
            echo "</details>"
        elif [[ "$result" == *":EMPTY" ]]; then
            echo "*Empty response*"
        else
            echo "*Consultant did not respond*"
        fi
        echo ""
    done

    echo "---"
    echo ""
    echo "## Output Files"
    echo ""
    echo "- Context: \`$CONTEXT_FILE\`"
    echo "- Voting: \`$OUTPUT_DIR/voting.json\`"
    [[ -n "$SYNTHESIS_FILE" ]] && echo "- Synthesis: \`$SYNTHESIS_FILE\`"
    for i in "${!NAMES[@]}"; do
        echo "- ${NAMES[$i]}: \`${OUTPUT_FILES[$i]}\`"
    done

} > "$REPORT_FILE"

log_success "Report generated: $REPORT_FILE"
echo "" >&2

# --- Session Management ---
SESSION_ID=$(save_session "$(generate_session_id)" "$QUERY" "$OUTPUT_DIR" "$QUESTION_CATEGORY")
log_info "Session saved: $SESSION_ID"

# --- Cost Tracking ---
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    ACTUAL_COST=$(calculate_session_cost "$OUTPUT_DIR")
    track_session_cost "$SESSION_ID" "$ACTUAL_COST"
    log_info "Session cost: $(format_cost "$ACTUAL_COST")"
fi

# --- Final Summary ---
echo "" >&2
echo "════════════════════════════════════════════════════════════════" >&2
log_success "Consultation completed!"
echo "" >&2
log_info "Results:"
for result in "${RESULTS[@]}"; do
    name="${result%%:*}"
    status="${result##*:}"
    case "$status" in
        OK) log_success "  - $name: Success" ;;
        EMPTY) log_warn "  - $name: Empty response" ;;
        FAILED) log_error "  - $name: Failed" ;;
    esac
done
echo "" >&2
log_info "Consensus: ${CONSENSUS_SCORE}% ($CONSENSUS_LEVEL)"
echo "" >&2
log_info "To view the report:"
log_info "  cat $REPORT_FILE"
echo "" >&2
log_info "For follow-up:"
log_info "  ./followup.sh \"Your follow-up question\""
echo "" >&2
log_info "Output directory: $OUTPUT_DIR"
echo "════════════════════════════════════════════════════════════════" >&2

# Output path for calling scripts
echo "$OUTPUT_DIR"
