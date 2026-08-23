#!/bin/bash
# followup.sh - Follow-up queries for AI Consultants v2.0
#
# Allows continuing a previous consultation with follow-up
# questions that maintain context.
#
# Usage:
#   ./followup.sh "Ask Gemini to elaborate on point X"
#   ./followup.sh --clarify "Codex and Mistral disagree on Y"
#   ./followup.sh --all "Reformulate with focus on performance"
#   ./followup.sh --session <session_id> "Question"
#   ./followup.sh --query-file <private_file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/session.sh"

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

MODE="default"
TARGET_CONSULTANT=""
SESSION_ID=""
INSTRUCTION=""
INSTRUCTION_FILE=""
POSITIONAL_INSTRUCTIONS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clarify)
            MODE="clarify"
            shift
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --consultant|-c)
            [[ -n "${2:-}" ]] || { log_error "$1 requires a consultant"; exit 1; }
            MODE="single"
            TARGET_CONSULTANT="$2"
            shift 2
            ;;
        --session|-s)
            [[ -n "${2:-}" ]] || { log_error "$1 requires a session ID"; exit 1; }
            SESSION_ID="$2"
            shift 2
            ;;
        --query-file)
            if [[ -n "${2:-}" && -f "$2" ]]; then
                INSTRUCTION_FILE="$2"
                shift 2
            else
                log_error "--query-file requires an existing file path"
                exit 1
            fi
            ;;
        --help|-h)
            echo "Usage: $0 [options] \"instruction\""
            echo ""
            echo "Options:"
            echo "  --clarify          Request clarification on a point of disagreement"
            echo "  --all              Send follow-up to all consultants"
            echo "  --consultant, -c   Send only to a specific consultant"
            echo "  --session, -s      Use a specific session (default: current)"
            echo "  --query-file       Read the follow-up instruction from a file"
            echo "  --help, -h         Show this message"
            echo ""
            echo "Examples:"
            echo "  $0 \"Elaborate on the architecture point\""
            echo "  $0 --clarify \"Why do Codex and Mistral disagree?\""
            echo "  $0 -c Gemini \"Can you provide a code example?\""
            exit 0
            ;;
        *)
            POSITIONAL_INSTRUCTIONS+=("$1")
            shift
            ;;
    esac
done

