#!/bin/bash
# consult_all.sh - AI Consultants v2.2 - Main Orchestrator
#
# Complete workflow for multi-model AI consultation with:
# - Specialized personas for each consultant
# - Confidence scoring and weighted voting
# - Auto-synthesis of responses with multiple strategies
# - Optional Multi-Agent Debate (MAD)
# - Smart routing based on question category
# - Configuration presets for quick setup
# - Session management for follow-up
# - Cost tracking
# - Panic button mode for uncertainty detection
#
# Usage: ./consult_all.sh [options] "Your question" [file1] [file2] ...
#
# Options:
#   --preset <name>      Use a configuration preset (minimal, balanced, thorough, high-stakes, local, security, cost-capped)
#   --strategy <name>    Synthesis strategy (majority, risk_averse, security_first, cost_capped, compare_only)
#   --list-presets       List available presets
#   --list-strategies    List available synthesis strategies
#   --help               Show this help message
#
# Environment variables:
#   ENABLE_SYNTHESIS=true    Enable automatic synthesis
#   ENABLE_DEBATE=true       Enable multi-round debate
#   DEBATE_ROUNDS=2          Number of debate rounds
#   ENABLE_SMART_ROUTING=true Select consultants based on question
#   ENABLE_PANIC_MODE=auto   Panic mode (auto, always, never)

set -euo pipefail

# --- Initial Setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/voting.sh"
source "$SCRIPT_DIR/lib/routing.sh"
source "$SCRIPT_DIR/lib/cache.sh"

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

# --- Show usage help ---
show_help() {
    cat << 'EOF'
AI Consultants v2.2 - Multi-Model AI Consultation

Usage: ./consult_all.sh [options] "Your question" [file1] [file2] ...

Options:
  --preset <name>      Use a configuration preset:
                         minimal      - 2 models, fast and cheap
                         balanced     - 4 models, good coverage
                         thorough     - 5 models, comprehensive
                         high-stakes  - All models + debate
                         local        - Ollama only, full privacy
                         security     - Security-focused + debate
                         cost-capped  - Budget-conscious options

  --strategy <name>    Synthesis strategy:
                         majority       - Simple voting, most common wins
                         risk_averse    - Weight conservative responses higher
                         security_first - Prioritize security-focused insights
                         cost_capped    - Prefer cheaper consultant opinions
                         compare_only   - No recommendation, just comparison

  --list-presets       List all available presets
  --list-strategies    List all synthesis strategies
  --help, -h           Show this help message

Examples:
  ./consult_all.sh "How to optimize this SQL query?"
  ./consult_all.sh --preset minimal "Quick question about Python lists"
  ./consult_all.sh --preset high-stakes --strategy risk_averse "Critical architecture decision"
  ./consult_all.sh "Review this code" src/main.py src/utils.py

Environment Variables:
  ENABLE_SYNTHESIS=true       Enable automatic synthesis
  ENABLE_DEBATE=true          Enable multi-round debate
  DEBATE_ROUNDS=2             Number of debate rounds
  ENABLE_SMART_ROUTING=true   Select consultants based on question category
  ENABLE_PANIC_MODE=auto      Panic mode: auto, always, never
  MAX_SESSION_COST=1.00       Maximum budget per session ($)

For more information, run: ./doctor.sh
EOF
}

# --- List synthesis strategies ---
list_strategies() {
    cat << 'EOF'
Available synthesis strategies:

  majority       Simple voting - most common answer wins (default)
  risk_averse    Weight conservative responses higher, prefer safety
  security_first Prioritize security-focused consultants and insights
  cost_capped    Prefer opinions from cheaper consultants within budget
  compare_only   No recommendation, just structured comparison table

Usage: ./consult_all.sh --strategy <name> "Your question"
EOF
}

