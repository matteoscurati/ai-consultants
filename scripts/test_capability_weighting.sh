#!/bin/bash
# test_capability_weighting.sh — capability-aware voting + composition (v2.20)
#
# Covers the opt-in capability axes added to references/affinity.json v1.1 and
# wired into routing.sh (get_capability, get_category_axis, blended
# composition) and voting.sh (capability-modulated vote weight):
#   - get_capability lookup + fallback (unknown consultant/axis -> default)
#   - get_category_axis mapping (taste vs intelligence) + unmapped default
#   - _effective_vote_weight math (off -> confidence; on -> conf*(S+cap)/S)
#   - capability-weighted recommendation FLIPS the winner on a taste category
#   - back-compat: flags off -> confidence-only winner (identical to before)
#   - composition: ENABLE_CAPABILITY_ROUTING reorders eligible consultants
#
# Usage: ./scripts/test_capability_weighting.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/voting.sh
source "$SCRIPT_DIR/lib/voting.sh"
# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"

# Isolated temp dir for fake response fixtures
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/capweight.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Emit a minimal consultant response JSON.
# Usage: _mk_response <dir> <name> <consultant> <approach> <confidence>
_mk_response() {
    jq -n --arg c "$3" --arg a "$4" --argjson s "$5" \
        '{consultant:$c, response:{approach:$a}, confidence:{score:$s}}' > "$1/$2.json"
}

# Echo "yes" if <a> appears before <b> in a newline-separated list, else "no".
# Usage: _first_before "$list" <a> <b>
_first_before() {
    local list="$1" a="$2" b="$3" pa pb
    pa=$(printf '%s\n' "$list" | grep -nx "$a" | head -1 | cut -d: -f1)
    pb=$(printf '%s\n' "$list" | grep -nx "$b" | head -1 | cut -d: -f1)
    if [[ -n "$pa" && -n "$pb" && "$pa" -lt "$pb" ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

_reset_state() {
    unset ENABLE_CAPABILITY_WEIGHTING ENABLE_CAPABILITY_ROUTING QUESTION_CATEGORY 2>/dev/null || true
    CAPABILITY_WEIGHT_STRENGTH=10
    CAPABILITY_DEFAULT=5
}

# ---- get_capability ----
test_get_capability() {
    assert_eq "8" "$(get_capability Claude taste)" "Claude taste = 8 (grounded on model-routing table)"
    assert_eq "8" "$(get_capability DeepSeek intelligence)" "DeepSeek intelligence = 8 (seed)"
    assert_eq "5" "$(get_capability Nonexistent taste)" "unknown consultant -> capability_default (5)"
    assert_eq "5" "$(get_capability Claude nonexistent_axis)" "unknown axis -> capability_default (5)"
}

# ---- get_category_axis ----
test_get_category_axis() {
    assert_eq "taste" "$(get_category_axis CODE_REVIEW)" "CODE_REVIEW -> taste (moved in v1.1)"
    assert_eq "taste" "$(get_category_axis API_DESIGN)" "API_DESIGN -> taste"
    assert_eq "intelligence" "$(get_category_axis ALGORITHM)" "ALGORITHM -> intelligence"
    assert_eq "intelligence" "$(get_category_axis SECURITY)" "SECURITY -> intelligence"
    assert_eq "intelligence" "$(get_category_axis TOTALLY_UNKNOWN)" "unmapped category -> intelligence"
}

# ---- _effective_vote_weight ----
test_effective_weight() {
    # off: empty axis -> plain confidence
    assert_eq "8" "$(_effective_vote_weight Claude 8 "")" "no axis -> weight == confidence"
    # on, taste axis: Claude taste 8, S=10 -> 8*(10+8)/10 = 14
    assert_eq "14" "$(_effective_vote_weight Claude 8 taste)" "Claude taste: 8*(10+8)/10 = 14"
    # neutral capability (unknown consultant -> 5): 8*(10+5)/10 = 12
    assert_eq "12" "$(_effective_vote_weight Nobody 8 taste)" "neutral cap: 8*(10+5)/10 = 12"
    # strength tunable: S=20 -> 8*(20+8)/20 = 11 (gentler nudge)
    CAPABILITY_WEIGHT_STRENGTH=20
    assert_eq "11" "$(_effective_vote_weight Claude 8 taste)" "strength=20 gentler: 8*(20+8)/20 = 11"
}

# ---- weighted recommendation flips winner on a taste category ----
test_weighting_flips_winner() {
    local dir="$TEST_TMPDIR/vote"
    mkdir -p "$dir"
    rm -f "$dir"/*.json
    # Claude backs ApproachX (conf 9, taste 8); Codex+DeepSeek back ApproachY
    # (conf 5 each, taste 5). Unweighted: Y=10 > X=9. Weighted(taste): X=16 > Y=14.
    _mk_response "$dir" a Claude   ApproachX 9
    _mk_response "$dir" b Codex    ApproachY 5
    _mk_response "$dir" c DeepSeek ApproachY 5
    QUESTION_CATEGORY=CODE_REVIEW

    ENABLE_CAPABILITY_WEIGHTING=false
    local off
    off=$(calculate_weighted_recommendation "$dir" | jq -r '.recommended_approach')
    assert_eq "ApproachY" "$off" "weighting OFF: confidence-only winner is ApproachY"

    ENABLE_CAPABILITY_WEIGHTING=true
    local on
    on=$(calculate_weighted_recommendation "$dir" | jq -r '.recommended_approach')
    assert_eq "ApproachX" "$on" "weighting ON (taste): high-taste Claude flips winner to ApproachX"
}

# ---- composition: capability routing reorders eligible consultants ----
test_capability_routing_reorders() {
    # On CODE_REVIEW (taste): Claude (affinity 8, taste 8 -> rank 11) should
    # outrank Codex (affinity 10, taste 5 -> rank 10) once routing is on;
    # with routing off, Codex (10) outranks Claude (8).
    ENABLE_CAPABILITY_ROUTING=false
    local off_order
    off_order=$(select_consultants CODE_REVIEW 7 14)
    assert_eq "yes" "$(_first_before "$off_order" Codex Claude)" \
        "routing OFF: Codex (aff 10) ranks above Claude (aff 8)"

    ENABLE_CAPABILITY_ROUTING=true
    local on_order
    on_order=$(select_consultants CODE_REVIEW 7 14)
    assert_eq "yes" "$(_first_before "$on_order" Claude Codex)" \
        "routing ON (taste): Claude (rank 11) ranks above Codex (rank 10)"
}

run_test "Test 1: get_capability lookup + fallback"  test_get_capability
run_test "Test 2: get_category_axis mapping"         test_get_category_axis
run_test "Test 3: _effective_vote_weight math"       test_effective_weight
run_test "Test 4: capability weighting flips winner" test_weighting_flips_winner
run_test "Test 5: capability routing reorders panel" test_capability_routing_reorders

test_summary "capability_weighting"
