#!/bin/bash
# breadth_experiment.sh - the A/W/C coverage comparison on breadth items (where headroom EXISTS:
# arm-A rubric coverage measured ~71%, unlike defect-finding which saturated at 100%).
#
# Per item, rubric = a SET of valid points; an arm's coverage = fraction of rubric points that appear
# in the arm's answer(s):
#   arm A = the strong model, ONCE.
#   arm W = the diverse PANEL fanned out once each (NO deliberation — just the union of raw answers).
#   arm C = the strong model sampled k times (k = panel size), union of the k answers.
# The two comparisons that decide it:
#   W > A  -> the panel covers points one model misses (the panel's claimed edge).
#   W vs C -> is that extra coverage from DIVERSE models (W > C) or just more attempts (W ~ C)?
#
# Grader = codex sol-high (grade.sh::_grade_one), one grade per (arm, rubric point).
# THIS SPENDS REAL MODEL CALLS. Panel excludes the grader vendor (CODEX), the session CLI (CLAUDE),
# and dead consultants (CURSOR) — vendor-disjointness, as the defect pilot established.
#
# Usage: breadth_experiment.sh [breadth_pool.json] [outdir]
# Env: STRONG_CONSULTANT (default Gemini), BREADTH_PANEL (space-separated ids), PROBE_VOTES (grader
#      votes, default 1), PROBE_RETRIES (default 2), JUDGE_* (grader backend).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/lib/common.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/grade.sh"

POOL="${1:-$SCRIPT_DIR/benchmark_breadth.json}"
OUT="${2:-$SCRIPT_DIR/out_breadth}"
[[ -f "$POOL" ]] || { echo "no breadth pool: $POOL" >&2; exit 1; }
STRONG="${STRONG_CONSULTANT:-Gemini}"
PANEL="${BREADTH_PANEL:-Gemini Mistral Kimi Qwen3 GLM Grok DeepSeek MiniMax}"
export JUDGE_VOTES="${PROBE_VOTES:-1}"
CFG="${AI_CONSULTANTS_CONFIG_DIR:-$HOME/.config/ai-consultants}"
rm -rf "$OUT"; mkdir -p "$OUT"
read -r -a PANEL_ARR <<< "$PANEL"
K=${#PANEL_ARR[@]}

# Run one consultant once; echo its full answer text ("" on failure/degraded, with retries).
_one_answer() {  # consultant  ctxfile
  local c="$1" ctx="$2" qscript out ans attempt=0
  qscript="$REPO/query_$(to_lower "$c").sh"
  [[ -x "$qscript" ]] || { echo ""; return; }
  out=$(mktemp)
  while :; do
    env AI_CONSULTANTS_CONFIG_DIR="$CFG" INVOKING_AGENT="" ENABLE_SEMANTIC_CACHE=false \
      "$qscript" "" "$ctx" "$out" >/dev/null 2>&1 || true
    ans=$(jq -r '[.response.summary, .response.detailed,
                  (.response.pros//[]|join(" ; ")), (.response.cons//[]|join(" ; ")),
                  (.response.caveats//[]|join(" ; "))]
                 | map(select(. != null and . != "")) | join("\n")' "$out" 2>/dev/null || echo "")
    [[ -n "$ans" && "$ans" != Unstructured\ response* ]] && break
    attempt=$((attempt + 1)); [[ $attempt -gt "${PROBE_RETRIES:-2}" ]] && { ans=""; break; }
  done
  rm -f "$out"; printf '%s' "$ans"
}

# Coverage of a rubric by an answer blob -> "covered total". Prints per-point HIT/miss to stderr.
_coverage() {  # id  answerblob
  local id="$1" blob="$2" np j point cov=0
  np=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.rubric|length' "$POOL")
  for ((j=0; j<np; j++)); do
    point=$(jq -r --arg id "$id" --argjson j "$j" '.questions[]|select(.id==$id)|.rubric[$j]' "$POOL")
    if [[ -n "$blob" && "$(_grade_one "$point" "$blob")" == "YES" ]]; then cov=$((cov+1)); fi
  done
  echo "$cov $np"
}

echo "breadth A/W/C: STRONG=$STRONG  PANEL=($PANEL) K=$K  grader=codex sol-high votes=$JUDGE_VOTES"
echo "=================================================================================="
SUM_A=0; SUM_W=0; SUM_C=0; SUM_D=0   # plain ints (macOS /bin/bash is 3.2 — no associative arrays)
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  q=$(jq -r --arg id "$id" '.questions[]|select(.id==$id)|.prompt' "$POOL")
  ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"

  # arm A: strong once
  ansA=$(_one_answer "$STRONG" "$ctx")
  # arm W: panel union
  blobW=""
  for c in "${PANEL_ARR[@]}"; do
    a=$(_one_answer "$c" "$ctx"); [[ -n "$a" ]] && blobW+="=== $c ==="$'\n'"$a"$'\n\n'
  done
  # arm C: strong x K union
  blobC=""
  for ((i=1; i<=K; i++)); do
    a=$(_one_answer "$STRONG" "$ctx"); [[ -n "$a" ]] && blobC+="=== sample $i ==="$'\n'"$a"$'\n\n'
  done
  rm -f "$ctx"
  # Persist raw answers so grader coverage decisions can be hand-checked (verify, don't trust counts).
  printf '%s' "$ansA" > "$OUT/$id.A.txt"; printf '%s' "$blobW" > "$OUT/$id.W.txt"; printf '%s' "$blobC" > "$OUT/$id.C.txt"

  read -r cA nA < <(_coverage "$id" "$ansA")
  read -r cW _  < <(_coverage "$id" "$blobW")
  read -r cC _  < <(_coverage "$id" "$blobC")
  printf '  %-26s A=%2d/%-2d   W=%2d/%-2d   C=%2d/%-2d\n' "$id" "$cA" "$nA" "$cW" "$nA" "$cC" "$nA"
  SUM_A=$(( SUM_A + cA )); SUM_W=$(( SUM_W + cW )); SUM_C=$(( SUM_C + cC )); SUM_D=$(( SUM_D + nA ))
  jq -nc --arg id "$id" --argjson a "$cA" --argjson w "$cW" --argjson c "$cC" --argjson n "$nA" \
    '{id:$id, A:$a, W:$w, C:$c, n:$n}' >> "$OUT/breadth_coverage.jsonl"
done < <(jq -r '.questions[].id' "$POOL")
echo "=================================================================================="
if [[ $SUM_D -gt 0 ]]; then
  printf 'OVERALL coverage:  A = %d/%d (%d%%)   W = %d/%d (%d%%)   C = %d/%d (%d%%)\n' \
    "$SUM_A" "$SUM_D" "$(( 100*SUM_A/SUM_D ))" \
    "$SUM_W" "$SUM_D" "$(( 100*SUM_W/SUM_D ))" \
    "$SUM_C" "$SUM_D" "$(( 100*SUM_C/SUM_D ))"
  echo "  W > A: panel covers what one model misses.   W > C: diversity, not just volume.   W ~ C: volume."
fi
echo "-> $OUT/breadth_coverage.jsonl"
