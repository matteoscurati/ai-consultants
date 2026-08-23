#!/usr/bin/env bash
# Regression tests for safe follow-up query handoff and host self-exclusion.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_followup.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

SESSION_DIR_TEST="$TMP_ROOT/sessions"
RESPONSES_DIR_TEST="$TMP_ROOT/responses"
CONFIG_DIR_TEST="$TMP_ROOT/config"
STUB_CLI="$SCRIPT_DIR/test_fixtures/stub_cli.sh"

reset_session_fixture() {
    rm -rf "$SESSION_DIR_TEST" "$RESPONSES_DIR_TEST" "$CONFIG_DIR_TEST" "$TMP_ROOT/runtime"
    mkdir -p "$SESSION_DIR_TEST" "$RESPONSES_DIR_TEST" "$CONFIG_DIR_TEST" "$TMP_ROOT/runtime"
    printf '%s\n' '{"consultant":"Gemini","model":"m","response":{"summary":"original","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' \
        > "$RESPONSES_DIR_TEST/gemini.json"
    jq -n --arg dir "$RESPONSES_DIR_TEST" '{
        id: "session_test",
        query: "original question",
        responses_dir: $dir,
        category: "GENERAL",
        timestamp: "2026-08-23T00:00:00Z",
        follow_ups: []
    }' > "$SESSION_DIR_TEST/current_session.json"
}

_reset_state() {
    reset_session_fixture
}

test_query_file_conflicts_with_positional_followup() {
    local qfile="$TMP_ROOT/conflict.txt" stderr
    printf '%s\n' 'from file' > "$qfile"
    stderr=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        "$SCRIPT_DIR/followup.sh" --query-file "$qfile" "from argv" 2>&1 >/dev/null || true)
    assert_match "conflicts with a positional follow-up instruction" "$stderr" \
        "follow-up query-file rejects positional instruction text"
}

test_targeted_followup_rejects_invoking_consultant() {
    local qfile="$TMP_ROOT/self.txt" sentinel="$TMP_ROOT/gemini-sentinel" stderr rc
    printf '%s\n' 'explain further' > "$qfile"
    cat > "$sentinel" <<'EOF'
#!/bin/bash
touch "$FOLLOWUP_DISPATCH_MARKER"
exit 99
EOF
    chmod +x "$sentinel"

    stderr=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        INVOKING_AGENT=gemini GEMINI_CMD="$sentinel" \
        FOLLOWUP_DISPATCH_MARKER="$TMP_ROOT/self-dispatched" \
        "$SCRIPT_DIR/followup.sh" -c Gemini --query-file "$qfile" 2>&1 >/dev/null)
    rc=$?

    assert_eq "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)" \
        "targeted follow-up to invoking consultant fails"
    assert_match "Refusing follow-up self-consultation" "$stderr" \
        "self-follow-up failure is diagnosed"
    assert_eq "0" "$([[ -e "$TMP_ROOT/self-dispatched" ]] && echo 1 || echo 0)" \
        "self-follow-up never launches the provider adapter"
}

test_query_file_followup_to_other_consultant_succeeds() {
    local qfile="$TMP_ROOT/other.txt" run_out rc followup_dir recorded
    printf '%s\n' "Why shouldn't the host trust raw output?" > "$qfile"

    run_out=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        INVOKING_AGENT=claude MISTRAL_CMD="$STUB_CLI" MAX_RETRIES=1 \
        ENABLE_PERSONA=false ENABLE_SEMANTIC_CACHE=false \
        "$SCRIPT_DIR/followup.sh" -c Mistral --query-file "$qfile" 2>"$TMP_ROOT/other.err")
    rc=$?
    followup_dir=$(printf '%s\n' "$run_out" | tail -n 1)
    recorded=$(jq -r '.follow_ups[0].query // empty' "$SESSION_DIR_TEST/current_session.json")

    assert_eq "0" "$rc" "query-file follow-up to another consultant succeeds"
    assert_eq "structured" "$(jq -r '.metadata.response_quality' "$followup_dir/mistral.json")" \
        "non-host follow-up produces a structured response"
    assert_eq "Why shouldn't the host trust raw output?" "$recorded" \
        "follow-up query-file preserves apostrophes exactly"
    assert_eq "0" "$(find "$TMP_ROOT/runtime" -maxdepth 1 -type f -name 'ai-consultants-followup.*' | wc -l | tr -d ' ')" \
        "private follow-up context file is removed after dispatch"
}

test_targeted_followup_supports_full_roster_adapter() {
    local qfile="$TMP_ROOT/minimax.txt" run_out rc followup_dir
    printf '%s\n' 'Give one additional optimization caveat.' > "$qfile"

    run_out=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        INVOKING_AGENT=claude MINIMAX_CMD="$STUB_CLI" MINIMAX_USE_API=false \
        MAX_RETRIES=1 ENABLE_PERSONA=false ENABLE_SEMANTIC_CACHE=false \
        "$SCRIPT_DIR/followup.sh" -c MiniMax --query-file "$qfile" 2>"$TMP_ROOT/minimax.err")
    rc=$?
    followup_dir=$(printf '%s\n' "$run_out" | tail -n 1)

    assert_eq "0" "$rc" "targeted follow-up supports a consultant beyond the legacy trio"
    assert_eq "structured" "$(jq -r '.metadata.response_quality' "$followup_dir/minimax.json")" \
        "full-roster adapter follow-up produces a structured response"
}

test_targeted_followup_respects_disabled_consultant() {
    local qfile="$TMP_ROOT/disabled.txt" stderr rc
    printf '%s\n' 'should not dispatch' > "$qfile"
    stderr=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" \
        AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" INVOKING_AGENT=claude \
        ENABLE_MINIMAX=false MINIMAX_CMD="$STUB_CLI" \
        "$SCRIPT_DIR/followup.sh" -c MiniMax --query-file "$qfile" 2>&1 >/dev/null)
    rc=$?
    assert_eq "1" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)" \
        "targeted follow-up to a disabled consultant fails"
    assert_match "Consultant is disabled" "$stderr" \
        "disabled targeted follow-up is diagnosed"
}

run_test "Follow-up query-file rejects positional text" test_query_file_conflicts_with_positional_followup
run_test "Targeted follow-up rejects invoking consultant" test_targeted_followup_rejects_invoking_consultant
run_test "Query-file follow-up to another consultant succeeds" test_query_file_followup_to_other_consultant_succeeds
run_test "Targeted follow-up supports a full-roster adapter" test_targeted_followup_supports_full_roster_adapter
run_test "Targeted follow-up respects disabled consultants" test_targeted_followup_respects_disabled_consultant
test_summary "followup"
