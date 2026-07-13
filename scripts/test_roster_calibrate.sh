#!/bin/bash
# test_roster_calibrate.sh — measured capability calibration (Tier A, v2.20)
#
# Builds two consultations with known blind peer-scores (one taste-axis, one
# intelligence-axis) and token counts that force a clear cost ordering, then
# asserts roster_calibrate derives the expected intelligence/taste/cost scores.
#
# Usage: ./scripts/test_roster_calibrate.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/rcalib.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# A consultant response with a token count (same model, so cost tracks tokens).
_resp() { # <dir> <consultant> <tokens>
    jq -n --arg c "$2" --argjson t "$3" \
        '{consultant:$c, model:"gpt-5.5", response:{approach:("appr-"+$c)}, confidence:{score:7}, metadata:{tokens_used:$t}}' \
        > "$1/$2.json"
}
# A blind peer-review aggregate (the shape aggregate_peer_scores writes).
_peer() { # <dir> <c1> <s1> <c2> <s2> <c3> <s3>
    mkdir -p "$1/peer_review"
    jq -n --arg a "$2" --argjson as "$3" --arg b "$4" --argjson bs "$5" --arg e "$6" --argjson es "$7" \
        '[{consultant:$a,average_peer_score:$as},{consultant:$b,average_peer_score:$bs},{consultant:$e,average_peer_score:$es}]' \
        > "$1/peer_review/aggregated.json"
}
_cat() { jq -n --arg cat "$2" '{quality_metrics:{category:$cat}}' > "$1/optimization_metrics.json"; }

# Consultation 1: CODE_REVIEW (taste axis). Peer: Gemini 8, Codex 6, Grok 5.
C1="$TEST_TMPDIR/c1"; mkdir -p "$C1"
_cat "$C1" CODE_REVIEW
_peer "$C1" Gemini 8 Codex 6 Grok 5
_resp "$C1" Gemini 1000; _resp "$C1" Codex 10000; _resp "$C1" Grok 100

# Consultation 2: ALGORITHM (intelligence axis). Peer: Gemini 6, Codex 9, Grok 7.
C2="$TEST_TMPDIR/c2"; mkdir -p "$C2"
_cat "$C2" ALGORITHM
_peer "$C2" Gemini 6 Codex 9 Grok 7
_resp "$C2" Gemini 1000; _resp "$C2" Codex 10000; _resp "$C2" Grok 100

OUT=$(bash "$SCRIPT_DIR/roster_calibrate.sh" --json "$C1" "$C2")
_f() { echo "$OUT" | jq -r "$1"; }

test_calibrate() {
    # intelligence/taste = mean blind peer score on that axis's categories
    assert_eq "8" "$(_f '.measured_capabilities.Gemini.taste')"        "Gemini taste = peer score on taste-axis (8)"
    assert_eq "6" "$(_f '.measured_capabilities.Gemini.intelligence')" "Gemini intelligence = peer on intel-axis (6)"
    assert_eq "9" "$(_f '.measured_capabilities.Codex.intelligence')"  "Codex intelligence = 9"
    assert_eq "6" "$(_f '.measured_capabilities.Codex.taste')"         "Codex taste = 6"
    # cost = rank of observed $/response (cheapest = 10). Grok<Gemini<Codex by tokens.
    assert_eq "10" "$(_f '.measured_capabilities.Grok.cost')"          "Grok cheapest -> cost 10"
    assert_eq "6"  "$(_f '.measured_capabilities.Gemini.cost')"        "Gemini middle -> cost 6"
    assert_eq "1"  "$(_f '.measured_capabilities.Codex.cost')"         "Codex priciest -> cost 1"
    # sample counts surfaced for confidence
    assert_eq "1" "$(_f '.samples.Gemini.taste_n')"                    "Gemini taste sampled once"
    assert_eq "1" "$(_f '.samples.Gemini.intelligence_n')"             "Gemini intelligence sampled once"
}

# No peer-review data but cost present -> COST is still measured, exit 0 (the
# axis that only needs tokens_used is not thrown away with the peer axes).
test_cost_only_no_peer() {
    local d="$TEST_TMPDIR/nopeer"; mkdir -p "$d"
    _cat "$d" ALGORITHM
    _resp "$d" Gemini 1000; _resp "$d" Codex 10000
    local json rc
    json=$(bash "$SCRIPT_DIR/roster_calibrate.sh" --json "$d" 2>/dev/null)
    rc=$?
    assert_eq "0"  "$rc" "no peer but cost present -> exit 0 (cost still measured)"
    assert_eq "10" "$(echo "$json" | jq -r '.measured_capabilities.Gemini.cost // "MISSING"')" "cheapest (Gemini 1000t) -> cost 10"
    assert_eq "1"  "$(echo "$json" | jq -r '.measured_capabilities.Codex.cost // "MISSING"')"  "priciest (Codex 10000t) -> cost 1"
    assert_eq "null" "$(echo "$json" | jq -r '.measured_capabilities.Gemini.intelligence')" "no peer -> intelligence absent (null)"
}

# Nothing usable at all (no peer AND no cost/token data) -> exit 1.
test_no_data_exit() {
    local d="$TEST_TMPDIR/nodata"; mkdir -p "$d"
    _cat "$d" ALGORITHM
    bash "$SCRIPT_DIR/roster_calibrate.sh" --json "$d" >/dev/null 2>&1
    local rc=$?
    assert_eq "1" "$rc" "no peer AND no cost -> exit 1"
}

run_test "Test 1: measured capabilities from peer-review + cost" test_calibrate
run_test "Test 2: no peer but cost -> cost-only, exit 0"        test_cost_only_no_peer
run_test "Test 3: no usable data -> exit 1"                     test_no_data_exit

test_summary "roster_calibrate"
