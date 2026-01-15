#!/bin/bash
# session.sh - Session state management for AI Consultants v2.0
#
# Manages session state to support follow-up queries
# and maintain context between successive consultations.

# =============================================================================
# CONFIGURATION
# =============================================================================

# Directory for session files
SESSION_DIR="${SESSION_DIR:-/tmp/ai_consultants_sessions}"
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

    jq -n \
        --arg id "$session_id" \
        --arg query "$query" \
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

# Get current session ID
# Usage: get_current_session_id
get_current_session_id() {
    if has_active_session; then
        jq -r '.id' "$SESSION_FILE"
    else
        echo ""
    fi
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

    jq --arg query "$follow_up_query" \
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

    jq --arg id "$session_id" \
       --arg query "$query_preview" \
       --arg dir "$responses_dir" \
       --arg cat "$category" \
       --arg ts "$timestamp" \
       '.sessions += [{id: $id, query_preview: $query, responses_dir: $dir, category: $cat, timestamp: $ts}]' \
       "$SESSION_HISTORY_FILE" > "${SESSION_HISTORY_FILE}.tmp" && \
       mv "${SESSION_HISTORY_FILE}.tmp" "$SESSION_HISTORY_FILE"
}

# Get last N sessions from history
# Usage: get_recent_sessions [count]
get_recent_sessions() {
    local count="${1:-5}"

    init_history

    jq --argjson n "$count" '.sessions | .[-$n:]' "$SESSION_HISTORY_FILE"
}

# Search session by ID
# Usage: get_session_by_id <session_id>
get_session_by_id() {
    local session_id="$1"

    init_history

    jq --arg id "$session_id" '.sessions[] | select(.id == $id)' "$SESSION_HISTORY_FILE"
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
            if [[ -f "$f" ]]; then
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

# =============================================================================
# CLEANUP
# =============================================================================

# Clear current session
# Usage: clear_current_session
clear_current_session() {
    rm -f "$SESSION_FILE"
}

# Clean up sessions older than N days
# Usage: cleanup_old_sessions [days]
cleanup_old_sessions() {
    local days="${1:-7}"

    # Clean up old output files
    find /tmp/ai_consultations -type d -mtime "+$days" -exec rm -rf {} \; 2>/dev/null || true

    # Remove old sessions from history
    init_history

    local cutoff=$(date -d "-$days days" -Iseconds 2>/dev/null || date -v-${days}d -Iseconds 2>/dev/null || echo "")

    if [[ -n "$cutoff" ]]; then
        jq --arg cutoff "$cutoff" '.sessions |= [.[] | select(.timestamp > $cutoff)]' \
            "$SESSION_HISTORY_FILE" > "${SESSION_HISTORY_FILE}.tmp" && \
            mv "${SESSION_HISTORY_FILE}.tmp" "$SESSION_HISTORY_FILE"
    fi
}

# =============================================================================
# DISPLAY
# =============================================================================

# Show current session info
# Usage: show_session_info
show_session_info() {
    if ! has_active_session; then
        echo "No active session"
        return
    fi

    local session=$(get_current_session)
    local id=$(echo "$session" | jq -r '.id')
    local query=$(echo "$session" | jq -r '.query')
    local timestamp=$(echo "$session" | jq -r '.timestamp')
    local follow_ups=$(echo "$session" | jq -r '.follow_ups | length')

    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Current Session                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  ID: $id"
    echo "  Query: ${query:0:50}..."
    echo "  Started: $timestamp"
    echo "  Follow-ups: $follow_ups"
    echo ""
}
