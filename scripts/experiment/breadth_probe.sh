#!/bin/bash
# breadth_probe.sh - measure a single strong model's COVERAGE of a breadth rubric (arm-A headroom).
#
# Breadth is the one regime where a diverse panel could still beat one model: open-ended questions
# with a SET of valid points, where a union of different models might cover points one model misses.
# The precondition (as with the difficulty probe) is measured first: does a single strong model
# already SATURATE the rubric?
#   coverage_A ~ 100%  -> breadth saturates too; the panel has no headroom (same verdict as defects).
#   coverage_A partial -> headroom exists; running the panel union to see if it fills the gap is worth it.
#
# For each item: run the strong model once (retrying past the degraded "Unstructured response" stub),
# collect its full enumerated answer, then grade EACH rubric point for coverage with the codex grader
# (grade.sh::_grade_one). Reuses the difficulty-probe machinery for a SET-valued key.
#
# Usage: breadth_probe.sh [breadth_pool.json]
# Env:   STRONG_CONSULTANT (default Gemini), PROBE_VOTES (grader votes, default 1 — breadth is many
#        grades/item), PROBE_RETRIES (default 2), JUDGE_* (grader backend; default codex sol-high).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/grade.sh"                      # source-safe; provides _grade_one

POOL="${1:-$SCRIPT_DIR/benchmark_breadth.json}"
[[ -f "$POOL" ]] || { echo "no breadth pool: $POOL" >&2; exit 1; }
STRONG="${STRONG_CONSULTANT:-Gemini}"
export JUDGE_VOTES="${PROBE_VOTES:-1}"
strong_q="$REPO/query_$(to_lower "$STRONG").sh"
[[ -x "$strong_q" ]] || { echo "no query script for STRONG_CONSULTANT=$STRONG ($strong_q)" >&2; exit 1; }
CFG="${AI_CONSULTANTS_CONFIG_DIR:-$HOME/.config/ai-consultants}"

echo "breadth probe (arm-A coverage): STRONG=$STRONG, grader=${JUDGE_BACKEND:-codex}/${JUDGE_MODEL:-gpt-5.6-sol}@${JUDGE_EFFORT:-high}, votes=$JUDGE_VOTES"
echo "======================================================================================"
num_total=0; den_total=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  q=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.prompt' "$POOL")
  ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"; out=$(mktemp)
  finding=""; attempt=0
  while :; do
    env AI_CONSULTANTS_CONFIG_DIR="$CFG" INVOKING_AGENT="" ENABLE_SEMANTIC_CACHE=false \
      "$strong_q" "" "$ctx" "$out" >/dev/null 2>&1 || true
    # Full enumerated answer: join every text field of the structured envelope.
    finding=$(jq -r '[.response.summary, .response.detailed,
                      (.response.pros//[]|join(" ; ")), (.response.cons//[]|join(" ; ")),
                      (.response.caveats//[]|join(" ; "))]
                     | map(select(. != null and . != "")) | join("\n")' "$out" 2>/dev/null || echo "")
    [[ -n "$finding" && "$finding" != Unstructured\ response* ]] && break
    attempt=$((attempt + 1)); [[ $attempt -gt "${PROBE_RETRIES:-2}" ]] && break
  done
  rm -f "$ctx" "$out"

  local_npts=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.rubric|length' "$POOL")
  if [[ -z "$finding" || "$finding" == Unstructured\ response* ]]; then
    printf '  %-26s NO-ANSWER (response failure -> re-probe)\n' "$id"; continue
  fi
  covered=0
  echo "  $id  ($local_npts rubric points):"
  for ((j=0; j<local_npts; j++)); do
    point=$(jq -r --arg id "$id" --argjson j "$j" '.questions[]|select(.id==$id)|.rubric[$j]' "$POOL")
    if [[ "$(_grade_one "$point" "$finding")" == "YES" ]]; then
      covered=$((covered + 1)); mark="HIT "
    else
      mark="miss"
    fi
    printf '      [%s] %s\n' "$mark" "$(printf '%s' "$point" | cut -c1-92)"
  done
  printf '    -> coverage_A = %d/%d\n' "$covered" "$local_npts"
  num_total=$((num_total + covered)); den_total=$((den_total + local_npts))
done < <(jq -r '.questions[].id' "$POOL")
echo "======================================================================================"
if [[ $den_total -gt 0 ]]; then
  printf 'OVERALL arm-A rubric coverage = %d/%d (%d%%)\n' "$num_total" "$den_total" "$(( 100 * num_total / den_total ))"
  echo "  (~100% -> breadth saturates, panel has no headroom; clearly partial -> run the panel union)"
fi