# Resolve the instruction source before session work. Follow-ups have no
# context-file positional arguments, so --query-file conflicts with any
# positional text instead of silently reinterpreting it.
if [[ -n "$INSTRUCTION_FILE" ]]; then
    if [[ ${#POSITIONAL_INSTRUCTIONS[@]} -gt 0 ]]; then
        log_error "--query-file conflicts with a positional follow-up instruction"
        exit 1
    fi
    INSTRUCTION=$(cat "$INSTRUCTION_FILE")
elif [[ ${#POSITIONAL_INSTRUCTIONS[@]} -eq 1 ]]; then
    INSTRUCTION="${POSITIONAL_INSTRUCTIONS[0]}"
elif [[ ${#POSITIONAL_INSTRUCTIONS[@]} -gt 1 ]]; then
    log_error "Pass the follow-up instruction as one quoted argument or use --query-file"
    exit 1
fi

# =============================================================================
# VALIDATION
# =============================================================================

if [[ -z "$INSTRUCTION" ]]; then
    log_error "Follow-up instruction required"
    log_info "Usage: $0 \"instruction\""
    exit 1
fi

# Load specific session if requested
if [[ -n "$SESSION_ID" ]]; then
    session_data=$(get_session_by_id "$SESSION_ID")
    if [[ -z "$session_data" || "$session_data" == "null" ]]; then
        log_error "Session '$SESSION_ID' not found"
        exit 1
    fi
    # Set as current session
    echo "$session_data" > "$SESSION_FILE"
fi

# Verify there's an active session
if ! has_active_session; then
    log_error "No active session. Run a consultation first."
    log_info "Use: ./consult_all.sh \"question\""
    exit 1
fi

# =============================================================================
# BUILD FOLLOW-UP CONTEXT
# =============================================================================

log_info "Building follow-up context..."

ORIGINAL_QUERY=$(get_current_query)
RESPONSES_DIR=$(get_current_responses_dir)

if [[ ! -d "$RESPONSES_DIR" ]]; then
    log_error "Responses directory not found: $RESPONSES_DIR"
    exit 1
fi

# Build complete context
FOLLOW_UP_CONTEXT=$(build_follow_up_context "$INSTRUCTION")

FOLLOWUP_CONTEXT_FILE=""
_cleanup_followup_context_file() {
    local runtime_base="${TMPDIR:-/tmp}"
    runtime_base="${runtime_base%/}"
    if [[ -n "$FOLLOWUP_CONTEXT_FILE" && -f "$FOLLOWUP_CONTEXT_FILE" \
        && "$FOLLOWUP_CONTEXT_FILE" == "$runtime_base"/ai-consultants-followup.* ]]; then
        rm -f -- "$FOLLOWUP_CONTEXT_FILE"
    fi
    FOLLOWUP_CONTEXT_FILE=""
}
_followup_runtime_base="${TMPDIR:-/tmp}"
_followup_runtime_base="${_followup_runtime_base%/}"
FOLLOWUP_CONTEXT_FILE=$(mktemp "$_followup_runtime_base/ai-consultants-followup.XXXXXX")
chmod 600 "$FOLLOWUP_CONTEXT_FILE"
printf '%s' "$FOLLOW_UP_CONTEXT" > "$FOLLOWUP_CONTEXT_FILE"
trap _cleanup_followup_context_file EXIT
unset _followup_runtime_base

# =============================================================================
# EXECUTE FOLLOW-UP
# =============================================================================

# Directory for follow-up output
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FOLLOW_UP_DIR="${RESPONSES_DIR}/followup_${TIMESTAMP}"
mkdir -p "$FOLLOW_UP_DIR"

log_info "Executing follow-up (mode: $MODE)..."

case "$MODE" in
    single)
        # Follow-up to a single consultant
        if [[ -z "$TARGET_CONSULTANT" ]]; then
            log_error "Specify consultant with -c/--consultant"
            exit 1
        fi

        _target_lower=$(to_lower "$TARGET_CONSULTANT")
        case "$_target_lower" in
            qwen) _target_lower=qwen3 ;;
            gemini|codex|mistral|kimi|claude|qwen3|glm|grok|deepseek|minimax) ;;
            *)
                log_error "Unknown consultant: $TARGET_CONSULTANT"
                exit 1
                ;;
        esac

        if should_skip_consultant "$_target_lower"; then
            log_error "Refusing follow-up self-consultation: $TARGET_CONSULTANT is the invoking agent"
            exit 1
        fi

        _target_enable_var="ENABLE_$(to_upper "$_target_lower")"
        if [[ "${!_target_enable_var:-false}" != "true" ]]; then
            log_error "Consultant is disabled: $TARGET_CONSULTANT"
            exit 1
        fi

        _target_script="$SCRIPT_DIR/query_${_target_lower}.sh"
        if [[ ! -x "$_target_script" ]]; then
            log_error "Consultant adapter unavailable: $TARGET_CONSULTANT"
            exit 1
        fi

        log_info "Follow-up to $TARGET_CONSULTANT..."
        "$_target_script" "" "$FOLLOWUP_CONTEXT_FILE" "$FOLLOW_UP_DIR/${_target_lower}.json"
        unset _target_lower _target_script _target_enable_var
        ;;

    clarify)
        # Request clarification - focus on disagreement points
        CLARIFY_PROMPT="$FOLLOW_UP_CONTEXT

NOTE: This is a CLARIFICATION request on a point of disagreement between consultants.
Explain your reasoning in detail and why your position differs from others."
        printf '%s' "$CLARIFY_PROMPT" > "$FOLLOWUP_CONTEXT_FILE"

        log_info "Requesting clarification from all consultants..."
        "$SCRIPT_DIR/consult_all.sh" --query-file "$FOLLOWUP_CONTEXT_FILE"
        ;;

    all|default)
        # Follow-up to all consultants
        log_info "Follow-up to all consultants..."
        "$SCRIPT_DIR/consult_all.sh" --query-file "$FOLLOWUP_CONTEXT_FILE"
        ;;
esac

# =============================================================================
# UPDATE SESSION
# =============================================================================

# Record follow-up in session
add_follow_up "$INSTRUCTION" "$FOLLOW_UP_DIR"
_cleanup_followup_context_file
trap - EXIT

log_success "Follow-up completed"
log_info "Responses in: $FOLLOW_UP_DIR"

# Show summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Follow-up Summary                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Original query: ${ORIGINAL_QUERY:0:50}..."
echo "  Follow-up: ${INSTRUCTION:0:50}..."
echo "  Mode: $MODE"
echo "  Total follow-ups in session: $(get_follow_up_count)"
echo ""

# Output directory for calling scripts
echo "$FOLLOW_UP_DIR"
