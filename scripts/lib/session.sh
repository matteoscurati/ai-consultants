#!/bin/bash
# session.sh - Session state management for AI Consultants v2.0
#
# Manages session state to support follow-up queries
# and maintain context between successive consultations.

# =============================================================================
# CONFIGURATION
# =============================================================================

# Directory for session files
SESSION_DIR="${SESSION_DIR:-${_AI_CONSULTANTS_XDG_STATE:-/tmp/ai_consultants}/sessions}"
SESSION_FILE="${SESSION_DIR}/current_session.json"
SESSION_HISTORY_FILE="${SESSION_DIR}/history.json"

# Create directory with secure permissions (owner-only access)
if [[ ! -d "$SESSION_DIR" ]]; then
    mkdir -p "$SESSION_DIR" 2>/dev/null || true
fi
chmod 700 "$SESSION_DIR" 2>/dev/null || true

# =============================================================================
# SESSION MANAGEMENT
# =============================================================================

# Generate new session ID
# Usage: generate_session_id
generate_session_id() {
    echo "session_$(date +%Y%m%d_%H%M%S)_$$"
}

# Save current session
# Usage: save_session <session_id> <query> <responses_dir> [category]
save_session() {
    local session_id="$1"
    local query="$2"
    local responses_dir="$3"
    local category="${4:-GENERAL}"

    local timestamp=$(date -Iseconds)

    # Create file with secure permissions before writing
    touch "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"

    # The question goes through stdin, never jq argv: a --query-file question
    # can exceed the single-argument limit (128 KiB on Linux).
    printf '%s' "$query" | jq -n \
        --arg id "$session_id" \
        --rawfile query /dev/stdin \
        --arg dir "$responses_dir" \
        --arg category "$category" \
        --arg timestamp "$timestamp" \
        '{
            id: $id,
            query: $query,
            responses_dir: $dir,
            category: $category,
            timestamp: $timestamp,
            follow_ups: []
        }' > "$SESSION_FILE"

    # Add to history
    add_to_history "$session_id" "$query" "$responses_dir" "$category"

    echo "$session_id"
}

# Get current session
# Usage: get_current_session
get_current_session() {
    if [[ -f "$SESSION_FILE" ]]; then
        cat "$SESSION_FILE"
    else
        echo "{}"
    fi
}

# Check if an active session exists
# Usage: has_active_session
has_active_session() {
    if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
        local id=$(jq -r '.id // empty' "$SESSION_FILE" 2>/dev/null)
        [[ -n "$id" ]] && return 0
    fi
    return 1
}

# Get query from current session
# Usage: get_current_query
get_current_query() {
    if has_active_session; then
        jq -r '.query' "$SESSION_FILE"
    else
        echo ""
    fi
}

# Get responses directory from current session
# Usage: get_current_responses_dir
get_current_responses_dir() {
    if has_active_session; then
        jq -r '.responses_dir' "$SESSION_FILE"
    else
        echo ""
    fi
}

# =============================================================================
# FOLLOW-UP MANAGEMENT
# =============================================================================

# Add follow-up to session
# Usage: add_follow_up <follow_up_query> <follow_up_responses_dir>
add_follow_up() {
    local follow_up_query="$1"
    local follow_up_dir="$2"

    if ! has_active_session; then
        return 1
    fi

    local timestamp=$(date -Iseconds)

    printf '%s' "$follow_up_query" | jq --rawfile query /dev/stdin \
       --arg dir "$follow_up_dir" \
       --arg ts "$timestamp" \
       '.follow_ups += [{query: $query, responses_dir: $dir, timestamp: $ts}]' \
       "$SESSION_FILE" > "${SESSION_FILE}.tmp" && \
       mv "${SESSION_FILE}.tmp" "$SESSION_FILE"
}

# Get number of follow-ups in session
# Usage: get_follow_up_count
get_follow_up_count() {
    if has_active_session; then
        jq -r '.follow_ups | length // 0' "$SESSION_FILE"
    else
        echo 0
    fi
}

