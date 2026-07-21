#!/bin/bash
# consult_all.sh - AI Consultants - Main Orchestrator
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
#   --preset <name>      Use a configuration preset (minimal, balanced, thorough, high-stakes, security, cost-capped)
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
source "$SCRIPT_DIR/lib/reliability.sh"
source "$SCRIPT_DIR/lib/voting.sh"
source "$SCRIPT_DIR/lib/routing.sh"
source "$SCRIPT_DIR/lib/cache.sh"
source "$SCRIPT_DIR/lib/orchestration.sh"

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
    echo "AI Consultants v${AI_CONSULTANTS_VERSION:-2.10.0} - Multi-Model AI Consultation"
    cat << 'EOF'

Usage: ./consult_all.sh [options] "Your question" [file1[@TAG]] [file2[@TAG]] ...

  File @TAG: PRIMARY (default, focus of question) or CONTEXT (ambient reference)

Options:
  --preset <name>      Use a configuration preset:
                         minimal      - 2 models, fast and cheap
                         balanced     - 4 models, good coverage
                         thorough     - 5 models, comprehensive
                         high-stakes  - All models + debate
                         max_quality  - 8 of 11 consultants + premium models + peer review
                         medium       - 4 models + standard models + light debate
                         fast         - 2 models + economy models, no debate
                         security     - Security-focused + debate
                         cost-capped  - Budget-conscious options

  --strategy <name>    Synthesis strategy:
                         majority       - Simple voting, most common wins
                         risk_averse    - Weight conservative responses higher
                         security_first - Prioritize security-focused insights
                         cost_capped    - Prefer cheaper consultant opinions
                         compare_only   - No recommendation, just comparison

  --query-file <path>  Read the question from a file (use when the inline
                       query would exceed shell limits or contain awkward
                       quoting). Conflicts with a positional question argument.
  --list-presets       List all available presets
  --list-strategies    List all synthesis strategies
  --help, -h           Show this help message

Examples:
  ./consult_all.sh "How to optimize this SQL query?"
  ./consult_all.sh --preset minimal "Quick question about Python lists"
  ./consult_all.sh --preset high-stakes --strategy risk_averse "Critical architecture decision"
  ./consult_all.sh "Review this code" src/main.py src/utils.py
  ./consult_all.sh "Compare auth approaches" src/auth.ts@PRIMARY src/logger.ts@CONTEXT
  ./consult_all.sh --query-file /tmp/long_question.txt src/big.py

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
QUERY_FILE=""
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
        --query-file)
            if [[ -n "${2:-}" && -f "$2" ]]; then
                QUERY_FILE="$2"
                shift 2
            else
                log_error "--query-file requires an existing file path"
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

# Resolve query source: --query-file wins over the empty positional slot but
# conflicts with an inline positional query.
if [[ -n "$QUERY_FILE" ]]; then
    if [[ -n "$QUERY" ]]; then
        log_error "--query-file conflicts with a positional query argument"
        exit 1
    fi
    QUERY=$(cat "$QUERY_FILE")
fi

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

# --- Pre-flight Check (optional, delegates to doctor.sh since v2.10.9) ---
if [[ "$ENABLE_PREFLIGHT" == "true" ]]; then
    log_info "Running pre-flight check (via doctor.sh)..."
    preflight_args=()
    [[ "$PREFLIGHT_QUICK" == "true" ]] && preflight_args+=("--quick")
    # Capture output to a tmpfile so a failed check shows the actual problem
    # rather than the silent "Pre-flight check failed" of pre-v2.10.10.
    preflight_log=$(mktemp -t ai_consultants_preflight.XXXXXX.log)
    if ! "$SCRIPT_DIR/doctor.sh" ${preflight_args[@]+"${preflight_args[@]}"} > "$preflight_log" 2>&1; then
        log_error "Pre-flight check failed:"
        cat "$preflight_log" >&2
        rm -f "$preflight_log"
        log_error "Re-run ./scripts/doctor.sh for full diagnostic."
        exit 1
    fi
    rm -f "$preflight_log"
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

