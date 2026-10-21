#!/bin/bash
# consult_all.sh - AI Consultants - Main Orchestrator
#
# Complete workflow for multi-model AI consultation with:
# - Specialized personas for each consultant
# - Explicit response quality, identity, and confidence metadata
# - Coverage-union synthesis with optional alternative strategies
# - Smart routing based on question category
# - Configuration presets for quick setup
# - Session management for follow-up
# - Cost tracking
#
# Usage: ./consult_all.sh [options] "Your question" [file1] [file2] ...
#
# Options:
#   --mode <name>        Use a public mode (preset plus default strategy)
#   --preset <name>      Use a configuration preset
#   --strategy <name>    Synthesis strategy
#   --list-presets       List available presets
#   --list-strategies    List available synthesis strategies
#   --help               Show this help message
#
# Environment variables:
#   ENABLE_SYNTHESIS=true    Enable automatic synthesis
#   ENABLE_SMART_ROUTING=true Select consultants based on question

set -euo pipefail

# --- Initial Setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=public_registry.sh
source "$SCRIPT_DIR/public_registry.sh"

# Help must remain registry-only (no user config), while still reporting the
# release version from the same read-only config source as the npm entry point.
PUBLIC_VERSION=$(grep -E '^AI_CONSULTANTS_VERSION=' "$SCRIPT_DIR/config.sh" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if ! [[ "$PUBLIC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    PUBLIC_VERSION="unknown"
fi

# --- Custom API Agent Discovery ---
# Discovers custom API agents from environment variables
# Convention: ENABLE_AGENTNAME=true with AGENTNAME_API_URL set
_discover_custom_api_agents() {
    local agent_name
    while IFS= read -r agent_name; do
        [[ -n "$agent_name" ]] || continue
        SELECTED_CONSULTANTS+=("$agent_name")
        log_debug "Discovered custom API agent: $agent_name"
    done < <(_list_custom_api_agents | sort -u)
}

# --- Show usage help ---
show_help() {
    echo "AI Consultants v${PUBLIC_VERSION} - Multi-Model AI Consultation"
    cat <<EOF

Usage: ./consult_all.sh [options] "Your question" [file1[@TAG]] [file2[@TAG]] ...

  File @TAG: PRIMARY (default, focus of question) or CONTEXT (ambient reference)

Options:
$(registry_render_help_options)

  --query-file <path>  Read the question from a file. Remaining positional
                       arguments are existing context-file paths, optionally
                       tagged @PRIMARY or @CONTEXT.
  --context-root <dir> Resolve host-provided relative context paths from this
                       project root and stage regular in-root files privately.
  --help, -h           Show this help message

Examples:
  ./consult_all.sh "How to optimize this SQL query?"
  ./consult_all.sh --mode fast-check "Quick question about Python lists"
  ./consult_all.sh --preset high-stakes --strategy risk_averse "Critical architecture decision"
  ./consult_all.sh "Review this code" src/main.py src/utils.py
  ./consult_all.sh "Compare auth approaches" src/auth.ts@PRIMARY src/logger.ts@CONTEXT
  ./consult_all.sh --query-file /tmp/long_question.txt src/big.py

Environment Variables:
  ENABLE_SYNTHESIS=true       Enable automatic synthesis
  ENABLE_SMART_ROUTING=true   Select consultants based on question category
  MAX_SESSION_COST=1.00       Maximum budget per session ($)

For more information, run: ./doctor.sh
EOF
}

# --- List synthesis strategies ---
list_strategies() {
    registry_list_strategies
}

list_modes() { registry_list_modes; }

# --- Argument Parsing ---
PRESET=""
# SYNTHESIS_STRATEGY in the environment is a documented per-run default; keep
# it below --strategy and a --mode default, above DEFAULT_STRATEGY.
ENV_SYNTHESIS_STRATEGY="${SYNTHESIS_STRATEGY:-}"
SYNTHESIS_STRATEGY=""
MODE=""
MODE_DEFAULT_STRATEGY=""
PRESET_EXPLICIT=false
STRATEGY_EXPLICIT=false
QUERY=""
QUERY_FILE=""
CONTEXT_ROOT=""
FILES=()
DISPLAY_FILES=()
POSITIONALS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            if [[ -n "${2:-}" ]]; then
                MODE="$2"
                shift 2
            else
                echo "Error: --mode requires a value" >&2
                exit 1
            fi
            ;;
        --preset)
            if [[ -n "${2:-}" ]]; then
                PRESET="$2"
                PRESET_EXPLICIT=true
                shift 2
            else
                echo "Error: --preset requires a value" >&2
                exit 1
            fi
            ;;
        --strategy)
            if [[ -n "${2:-}" ]]; then
                SYNTHESIS_STRATEGY="$2"
                STRATEGY_EXPLICIT=true
                shift 2
            else
                echo "Error: --strategy requires a value" >&2
                exit 1
            fi
            ;;
        --query-file)
            if [[ -n "${2:-}" && -f "$2" ]]; then
                QUERY_FILE="$2"
                shift 2
            else
                echo "Error: --query-file requires an existing file path" >&2
                exit 1
            fi
            ;;
        --context-root)
            if [[ -n "${2:-}" && -d "$2" && ! -L "$2" ]]; then
                CONTEXT_ROOT=$(cd "$2" && pwd -P)
                shift 2
            else
                echo "Error: --context-root requires an existing non-symlink directory" >&2
                exit 1
            fi
            ;;
        --list-presets)
            registry_list_presets
            exit 0
            ;;
        --list-strategies)
            registry_list_strategies
            exit 0
            ;;
        --list-modes)
            registry_list_modes
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            show_help
            exit 1
            ;;
        *)
            POSITIONALS+=("$1")
            shift
            ;;
    esac
done

# Validate public contract arguments before loading user configuration, making
# output directories, probing health, or considering any provider transport.
if [[ -n "$MODE" && "$PRESET_EXPLICIT" == "true" ]]; then
    echo "Error: --mode and --preset cannot be used together; choose one." >&2
    exit 1
fi
if [[ -n "$MODE" ]]; then
    if ! registry_mode_metadata "$MODE" >/dev/null; then
        echo "Error: unknown mode '$MODE'. Run --list-modes to see supported modes." >&2
        exit 1
    fi
    _mode_resolution=$(registry_resolve_mode "$MODE" "${SYNTHESIS_STRATEGY:-}")
    PRESET="${_mode_resolution%%|*}"
    MODE_DEFAULT_STRATEGY="${_mode_resolution#*|}"
    unset _mode_resolution