# --- Argument Parsing ---
PRESET=""
SYNTHESIS_STRATEGY=""
QUERY=""
FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset)
            if [[ -n "${2:-}" ]]; then
                PRESET="$2"
                shift 2
            else
                log_error "--preset requires a value"
                exit 1
            fi
            ;;
        --strategy)
            if [[ -n "${2:-}" ]]; then
                SYNTHESIS_STRATEGY="$2"
                shift 2
            else
                log_error "--strategy requires a value"
                exit 1
            fi
            ;;
        --list-presets)
            list_presets
            exit 0
            ;;
        --list-strategies)
            list_strategies
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$QUERY" ]]; then
                QUERY="$1"
            else
                FILES+=("$1")
            fi
            shift
            ;;
    esac
done

# --- Apply Preset (CLI flag or default) ---
# Use CLI flag if provided, otherwise fall back to DEFAULT_PRESET
PRESET="${PRESET:-${DEFAULT_PRESET:-}}"
if [[ -n "$PRESET" ]]; then
    if ! apply_preset "$PRESET"; then
        exit 1
    fi
    log_info "Applied preset: $PRESET"
fi

# Set synthesis strategy: CLI flag > environment > DEFAULT_STRATEGY > fallback
SYNTHESIS_STRATEGY="${SYNTHESIS_STRATEGY:-${DEFAULT_STRATEGY:-majority}}"

# Export synthesis strategy for use by synthesize.sh
export SYNTHESIS_STRATEGY

# --- Input Validation ---
if [[ -z "$QUERY" ]]; then
    log_error "Usage: $0 [options] \"Your question\" [file1] [file2] ..."
    log_info "Example: $0 \"How to optimize this function?\" src/utils.py"
    log_info "Run with --help for more options"
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
    # Log self-exclusion status for debugging
    log_self_exclusion_status

    # All enabled consultants - use a compact loop
    _consultant_map="GEMINI:Gemini CODEX:Codex MISTRAL:Mistral KILO:Kilo CURSOR:Cursor AIDER:Aider CLAUDE:Claude QWEN3:Qwen3 GLM:GLM GROK:Grok DEEPSEEK:DeepSeek OLLAMA:Ollama"
    for _entry in $_consultant_map; do
        _flag="${_entry%%:*}"
        _name="${_entry#*:}"
        _enable_var="ENABLE_${_flag}"

        # Skip self (invoking agent shouldn't query itself)
        if should_skip_consultant "$_flag"; then
            log_debug "Skipping $_name (self-exclusion: invoking agent)"
            continue
        fi

        [[ "${!_enable_var:-false}" == "true" ]] && SELECTED_CONSULTANTS+=("$_name")
    done
    unset _consultant_map _entry _flag _name _enable_var

    # Discover custom API agents from environment
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

# Track cache hits
declare -a CACHE_HITS=()

# Launch consultants in parallel (with cache check)
for consultant in "${SELECTED_CONSULTANTS[@]}"; do
    consultant_lower=$(to_lower "$consultant")
    local_output_file="$OUTPUT_DIR/${consultant_lower}.json"
    OUTPUT_FILES+=("$local_output_file")
    NAMES+=("$consultant")

    # Check cache first (v2.3)
    if is_cache_enabled; then
        cached_response=$(check_cache "$QUERY" "$QUESTION_CATEGORY" "$consultant_lower" "$CONTEXT_FILE" 2>/dev/null || echo "")
        if [[ -n "$cached_response" ]]; then
            # Use cached response
            echo "$cached_response" | mark_from_cache > "$local_output_file"
            PIDS+=("cache")  # Marker for cache hit
            CACHE_HITS+=("$consultant")
            update_progress "$consultant" 100 "cached"
            log_debug "Cache hit for $consultant"
            continue
        fi
    fi

    # Convention: query script is query_<lowercase_name>.sh
    query_script="$SCRIPT_DIR/query_${consultant_lower}.sh"

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

