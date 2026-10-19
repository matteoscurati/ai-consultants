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

# M2a: --session restores the full original question, not a null preview.
test_session_restore_keeps_original_query() {
    local qfile="$TMP_ROOT/restore.txt" rc restored
    printf '%s\n' 'one more caveat' > "$qfile"
    jq -n --arg dir "$RESPONSES_DIR_TEST" '{sessions: [
        {id: "hist_full", query: "FULL ORIGINAL QUESTION well beyond any preview", query_preview: "FULL ORIGINAL", responses_dir: $dir, category: "GENERAL", timestamp: "t"},
        {id: "hist_legacy", query_preview: "LEGACY PREVIEW", responses_dir: $dir, category: "GENERAL", timestamp: "t"}
    ]}' > "$SESSION_DIR_TEST/history.json"

    TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        INVOKING_AGENT=claude MISTRAL_CMD="$STUB_CLI" MAX_RETRIES=1 \
        ENABLE_PERSONA=false ENABLE_SEMANTIC_CACHE=false \
        "$SCRIPT_DIR/followup.sh" --session hist_full -c Mistral --query-file "$qfile" \
        >/dev/null 2>"$TMP_ROOT/restore.err"
    rc=$?
    restored=$(jq -r '.query' "$SESSION_DIR_TEST/current_session.json")
    assert_eq 0 "$rc" "follow-up on a restored session succeeds"
    assert_eq "FULL ORIGINAL QUESTION well beyond any preview" "$restored" \
        "restored session keeps the full original question"
    assert_eq "one more caveat" "$(jq -r '.follow_ups[0].query' "$SESSION_DIR_TEST/current_session.json")" \
        "restored session records the follow-up"

    TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        INVOKING_AGENT=claude MISTRAL_CMD="$STUB_CLI" MAX_RETRIES=1 \
        ENABLE_PERSONA=false ENABLE_SEMANTIC_CACHE=false \
        "$SCRIPT_DIR/followup.sh" --session hist_legacy -c Mistral --query-file "$qfile" \
        >/dev/null 2>>"$TMP_ROOT/restore.err"
    assert_eq "LEGACY PREVIEW" "$(jq -r '.query' "$SESSION_DIR_TEST/current_session.json")" \
        "a legacy history record falls back to its preview, never null"

    local long_query saved
    long_query="$(printf 'Q%.0s' {1..150}) end"
    saved=$(SESSION_DIR="$TMP_ROOT/history-roundtrip" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" bash -c '
        source "$1/lib/common.sh"; source "$1/lib/session.sh"
        save_session sess_roundtrip "$2" /tmp/x GENERAL >/dev/null
        get_session_by_id sess_roundtrip | jq -r .query' _ "$SCRIPT_DIR" "$long_query")
    assert_eq "$long_query" "$saved" "history stores the full query for later --session restores"

    # A --query-file question can exceed one argv element (128 KiB on Linux),
    # so the session records must take it through stdin, not jq --arg.
    local huge_file="$TMP_ROOT/huge-question.txt" huge_lengths
    head -c 200000 /dev/zero | tr '\0' 'Q' > "$huge_file"
    huge_lengths=$(SESSION_DIR="$TMP_ROOT/history-huge" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" bash -c '
        source "$1/lib/common.sh"; source "$1/lib/session.sh"
        q=$(cat "$2")
        save_session sess_huge "$q" /tmp/x GENERAL >/dev/null
        add_follow_up "$q" /tmp/y
        printf "%s|%s|%s" "$(jq -r ".query | length" "$SESSION_FILE")" \
            "$(get_session_by_id sess_huge | jq -r ".query | length")" \
            "$(jq -r ".follow_ups[0].query | length" "$SESSION_FILE")"' _ "$SCRIPT_DIR" "$huge_file")
    assert_eq "200000|200000|200000" "$huge_lengths" \
        "session records keep a question larger than one argv element"
}

# M2b/c: a whole-panel follow-up is recorded on the ORIGINAL session and
# points at the directory that actually holds the new responses.
test_panel_followup_records_on_original_session() {
    local qfile="$TMP_ROOT/panel.txt" run_out rc recorded_dir
    printf '%s\n' 'Reconsider the caching trade-off' > "$qfile"
    printf '%s\n' '{"synthesis_version":"3.0","coverage":[]}' > "$RESPONSES_DIR_TEST/synthesis.json"

    run_out=$(TMPDIR="$TMP_ROOT/runtime" SESSION_DIR="$SESSION_DIR_TEST" AI_CONSULTANTS_CONFIG_DIR="$CONFIG_DIR_TEST" \
        HOME="$TMP_ROOT/home" XDG_CACHE_HOME="$TMP_ROOT/xdg-cache" XDG_DATA_HOME="$TMP_ROOT/xdg-data" \
        INVOKING_AGENT=claude DEFAULT_PRESET="" \
        ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true ENABLE_KIMI=false ENABLE_CLAUDE=false \
        ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        GEMINI_USE_API=false CODEX_USE_API=false MISTRAL_USE_API=false \
        GEMINI_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" MISTRAL_CMD="$STUB_CLI" \
        MAX_RETRIES=1 LAUNCH_STAGGER_MAX_SECONDS=0 ENABLE_SYNTHESIS=false ENABLE_SEMANTIC_CACHE=false \
        "$SCRIPT_DIR/followup.sh" --query-file "$qfile" 2>"$TMP_ROOT/panel.err")
    rc=$?
    recorded_dir=$(jq -r '.follow_ups[0].responses_dir // empty' "$SESSION_DIR_TEST/current_session.json")

    assert_eq 0 "$rc" "whole-panel follow-up succeeds"
    assert_eq session_test "$(jq -r '.id' "$SESSION_DIR_TEST/current_session.json")" \
        "whole-panel follow-up keeps the original session current"
    assert_eq "Reconsider the caching trade-off" "$(jq -r '.follow_ups[0].query' "$SESSION_DIR_TEST/current_session.json")" \
        "whole-panel follow-up is recorded on the original session"
    assert_eq 1 "$([[ -s "$recorded_dir/codex.json" ]] && echo 1 || echo 0)" \
        "recorded follow-up directory holds the new responses"
    assert_eq "$recorded_dir" "$(printf '%s\n' "$run_out" | tail -n 1)" \
        "follow-up prints the directory holding the responses"
    assert_eq 0 "$(grep -c 'Unknown' "$recorded_dir/context.md" || true)" \
        "follow-up context excludes non-consultant artifacts"
}

run_test "Follow-up query-file rejects positional text" test_query_file_conflicts_with_positional_followup
run_test "Targeted follow-up rejects invoking consultant" test_targeted_followup_rejects_invoking_consultant
run_test "Query-file follow-up to another consultant succeeds" test_query_file_followup_to_other_consultant_succeeds
run_test "Targeted follow-up supports a full-roster adapter" test_targeted_followup_supports_full_roster_adapter
run_test "Targeted follow-up respects disabled consultants" test_targeted_followup_respects_disabled_consultant
run_test "Session restore keeps the original query" test_session_restore_keeps_original_query
run_test "Whole-panel follow-up records on the original session" test_panel_followup_records_on_original_session
test_summary "followup"
