#!/bin/bash
# test_roster_audit.sh — uncorrelated-value roster audit (v2.20)
#
# Builds synthetic consultations where Gemini & Codex propose the SAME approach
# (correlated) and Grok always proposes a DISTINCT one, then asserts the audit
# flags Grok as unique-value and the echoers as redundant.
#
# Usage: ./scripts/test_roster_audit.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/rosteraudit.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Emit a consultant response JSON named after the consultant.
# Usage: _mk <dir> <consultant> <approach>
_mk() {
    jq -n --arg c "$2" --arg a "$3" \
        '{consultant:$c, response:{approach:$a}, confidence:{score:7}}' > "$1/${2}.json"
}

# 3 consultations: Gemini == Codex approach (correlated), Grok distinct each time.
for r in 1 2 3; do
    d="$TEST_TMPDIR/consult_$r"
    mkdir -p "$d"
    _mk "$d" Gemini "microservices event-driven architecture"
    _mk "$d" Codex  "microservices event-driven architecture"
    _mk "$d" Grok   "monolith modular boundaries"
done

OUT=$(bash "$SCRIPT_DIR/roster_audit.sh" --json \
    "$TEST_TMPDIR/consult_1" "$TEST_TMPDIR/consult_2" "$TEST_TMPDIR/consult_3")

_field() { echo "$OUT" | jq -r "$1"; }

test_audit() {
    assert_eq "3" "$(_field '.consultations_audited')" \
        "audited all 3 consultations"
    assert_eq "100" "$(_field '.roster[] | select(.consultant=="Grok") | .distinct_pct')" \
        "Grok distinct in 100% of rounds (unique approach)"
    assert_eq "unique-value" "$(_field '.roster[] | select(.consultant=="Grok") | .verdict')" \
        "Grok verdict = unique-value"
    assert_eq "0" "$(_field '.roster[] | select(.consultant=="Gemini") | .distinct_pct')" \
        "Gemini never distinct (echoes Codex)"
    assert_eq "redundant?" "$(_field '.roster[] | select(.consultant=="Codex") | .verdict')" \
        "Codex verdict = redundant? (correlated echo)"
}

# A single-responder consultation must be skipped (can't assess correlation).
test_skips_single_responder() {
    local d="$TEST_TMPDIR/solo"
    mkdir -p "$d"
    _mk "$d" Gemini "some lone approach"
    local out
    out=$(bash "$SCRIPT_DIR/roster_audit.sh" --json "$d" 2>/dev/null; echo "rc=$?")
    assert_match "rc=1" "$out" "single-responder consultation -> nothing to audit (exit 1)"
}

run_test "Test 1: audit flags redundant vs unique consultants" test_audit
run_test "Test 2: skips single-responder consultations"        test_skips_single_responder

test_summary "roster_audit"
