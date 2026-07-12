#!/bin/bash
# test_taste_elo.sh — Tier-B pairwise-judge taste Elo (v2.20)
#
# Uses a deterministic stub judge (Claude > Codex > Grok) over two taste-axis
# consultations and asserts the Elo ranking + 1-10 normalization, plus that
# non-taste consultations are ignored.
#
# Usage: ./scripts/test_taste_elo.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/telo.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Stub judge: strictly prefers Claude > Codex > Grok. Called: judge <ctx> <A> <B>.
JUDGE="$TEST_TMPDIR/judge.sh"
cat > "$JUDGE" <<'EOF'
#!/bin/bash
rank() { case "$1" in Claude) echo 3;; Codex) echo 2;; Grok) echo 1;; *) echo 0;; esac; }
ca=$(jq -r '.consultant' "$2"); cb=$(jq -r '.consultant' "$3")
if [[ "$(rank "$ca")" -ge "$(rank "$cb")" ]]; then echo A; else echo B; fi
EOF
chmod +x "$JUDGE"

_resp() { jq -n --arg c "$2" '{consultant:$c, response:{summary:("s-"+$c), approach:("a-"+$c)}, confidence:{score:7}}' > "$1/$2.json"; }
_cat()  { jq -n --arg cat "$2" '{quality_metrics:{category:$cat}}' > "$1/optimization_metrics.json"; }

for r in 1 2; do
    d="$TEST_TMPDIR/c$r"; mkdir -p "$d"
    _cat "$d" CODE_REVIEW
    _resp "$d" Claude; _resp "$d" Codex; _resp "$d" Grok
done

OUT=$(TASTE_JUDGE_CMD="$JUDGE" bash "$SCRIPT_DIR/taste_elo.sh" --json "$TEST_TMPDIR/c1" "$TEST_TMPDIR/c2")
_f() { echo "$OUT" | jq -r "$1"; }

test_elo() {
    assert_eq "6"    "$(_f '.pairs_judged')"                          "6 pairwise judgments (3 pairs x 2 consultations)"
    assert_eq "10"   "$(_f '.taste_scores.Claude')"                   "Claude wins all -> taste 10"
    assert_eq "1"    "$(_f '.taste_scores.Grok')"                     "Grok loses all -> taste 1"
    assert_eq "true" "$(_f '.taste_elo.Claude > .taste_elo.Codex')"   "Claude Elo > Codex Elo"
    assert_eq "true" "$(_f '.taste_elo.Codex > .taste_elo.Grok')"     "Codex Elo > Grok Elo"
}

# Intelligence-axis consultations must be ignored -> nothing to rank -> exit 1.
test_skips_non_taste() {
    local d="$TEST_TMPDIR/algo"; mkdir -p "$d"
    _cat "$d" ALGORITHM
    _resp "$d" Claude; _resp "$d" Codex
    local out
    out=$(TASTE_JUDGE_CMD="$JUDGE" bash "$SCRIPT_DIR/taste_elo.sh" --json "$d" 2>/dev/null; echo "rc=$?")
    assert_match "rc=1" "$out" "intelligence-axis consultation ignored -> exit 1"
}

run_test "Test 1: pairwise-judge Elo ranks taste" test_elo
run_test "Test 2: skips non-taste consultations"  test_skips_non_taste

test_summary "taste_elo"
