#!/bin/bash
# test_voting_metadata.sh - regression tests for the v2.21 voting fixes.
#
#   Fix A: pipeline metadata files written into the responses dir
#          (orchestration.json, panic_diagnosis.json, voting.json, ...) must NOT
#          be counted as phantom "unknown"/confidence-5 votes that outvote real
#          approaches and can even win the recommendation.
#   Fix B: consensus = size of the LARGEST cluster of mutually-similar approaches
#          (does a majority agree?), not whole-panel pairwise similarity density
#          (which is structurally capped low whenever any single agent dissents).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/routing.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/voting.sh" >/dev/null 2>&1

TD="$(mktemp -d "${TMPDIR:-/tmp}/vmeta.XXXXXX")"
trap 'rm -rf "$TD"' EXIT
_r() { printf '{"consultant":"%s","response":{"approach":"%s"},"confidence":{"score":%s}}\n' "$1" "$2" "$3" > "$TD/$1.json"; }

# Fix A: metadata files in the same dir must not become phantom votes.
test_metadata_not_voted() {
    rm -f "$TD"/*.json
    _r Codex  "keep the npm lockfile committed"        9
    _r GLM    "always commit package-lock json"        9
    _r Cursor "commit the lockfile to version control" 9
    _r Gemini "unknown"                                5   # a real fallback response
    printf '{"shape":"converge","rounds_run":3}\n' > "$TD/orchestration.json"
    printf '{"panic":false}\n'                     > "$TD/panic_diagnosis.json"

    # The helper gates the glob at every voting site.
    assert_eq "1" "$(_is_consultant_response_file "$TD/Codex.json" && echo 1 || echo 0)"            "consultant response file accepted"
    assert_eq "0" "$(_is_consultant_response_file "$TD/orchestration.json" && echo 1 || echo 0)"    "orchestration.json rejected"
    assert_eq "0" "$(_is_consultant_response_file "$TD/panic_diagnosis.json" && echo 1 || echo 0)"  "panic_diagnosis.json rejected"

    # End effect: a real approach wins, not the phantom "unknown" (Gemini's real
    # unknown + 2 metadata = 3x unknown@5 would have outvoted every 9-weight
    # single approach under the old unfiltered glob).
    local rec
    rec=$(calculate_weighted_recommendation "$TD" 2>/dev/null | jq -r '.recommended_approach // "ERR"')
    assert_eq "0" "$([[ "$rec" == "unknown" || "$rec" == "ERR" || -z "$rec" ]] && echo 1 || echo 0)" \
        "recommendation is a real approach, not phantom 'unknown' (got: $rec)"
}

# Fix B: consensus reflects the largest agreeing cluster.
test_cluster_consensus() {
    rm -f "$TD"/*.json
    local n
    for n in 1 2 3 4 5; do _r "C$n" "commit the lockfile to version control" 9; done
    _r Dissent "delete node modules and rebuild everything" 6
    assert_eq "83" "$(calculate_consensus_score "$TD")" "5-of-6 agreeing (identical) cluster -> 83%"

    rm -f "$TD/Dissent.json"
    _r C6 "commit the lockfile to version control" 9
    assert_eq "100" "$(calculate_consensus_score "$TD")" "6-of-6 identical -> 100%"

    # A single response is trivially unanimous.
    rm -f "$TD"/*.json
    _r Solo "just do it" 8
    assert_eq "100" "$(calculate_consensus_score "$TD")" "single response -> 100%"
}

run_test "Fix A: pipeline metadata not counted as votes" test_metadata_not_voted
run_test "Fix B: consensus = largest agreeing cluster"   test_cluster_consensus

test_summary "voting_metadata"
