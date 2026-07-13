#!/bin/bash
# reliability.sh - Persistent per-consultant reliability tracking
#
# Records whether each consultant responds successfully on every run and
# exposes a rolling success rate. This is bookkeeping, not control flow: the
# recording path mirrors lib/costs.sh::track_session_cost exactly (best-effort,
# lock + mktemp + corrupt-file self-heal, never aborts a run).
#
# Foundation for a future self-tuning roster (auto-weighting/pruning is a
# follow-up, NOT implemented here).

# File for cumulative tracking (XDG-aware, mirrors COST_TRACKING_FILE in costs.sh)
RELIABILITY_FILE="${RELIABILITY_FILE:-${_AI_CONSULTANTS_XDG_DATA:-/tmp/ai_consultants}/reliability.json}"

# Record a consultant outcome (success or fail) for this run.
# Usage: record_consultant_outcome <consultant> <success|fail>
# Best-effort: never propagates failure to the caller. Mirrors
# track_session_cost's locking/hardening exactly.
record_consultant_outcome() {
    local consultant="$1"
    local outcome="$2"

    # The XDG data dir may not exist yet on a fresh install
    if ! mkdir -p "$(dirname "$RELIABILITY_FILE")" 2>/dev/null; then
        log_warn "Reliability tracking skipped: cannot create $(dirname "$RELIABILITY_FILE")"
        return 0
    fi

    # Serialize the read-modify-write against concurrent consultations with a
    # portable mkdir lock (flock is unavailable on macOS). Bounded wait, then
    # proceed unlocked: bookkeeping must never block or abort the run.
    local lock_dir="${RELIABILITY_FILE}.lock" locked=false _i
    for _i in {1..50}; do
        if mkdir "$lock_dir" 2>/dev/null; then locked=true; break; fi
        sleep 0.1
    done
    if [[ "$locked" != "true" ]]; then
        log_warn "Reliability tracking lock busy for 5s (stale ${lock_dir}?), proceeding unlocked"
    fi

    _record_consultant_outcome_update "$consultant" "$outcome" || true

    if [[ "$locked" == "true" ]]; then
        rmdir "$lock_dir" 2>/dev/null || true
    fi
    return 0
}

# Inner update for record_consultant_outcome — runs with the lock held.
# Never propagates failure; logs a warning and returns instead.
_record_consultant_outcome_update() {
    local consultant="$1"
    local outcome="$2"

    # A corrupt file (truncated write, interleaved concurrent update) would
    # fail every future jq update and never self-heal: set it aside and reset
    if [[ -f "$RELIABILITY_FILE" ]]; then
        if ! jq empty "$RELIABILITY_FILE" 2>/dev/null; then
            log_warn "Reliability tracking file corrupt, resetting (backup: ${RELIABILITY_FILE}.corrupt)"
            mv -f "$RELIABILITY_FILE" "${RELIABILITY_FILE}.corrupt" 2>/dev/null || true
        fi
    fi
    if [[ ! -f "$RELIABILITY_FILE" ]]; then
        if ! { echo '{"consultants": {}}' > "$RELIABILITY_FILE"; } 2>/dev/null; then
            log_warn "Reliability tracking skipped: cannot write $RELIABILITY_FILE"
            return 0
        fi
    fi

    local success_inc=0
    [[ "$outcome" == "success" ]] && success_inc=1

    # Unique temp file: even an unlocked writer must not share a fixed .tmp
    # sibling with other runs (lost records, failed mv)
    local tmp_file
    if ! tmp_file=$(mktemp "${RELIABILITY_FILE}.XXXXXX" 2>/dev/null); then
        log_warn "Reliability tracking skipped: cannot create temp file for $RELIABILITY_FILE"
        return 0
    fi
    if jq --arg c "$consultant" \
          --argjson s "$success_inc" \
          '.consultants[$c].attempts = ((.consultants[$c].attempts // 0) + 1)
           | .consultants[$c].successes = ((.consultants[$c].successes // 0) + $s)' \
          "$RELIABILITY_FILE" > "$tmp_file" 2>/dev/null; then
        mv -f "$tmp_file" "$RELIABILITY_FILE" 2>/dev/null || rm -f "$tmp_file"
    else
        rm -f "$tmp_file"
        log_warn "Reliability tracking update failed for consultant $consultant"
    fi
    return 0
}

# Get the rolling success rate for a consultant as an integer 0-100.
# Usage: get_consultant_reliability <consultant>
# Returns: "-1" if no attempts have been recorded yet
get_consultant_reliability() {
    local consultant="$1"

    if [[ ! -f "$RELIABILITY_FILE" ]]; then
        echo "-1"
        return 0
    fi

    jq -r --arg c "$consultant" \
        '(.consultants[$c].attempts // 0) as $a
         | (.consultants[$c].successes // 0) as $s
         | if $a > 0 then (($s * 100) / $a | floor) else -1 end' \
        "$RELIABILITY_FILE" 2>/dev/null || echo "-1"
}

# Format a short human-readable reliability report, sorted by success% asc.
# Usage: format_reliability_report
format_reliability_report() {
    if [[ ! -f "$RELIABILITY_FILE" ]]; then
        echo "No reliability data available"
        return
    fi

    echo "  Consultant           | Attempts | Success%"
    echo "  ---------------------|----------|---------"
    jq -r '
        .consultants
        | to_entries
        | map({name: .key, attempts: (.value.attempts // 0), successes: (.value.successes // 0)})
        | map(. + {rate: (if .attempts > 0 then (((.successes * 100) / .attempts) | floor) else -1 end)})
        | sort_by(.rate)
        | .[]
        | "  \(.name)|\(.attempts)|\(.rate)"
    ' "$RELIABILITY_FILE" 2>/dev/null | while IFS='|' read -r name attempts rate; do
        printf "  %-20s | %-8s | %s%%\n" "$name" "$attempts" "$rate"
    done
}
