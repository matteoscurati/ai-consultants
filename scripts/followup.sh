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
            MODE="single"
            TARGET_CONSULTANT="$2"
            shift 2
            ;;
        --session|-s)
            SESSION_ID="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options] \"instruction\""
            echo ""
            echo "Options:"
            echo "  --clarify          Request clarification on a point of disagreement"
            echo "  --all              Send follow-up to all consultants"
            echo "  --consultant, -c   Send only to a specific consultant"
            echo "  --session, -s      Use a specific session (default: current)"
            echo "  --help, -h         Show this message"
            echo ""
            echo "Examples:"
            echo "  $0 \"Elaborate on the architecture point\""
            echo "  $0 --clarify \"Why do Codex and Mistral disagree?\""
            echo "  $0 -c Gemini \"Can you provide a code example?\""
            exit 0
            ;;
        *)
            INSTRUCTION="$1"
            shift
            ;;
    esac
done

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

        log_info "Follow-up to $TARGET_CONSULTANT..."

        case "$TARGET_CONSULTANT" in
            Gemini|gemini)
                "$SCRIPT_DIR/query_gemini.sh" "$FOLLOW_UP_CONTEXT" "" "$FOLLOW_UP_DIR/gemini.json"
                ;;
            Codex|codex)
                "$SCRIPT_DIR/query_codex.sh" "$FOLLOW_UP_CONTEXT" "" "$FOLLOW_UP_DIR/codex.json"
                ;;
            Mistral|mistral)
                "$SCRIPT_DIR/query_mistral.sh" "$FOLLOW_UP_CONTEXT" "" "$FOLLOW_UP_DIR/mistral.json"
                ;;
            Kilo|kilo)
                "$SCRIPT_DIR/query_kilo.sh" "$FOLLOW_UP_CONTEXT" "" "$FOLLOW_UP_DIR/kilo.json"
                ;;
            *)
                log_error "Unknown consultant: $TARGET_CONSULTANT"
                exit 1
                ;;
        esac
        ;;

    clarify)
        # Request clarification - focus on disagreement points
        CLARIFY_PROMPT="$FOLLOW_UP_CONTEXT

NOTE: This is a CLARIFICATION request on a point of disagreement between consultants.
Explain your reasoning in detail and why your position differs from others."

        log_info "Requesting clarification from all consultants..."
        "$SCRIPT_DIR/consult_all.sh" "$CLARIFY_PROMPT"
        ;;

    all|default)
        # Follow-up to all consultants
        log_info "Follow-up to all consultants..."
        "$SCRIPT_DIR/consult_all.sh" "$FOLLOW_UP_CONTEXT"
        ;;
esac

# =============================================================================
# UPDATE SESSION
# =============================================================================

# Record follow-up in session
add_follow_up "$INSTRUCTION" "$FOLLOW_UP_DIR"

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
