#!/bin/bash
# shellcheck disable=SC2329
# (test_*/assert_* are invoked indirectly via `run_test "$@"`)
#
# test_orchestration.sh - Tests for the dynamic orchestration planner (v2.16.0)
#
# Covers the deterministic, CLI-free surface of lib/orchestration.sh:
#   - detect_intent: compare / exhaustive / advise
#   - select_orchestration_shape: auto resolution (intent > category > complexity),
#     explicit shape overrides, and the "fixed" legacy bypass
#   - _convergence_should_stop: converged / stalled / continue (incl. regressions)
#   - _approach_signature: distinct-approach signature over response fixtures
#   - config.sh default: ORCHESTRATION_MODE=auto
#
# The round-running executors (run_convergence_loop, run_exhaustive_loop, ...)
# invoke debate_round.sh + live consultant CLIs and are not exercised here; the
# loop CONTROL logic they depend on is covered via the pure helpers above.
#
# Usage: ./scripts/test_orchestration.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" >/dev/null 2>&1
# shellcheck source=lib/orchestration.sh
source "$SCRIPT_DIR/lib/orchestration.sh"

_reset_state() {
    unset ORCHESTRATION_MODE COMPLEXITY_THRESHOLD_SIMPLE 2>/dev/null || true
}

TMP=$(mktemp -d -t ai_consultants_orch_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# -----------------------------------------------------------------------------
# detect_intent
# -----------------------------------------------------------------------------
test_intent_compare() {
    assert_eq "compare" "$(detect_intent 'Should I use REST vs GraphQL?')" "vs -> compare"
    assert_eq "compare" "$(detect_intent 'compare Postgres and MySQL for this')" "compare -> compare"
    assert_eq "compare" "$(detect_intent 'which approach is better here')" "which approach -> compare"
}

test_intent_exhaustive() {
    assert_eq "exhaustive" "$(detect_intent 'find all security bugs in this file')" "find all -> exhaustive"
    assert_eq "exhaustive" "$(detect_intent 'audit the auth module for issues')" "audit -> exhaustive"
    assert_eq "exhaustive" "$(detect_intent 'list all edge cases I am missing')" "list all -> exhaustive"
}

test_intent_advise() {
    assert_eq "advise" "$(detect_intent 'how do I parse JSON in bash?')" "plain question -> advise"
    assert_eq "advise" "$(detect_intent 'explain this stack trace')" "explain -> advise"
}

# -----------------------------------------------------------------------------
# select_orchestration_shape (auto resolution)
# -----------------------------------------------------------------------------
test_shape_intent_priority() {
    # Intent is the strongest signal: exhaustive/compare win over category/complexity.
    assert_eq "exhaustive" "$(ORCHESTRATION_MODE=auto select_orchestration_shape SECURITY 8 exhaustive)" "exhaustive intent beats SECURITY"
    assert_eq "tournament" "$(ORCHESTRATION_MODE=auto select_orchestration_shape GENERAL 2 compare)" "compare intent beats low complexity"
}

test_shape_category() {
    assert_eq "adversarial" "$(ORCHESTRATION_MODE=auto select_orchestration_shape SECURITY 5 advise)" "SECURITY -> adversarial"
    # ARCHITECTURE is a mandatory-debate category: must map to converge (never
    # quick), even at low complexity, so it always gets a critique round.
    assert_eq "converge" "$(ORCHESTRATION_MODE=auto select_orchestration_shape ARCHITECTURE 7 advise)" "ARCHITECTURE -> converge"
    assert_eq "converge" "$(ORCHESTRATION_MODE=auto select_orchestration_shape ARCHITECTURE 2 advise)" "ARCHITECTURE (low complexity) -> converge, not quick"
}

test_shape_complexity() {
    assert_eq "quick"    "$(ORCHESTRATION_MODE=auto select_orchestration_shape GENERAL 2 advise)" "low complexity -> quick"
    assert_eq "converge" "$(ORCHESTRATION_MODE=auto select_orchestration_shape GENERAL 7 advise)" "high complexity -> converge"
    # Boundary: complexity == COMPLEXITY_THRESHOLD_SIMPLE (default 3) is still quick
    assert_eq "quick"    "$(ORCHESTRATION_MODE=auto select_orchestration_shape GENERAL 3 advise)" "complexity at threshold -> quick"
    assert_eq "converge" "$(ORCHESTRATION_MODE=auto select_orchestration_shape GENERAL 4 advise)" "complexity above threshold -> converge"
}

test_shape_overrides() {
    assert_eq "fixed"      "$(ORCHESTRATION_MODE=fixed select_orchestration_shape SECURITY 8 exhaustive)" "fixed override bypasses planner"
    assert_eq "tournament" "$(ORCHESTRATION_MODE=tournament select_orchestration_shape GENERAL 2 advise)" "explicit tournament override"
    assert_eq "quick"      "$(ORCHESTRATION_MODE=quick select_orchestration_shape SECURITY 9 compare)" "explicit quick override"
}

# -----------------------------------------------------------------------------
# _convergence_should_stop
# -----------------------------------------------------------------------------
test_convergence_decision() {
    assert_eq "converged" "$(_convergence_should_stop 80 60 75 5)" "score >= target -> converged"
    assert_eq "converged" "$(_convergence_should_stop 75 70 75 5)" "score == target -> converged"
    assert_eq "stalled"   "$(_convergence_should_stop 62 60 75 5)" "gain < epsilon -> stalled"
    assert_eq "stalled"   "$(_convergence_should_stop 58 60 75 5)" "negative gain (abs < epsilon) -> stalled"
    assert_eq "continue"  "$(_convergence_should_stop 70 60 75 5)" "gain >= epsilon, below target -> continue"
}

# -----------------------------------------------------------------------------
# _approach_signature
# -----------------------------------------------------------------------------
test_approach_signature() {
    local dir="$TMP/sig"
    mkdir -p "$dir"
    printf '%s\n' '{"response":{"approach":"Event sourcing"}}' > "$dir/Gemini.json"
    printf '%s\n' '{"response":{"approach":"CRUD"}}'           > "$dir/Codex.json"
    printf '%s\n' '{"response":{"approach":"Event sourcing"}}' > "$dir/Mistral.json"
    # summary/voting/orchestration files must be ignored
    printf '%s\n' '{"summary":"x"}'                            > "$dir/summary.json"
    printf '%s\n' '{"voting_report":{}}'                       > "$dir/voting.json"

    local sig
    sig=$(_approach_signature "$dir")
    # sorted-unique, pipe-joined: "CRUD|Event sourcing|"
    assert_eq "CRUD|Event sourcing|" "$sig" "distinct approaches sorted+unique, helper files excluded"
}

test_approach_signature_change() {
    local dir="$TMP/sig2"
    mkdir -p "$dir"
    printf '%s\n' '{"response":{"approach":"A"}}' > "$dir/Gemini.json"
    local before after
    before=$(_approach_signature "$dir")
    printf '%s\n' '{"response":{"approach":"B"}}' > "$dir/Codex.json"
    after=$(_approach_signature "$dir")
    assert_eq "A|" "$before" "before: only A"
    assert_eq "A|B|" "$after" "after: A and B (new angle detected)"
}

# -----------------------------------------------------------------------------
# _apply_debate_round: promote (dynamic) vs legacy merge
# -----------------------------------------------------------------------------
# The round file carries the consultant's *updated* top-level .response.approach.
# promote=true (dynamic loops) must adopt it so consensus can move; promote=false
# (legacy/fixed) must keep the original approach byte-for-byte.
_stub_debate_round() {
    local stubdir="$1"
    mkdir -p "$stubdir"
    cat > "$stubdir/debate_round.sh" <<'EOF'
#!/bin/bash
mkdir -p "$3"
echo '{"consultant":"Gemini","response":{"approach":"unified approach"},"confidence":{"score":9}}' > "$3/Gemini.json"
EOF
    chmod +x "$stubdir/debate_round.sh"
}

test_apply_debate_round_promote() {
    local stubdir="$TMP/promote_stub" rdir="$TMP/promote_resp"
    _stub_debate_round "$stubdir"
    mkdir -p "$rdir"
    echo '{"consultant":"Gemini","response":{"approach":"old approach"},"confidence":{"score":5}}' > "$rdir/Gemini.json"

    local saved="$SCRIPT_DIR"; SCRIPT_DIR="$stubdir"
    _apply_debate_round "$rdir" 2 GENERAL true
    SCRIPT_DIR="$saved"

    assert_eq "unified approach" "$(jq -r '.response.approach' "$rdir/Gemini.json")" "promote=true adopts the updated approach (consensus can move)"
    assert_eq "9" "$(jq -r '.confidence.score' "$rdir/Gemini.json")" "promote=true adopts the updated confidence"
}

test_apply_debate_round_legacy() {
    local stubdir="$TMP/legacy_stub" rdir="$TMP/legacy_resp"
    _stub_debate_round "$stubdir"
    mkdir -p "$rdir"
    echo '{"consultant":"Gemini","response":{"approach":"old approach"},"confidence":{"score":5}}' > "$rdir/Gemini.json"

    local saved="$SCRIPT_DIR"; SCRIPT_DIR="$stubdir"
    _apply_debate_round "$rdir" 2 GENERAL false
    SCRIPT_DIR="$saved"

    assert_eq "old approach" "$(jq -r '.response.approach' "$rdir/Gemini.json")" "promote=false keeps the original approach (legacy parity)"
}

# -----------------------------------------------------------------------------
# config.sh default
# -----------------------------------------------------------------------------
test_config_default_mode_auto() {
    local val
    val=$(unset ORCHESTRATION_MODE; bash -c '
        source scripts/config.sh
        echo "$ORCHESTRATION_MODE"
    ')
    assert_eq "auto" "$val" "ORCHESTRATION_MODE defaults to auto (v2.16.0)"
}

run_test "Test 1: intent compare"               test_intent_compare
run_test "Test 2: intent exhaustive"            test_intent_exhaustive
run_test "Test 3: intent advise"                test_intent_advise
run_test "Test 4: shape intent priority"        test_shape_intent_priority
run_test "Test 5: shape by category"            test_shape_category
run_test "Test 6: shape by complexity"          test_shape_complexity
run_test "Test 7: shape overrides"              test_shape_overrides
run_test "Test 8: convergence stop decision"    test_convergence_decision
run_test "Test 9: approach signature"           test_approach_signature
run_test "Test 10: approach signature change"   test_approach_signature_change
run_test "Test 11: config default mode auto"    test_config_default_mode_auto
run_test "Test 12: debate round promote (dynamic)" test_apply_debate_round_promote
run_test "Test 13: debate round legacy parity"     test_apply_debate_round_legacy

test_summary "orchestration"
