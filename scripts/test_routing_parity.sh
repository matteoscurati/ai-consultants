#!/bin/bash
# test_routing_parity.sh - Golden test for routing affinity matrix
#
# Locks in the (category, consultant) -> score table that was previously
# encoded as nested case statements in lib/routing.sh (pre-v2.11.0). After
# externalizing the matrix to references/affinity.json, this test guards
# against silent drift: any change to the JSON must be reflected here on
# purpose, not by accident.
#
# Also covers:
#   - Unknown consultants always return default_score (5)
#   - Unknown categories return general_score (8) for known consultants
#   - GENERAL category behaves like an unknown category
#   - AFFINITY_FILE override switches the data source
#
# Usage: ./scripts/test_routing_parity.sh
# Exit:  0 on full match, 1 on any mismatch

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/routing.sh"

failed=0
checked=0

assert_score() {
    local category="$1"
    local consultant="$2"
    local expected="$3"
    local actual
    actual=$(get_affinity "$category" "$consultant")
    ((checked++)) || true
    if [[ "$actual" != "$expected" ]]; then
        echo -e "  ${C_RED}FAIL${C_RESET}: $category / $consultant -> expected $expected, got $actual"
        ((failed++)) || true
    fi
}

# Format below: one line per category, columns in fixed order matching
# known_consultants in references/affinity.json.
order=(Gemini Codex Mistral Cursor Kimi Claude Qwen3 GLM Grok DeepSeek MiniMax)

#                  Gem Cdx Mst Crs Kim Cld Qw3 GLM Grk DSk MnM
golden_CODE_REVIEW=(7 10  8   9   7   8   8   8   7   10  8)
golden_BUG_DEBUG=(  7 10  9   9   6   7   8   8   7   9   8)
golden_ARCHITECTURE=(10 6  8   8   9   9   7   7   9   7   7)
golden_ALGORITHM=(  9  8  7   7   8   7   9   7   8   10  8)
golden_SECURITY=(   9  9 10   8   7   8   7   8   8   8   7)
golden_QUICK_SYNTAX=(10 8 5   7   5   6   7   6   5   9   8)
golden_DATABASE=(   8  9  7   8   7   7   9   7   6   9   8)
golden_API_DESIGN=(10  9  7   9   8   8   7   8   8   8   8)
golden_TESTING=(    7 10  9   9   6   7   8  10   7   8   7)

check_category() {
    local category="$1"
    shift
    local -a scores=("$@")
    local i=0
    for consultant in "${order[@]}"; do
        assert_score "$category" "$consultant" "${scores[$i]}"
        i=$((i+1))
    done
}

echo "Golden parity: 9 categories x 11 consultants"
check_category CODE_REVIEW   "${golden_CODE_REVIEW[@]}"
check_category BUG_DEBUG     "${golden_BUG_DEBUG[@]}"
check_category ARCHITECTURE  "${golden_ARCHITECTURE[@]}"
check_category ALGORITHM     "${golden_ALGORITHM[@]}"
check_category SECURITY      "${golden_SECURITY[@]}"
check_category QUICK_SYNTAX  "${golden_QUICK_SYNTAX[@]}"
check_category DATABASE      "${golden_DATABASE[@]}"
check_category API_DESIGN    "${golden_API_DESIGN[@]}"
check_category TESTING       "${golden_TESTING[@]}"

echo ""
echo "Edge cases:"

# Unknown consultant: always default_score (5)
for cat in CODE_REVIEW SECURITY GENERAL UNRECOGNIZED_CAT; do
    assert_score "$cat" "FakeConsultant" 5
done

# Unknown category for known consultant: general_score (8)
for c in Gemini Codex DeepSeek; do
    assert_score "GENERAL"          "$c" 8
    assert_score "TOTALLY_UNKNOWN"  "$c" 8
done

