#!/bin/bash
# difficulty_probe.sh - measure per-candidate difficulty for the arm-A strong model.
#
# The pilot's lesson: only items a single strong model plausibly MISSES can reveal panel value;
# documented textbook defects (which a strong model nails) make every arm 100% and the experiment
# INCONCLUSIVE by construction. So curation is data-driven, not a guess about "subtlety":
#
#   For each candidate: run the strong model once (arm-A style), grade its finding against the key.
#     CAUGHT  (grader=YES) -> the single strong model already identifies it -> TOO EASY, drop.
#     MISSED  (grader!=YES) -> the strong model does not -> DISCRIMINATING, promote to benchmark.json.
#
# Grader = the validated codex sol-high backend (grade.sh::_grade_one). The item set is therefore
# conditioned on THIS strong model's blind spots — which is the point (panel vs THIS strong model),
# and must be recorded as such in the pre-registration.
#
# Usage: difficulty_probe.sh [pool.json]
# Env:   STRONG_CONSULTANT (default Gemini; must be the binding run's arm-A model),
#        PROBE_VOTES (grader votes, default 3), JUDGE_* (grader backend; default codex sol-high).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/grade.sh"                      # source-safe; provides _grade_one

POOL="${1:-$SCRIPT_DIR/benchmark_pool.json}"
[[ -f "$POOL" ]] || { echo "no pool file: $POOL" >&2; exit 1; }
STRONG="${STRONG_CONSULTANT:-Gemini}"
export JUDGE_VOTES="${PROBE_VOTES:-3}"
strong_q="$REPO/query_$(to_lower "$STRONG").sh"
[[ -x "$strong_q" ]] || { echo "no query script for STRONG_CONSULTANT=$STRONG ($strong_q)" >&2; exit 1; }
CFG="${AI_CONSULTANTS_CONFIG_DIR:-$HOME/.config/ai-consultants}"

miss=0; caught=0; noans=0; n=0; promote=()
echo "difficulty probe: STRONG=$STRONG, grader=${JUDGE_BACKEND:-codex}/${JUDGE_MODEL:-gpt-5.6-sol}@${JUDGE_EFFORT:-high}, votes=$JUDGE_VOTES"
echo "======================================================================================"
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  q=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.prompt' "$POOL")
  key=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.key' "$POOL")
  diff=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.difficulty' "$POOL")
  ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"; out=$(mktemp)
  # A degraded consultant emits the fallback stub "Unstructured response - see detailed" (summary)
  # instead of a real answer. Grading that stub yields NO and would COUNT AS A MISS — a false
  # discriminating item. Detect it (and empty output), RETRY, and if it persists mark NO-ANSWER
  # (a response failure, never a miss). This is a data-collection failure, not evidence the model
  # missed the bug.
  finding=""; attempt=0
  while :; do
    env AI_CONSULTANTS_CONFIG_DIR="$CFG" INVOKING_AGENT="" ENABLE_SEMANTIC_CACHE=false \
      "$strong_q" "" "$ctx" "$out" >/dev/null 2>&1 || true
    finding=$(jq -r '.response.summary // .response.detailed // ""' "$out" 2>/dev/null || echo "")
    [[ -n "$finding" && "$finding" != Unstructured\ response* ]] && break
    attempt=$((attempt + 1)); [[ $attempt -gt "${PROBE_RETRIES:-2}" ]] && break
  done
  n=$((n + 1))
  if [[ -z "$finding" || "$finding" == Unstructured\ response* ]]; then
    verdict="NO-ANSWER"; noans=$((noans + 1)); tag="NO-ANSWER (response failure -> re-probe; NOT a miss)"
  elif [[ "$(_grade_one "$key" "$finding")" == "YES" ]]; then
    verdict="YES"; caught=$((caught + 1)); tag="CAUGHT  (too easy -> drop)"
  else
    verdict="NO"; miss=$((miss + 1)); tag="MISSED  (discriminating -> promote)"; promote+=("$id")
  fi
  printf '  %-26s a-priori=%-6s strong=%-9s %s\n' "$id" "$diff" "$verdict" "$tag"
  printf '      finding: %s\n' "$(printf '%s' "$finding" | tr '\n' ' ' | cut -c1-150)"
  rm -f "$ctx" "$out"
done < <(jq -r '.questions[].id' "$POOL")
echo "======================================================================================"
echo "MISSED (promote) = $miss / $n    CAUGHT (drop) = $caught / $n    NO-ANSWER = $noans / $n"
[[ ${#promote[@]} -gt 0 ]] && printf 'promote: %s\n' "${promote[*]}"
