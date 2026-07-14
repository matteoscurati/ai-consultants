#!/bin/bash
# test_stance.sh - stance-based semantic consensus (v2.21, ENABLE_STANCE_CONSENSUS).
#
# The LLM generation step (generate_stance_options) is not unit-tested here (it
# needs a live synthesizer CLI); its pure parsing (_stance_clean), the prompt
# addendum (build_stance_prompt), and the exact-match consensus in voting.sh are.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh"  >/dev/null 2>&1
source "$SCRIPT_DIR/lib/routing.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/voting.sh"  >/dev/null 2>&1
source "$SCRIPT_DIR/lib/stance.sh"  >/dev/null 2>&1

TD="$(mktemp -d "${TMPDIR:-/tmp}/stance.XXXXXX")"
trap 'rm -rf "$TD"' EXIT
_rs() { printf '{"consultant":"%s","response":{"approach":"wildly different phrasing %s","stance":"%s"},"confidence":{"score":9}}\n' "$1" "$1" "$2" > "$TD/$1.json"; }

test_stance_parse() {
    assert_eq '["Commit the lockfile","Do not commit it"]' \
        "$(_stance_clean '["Commit the lockfile","Do not commit it"]')" "valid 2-item array kept"
    assert_eq '[]' "$(_stance_clean '["only one"]')"       "single item -> [] (need >=2)"
    assert_eq '[]' "$(_stance_clean '{"not":"an array"}')" "non-array -> []"
    assert_eq '[]' "$(_stance_clean 'totally not json')"   "garbage -> []"
    assert_eq '["a","b"]' "$(_stance_clean '["a","",  "b"]')" "empty strings dropped"
}

test_stance_prompt() {
    local p; p=$(build_stance_prompt '["Commit the lockfile","Do not commit it","Depends"]')
    assert_match "Commit the lockfile" "$p" "addendum lists the options"
    assert_match "VERBATIM"            "$p" "addendum demands a verbatim choice"
    local rc=0
    build_stance_prompt '["only one"]' >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "fewer than 2 options -> returns 1 (no addendum)"
}

test_stance_consensus() {
    rm -f "$TD"/*.json
    _rs C1 "Commit the lockfile"
    _rs C2 "commit the lockfile"          # different case -> normalized to a match
    _rs C3 "Commit the lockfile"
    _rs C4 "Commit the lockfile"
    _rs D1 "Do not commit it"
    printf '{"shape":"converge"}\n' > "$TD/orchestration.json"   # metadata, excluded
    assert_eq "80" "$(ENABLE_STANCE_CONSENSUS=true calculate_consensus_score "$TD")" \
        "4-of-5 plurality (case-insensitive), metadata excluded, immune to approach phrasing -> 80"

    _rs D1 "Commit the lockfile"          # now unanimous
    assert_eq "100" "$(ENABLE_STANCE_CONSENSUS=true calculate_consensus_score "$TD")" \
        "unanimous stance -> 100"

    # No stance fields present -> stance path falls through to the lexical cluster
    # without crashing (and identical approaches cluster to 100).
    rm -f "$TD"/*.json
    printf '{"consultant":"A","response":{"approach":"commit it"},"confidence":{"score":9}}\n' > "$TD/A.json"
    printf '{"consultant":"B","response":{"approach":"commit it"},"confidence":{"score":9}}\n' > "$TD/B.json"
    assert_eq "100" "$(ENABLE_STANCE_CONSENSUS=true calculate_consensus_score "$TD")" \
        "no stance fields -> graceful cluster fallback (not a crash)"
}

run_test "stance option parsing (_stance_clean)"      test_stance_parse
run_test "stance prompt addendum (build_stance_prompt)" test_stance_prompt
run_test "stance-based exact-match consensus"          test_stance_consensus

test_summary "stance"