fi
if [[ -n "$PRESET" ]] && ! registry_canonical_preset "$PRESET" >/dev/null; then
    echo "Error: unknown preset '$PRESET'. Run --list-presets to see supported presets." >&2
    exit 1
fi
if [[ -n "$SYNTHESIS_STRATEGY" ]] && ! registry_strategy_metadata "$SYNTHESIS_STRATEGY" >/dev/null; then
    echo "Error: unknown strategy '$SYNTHESIS_STRATEGY'. Run --list-strategies to see supported strategies." >&2
    exit 1
fi
if [[ -n "$ENV_SYNTHESIS_STRATEGY" ]] && ! registry_strategy_metadata "$ENV_SYNTHESIS_STRATEGY" >/dev/null; then
    echo "Error: unknown SYNTHESIS_STRATEGY '$ENV_SYNTHESIS_STRATEGY'. Run --list-strategies to see supported strategies." >&2
    exit 1
fi

# Runtime libraries source config.sh. Deferring them keeps registry listings and
# invalid mode diagnostics side-effect-free with respect to user config.
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/progress.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/reliability.sh"
source "$SCRIPT_DIR/lib/routing.sh"
source "$SCRIPT_DIR/lib/cache.sh"

# Resolve query source. With --query-file, every positional argument is a
# context file; reject non-files so an accidental inline query cannot be
# silently reinterpreted as context. Without it, the first positional is the
# query and the rest are context files (the historical CLI contract).
if [[ -n "$QUERY_FILE" ]]; then
    QUERY=$(cat "$QUERY_FILE")
    FILES=(${POSITIONALS[@]+"${POSITIONALS[@]}"})