# =============================================================================
# SESSION HISTORY
# =============================================================================

# Initialize history file if it doesn't exist
init_history() {
    if [[ ! -f "$SESSION_HISTORY_FILE" ]]; then
        # Create file with secure permissions before writing
        touch "$SESSION_HISTORY_FILE"
        chmod 600 "$SESSION_HISTORY_FILE"
        echo '{"sessions": []}' > "$SESSION_HISTORY_FILE"
    fi
}

# Add session to history
# Usage: add_to_history <session_id> <query> <responses_dir> <category>
add_to_history() {
    local session_id="$1"
    local query="$2"
    local responses_dir="$3"
    local category="$4"

    init_history

    local timestamp=$(date -Iseconds)
    local query_preview="${query:0:100}"

    # Keep the full query too: `followup.sh --session <id>` restores a session
    # from this record, and a 100-character preview is not the question. It
    # travels through stdin, not argv (see save_session).
    printf '%s' "$query" | jq --arg id "$session_id" \
       --arg query "$query_preview" \
       --rawfile full_query /dev/stdin \
       --arg dir "$responses_dir" \
       --arg cat "$category" \
       --arg ts "$timestamp" \
       '.sessions += [{id: $id, query: $full_query, query_preview: $query, responses_dir: $dir, category: $cat, timestamp: $ts}]' \
       "$SESSION_HISTORY_FILE" > "${SESSION_HISTORY_FILE}.tmp" && \
       mv "${SESSION_HISTORY_FILE}.tmp" "$SESSION_HISTORY_FILE"
}

# Search session by ID. Returns a record in the current-session shape, so it
# can be restored as $SESSION_FILE. History entries written before the full
# query was stored fall back to their preview.
# Usage: get_session_by_id <session_id>
get_session_by_id() {
    local session_id="$1"

    init_history

    jq --arg id "$session_id" '
        [.sessions[] | select(.id == $id)] | last
        | if . == null then empty else {
            id,
            query: (.query // .query_preview // ""),
            responses_dir,
            category: (.category // "GENERAL"),
            timestamp,
            follow_ups: (.follow_ups // [])
          } end' "$SESSION_HISTORY_FILE"
}

# =============================================================================
# CONTEXT BUILDING
# =============================================================================

# Build context from session for follow-up
# Usage: build_follow_up_context <follow_up_instruction>
build_follow_up_context() {
    local instruction="$1"

    if ! has_active_session; then
        echo "$instruction"
        return
    fi

    local session=$(get_current_session)
    local original_query=$(echo "$session" | jq -r '.query')
    local responses_dir=$(echo "$session" | jq -r '.responses_dir')

    local context="# Previous Session Context

## Original Question
$original_query

## Consultant Responses
"

    # Add response summaries
    if [[ -d "$responses_dir" ]]; then
        for f in "$responses_dir"/*.json; do
            # Only consultant envelopes: synthesis.json and
            # optimization_metrics.json are not responses.
            if [[ -f "$f" ]] && { ! declare -f _is_consultant_response_file >/dev/null 2>&1 \
                    || _is_consultant_response_file "$f"; }; then
                local consultant=$(jq -r '.consultant // "Unknown"' "$f" 2>/dev/null)
                local summary=$(jq -r '.response.summary // "No summary"' "$f" 2>/dev/null)
                local approach=$(jq -r '.response.approach // "unknown"' "$f" 2>/dev/null)

                context+="
### $consultant
Approach: $approach
Summary: $summary
"
            fi
        done
    fi

    # Add any previous follow-ups
    local follow_up_count=$(get_follow_up_count)
    if [[ $follow_up_count -gt 0 ]]; then
        context+="
## Previous Follow-ups
"
        echo "$session" | jq -r '.follow_ups[] | "- \(.query)"' >> /dev/null 2>&1 && \
            context+="$(echo "$session" | jq -r '.follow_ups[] | "- \(.query)"')"
    fi

    context+="

# New Request
$instruction"

    echo "$context"
}