# --- Orchestration Planning (v2.16.0) ---
# Pick the orchestration shape from category + complexity + intent. Shape drives
# how the panel deliberates (convergence loop, adversarial gate, tournament,
# exhaustive sweep) rather than a fixed debate-round count. ORCHESTRATION_MODE=fixed
# bypasses the planner and preserves the legacy pipeline exactly.
QUERY_COMPLEXITY=$(calculate_query_complexity "$QUERY" "${#FILES[@]}" "$QUESTION_CATEGORY" 2>/dev/null || echo 5)
QUERY_INTENT=$(detect_intent "$QUERY")
ORCH_SHAPE=$(select_orchestration_shape "$QUESTION_CATEGORY" "$QUERY_COMPLEXITY" "$QUERY_INTENT")
if [[ "$ORCH_SHAPE" != "fixed" ]]; then
    log_info "Orchestration: shape=$ORCH_SHAPE (complexity=$QUERY_COMPLEXITY, intent=$QUERY_INTENT)"
    # The adversarial shape uses anonymous peer review as its refutation gate.
    if [[ "$ORCH_SHAPE" == "adversarial" && "${ENABLE_ADVERSARIAL_VERIFY:-true}" == "true" ]]; then
        ENABLE_PEER_REVIEW=true
    fi
fi

# --- Create Output Directory (with secure permissions) ---
# Add random suffix to prevent predictable directory names (security improvement)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RANDOM_SUFFIX="${RANDOM}${$}"
OUTPUT_DIR="${DEFAULT_OUTPUT_DIR_BASE}/${TIMESTAMP}_${RANDOM_SUFFIX}"
# Create base directory with restricted permissions (owner only)
mkdir -p "$DEFAULT_OUTPUT_DIR_BASE"
chmod 700 "$DEFAULT_OUTPUT_DIR_BASE"
# Create session-specific directory
mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"

# --- Stance options (v2.21, opt-in): generate a shared enumerated stance set so
# every consultant picks the same one -> exact-match consensus. Fully graceful:
# on any failure STANCE_OPTIONS_PROMPT stays empty and consensus uses the cluster.
if [[ "${ENABLE_STANCE_CONSENSUS:-false}" == "true" ]]; then
    source "$SCRIPT_DIR/lib/stance.sh"
    STANCE_OPTIONS=$(generate_stance_options "$QUERY" 2>/dev/null || echo "[]")
    echo "$STANCE_OPTIONS" > "$OUTPUT_DIR/stance_options.json" 2>/dev/null || true
    if STANCE_OPTIONS_PROMPT=$(build_stance_prompt "$STANCE_OPTIONS" 2>/dev/null); then
        export STANCE_OPTIONS_PROMPT
        log_info "Stance consensus: $(echo "$STANCE_OPTIONS" | jq -r 'length' 2>/dev/null || echo '?') options generated"
    else
        log_warn "Stance consensus: no usable options — falling back to lexical cluster consensus"
    fi
fi

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
CONTEXT_SIZE=0
ESTIMATED_COST=0
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    CONTEXT_SIZE=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')
    ESTIMATED_COST=$(estimate_consultation_cost 4 "$CONTEXT_SIZE")
    log_info "Estimated cost: $(format_cost "$ESTIMATED_COST")"
fi

# --- Budget Check: Before Round 1 ---
if is_budget_enabled; then
    log_debug "Budget enforcement enabled: \$${MAX_SESSION_COST} limit"
    if ! enforce_budget 0 "$ESTIMATED_COST" "initial consultation"; then
        log_error "Consultation aborted: estimated cost exceeds budget"
        exit 1
    fi
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
    # Order matches ALL_CONSULTANTS in config.sh for consistency
    _consultant_map="GEMINI:Gemini CODEX:Codex MISTRAL:Mistral CURSOR:Cursor KIMI:Kimi CLAUDE:Claude QWEN3:Qwen3 GLM:GLM GROK:Grok DEEPSEEK:DeepSeek MINIMAX:MiniMax"
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