# Log cache status
if [[ ${#CACHE_HITS[@]} -gt 0 ]]; then
    log_info "Cache hits: ${CACHE_HITS[*]}"
fi

# --- Wait and Collect Results ---
log_info "Waiting for responses from ${#PIDS[@]} consultants..."

declare -a RESULTS=()
SUCCESS_COUNT=0

for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    name="${NAMES[$i]}"
    output_file="${OUTPUT_FILES[$i]}"
    name_lower=$(to_lower "$name")

    # Handle cache hits (pid is "cache" marker)
    if [[ "$pid" == "cache" ]]; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK (cached)"
            RESULTS+=("$name:OK")
            ((SUCCESS_COUNT++))
        else
            log_warn "  $name: Cache miss"
            RESULTS+=("$name:EMPTY")
        fi
        continue
    fi

    if wait "$pid" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            RESULTS+=("$name:OK")
            ((SUCCESS_COUNT++))
            update_progress "$name" 100 "success"

            # Store in cache (v2.3)
            if is_cache_enabled; then
                response_content=$(cat "$output_file")
                store_cache "$QUERY" "$QUESTION_CATEGORY" "$name_lower" "$response_content" "$CONTEXT_FILE" 2>/dev/null || true
            fi
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

# --- Panic Mode Detection (v2.2) ---
PANIC_TRIGGERED=false
if [[ "$ENABLE_PANIC_MODE" != "never" && $SUCCESS_COUNT -gt 1 ]]; then
    if should_trigger_panic "$OUTPUT_DIR"; then
        PANIC_TRIGGERED=true
        PANIC_DIAGNOSIS=$(get_panic_diagnosis "$OUTPUT_DIR")

        log_warn "PANIC MODE TRIGGERED - Uncertainty detected!"
        log_warn "  Diagnosis: $(echo "$PANIC_DIAGNOSIS" | jq -r '.triggers | join(", ")')"

        # Save diagnosis
        echo "$PANIC_DIAGNOSIS" > "$OUTPUT_DIR/panic_diagnosis.json"

        # Actions: Enable debate if not already enabled, switch to risk_averse strategy
        if [[ "$ENABLE_DEBATE" != "true" ]]; then
            log_info "  Action: Enabling multi-agent debate"
            ENABLE_DEBATE=true
            DEBATE_ROUNDS="${PANIC_EXTRA_DEBATE_ROUNDS:-1}"
            DEBATE_ROUNDS=$((DEBATE_ROUNDS + 1))  # At least one extra round
        else
            # Add extra debate rounds
            EXTRA_ROUNDS="${PANIC_EXTRA_DEBATE_ROUNDS:-1}"
            DEBATE_ROUNDS=$((DEBATE_ROUNDS + EXTRA_ROUNDS))
            log_info "  Action: Adding $EXTRA_ROUNDS extra debate round(s) (total: $DEBATE_ROUNDS)"
        fi

        # Switch to risk_averse synthesis strategy
        if [[ "$SYNTHESIS_STRATEGY" == "majority" ]]; then
            log_info "  Action: Switching to risk_averse synthesis strategy"
            SYNTHESIS_STRATEGY="risk_averse"
            export SYNTHESIS_STRATEGY
        fi

        echo "" >&2
    fi
fi

# --- Round 2+: Multi-Agent Debate (optional) ---
if [[ "$ENABLE_DEBATE" == "true" && $DEBATE_ROUNDS -gt 1 && $SUCCESS_COUNT -gt 1 ]]; then
    log_info "Starting Multi-Agent Debate (${DEBATE_ROUNDS} total rounds)..."

    for ((round=2; round<=DEBATE_ROUNDS; round++)); do
        log_info "  Round $round..."
        # v2.3: Pass category for mandatory debate check (SECURITY/ARCHITECTURE always debate)
        DEBATE_OUTPUT=$("$SCRIPT_DIR/debate_round.sh" "$OUTPUT_DIR" "$round" "$OUTPUT_DIR/round_$round" "$QUESTION_CATEGORY")

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

# --- Quality Monitoring (v2.3) ---
# Log optimization metrics for quality tracking
if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
    log_debug "=== Token Optimization Metrics ==="
    log_debug "  Cache enabled: ${ENABLE_SEMANTIC_CACHE:-true}"
    log_debug "  Cache hits: ${#CACHE_HITS[@]}"
    log_debug "  Response limits enabled: ${ENABLE_RESPONSE_LIMITS:-false}"
    log_debug "  Cost-aware routing: ${ENABLE_COST_AWARE_ROUTING:-false}"
    log_debug "  Debate optimization: ${ENABLE_DEBATE_OPTIMIZATION:-false}"
fi

# Save optimization metrics to output directory
jq -n \
    --argjson cache_enabled "${ENABLE_SEMANTIC_CACHE:-true}" \
    --argjson cache_hits "${#CACHE_HITS[@]}" \
    --argjson response_limits "${ENABLE_RESPONSE_LIMITS:-false}" \
    --argjson cost_aware "${ENABLE_COST_AWARE_ROUTING:-false}" \
    --argjson debate_opt "${ENABLE_DEBATE_OPTIMIZATION:-false}" \
    --argjson compact "${ENABLE_COMPACT_REPORT:-true}" \
    --argjson consensus "$CONSENSUS_SCORE" \
    --arg consensus_level "$CONSENSUS_LEVEL" \
    --argjson success_count "$SUCCESS_COUNT" \
    --argjson total "${#PIDS[@]}" \
    --arg category "$QUESTION_CATEGORY" \
    '{
        optimization_settings: {
            cache_enabled: $cache_enabled,
            cache_hits: $cache_hits,
            response_limits_enabled: $response_limits,
            cost_aware_routing: $cost_aware,
            debate_optimization: $debate_opt,
            compact_report: $compact
        },
        quality_metrics: {
            consensus_score: $consensus,
            consensus_level: $consensus_level,
            successful_responses: $success_count,
            total_consultants: $total,
            category: $category
        },
        timestamp: (now | todate)
    }' > "$OUTPUT_DIR/optimization_metrics.json"

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

# --- Anonymous Peer Review (v2.2, optional) ---
if [[ "${ENABLE_PEER_REVIEW:-false}" == "true" ]]; then
    MIN_RESPONSES="${PEER_REVIEW_MIN_RESPONSES:-3}"
    if [[ $SUCCESS_COUNT -ge $MIN_RESPONSES ]]; then
        log_info "Running anonymous peer review..."
        PEER_REVIEW_DIR="$OUTPUT_DIR/peer_review"
        mkdir -p "$PEER_REVIEW_DIR"

        if "$SCRIPT_DIR/peer_review.sh" "$OUTPUT_DIR" "$PEER_REVIEW_DIR" > /dev/null 2>&1; then
            log_success "Peer review completed: $PEER_REVIEW_DIR"
        else
            log_warn "Peer review failed or unavailable"
        fi
    else
        log_info "Skipping peer review: need ${MIN_RESPONSES}+ responses (got $SUCCESS_COUNT)"
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

    # Quick Summary Table (v2.3)
    echo "## Quick Summary"
    echo ""
    echo "| Consultant | Confidence | Approach |"
    echo "|------------|------------|----------|"
    for i in "${!NAMES[@]}"; do
        name="${NAMES[$i]}"
        output_file="${OUTPUT_FILES[$i]}"
        result="${RESULTS[$i]}"
        if [[ "$result" == *":OK" ]] && [[ -s "$output_file" ]]; then
            conf=$(jq -r '.confidence.score // "?"' "$output_file" 2>/dev/null)
            appr=$(jq -r '.response.approach // "N/A"' "$output_file" 2>/dev/null | head -c 30)
            echo "| $name | $conf/10 | $appr |"
        else
            echo "| $name | - | (no response) |"
        fi
    done
    echo ""

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

            echo "**Persona**: $persona | **Confidence**: $confidence/10 | **Approach**: $approach"
            echo ""
            echo "$summary"
            echo ""

            # Include full JSON only if compact report is disabled (v2.3)
            if [[ "${ENABLE_COMPACT_REPORT:-true}" != "true" ]]; then
                local max_lines="${REPORT_MAX_JSON_LINES:-50}"
                echo "<details>"
                echo "<summary>Full response</summary>"
                echo ""
                echo '```json'
                jq '.' "$output_file" 2>/dev/null | head -"$max_lines"
                if [[ $(wc -l < "$output_file") -gt $max_lines ]]; then
                    echo ""
                    echo "[... truncated, see ${output_file} for full response ...]"
                fi
                echo '```'
                echo "</details>"
                echo ""
            fi
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