# AFFINITY_FILE override + auto-invalidation of the file-content cache.
# We deliberately do NOT manually reset _AFFINITY_LOADED_FILE: this proves
# that _load_affinity_data() picks up the new file path without intervention.
tmpfile=$(mktemp -t ai_consultants_affinity_test.XXXXXX.json)
trap 'rm -f "$tmpfile"' EXIT
cat > "$tmpfile" <<'JSON'
{
  "version": "1.0",
  "default_score": 1,
  "general_score": 2,
  "known_consultants": ["Gemini"],
  "categories": { "TEST_CAT": { "Gemini": 99 } }
}
JSON

# Warm the default cache first so we'd see a stale read if invalidation broke
get_affinity CODE_REVIEW Gemini >/dev/null

AFFINITY_FILE="$tmpfile" assert_score "TEST_CAT" "Gemini" 99
AFFINITY_FILE="$tmpfile" assert_score "TEST_CAT" "Codex"  1   # Codex not in known_consultants
AFFINITY_FILE="$tmpfile" assert_score "OTHER"    "Gemini" 2   # Gemini known, category absent

# Switch back to default — must invalidate again
assert_score "CODE_REVIEW" "Gemini" 7   # default file's value, NOT 99 from override

# Cache substring-collision regression (HIGH bug fixed in v2.11.0 review pass).
# Pre-fix, the cache used `*"${key}"*` glob match where key was "CAT|C=" with
# no boundary delimiter, so e.g. "DEBUG|X=" was a substring of "BUG_DEBUG|X="
# and the second lookup would return the first's score.
collision_file=$(mktemp -t ai_consultants_collision_test.XXXXXX.json)
trap 'rm -f "$tmpfile" "$collision_file"' EXIT
cat > "$collision_file" <<'JSON'
{
  "version": "1.0",
  "default_score": 5,
  "general_score": 8,
  "known_consultants": ["Z"],
  "categories": {
    "BUG_DEBUG": { "Z": 99 },
    "DEBUG":     { "Z": 11 }
  }
}
JSON
# Order matters: hit BUG_DEBUG first to seed the cache, then verify DEBUG
# does NOT incorrectly return BUG_DEBUG's value.
AFFINITY_FILE="$collision_file" assert_score "BUG_DEBUG" "Z" 99
AFFINITY_FILE="$collision_file" assert_score "DEBUG"     "Z" 11
# Reverse direction too: warm DEBUG, then verify BUG_DEBUG isn't affected
_AFFINITY_LOADED_FILE=""   # force reload to clear result cache
AFFINITY_FILE="$collision_file" assert_score "DEBUG"     "Z" 11
AFFINITY_FILE="$collision_file" assert_score "BUG_DEBUG" "Z" 99

# v2.12 search path: user-dir affinity.json picked up when AFFINITY_FILE unset.
# Pre-v2.12 the user dir was ignored; only AFFINITY_FILE or bundled was read.
user_dir_test=$(mktemp -d -t ai_consultants_userdir_test.XXXXXX)
trap 'rm -f "$tmpfile" "$collision_file"; rm -rf "$user_dir_test"' EXIT
cat > "$user_dir_test/affinity.json" <<'JSON'
{
  "version": "1.0",
  "default_score": 5,
  "general_score": 8,
  "known_consultants": ["Y"],
  "categories": { "USER_CAT": { "Y": 77 } }
}
JSON
# Force a fresh resolution: clear any cached state and unset AFFINITY_FILE
unset AFFINITY_FILE
_AFFINITY_LOADED_FILE=""
AI_CONSULTANTS_CONFIG_DIR="$user_dir_test" assert_score "USER_CAT" "Y" 77

# AFFINITY_FILE still wins over user dir
unset AFFINITY_FILE
_AFFINITY_LOADED_FILE=""
AFFINITY_FILE="$collision_file" AI_CONSULTANTS_CONFIG_DIR="$user_dir_test" \
    assert_score "BUG_DEBUG" "Z" 99   # collision_file value wins, NOT user-dir

echo ""
if [[ $failed -eq 0 ]]; then
    echo -e "${C_GREEN}routing parity: OK${C_RESET} ($checked checks passed)"
    exit 0
else
    echo -e "${C_RED}routing parity: FAILED${C_RESET} ($failed of $checked checks failed)"
    exit 1
fi