# --- Health Gate (v2.19.0, opt-in) ---
# Ping each selected consultant in parallel and drop the non-responsive ones
# (installed-but-unauthenticated CLIs, stale installs) BEFORE the real run, so
# the quorum/budget checks below see the genuinely-working panel. Opt-in: costs
# one tiny extra query per consultant. Prunes; does not switch transport.
if [[ "${ENABLE_HEALTH_GATE:-false}" == "true" && ${#SELECTED_CONSULTANTS[@]} -gt 0 ]]; then
    HG_DIR=$(mktemp -d)
    declare -a HG_PIDS=() HG_NAMES=() RESPONSIVE=()
    for _c in "${SELECTED_CONSULTANTS[@]}"; do
        _cl=$(to_lower "$_c")
        # Cache-aware: a consultant whose response is already cached costs nothing
        # in Round 1 (check_cache short-circuits), so keep it without a billed ping.
        if is_cache_enabled && [[ -n "$(check_cache "$QUERY" "$QUESTION_CATEGORY" "$_cl" "$CONTEXT_FILE" 2>/dev/null || echo "")" ]]; then
            RESPONSIVE+=("$_c")
            log_debug "  Health gate: $_c cached, kept (not pinged)"
            continue
        fi
        ( ping_consultant "$_cl" "$SCRIPT_DIR" "${HEALTH_GATE_TIMEOUT:-30}" "$HG_DIR/${_cl}.json" "$HG_DIR/${_cl}.err" ) &
        HG_PIDS+=("$!"); HG_NAMES+=("$_c")
    done
    [[ ${#HG_PIDS[@]} -gt 0 ]] && log_info "Health gate: pinging ${#HG_PIDS[@]} consultants in parallel..."
    for _i in "${!HG_PIDS[@]}"; do
        if wait "${HG_PIDS[$_i]}" 2>/dev/null; then _rc=0; else _rc=$?; fi
        _nm="${HG_NAMES[$_i]}"
        if [[ $_rc -eq 0 || $_rc -eq 2 ]]; then
            RESPONSIVE+=("$_nm")
            [[ $_rc -eq 2 ]] && log_debug "  Health gate: $_nm not probeable (no query script), kept"
        else
            _cl=$(to_lower "$_nm")
            _reason=$(get_consultant_error_reason "$HG_DIR/${_cl}.err")
            log_warn "  Health gate dropped $_nm${_reason:+: $_reason}"
        fi
    done
    rm -rf "$HG_DIR"
    _hg_total=${#SELECTED_CONSULTANTS[@]}
    SELECTED_CONSULTANTS=(${RESPONSIVE[@]+"${RESPONSIVE[@]}"})
    log_info "Health gate: ${#SELECTED_CONSULTANTS[@]} of ${_hg_total} usable"
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

# --- Refined Cost Estimation (v2.4) ---
# Now that we know which consultants are selected, recalculate with accurate model rates
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    CONSULTANT_LIST=$(IFS=','; echo "${SELECTED_CONSULTANTS[*]}")
    ESTIMATED_COST=$(estimate_consultation_cost "${#SELECTED_CONSULTANTS[@]}" "$CONTEXT_SIZE" "$CONSULTANT_LIST")
    log_debug "Refined estimate with ${#SELECTED_CONSULTANTS[@]} consultants: $(format_cost "$ESTIMATED_COST")"

    # Re-check budget with refined estimate
    if is_budget_enabled; then
        if ! enforce_budget 0 "$ESTIMATED_COST" "refined consultation estimate"; then
            log_error "Consultation aborted: refined estimate exceeds budget"
            exit 1
        fi
    fi
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
    # Capture each consultant's stderr so a failure (auth/CLI-missing/transient)
    # can be surfaced instead of silently discarded (was `2>&1` to /dev/null).
    local_err_file="$OUTPUT_DIR/${consultant_lower}.err"
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
        # Apply cost-aware model override if enabled (v2.3)
        if [[ "${ENABLE_COST_AWARE_ROUTING:-false}" == "true" ]] && type get_cost_aware_model &>/dev/null; then
            local_model=$(get_cost_aware_model "$consultant_lower" "${QUERY_COMPLEXITY:-5}" 2>/dev/null || echo "")
            if [[ -n "$local_model" ]]; then
                model_var="$(to_upper "${consultant_lower}")_MODEL"
                if [[ ! "$model_var" =~ ^[A-Z0-9_]+_MODEL$ ]]; then
                    log_warn "Invalid model variable name: $model_var, skipping cost-aware override"
                    continue
                fi
                log_debug "Cost-aware: $consultant using model $local_model"
                (
                    apply_launch_stagger
                    export "$model_var=$local_model"
                    "$query_script" "" "$CONTEXT_FILE" "$local_output_file"
                ) > /dev/null 2>"$local_err_file" &
                PIDS+=($!)
                update_progress "$consultant" 10 "running"
                continue
            fi
        fi
        # Standard launch (inherits current environment models)
        ( apply_launch_stagger; "$query_script" "" "$CONTEXT_FILE" "$local_output_file" ) > /dev/null 2>"$local_err_file" &
    else
        # Fallback: custom API agent via generic API query
        (
            apply_launch_stagger
            source "$SCRIPT_DIR/lib/api_query.sh"
            run_api_consultant "$consultant" "" "$CONTEXT_FILE" "$local_output_file"
        ) > /dev/null 2>"$local_err_file" &
    fi

    PIDS+=($!)
    update_progress "$consultant" 10 "running"
done

# Log cache status
if [[ ${#CACHE_HITS[@]} -gt 0 ]]; then
    log_info "Cache hits: ${CACHE_HITS[*]}"
fi

# Surface the captured stderr reason for a consultant that produced no usable
# output, so the user sees WHY (auth error, CLI missing, transient) instead of a
# bare "Failed". Derives the .err path from the .json output path.
_surface_consultant_error() {
    local cname="$1" out="$2"
    local ef="${out%.json}.err"
    local reason
    reason=$(get_consultant_error_reason "$ef")
    local detail="${reason:-no output and no error captured — CLI likely missing or not authenticated (run doctor.sh --live)}"
    log_warn "    ↳ ${cname}: ${detail}"
    # Record for the report's "Diagnosed Failures" section (quorum grading, v2.19.0).
    DIAGNOSED_FAILURES+=("${cname}|${detail}")
}

# --- Wait and Collect Results ---
log_info "Waiting for responses from ${#PIDS[@]} consultants..."

declare -a RESULTS=()
declare -a DIAGNOSED_FAILURES=()
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
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" success 2>/dev/null || true
            fi
        else
            log_warn "  $name: Cache miss"
            RESULTS+=("$name:EMPTY")
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" fail 2>/dev/null || true
            fi
        fi
        continue
    fi

    if wait "$pid" 2>/dev/null; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            RESULTS+=("$name:OK")
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            update_progress "$name" 100 "success"
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" success 2>/dev/null || true
            fi

            # Store in cache (v2.3)
            if is_cache_enabled; then
                response_content=$(cat "$output_file")
                store_cache "$QUERY" "$QUESTION_CATEGORY" "$name_lower" "$response_content" "$CONTEXT_FILE" 2>/dev/null || true
            fi
        else
            log_warn "  $name: Empty response"
            _surface_consultant_error "$name" "$output_file"
            RESULTS+=("$name:EMPTY")
            update_progress "$name" 100 "failed"
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" fail 2>/dev/null || true
            fi
        fi
    else
        log_error "  $name: Failed"
        _surface_consultant_error "$name" "$output_file"
        RESULTS+=("$name:FAILED")
        update_progress "$name" 100 "failed"
        if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
            record_consultant_outcome "$name" fail 2>/dev/null || true
        fi
    fi
done

echo "" >&2

# --- Quorum Grading (v2.19.0) ---
# Grade the run by how many consultants actually responded, so a silently-shrunk
# panel is reported as DEGRADED/FAILED instead of presenting as authoritative.
QUORUM_ATTEMPTED=${#PIDS[@]}
QUORUM_MIN_EFF="${QUORUM_MIN:-2}"
QUORUM_OUTCOME=$(grade_quorum "$SUCCESS_COUNT" "$QUORUM_ATTEMPTED" "$QUORUM_MIN_EFF")

if [[ "$QUORUM_OUTCOME" == "DEGRADED" ]]; then
    log_warn "Quorum: DEGRADED — ${SUCCESS_COUNT}/${QUORUM_ATTEMPTED} consultants responded"
elif [[ "$QUORUM_OUTCOME" == "FAILED" ]]; then
    log_error "Quorum: FAILED — only ${SUCCESS_COUNT}/${QUORUM_ATTEMPTED} responded (need >= ${QUORUM_MIN_EFF})"
    if [[ ${#DIAGNOSED_FAILURES[@]} -gt 0 ]]; then
        log_error "Diagnosed failures:"
        for _df in "${DIAGNOSED_FAILURES[@]}"; do log_error "$(render_diagnosed_failure "$_df")"; done
    fi
    if [[ "${QUORUM_ACTION:-warn}" == "stop" ]]; then
        log_error "Aborting below quorum (QUORUM_ACTION=stop). Set QUORUM_ACTION=warn to continue."
        exit 1
    fi
fi

# --- Budget Check: After Round 1 ---
CURRENT_COST=0
if [[ "$ENABLE_COST_TRACKING" == "true" && $SUCCESS_COUNT -gt 0 ]]; then
    CURRENT_COST=$(calculate_session_cost "$OUTPUT_DIR")

    # Check warning threshold
    if check_warning_threshold "$CURRENT_COST"; then
        log_warn "Cost warning: $(format_budget_status "$CURRENT_COST")"
    fi

    # Budget enforcement check
    if is_budget_enabled; then
        log_debug "Current cost after Round 1: $(format_cost "$CURRENT_COST")"
    fi
fi

# --- Fallback Escalation: Re-query low-confidence with premium models ---
if is_escalation_enabled && [[ $SUCCESS_COUNT -gt 0 ]]; then
    ESCALATED_COUNT=0
    for consultant in "${SELECTED_CONSULTANTS[@]}"; do
        consultant_lower=$(to_lower "$consultant")
        response_file="$OUTPUT_DIR/${consultant_lower}.json"

        if needs_escalation "$response_file"; then
            premium_model=$(get_premium_model "$consultant_lower")
            if [[ -n "$premium_model" ]]; then
                original_confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
                [[ "$original_confidence" =~ ^[0-9]+$ ]] || original_confidence=5
                log_info "Escalating $consultant (confidence: $original_confidence) → premium model: $premium_model"

                query_script="$SCRIPT_DIR/query_${consultant_lower}.sh"
                if [[ -x "$query_script" ]]; then
                    escalation_file="$OUTPUT_DIR/${consultant_lower}_escalated.json"
                    model_var="$(to_upper "${consultant_lower}")_MODEL"
                    if [[ ! "$model_var" =~ ^[A-Z0-9_]+_MODEL$ ]]; then
                        log_warn "Invalid model variable name: $model_var, skipping escalation for $consultant"
                        continue
                    fi
                    (
                        export "$model_var=$premium_model"
                        "$query_script" "" "$CONTEXT_FILE" "$escalation_file"
                    ) > /dev/null 2>&1

                    # Replace original if escalated response has higher confidence
                    if [[ -f "$escalation_file" && -s "$escalation_file" ]]; then
                        new_confidence=$(jq -r '.confidence.score // 0' "$escalation_file" 2>/dev/null)
                        [[ "$new_confidence" =~ ^[0-9]+$ ]] || new_confidence=0
                        if [[ "$new_confidence" -gt "$original_confidence" ]]; then
                            cp "$escalation_file" "$response_file"
                            # Remove the copy: leaving it makes one query look
                            # like two to every glob over this directory -
                            # cost (now that tokens are real) and voting alike.
                            rm -f "$escalation_file"
                            log_success "  $consultant escalated: confidence $original_confidence → $new_confidence"
                            ESCALATED_COUNT=$((ESCALATED_COUNT + 1))
                        else
                            rm -f "$escalation_file"
                            log_debug "  $consultant escalation did not improve confidence"
                        fi
                    fi
                fi
            fi
        fi
    done
    if [[ $ESCALATED_COUNT -gt 0 ]]; then
        log_info "Escalated $ESCALATED_COUNT consultant(s) to premium models"
    fi
fi

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

# --- Round 2+: Deliberation (dynamic orchestration or legacy debate) ---
if [[ "$ORCHESTRATION_MODE" == "fixed" ]]; then
    # Legacy pipeline (pre-v2.16): fixed number of debate rounds.
    if [[ "$ENABLE_DEBATE" == "true" && $DEBATE_ROUNDS -gt 1 && $SUCCESS_COUNT -gt 1 ]]; then
        # Budget Check: Before Debate
        if is_budget_enabled; then
            DEBATE_ESTIMATE=$(estimate_phase_cost "debate" "$SUCCESS_COUNT" "$CONTEXT_SIZE")
            DEBATE_ESTIMATE=$(echo "scale=6; $DEBATE_ESTIMATE * $DEBATE_ROUNDS" | bc)
            if ! enforce_budget "$CURRENT_COST" "$DEBATE_ESTIMATE" "debate rounds"; then
                log_warn "Skipping debate due to budget constraints"
                ENABLE_DEBATE=false
            fi
        fi

        # Proceed with debate if still enabled after budget check
        if [[ "$ENABLE_DEBATE" == "true" ]]; then
            log_info "Starting Multi-Agent Debate (${DEBATE_ROUNDS} total rounds)..."

            for ((round=2; round<=DEBATE_ROUNDS; round++)); do
                log_info "  Round $round..."
                _apply_debate_round "$OUTPUT_DIR" "$round" "$QUESTION_CATEGORY"
            done
            echo "" >&2
        fi
    fi
else
    # Dynamic orchestration (v2.16.0): the planned shape drives deliberation
    # (convergence loop / adversarial gate / tournament / exhaustive sweep).
    # Per-round budget enforcement happens inside the loop.
    log_info "Deliberation: running '${ORCH_SHAPE}' orchestration..."
    run_orchestration "$ORCH_SHAPE" "$OUTPUT_DIR" "$QUESTION_CATEGORY"
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
    --arg orch_mode "${ORCHESTRATION_MODE:-auto}" \
    --arg orch_shape "${ORCH_SHAPE:-fixed}" \
    --argjson complexity "${QUERY_COMPLEXITY:-5}" \
    --arg intent "${QUERY_INTENT:-advise}" \
    --arg cap_axis "$(get_category_axis "$QUESTION_CATEGORY" 2>/dev/null || echo "")" \
    --argjson cap_weighting "${ENABLE_CAPABILITY_WEIGHTING:-false}" \
    --argjson cap_routing "${ENABLE_CAPABILITY_ROUTING:-false}" \
    '{
        optimization_settings: {
            cache_enabled: $cache_enabled,
            cache_hits: $cache_hits,
            response_limits_enabled: $response_limits,
            cost_aware_routing: $cost_aware,
            debate_optimization: $debate_opt,
            compact_report: $compact
        },
        orchestration: {
            mode: $orch_mode,
            shape: $orch_shape,
            complexity: $complexity,
            intent: $intent
        },
        capability: {
            weighting_enabled: $cap_weighting,
            routing_enabled: $cap_routing,
            axis: $cap_axis
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
    # Budget Check: Before Synthesis
    if is_budget_enabled; then
        # Update current cost after debate
        if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
            CURRENT_COST=$(calculate_session_cost "$OUTPUT_DIR")
        fi
        SYNTHESIS_ESTIMATE=$(estimate_phase_cost "synthesis" 1 "$CONTEXT_SIZE")
        if ! enforce_budget "$CURRENT_COST" "$SYNTHESIS_ESTIMATE" "synthesis"; then
            log_warn "Skipping synthesis due to budget constraints"
            ENABLE_SYNTHESIS=false
        fi
    fi

    # Proceed with synthesis if still enabled after budget check
    if [[ "$ENABLE_SYNTHESIS" == "true" ]]; then
        log_info "Generating automatic synthesis..."
        SYNTHESIS_FILE="$OUTPUT_DIR/synthesis.json"

        if "$SCRIPT_DIR/synthesize.sh" "$OUTPUT_DIR" "$SYNTHESIS_FILE" "$QUERY" > /dev/null 2>&1; then
            log_success "Synthesis generated: $SYNTHESIS_FILE"
        else
            log_warn "Synthesis failed, using fallback"
        fi
        echo "" >&2
    fi
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
    echo "**Outcome**: ${QUORUM_OUTCOME:-MET} (${SUCCESS_COUNT}/${QUORUM_ATTEMPTED:-${#PIDS[@]}} responded, quorum=${QUORUM_MIN_EFF:-2})"
    echo "**Consensus**: ${CONSENSUS_SCORE}% ($CONSENSUS_LEVEL)"
    echo ""

    # Diagnosed failures (quorum grading, v2.19.0) — surface WHY consultants
    # dropped, so a degraded panel is visible instead of silently authoritative.
    if [[ ${#DIAGNOSED_FAILURES[@]} -gt 0 ]]; then
        echo "## Diagnosed Failures"
        echo ""
        if [[ "${QUORUM_OUTCOME:-MET}" == "FAILED" ]]; then
            echo "> ⚠️ Below quorum (${SUCCESS_COUNT}/${QUORUM_MIN_EFF:-2}). Treat the recommendation as low-confidence."
        elif [[ "${QUORUM_OUTCOME:-MET}" == "DEGRADED" ]]; then
            echo "> Some consultants did not respond — the panel ran with ${SUCCESS_COUNT}/${QUORUM_ATTEMPTED:-${#PIDS[@]}}."
        fi
        echo ""
        echo "| Consultant | Reason |"
        echo "|------------|--------|"
        for _df in "${DIAGNOSED_FAILURES[@]}"; do
            echo "$(render_diagnosed_failure "$_df" table)"
        done
        echo ""
    fi

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

        # Comparison table (dynamic: reads actual consultant names from synthesis JSON)
        echo "### Consultant Comparison"
        echo ""

        jq -r '
            (.comparison_table[0] // {} | keys | map(select(. != "aspect"))) as $cs |
            if ($cs | length) > 0 then
                (["Aspect"] + $cs | map("| \(.) ") | join("")) + "|",
                (["-"] + ($cs | map("-")) | map("|---") | join("")) + "|",
                (.comparison_table[]? | . as $row |
                    ([.aspect] + [$cs[] as $c | ($row[$c] // "N/A")] |
                     map("| \(.) ") | join("")) + "|")
            else
                "| (comparison data unavailable) |"
            end
        ' "$SYNTHESIS_FILE" 2>/dev/null || echo "| (comparison data unavailable) |"

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
                max_lines="${REPORT_MAX_JSON_LINES:-50}"
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
    log_info "Session cost: $(format_cost "$ACTUAL_COST")$(format_cost_caveats "$OUTPUT_DIR")"
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