else
    if [[ ${#POSITIONALS[@]} -gt 0 ]]; then
        QUERY="${POSITIONALS[0]}"
    fi
    if [[ ${#POSITIONALS[@]} -gt 1 ]]; then
        FILES=("${POSITIONALS[@]:1}")
    fi
fi

# Resolve a context-file spec to a regular source file. When an agent host
# supplies --context-root, both relative and absolute inputs must remain inside
# that canonical project root. Symlinks are rejected before canonicalization so
# an in-tree link cannot smuggle an arbitrary secret into provider context.
_resolve_context_source() {
    local spec="$1" raw="$1" candidate canonical_dir canonical root="$CONTEXT_ROOT"
    if [[ -n "$root" && "$raw" != /* ]]; then
        candidate="$root/$raw"
    else
        candidate="$raw"
    fi
    if [[ ! -f "$candidate" && "$raw" == *@* ]]; then
        raw="${raw%@*}"
        [[ -n "$root" && "$raw" != /* ]] && candidate="$root/$raw" || candidate="$raw"
    fi
    [[ -f "$candidate" && ! -L "$candidate" ]] || return 1
    canonical_dir=$(cd "$(dirname "$candidate")" && pwd -P) || return 1
    canonical="$canonical_dir/$(basename "$candidate")"
    if [[ -n "$root" && "$canonical" != "$root"/* ]]; then
        return 1
    fi
    printf '%s' "$canonical"
}

# Validate every query-file positional as a real context file. This keeps an
# accidental inline query from being silently reinterpreted as a file while
# remaining safe for an empty array on stock macOS Bash 3.2.
if [[ -n "$QUERY_FILE" && ${#FILES[@]} -gt 0 ]]; then
    for _file_spec in "${FILES[@]}"; do
        if ! _resolve_context_source "$_file_spec" >/dev/null; then
            log_error "--query-file positional arguments must be existing permitted context files (got: $_file_spec)"
            exit 1
        fi
    done
    unset _file_spec
fi
DISPLAY_FILES=(${FILES[@]+"${FILES[@]}"})

# --- Apply Preset (CLI flag or default) ---
# Use CLI flag if provided, otherwise fall back to DEFAULT_PRESET
PRESET="${PRESET:-${DEFAULT_PRESET:-}}"
if [[ -n "$PRESET" ]]; then
    if ! apply_preset "$PRESET"; then
        exit 1
    fi
    log_info "Applied preset: $PRESET"
fi

# A public mode is a CLI selection: its default wins over persistent defaults,
# while an explicit --strategy remains the highest strategy selection.
if [[ "$STRATEGY_EXPLICIT" != "true" && -n "$MODE_DEFAULT_STRATEGY" ]]; then
    SYNTHESIS_STRATEGY="$MODE_DEFAULT_STRATEGY"
else
    SYNTHESIS_STRATEGY="${SYNTHESIS_STRATEGY:-${ENV_SYNTHESIS_STRATEGY:-${DEFAULT_STRATEGY:-$(registry_default_strategy)}}}"
fi
log_info "Synthesis strategy: $SYNTHESIS_STRATEGY${MODE:+ (mode: $MODE)}"

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
    QUESTION_CATEGORY=$(printf '%s' "$QUERY" | "$SCRIPT_DIR/classify_question.sh" - 2>/dev/null || echo "GENERAL")
    log_info "Category: $QUESTION_CATEGORY"
fi

# Complexity score (costs.sh) — used by opt-in cost-aware routing to pick cheaper
# models for simple queries. Not deliberation; just a routing signal.
QUERY_COMPLEXITY=$(calculate_query_complexity "$QUERY" "${#FILES[@]}" "$QUESTION_CATEGORY" 2>/dev/null || echo 5)

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
# Absolute from here on: build_context.sh runs from --context-root below, where
# a relative DEFAULT_OUTPUT_DIR_BASE would resolve to the wrong directory.
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

HOST_CONTEXT_STAGE=""
_cleanup_host_context_stage() {
    local runtime_base="${TMPDIR:-/tmp}"
    runtime_base="${runtime_base%/}"
    if [[ -n "$HOST_CONTEXT_STAGE" && -d "$HOST_CONTEXT_STAGE" \
        && "$HOST_CONTEXT_STAGE" == "$runtime_base"/ai-consultants-host-context.* ]]; then
        rm -rf -- "$HOST_CONTEXT_STAGE"
    fi
    HOST_CONTEXT_STAGE=""
}

# Agent hosts run the skill from its installation directory, while context
# files belong to the caller's project. Stage only regular files proven to be
# inside --context-root into a private temp directory; build_context.sh can then
# keep its strict temp/in-tree allowlist without granting arbitrary absolute
# filesystem reads.
if [[ -n "$CONTEXT_ROOT" && ${#FILES[@]} -gt 0 ]]; then
    _host_runtime_base="${TMPDIR:-/tmp}"
    _host_runtime_base="${_host_runtime_base%/}"
    HOST_CONTEXT_STAGE=$(mktemp -d "$_host_runtime_base/ai-consultants-host-context.XXXXXX")
    chmod 700 "$HOST_CONTEXT_STAGE"
    trap _cleanup_host_context_stage EXIT
    _staged_files=()
    for _file_spec in "${FILES[@]}"; do
        _source_path=$(_resolve_context_source "$_file_spec") || {
            log_error "Unable to stage context file: $_file_spec"
            exit 1
        }
        _source_candidate="$_file_spec"
        [[ "$_source_candidate" == /* ]] || _source_candidate="$CONTEXT_ROOT/$_source_candidate"
        _file_tag=""
        if [[ ! -f "$_source_candidate" && "$_file_spec" == *@* ]]; then
            _file_tag="${_file_spec##*@}"
        fi
        _relative_path="${_source_path#"$CONTEXT_ROOT"/}"
        _staged_path="$HOST_CONTEXT_STAGE/$_relative_path"
        mkdir -p "$(dirname "$_staged_path")"
        cp -- "$_source_path" "$_staged_path"
        chmod 600 "$_staged_path"
        if [[ -n "$_file_tag" ]]; then
            _staged_files+=("$_staged_path@$_file_tag")
        else
            _staged_files+=("$_staged_path")
        fi
    done
    FILES=("${_staged_files[@]}")
    unset _host_runtime_base _staged_files _file_spec _source_path \
        _source_candidate _file_tag _relative_path _staged_path
fi

log_info "Output: $OUTPUT_DIR"
log_info "Question: ${QUERY:0:80}$([ ${#QUERY} -gt 80 ] && echo '...')"
if [[ ${#DISPLAY_FILES[@]} -gt 0 ]]; then
    log_info "Files: ${DISPLAY_FILES[*]}"
fi
echo "" >&2

# --- Automatic Context Creation ---
log_info "Building automatic context..."
CONTEXT_FILE="$OUTPUT_DIR/context.md"
# Agent hosts cd into the skill root before running this script, so the
# caller's project is only known through --context-root. build_context.sh
# describes its working directory (pwd + project tree), so run it from that
# root; otherwise consultants receive the skill's own file tree as "the
# project". Staged files are absolute temp paths and remain valid there.
# QUESTION_CATEGORY is not exported, so pass it explicitly: build_context.sh
# omits the project tree for pointed categories (SECURITY, QUICK_SYNTAX, ...)
# and otherwise always sees GENERAL and lists the caller's files.
CONTEXT_BUILD_DIR="${CONTEXT_ROOT:-$PWD}"
if [[ ${#FILES[@]} -gt 0 ]]; then
    (cd "$CONTEXT_BUILD_DIR" && QUESTION_CATEGORY="$QUESTION_CATEGORY" CONTEXT_STAGE_ROOT="$HOST_CONTEXT_STAGE" \
        "$SCRIPT_DIR/build_context.sh" "$CONTEXT_FILE" - "${FILES[@]}") <<<"$QUERY" > /dev/null
else
    (cd "$CONTEXT_BUILD_DIR" && QUESTION_CATEGORY="$QUESTION_CATEGORY" \
        "$SCRIPT_DIR/build_context.sh" "$CONTEXT_FILE" -) <<<"$QUERY" > /dev/null
fi
log_success "Context created: $CONTEXT_FILE ($(wc -l < "$CONTEXT_FILE" | tr -d ' ') lines)"
if [[ -n "$HOST_CONTEXT_STAGE" ]]; then
    _cleanup_host_context_stage
    trap - EXIT
fi

# --- Cost Estimation (optional) ---
CONTEXT_SIZE=0
ESTIMATED_COST=0
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    CONTEXT_SIZE=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')
    # Generic default-rate estimate for the early budget check; the panel is
    # not selected yet, so the user-facing figure is the refined one below.
    ESTIMATED_COST=$(estimate_consultation_cost 4 "$CONTEXT_SIZE")
    log_debug "Preliminary estimate (4 consultants at the default rate): $(format_cost "$ESTIMATED_COST")"
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
PRESET_RAW_PANEL_SIZE=""
PRESET_EFFECTIVE_PANEL_SIZE=""

if [[ "$ENABLE_SMART_ROUTING" == "true" ]]; then
    log_info "Smart routing for category $QUESTION_CATEGORY..."
    while IFS= read -r c; do
        [[ -n "$c" ]] && SELECTED_CONSULTANTS+=("$c")
    done < <(select_consultants_cost_aware "$QUESTION_CATEGORY" "$QUERY_COMPLEXITY" "$MIN_AFFINITY")
    log_info "Selected consultants: ${SELECTED_CONSULTANTS[*]}"
else
    # Log self-exclusion status for debugging
    log_self_exclusion_status

    if [[ -n "$PRESET" ]]; then
        # A preset promises a fixed canonical panel.  Select only transports
        # that are statically configured, then fill a host-excluded slot from
        # the canonical roster.  This does no provider health probing.
        while IFS= read -r _name; do
            [[ -n "$_name" ]] && SELECTED_CONSULTANTS+=("$_name")
        done < <(select_preset_consultants "$PRESET")
        PRESET_RAW_PANEL_SIZE=$(get_preset_panel_size "$PRESET")
        PRESET_EFFECTIVE_PANEL_SIZE=$(get_effective_preset_panel_size "$PRESET")
    else
        # Explicit ENABLE_* selection keeps its existing semantics: enabled
        # consultants are selected even when no static transport check has
        # been requested by a preset.
        for _name in "${ALL_CONSULTANTS[@]}"; do
            _flag=$(to_upper "$_name")
            _enable_var="ENABLE_${_flag}"

            # Skip self (invoking agent shouldn't query itself)
            if should_skip_consultant "$_flag"; then
                log_debug "Skipping $_name (self-exclusion: invoking agent)"
                continue
            fi

            [[ "${!_enable_var:-false}" == "true" ]] && SELECTED_CONSULTANTS+=("$_name")
        done
        unset _flag _enable_var
    fi

    # Discover custom API agents from environment
    _discover_custom_api_agents

    # Custom API agents retain their existing behavior: they are appended to
    # the canonical preset panel and may satisfy its effective cardinality.
    # Canonical fallback itself remains limited to ALL_CONSULTANTS.
    if [[ -n "$PRESET_EFFECTIVE_PANEL_SIZE" && ${#SELECTED_CONSULTANTS[@]} -lt $PRESET_EFFECTIVE_PANEL_SIZE ]]; then
        log_preset_capacity_diagnostic "$PRESET" "$PRESET_RAW_PANEL_SIZE" "$PRESET_EFFECTIVE_PANEL_SIZE" "${#SELECTED_CONSULTANTS[@]}"
        exit 1
    fi
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

# A preset's static panel can still be reduced by the explicitly opt-in health
# gate. Preserve its effective target rather than silently running a smaller
# Round 1 panel.
if [[ -n "$PRESET_EFFECTIVE_PANEL_SIZE" && ${#SELECTED_CONSULTANTS[@]} -lt $PRESET_EFFECTIVE_PANEL_SIZE ]]; then
    log_preset_capacity_diagnostic "$PRESET" "$PRESET_RAW_PANEL_SIZE" "$PRESET_EFFECTIVE_PANEL_SIZE" "${#SELECTED_CONSULTANTS[@]}"
    exit 1
fi

if [[ ${#SELECTED_CONSULTANTS[@]} -eq 0 ]]; then
    log_error "No consultant enabled or selected"
    exit 1
fi

# Minimum 2 consultants required for a coverage panel
if [[ ${#SELECTED_CONSULTANTS[@]} -lt 2 ]]; then
    log_error "At least 2 consultants are required for a coverage panel."
    log_error "Currently enabled: ${#SELECTED_CONSULTANTS[@]} (${SELECTED_CONSULTANTS[*]})"
    echo "" >&2
    log_info "Run \"$SCRIPT_DIR/../bin/ai-consultants\" configure to configure additional consultants"
    log_info "Or manually enable more:"
    log_info "  ENABLE_GEMINI=true ENABLE_CODEX=true ./scripts/consult_all.sh \"query\""
    exit 1
fi

# --- Refined Cost Estimation (v2.4) ---
# Now that we know which consultants are selected, recalculate with accurate model rates
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    CONSULTANT_LIST=$(IFS=','; echo "${SELECTED_CONSULTANTS[*]}")
    ESTIMATED_COST=$(estimate_consultation_cost "${#SELECTED_CONSULTANTS[@]}" "$CONTEXT_SIZE" "$CONSULTANT_LIST")
    log_info "Estimated cost: $(format_cost "$ESTIMATED_COST") for ${#SELECTED_CONSULTANTS[@]} consultant(s), before synthesis and thinking tokens"

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
                model_var=$(model_env_var_for "$consultant_lower")
                if [[ ! "$model_var" =~ ^[A-Z0-9_]+_MODEL$ ]]; then
                    log_warn "Invalid model variable name: $model_var, skipping cost-aware override"
                    continue
                fi
                log_debug "Cost-aware: $consultant using model $local_model"
                (
                    trap '' INT
                    apply_launch_stagger
                    export "$model_var=$local_model"
                    "$query_script" "" "$CONTEXT_FILE" "$local_output_file"
                ) > /dev/null 2>"$local_err_file" &
                PIDS+=($!)
                update_progress "$consultant" 10 "running"
                continue
            fi
        fi
        # Standard launch (inherits current environment models). Every
        # consultant, escalation and synthesis job ignores SIGINT: a terminal
        # Ctrl-C reaches the whole process group, and only this script decides
        # what it means (proceed or abort) and stops their process trees.
        # Bash 3.2 ignores it in background jobs by itself; Bash 5 does not,
        # and an adapter killed by it would orphan its CLI.
        ( trap '' INT; apply_launch_stagger; "$query_script" "" "$CONTEXT_FILE" "$local_output_file" ) > /dev/null 2>"$local_err_file" &
    else
        # Fallback: custom API agent via generic API query
        (
            trap '' INT
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

# --- Host control while waiting ---
# Generation runs with no wall-clock limit unless a *_TIMEOUT is set, so the
# invoking host (an agent or a person) decides when to stop waiting:
#   proceed - stop the current phase (consultants, escalation or synthesis)
#             and continue with the answers already received:
#             touch "$OUTPUT_DIR/.proceed", kill -USR1 <pid>, or a first Ctrl-C
#   abort   - end the run, keeping the partial output directory:
#             touch "$OUTPUT_DIR/.abort", SIGTERM/SIGHUP, or a second Ctrl-C
# Stopped work is ended with its whole process tree so no CLI keeps running
# unobserved. A provider may still bill tokens it generated before the stop.
HOST_PROCEED_FILE="$OUTPUT_DIR/.proceed"
HOST_ABORT_FILE="$OUTPUT_DIR/.abort"
_HOST_PROCEED=false
_HOST_INTERRUPTS=0
_ACTIVE_CHILD_PIDS=""
WAIT_HEARTBEAT_SECONDS="${WAIT_HEARTBEAT_SECONDS:-30}"
[[ "$WAIT_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] || WAIT_HEARTBEAT_SECONDS=30
STOPPED_COUNT=0
SYNTHESIS_STOPPED=false

_track_child() { _ACTIVE_CHILD_PIDS="$_ACTIVE_CHILD_PIDS $1"; }
_untrack_child() {
    local p kept=""
    for p in $_ACTIVE_CHILD_PIDS; do
        [[ "$p" == "$1" ]] || kept="$kept $p"
    done
    _ACTIVE_CHILD_PIDS="$kept"
}

_abort_run() {
    local reason="$1" code="${2:-130}" p
    trap - INT TERM HUP USR1
    log_error "Consultation aborted ($reason); stopping the work still running..."
    for p in $_ACTIVE_CHILD_PIDS; do
        kill_process_tree "$p"
        wait "$p" 2>/dev/null || true
    done
    _ACTIVE_CHILD_PIDS=""
    log_info "Partial output kept in: $OUTPUT_DIR"
    exit "$code"
}

# A terminal Ctrl-C reaches the whole process group. If it ends a foreground
# command (jq, date) outside the wait loops, `set -e` exits before the trap
# can continue the run; even then no consultant CLI may keep running.
_stop_tracked_children() {
    local p
    for p in $_ACTIVE_CHILD_PIDS; do
        kill_process_tree "$p"
    done
    _ACTIVE_CHILD_PIDS=""
}

# One poll interval. A foreground `sleep` would die with a terminal Ctrl-C and
# `set -e` would end the run; an asynchronous one ignores SIGINT, and `wait`
# returns as soon as a trapped signal arrives.
_host_poll_pause() {
    sleep 1 &
    wait $! 2>/dev/null || true
}

_on_host_interrupt() {
    _HOST_INTERRUPTS=$((_HOST_INTERRUPTS + 1))
    if (( _HOST_INTERRUPTS > 1 )); then
        _abort_run "second interrupt"
    fi
    _HOST_PROCEED=true
    log_warn "Interrupt: continuing with the answers received so far (interrupt again to abort)"
}

trap _on_host_interrupt INT
trap '_HOST_PROCEED=true' USR1
trap '_abort_run SIGTERM 143' TERM
trap '_abort_run SIGHUP 129' HUP
trap _stop_tracked_children EXIT

_host_proceed_requested() {
    if [[ -e "$HOST_PROCEED_FILE" ]]; then
        rm -f "$HOST_PROCEED_FILE"
        _HOST_PROCEED=true
    fi
    [[ "$_HOST_PROCEED" == "true" ]]
}

_check_host_abort() {
    if [[ -e "$HOST_ABORT_FILE" ]]; then
        rm -f "$HOST_ABORT_FILE"
        _abort_run "abort requested by the host"
    fi
}

_host_control_hint() {
    log_info "  To continue with the answers received: touch \"$HOST_PROCEED_FILE\" (or kill -USR1 $$). To abort: touch \"$HOST_ABORT_FILE\"."
}

# A proceed request stops the phase that is running. One that arrives after
# that phase already finished (the last consultant answered in the same poll
# interval) must not stop the next phase, e.g. skip the synthesis.
# Usage: _discard_late_proceed <phase>
_discard_late_proceed() {
    if _host_proceed_requested; then
        _HOST_PROCEED=false
        log_info "Proceed request arrived after $1 had finished; it does not stop the next phase"
    fi
}

# Wait for one child under host control, with heartbeats.
# Usage: _wait_child_under_host_control <pid> <label>
# Returns the child's exit status, or 254 when the host asked to proceed and
# the child was stopped before it finished.
_wait_child_under_host_control() {
    local pid="$1" label="$2" started now last rc
    started=$(date +%s)
    last=$started
    _track_child "$pid"
    while kill -0 "$pid" 2>/dev/null; do
        _check_host_abort
        if _host_proceed_requested; then
            _HOST_PROCEED=false
            log_warn "Host requested to proceed: stopping $label after $(( $(date +%s) - started ))s"
            kill_process_tree "$pid"
            _untrack_child "$pid"
            # It may have finished in the instant before the stop.
            wait "$pid" 2>/dev/null && return 0
            return 254
        fi
        now=$(date +%s)
        if (( WAIT_HEARTBEAT_SECONDS > 0 && now - last >= WAIT_HEARTBEAT_SECONDS )); then
            last=$now
            log_info "Still waiting after $(( now - started ))s for: $label"
            _host_control_hint
        fi
        _host_poll_pause
    done
    _untrack_child "$pid"
    wait "$pid" 2>/dev/null && return 0
    rc=$?
    # A terminal Ctrl-C also reaches the child's CLI, which can exit before
    # the loop sees the request: that is a stop, not a failure.
    if _host_proceed_requested; then
        _HOST_PROCEED=false
        log_warn "Host requested to proceed: $label ended after $(( $(date +%s) - started ))s"
        return 254
    fi
    return "$rc"
}

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

# Record the outcome of Round 1 consultant <index> whose process exited <rc>.
_collect_round1_result() {
    local i="$1" rc="$2" name output_file name_lower response_content
    name="${NAMES[$i]}"
    output_file="${OUTPUT_FILES[$i]}"
    name_lower=$(to_lower "$name")

    if [[ "$rc" -eq 0 ]]; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK ($(wc -c < "$output_file" | tr -d ' ') bytes)"
            RESULTS[$i]="$name:OK"
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
            RESULTS[$i]="$name:EMPTY"
            update_progress "$name" 100 "failed"
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" fail 2>/dev/null || true
            fi
        fi
    else
        log_error "  $name: Failed"
        _surface_consultant_error "$name" "$output_file"
        RESULTS[$i]="$name:FAILED"
        update_progress "$name" 100 "failed"
        if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
            record_consultant_outcome "$name" fail 2>/dev/null || true
        fi
    fi
}

# Stop Round 1 consultant <index> because the host asked to proceed. Not a
# reliability failure: the consultant was still working.
_stop_round1_consultant() {
    local i="$1" elapsed="$2" output_file pid
    output_file="${OUTPUT_FILES[$i]}"
    pid="${PIDS[$i]}"
    kill_process_tree "$pid"
    _untrack_child "$pid"
    # It may have finished in the instant before the stop.
    if wait "$pid" 2>/dev/null && jq -e . "$output_file" >/dev/null 2>&1; then
        _collect_round1_result "$i" 0
        return
    fi
    _record_round1_stopped "$i" "$elapsed"
}

_record_round1_stopped() {
    local i="$1" elapsed="$2" name output_file
    name="${NAMES[$i]}"
    output_file="${OUTPUT_FILES[$i]}"
    # Never let a partial envelope reach synthesis, voting or cost.
    rm -f "$output_file"
    log_warn "  $name: Stopped by the host after ${elapsed}s"
    RESULTS[$i]="$name:STOPPED"
    STOPPED_COUNT=$((STOPPED_COUNT + 1))
    DIAGNOSED_FAILURES+=("${name}|stopped by the host after ${elapsed}s, before it answered (the provider may still bill what it generated)")
    update_progress "$name" 100 "stopped"
}

# --- Wait and Collect Results ---
log_info "Waiting for responses from ${#PIDS[@]} consultants (no timeout unless *_TIMEOUT is set)..."
_host_control_hint

declare -a RESULTS=()
declare -a DIAGNOSED_FAILURES=()
NETWORK_FAILURE_HINT=""
declare -a PENDING=()
SUCCESS_COUNT=0
WAIT_STARTED_AT=$(date +%s)

for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    name="${NAMES[$i]}"
    output_file="${OUTPUT_FILES[$i]}"

    # Handle cache hits (pid is "cache" marker)
    if [[ "$pid" == "cache" ]]; then
        if [[ -s "$output_file" ]]; then
            log_success "  $name: OK (cached)"
            RESULTS[$i]="$name:OK"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" success 2>/dev/null || true
            fi
        else
            log_warn "  $name: Cache miss"
            RESULTS[$i]="$name:EMPTY"
            if [[ "${ENABLE_RELIABILITY_TRACKING:-true}" == "true" ]]; then
                record_consultant_outcome "$name" fail 2>/dev/null || true
            fi
        fi
        continue
    fi
    PENDING+=("$i")
    _track_child "$pid"
done

# Poll instead of `wait`: Bash 3.2 has no `wait -n`, and a blocking wait on one
# consultant would delay the others' results and the host's requests.
# A terminal Ctrl-C also kills whatever short command (date, jq) the loop is
# running; under `set -e` that failure would end the run instead of letting
# the trap continue it, so the loop runs without errexit. (The single-child
# waits run in a `||` context, where errexit is already off.)
_last_heartbeat=$WAIT_STARTED_AT
set +e
while [[ ${#PENDING[@]} -gt 0 ]]; do
    # Handle host requests before collecting: a terminal Ctrl-C also reaches
    # the consultant CLIs, and one it ended was stopped, not failed.
    _check_host_abort
    if _host_proceed_requested; then
        _HOST_PROCEED=false
        _elapsed=$(( $(date +%s) - WAIT_STARTED_AT ))
        log_warn "Host requested to proceed: stopping ${#PENDING[@]} consultant(s) still running"
        for i in "${PENDING[@]}"; do
            _stop_round1_consultant "$i" "$_elapsed"
        done
        PENDING=()
        break
    fi

    _still_running=()
    for i in "${PENDING[@]}"; do
        pid="${PIDS[$i]}"
        if kill -0 "$pid" 2>/dev/null; then
            _still_running+=("$i")
            continue
        fi
        if wait "$pid" 2>/dev/null; then _rc=0; else _rc=$?; fi
        _untrack_child "$pid"
        # A terminal Ctrl-C reaches the consultant CLIs and this script at
        # once. One the interrupt ended can finish after this pass's host
        # check: it was stopped, not failed. (The next pass stops the rest.)
        if (( _rc != 0 )) && [[ "$_HOST_PROCEED" == "true" ]]; then
            _record_round1_stopped "$i" "$(( $(date +%s) - WAIT_STARTED_AT ))"
            continue
        fi
        _collect_round1_result "$i" "$_rc"
    done
    PENDING=("${_still_running[@]+"${_still_running[@]}"}")
    [[ ${#PENDING[@]} -gt 0 ]] || break

    _now=$(date +%s)
    if (( WAIT_HEARTBEAT_SECONDS > 0 && _now - _last_heartbeat >= WAIT_HEARTBEAT_SECONDS )); then
        _last_heartbeat=$_now
        _waiting_for=""
        for i in "${PENDING[@]}"; do
            _waiting_for="${_waiting_for:+$_waiting_for, }${NAMES[$i]}"
        done
        log_info "Still waiting after $(( _now - WAIT_STARTED_AT ))s for: $_waiting_for"
        _host_control_hint
    fi
    _host_poll_pause
done
set -e
unset _still_running _rc _elapsed _now _waiting_for _last_heartbeat
_discard_late_proceed "the consultants"

echo "" >&2

# --- Quorum Grading (v2.19.0) ---
# Grade the run by how many consultants actually responded, so a silently-shrunk
# panel is reported as DEGRADED/FAILED instead of presenting as authoritative.
QUORUM_ATTEMPTED=${#PIDS[@]}
QUORUM_MIN_EFF="${QUORUM_MIN:-2}"
QUORUM_OUTCOME=$(grade_quorum "$SUCCESS_COUNT" "$QUORUM_ATTEMPTED" "$QUORUM_MIN_EFF")
NETWORK_FAILURE_HINT=$(diagnosed_failures_network_hint "${DIAGNOSED_FAILURES[@]+"${DIAGNOSED_FAILURES[@]}"}")
[[ -z "$NETWORK_FAILURE_HINT" ]] || log_warn "$NETWORK_FAILURE_HINT"

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

        # Only a real low-confidence answer is worth a premium re-query: an
        # error envelope failed for a transport reason, and a fallback
        # envelope carries a synthetic confidence of 5.
        response_quality=$(jq -r '.metadata.response_quality // "unknown"' "$response_file" 2>/dev/null || echo unknown)
        [[ "$response_quality" == "structured" ]] || continue

        if needs_escalation "$response_file"; then
            premium_model=$(get_premium_model "$consultant_lower")
            model_var=$(model_env_var_for "$consultant_lower")
            if [[ ! "$model_var" =~ ^[A-Z0-9_]+_MODEL$ ]]; then
                log_warn "Invalid model variable name: $model_var, skipping escalation for $consultant"
                continue
            fi
            # Compare with the model that actually answered. A cost-aware
            # economy override exists only in the Round 1 launch subshell, so
            # the configured variable still names the premium model here.
            current_model=$(jq -r '.metadata.requested_model // .model // empty' "$response_file" 2>/dev/null || true)
            [[ -n "$current_model" ]] || current_model="${!model_var:-}"
            # Never re-ask the same model, and never "escalate" away from a
            # maximum-tier target (premium can be a smaller model).
            if [[ -n "$premium_model" && "$premium_model" != "$current_model" \
                && "$current_model" != "$(get_model_for_tier "$consultant_lower" maximum)" ]]; then
                original_confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
                [[ "$original_confidence" =~ ^[0-9]+$ ]] || original_confidence=5
                log_info "Escalating $consultant (confidence: $original_confidence) → premium model: $premium_model"

                query_script="$SCRIPT_DIR/query_${consultant_lower}.sh"
                if [[ -x "$query_script" ]] && is_budget_enabled; then
                    # Price the premium re-query (not the model that already
                    # answered), and count it before the next escalation is
                    # checked so several escalations cannot each pass alone.
                    ESCALATION_ESTIMATE=$(export "$model_var=$premium_model"; estimate_consultation_cost 1 "$CONTEXT_SIZE" "$consultant")
                    [[ -n "$ESCALATION_ESTIMATE" ]] || ESCALATION_ESTIMATE=0
                    if ! enforce_budget "$CURRENT_COST" "$ESCALATION_ESTIMATE" "escalation of $consultant"; then
                        log_warn "Skipping escalation of $consultant due to budget constraints"
                        continue
                    fi
                    CURRENT_COST=$(echo "scale=6; ${CURRENT_COST:-0} + $ESCALATION_ESTIMATE" | bc)
                fi
                if [[ -x "$query_script" ]]; then
                    escalation_file="$OUTPUT_DIR/${consultant_lower}_escalated.json"
                    (
                        trap '' INT
                        export "$model_var=$premium_model"
                        "$query_script" "" "$CONTEXT_FILE" "$escalation_file"
                    ) > /dev/null 2>&1 &
                    escalation_rc=0
                    _wait_child_under_host_control $! "escalation of $consultant" || escalation_rc=$?
                    if [[ $escalation_rc -eq 254 ]]; then
                        # A proceed request ends the whole escalation phase:
                        # keep the original answers, drop any partial
                        # re-query and start no further (billed) re-queries.
                        rm -f "$escalation_file"
                        log_warn "  $consultant escalation stopped by the host; keeping the original answers and skipping the remaining escalations"
                        break
                    fi

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
    _discard_late_proceed "the escalation"
fi

# --- Quality Monitoring (v2.3) ---
# Log optimization metrics for quality tracking
if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
    log_debug "=== Token Optimization Metrics ==="
    log_debug "  Cache enabled: ${ENABLE_SEMANTIC_CACHE:-true}"
    log_debug "  Cache hits: ${#CACHE_HITS[@]}"
    log_debug "  Response limits enabled: ${ENABLE_RESPONSE_LIMITS:-false}"
    log_debug "  Cost-aware routing: ${ENABLE_COST_AWARE_ROUTING:-false}"
fi

# Save optimization metrics to output directory. Flags are normalized to JSON
# booleans first: a hand-typed value such as TRUE or yes must not make
# `jq --argjson` abort the run after every consultant has been billed.
_json_bool() { [[ "$1" == "true" ]] && echo true || echo false; }
jq -n \
    --argjson cache_enabled "$(_json_bool "${ENABLE_SEMANTIC_CACHE:-true}")" \
    --argjson cache_hits "${#CACHE_HITS[@]}" \
    --argjson response_limits "$(_json_bool "${ENABLE_RESPONSE_LIMITS:-false}")" \
    --argjson cost_aware "$(_json_bool "${ENABLE_COST_AWARE_ROUTING:-false}")" \
    --argjson compact "$(_json_bool "${ENABLE_COMPACT_REPORT:-true}")" \
    --argjson success_count "$SUCCESS_COUNT" \
    --argjson total "${#PIDS[@]}" \
    --arg category "$QUESTION_CATEGORY" \
    '{
        optimization_settings: {
            cache_enabled: $cache_enabled,
            cache_hits: $cache_hits,
            response_limits_enabled: $response_limits,
            cost_aware_routing: $cost_aware,
            compact_report: $compact
        },
        quality_metrics: {
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
        # Refresh current cost before estimating synthesis.
        if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
            CURRENT_COST=$(calculate_session_cost "$OUTPUT_DIR")
        fi
        SYNTHESIS_ESTIMATE=$(estimate_phase_cost "synthesis" "$SUCCESS_COUNT" "$CONTEXT_SIZE")
        if ! enforce_budget "$CURRENT_COST" "$SYNTHESIS_ESTIMATE" "synthesis"; then
            log_warn "Skipping synthesis due to budget constraints"
            ENABLE_SYNTHESIS=false
        fi
    fi

    # Proceed with synthesis if still enabled after budget check
    if [[ "$ENABLE_SYNTHESIS" == "true" ]]; then
        log_info "Generating automatic synthesis..."
        SYNTHESIS_FILE="$OUTPUT_DIR/synthesis.json"

        ( trap '' INT; printf '%s' "$QUERY" | "$SCRIPT_DIR/synthesize.sh" "$OUTPUT_DIR" "$SYNTHESIS_FILE" - > /dev/null ) &
        synthesis_rc=0
        _wait_child_under_host_control $! "synthesis" || synthesis_rc=$?
        if [[ $synthesis_rc -eq 0 ]]; then
            log_success "Synthesis generated: $SYNTHESIS_FILE"
        elif [[ $synthesis_rc -eq 254 ]]; then
            # A partial synthesis must not be presented as the panel's answer.
            rm -f "$SYNTHESIS_FILE"
            SYNTHESIS_FILE=""
            SYNTHESIS_STOPPED=true
            log_warn "Synthesis stopped by the host; the report lists the answers without a synthesis (the provider may still bill the call)"
        else
            log_warn "Synthesis failed, using fallback"
        fi
        echo "" >&2
    fi
fi

# Nothing below waits on a child: restore default signal handling.
trap - INT TERM HUP USR1 EXIT
rm -f "$HOST_PROCEED_FILE"


# --- Generate Combined Report ---
log_info "Generating combined report..."

REPORT_FILE="$OUTPUT_DIR/report.md"

{
    echo "# AI Consultation Report"
    echo ""
    echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**Directory**: $CONTEXT_BUILD_DIR"
    echo "**Version**: AI Consultants v${AI_CONSULTANTS_VERSION}"
    echo "**Category**: $QUESTION_CATEGORY"
    echo "**Outcome**: ${QUORUM_OUTCOME:-MET} (${SUCCESS_COUNT}/${QUORUM_ATTEMPTED:-${#PIDS[@]}} responded, quorum=${QUORUM_MIN_EFF:-2})"
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
        if [[ -n "$NETWORK_FAILURE_HINT" ]]; then
            echo "> $NETWORK_FAILURE_HINT"
            echo ""
        fi
    fi

    echo "---"
    echo ""

    # Question
    echo "## Question"
    echo ""
    echo "$QUERY"
    echo ""

    # Included files
    if [[ ${#DISPLAY_FILES[@]} -gt 0 ]]; then
        echo "## Analyzed Files"
        echo ""
        for f in "${DISPLAY_FILES[@]}"; do
            echo "- \`$f\`"
        done
        echo ""
    fi

    # Quick Summary Table (v2.3)
    echo "## Quick Summary"
    echo ""
    echo "| Consultant | Quality | Confidence | Approach |"
    echo "|------------|---------|------------|----------|"
    for i in "${!NAMES[@]}"; do
        name="${NAMES[$i]}"
        output_file="${OUTPUT_FILES[$i]}"
        result="${RESULTS[$i]}"
        if [[ "$result" == *":OK" ]] && [[ -s "$output_file" ]]; then
            conf=$(jq -r '.confidence.score // "?"' "$output_file" 2>/dev/null)
            quality=$(jq -r '.metadata.response_quality // "unknown"' "$output_file" 2>/dev/null)
            appr=$(jq -r '.response.approach // "N/A"' "$output_file" 2>/dev/null | head -c 30)
            echo "| $name | $quality | $conf/10 | $appr |"
        elif [[ "$result" == *":STOPPED" ]]; then
            echo "| $name | stopped | - | (stopped by the host) |"
        else
            echo "| $name | error | - | (no response) |"
        fi
    done
    echo ""

    echo "---"
    echo ""

    if [[ "$SYNTHESIS_STOPPED" == "true" ]]; then
        echo "## Automatic Synthesis"
        echo ""
        echo "*Stopped by the host before it finished. Review the individual answers below.*"
        echo ""
    fi

    # Synthesis (if available)
    if [[ -n "$SYNTHESIS_FILE" && -f "$SYNTHESIS_FILE" ]]; then
        echo "## Automatic Synthesis"
        echo ""

        synthesis_provider=$(jq -r '.synthesis_provider // "unknown"' "$SYNTHESIS_FILE" 2>/dev/null)
        echo "**Synthesis Provider**: $synthesis_provider"
        echo ""

        integrity_status=$(jq -r '.coverage_integrity.status // "UNKNOWN"' "$SYNTHESIS_FILE" 2>/dev/null)
        integrity_expected=$(jq -r '.coverage_integrity.expected_count // 0' "$SYNTHESIS_FILE" 2>/dev/null)
        integrity_represented=$(jq -r '.coverage_integrity.represented_count // 0' "$SYNTHESIS_FILE" 2>/dev/null)
        integrity_disclosure=$(jq -r '.coverage_integrity.disclosure // "Coverage integrity was not recorded."' "$SYNTHESIS_FILE" 2>/dev/null)
        integrity_fields=$(jq -r '(.coverage_integrity.audited_fields // []) | join(", ")' "$SYNTHESIS_FILE" 2>/dev/null)
        coverage_input_truncated=$(jq -r '.coverage_input_truncated // false' "$SYNTHESIS_FILE" 2>/dev/null)
        truncated_consultants=$(jq -r '(.truncated_consultants // []) | join(", ")' "$SYNTHESIS_FILE" 2>/dev/null)
        echo "**Coverage Integrity**: $integrity_status ($integrity_represented/$integrity_expected normalized source IDs represented)"
        echo "**Audited Fields**: ${integrity_fields:-none} (MET applies only to these fields)"
        echo "**Coverage Input Truncated**: $coverage_input_truncated"
        echo "**Truncated Consultants**: ${truncated_consultants:-none}"
        echo ""
        echo "> $integrity_disclosure"
        echo ""

        recommendation=$(jq -r '.weighted_recommendation.summary // "N/A"' "$SYNTHESIS_FILE" 2>/dev/null)
        approach=$(jq -r '.weighted_recommendation.approach // "N/A"' "$SYNTHESIS_FILE" 2>/dev/null)

        echo "**Recommended Approach**: $approach"
        echo ""
        echo "$recommendation"
        echo ""

        echo "### Coverage Union"
        echo ""

        jq -r '
            if ((.coverage // []) | length) > 0 then
                .coverage[] |
                "- **\(.kind // "consideration")**: \(.point) — raised by \((.raised_by // []) | join(", "))"
            else
                "- (coverage data unavailable; see individual responses)"
            end
        ' "$SYNTHESIS_FILE" 2>/dev/null || echo "- (coverage data unavailable; see individual responses)"

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
        elif [[ "$result" == *":STOPPED" ]]; then
            echo "*Stopped by the host before it answered*"
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
    [[ -n "$SYNTHESIS_FILE" ]] && echo "- Synthesis: \`$SYNTHESIS_FILE\`"
    for i in "${!NAMES[@]}"; do
        echo "- ${NAMES[$i]}: \`${OUTPUT_FILES[$i]}\`"
    done

} > "$REPORT_FILE"

log_success "Report generated: $REPORT_FILE"
echo "" >&2

# --- Session Management ---
# followup.sh runs a whole-panel follow-up through this script and records it
# on the ORIGINAL session; it sets AI_CONSULTANTS_SKIP_SESSION_SAVE so this run
# does not replace the current session.
if [[ "${AI_CONSULTANTS_SKIP_SESSION_SAVE:-false}" == "true" ]]; then
    SESSION_ID=$(generate_session_id)
    log_debug "Session save skipped (follow-up run): $SESSION_ID"
else
    SESSION_ID=$(save_session "$(generate_session_id)" "$QUERY" "$OUTPUT_DIR" "$QUESTION_CATEGORY")
    log_info "Session saved: $SESSION_ID"
fi

# --- Cost Tracking ---
if [[ "$ENABLE_COST_TRACKING" == "true" ]]; then
    ACTUAL_COST=$(calculate_session_cost "$OUTPUT_DIR")
    track_session_cost "$SESSION_ID" "$ACTUAL_COST"
    log_info "Session cost: $(format_cost "$ACTUAL_COST")$(format_cost_caveats "$OUTPUT_DIR")"
    if [[ $STOPPED_COUNT -gt 0 || "$SYNTHESIS_STOPPED" == "true" ]]; then
        log_warn "Session cost excludes work stopped by the host; providers may still bill the tokens it generated"
    fi
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
        STOPPED) log_warn "  - $name: Stopped by the host" ;;
    esac
done
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
