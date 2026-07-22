#!/bin/bash
# grade.sh - Coverage grader for the v2 experiment.
#
# Forks the taste_elo.sh::_judge harness (pluggable CLI, stdin prompt, single-token verdict)
# but grades COVERAGE: for each arm, does ANY of its VERIFIED findings identify the item's
# keyed defect? Blind (no arm label in the prompt).
#
# Modes:
#   grade.sh --calibrate                Grade the fixed calibration pairs and report agreement.
#                                       The validity gate: run it, trust real grades only if it
#                                       clears (the pilot's low-effort grader failed here in
#                                       spirit — a correct finding scored wrong).
#   grade.sh <benchmark.json> <verified.jsonl> [coverage.jsonl]
#                                       For each {id, arm, verified:[...]} line, grade each
#                                       verified finding against the item key; the arm COVERS
#                                       the defect if any finding scores YES.
#
# Env: JUDGE_CLI (default claude; MUST differ from the arm-A/C model — PREREGISTRATION.md),
#      GRADE_CMD (optional external: "$GRADE_CMD" <key> <finding> -> YES|NO).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DEFAULT="$SCRIPT_DIR/benchmark.json"

# YES|NO: does a single finding identify the defect in the key?
_grade_one() {
  local key="$1" finding="$2"
  if [[ -n "${GRADE_CMD:-}" ]]; then
    "$GRADE_CMD" "$key" "$finding" 2>/dev/null | tr -d '[:space:]' | grep -oiE '(YES|NO)' | head -1 | tr '[:lower:]' '[:upper:]'
    return
  fi
  local prompt verdict
  prompt="You are grading whether a finding identified a specific defect. Decide ONLY against the KEY — ignore style, extra content, and whether the finding also found OTHER issues.

KEY (the defect that must be identified): $key

FINDING: $finding

Does the FINDING identify the defect described in the KEY? Reply with exactly one word: YES or NO."
  verdict=$(printf '%s' "$prompt" | "${JUDGE_CLI:-claude}" -p 2>/dev/null \
    | tr -d '[:space:]' | grep -oiE '(YES|NO)' | head -1 | tr '[:lower:]' '[:upper:]')
  echo "${verdict:-ERR}"
}

# --- calibration: prove the grader before trusting it ------------------------
_calibrate() {
  local bench="${1:-$BENCH_DEFAULT}"
  local n=0 agree=0 err=0
  echo "Grader calibration (JUDGE_CLI=${JUDGE_CLI:-claude})"
  echo "----------------------------------------------------"
  while IFS=$'\t' read -r id key answer expected; do
    [[ -n "$id" ]] || continue
    local got; got=$(_grade_one "$key" "$answer")
    n=$((n + 1))
    local mark
    if [[ "$got" == "ERR" ]]; then err=$((err + 1)); mark="ERR (no verdict)"
    elif [[ "$got" == "$expected" ]]; then agree=$((agree + 1)); mark="ok"
    else mark="MISMATCH (expected $expected)"; fi
    printf '  %-16s got=%-3s %s\n' "$id" "$got" "$mark"
  done < <(jq -r '.grader_calibration[] | [.id, .key, .answer, .expected_grade] | @tsv' "$bench")
  echo "----------------------------------------------------"
  [[ $n -eq 0 ]] && { echo "FAIL: no calibration pairs"; exit 1; }
  local pct=$(( agree * 100 / n ))
  echo "Agreement: $agree/$n (${pct}%), $err unparsed"
  if [[ $pct -lt 90 || $err -gt 0 ]]; then
    echo "GATE NOT PASSED — do not trust real grades with this grader/prompt."; exit 1
  fi
  echo "GATE PASSED."
}

# --- coverage grading --------------------------------------------------------
_grade_coverage() {
  local bench="$1" verified="$2" out="${3:-/dev/stdout}"
  [[ -f "$bench" && -f "$verified" ]] || { echo "usage: grade.sh <benchmark.json> <verified.jsonl> [coverage.jsonl]" >&2; exit 1; }

  local keymap; keymap=$(jq -c 'reduce .questions[] as $q ({}; .[$q.id] = $q.key)' "$bench")
  : > "$out"
  local line id arm key n i finding covered
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id=$(jq -r '.id' <<<"$line")
    arm=$(jq -r '.arm' <<<"$line")
    key=$(jq -r --arg id "$id" '.[$id] // ""' <<<"$keymap")
    [[ -n "$key" ]] || { echo "warn: no key for $id" >&2; continue; }
    n=$(jq '.verified | length' <<<"$line")
    covered="NO"
    for ((i=0; i<n; i++)); do
      finding=$(jq -r --argjson i "$i" '.verified[$i]' <<<"$line")
      [[ -n "$finding" ]] || continue
      if [[ "$(_grade_one "$key" "$finding")" == "YES" ]]; then covered="YES"; break; fi
    done
    jq -nc --arg id "$id" --arg arm "$arm" --arg covered "$covered" \
      '{id:$id, arm:$arm, covered:$covered}' >> "$out"
  done < "$verified"
  echo "coverage -> $out" >&2
}

case "${1:-}" in
  --calibrate) shift; _calibrate "${1:-}" ;;
  ""|-h|--help) echo "usage: grade.sh --calibrate | grade.sh <benchmark.json> <verified.jsonl> [coverage.jsonl]" ;;
  *) _grade_coverage "$1" "${2:-}" "${3:-/dev/stdout}" ;;
esac
