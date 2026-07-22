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
# The grader MUST be reliable and a DIFFERENT model from arm A/C (PREREGISTRATION.md). Choosing it
# is not incidental — it was measured (both directions, per call, N samples):
#   claude -p, session default : cal-correct-1 (obvious YES) graded YES only 5/12 — a coin flip.
#   claude -p --model opus      : 6-8/10 YES on that pair, and only 3/6 NO on an obvious-WRONG pair
#                                 (it over-matches under a sharper prompt). Noisy BOTH ways; unusable.
#   codex gpt-5.6-sol @ high    : 6/6 YES on the correct pair, 4/4 NO on the wrong pair. Reliable.
# So the DEFAULT backend is codex sol-high, not claude. (v1 also found Codex passed the gate 4/4.)
#
# Env: JUDGE_BACKEND codex (default) | claude
#      JUDGE_MODEL   backend model. codex: `-m` (default gpt-5.6-sol). claude: `--model` (e.g. opus).
#      JUDGE_EFFORT  codex reasoning effort (default high). Ignored by the claude backend.
#      JUDGE_CLI     claude-backend CLI name (default claude). Ignored by the codex backend.
#      JUDGE_VOTES   majority over N single-shots (default 1; the reliable backend needs little,
#                    use 3 for insurance). Variance reduction; applied to calibration and real grades.
#      GRADE_CMD     hard override (external: "$GRADE_CMD" <key> <finding> -> YES|NO).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DEFAULT="$SCRIPT_DIR/benchmark.json"

# Extract a single YES|NO from model text: last standalone verdict, upper-cased. Word-boundary
# so "no" inside "not"/"cannot"/"none" never matches; tail -1 takes the concluding token.
_extract_verdict() { grep -oiwE '(yes|no)' | tail -1 | tr '[:lower:]' '[:upper:]'; }

# Run ONE grader call on the chosen backend and echo its raw verdict text.
_judge_backend_call() {  # prompt
  local prompt="$1"
  case "${JUDGE_BACKEND:-codex}" in
    codex)
      # Brief on a file (never spliced into argv — it carries quotes/backticks/newlines);
      # -o <file> isolates the final message (raw stdout carries hook chatter). read-only.
      local bf of; bf=$(mktemp); of=$(mktemp); printf '%s' "$prompt" > "$bf"
      codex exec -m "${JUDGE_MODEL:-gpt-5.6-sol}" \
        -c model_reasoning_effort="${JUDGE_EFFORT:-high}" -s read-only \
        "$(cat "$bf")" </dev/null -o "$of" >/dev/null 2>&1 || true
      _extract_verdict < "$of"
      rm -f "$bf" "$of" ;;
    claude|*)
      local -a jcmd=("${JUDGE_CLI:-claude}" -p)
      [[ -n "${JUDGE_MODEL:-}" ]] && jcmd+=(--model "$JUDGE_MODEL")
      printf '%s' "$prompt" | "${jcmd[@]}" 2>/dev/null | _extract_verdict ;;
  esac
}

# ONE single-shot verdict (YES|NO|empty) from the grader.
_grade_once() {
  local key="$1" finding="$2"
  if [[ -n "${GRADE_CMD:-}" ]]; then
    "$GRADE_CMD" "$key" "$finding" 2>/dev/null | _extract_verdict
    return
  fi
  # Match on MEANING, not wording: a finding matches if it names the SAME underlying bug — even in
  # different words, or describing the cause OR the consequence. Reason-then-verdict; `tail -1`
  # grabs the conclusion. (This exact framing kept codex 6/6 on the correct pair AND 4/4 on the
  # wrong one; the looser "cause or consequence" clause made the noisy claude backend over-match,
  # which is why the backend, not just the prompt, had to change.)
  local prompt="You are grading whether a FINDING correctly identifies a specific known defect described in the KEY.

The FINDING MATCHES (YES) if it describes the SAME underlying bug as the KEY — even in different words, at a different level of detail, or focusing on the defect's CAUSE or its CONSEQUENCE. It does NOT match (NO) only if it points at a DIFFERENT issue, a vague/non-specific concern, or nothing relevant to the KEY's defect. Ignore writing style and any extra issues the finding also raises.

KEY: $key

FINDING: $finding

Think briefly, then on the FINAL line write your verdict as exactly YES or NO."
  _judge_backend_call "$prompt"
}

# YES|NO: does a finding identify the defect in the key? MAJORITY over JUDGE_VOTES single-shots.
# The codex sol-high backend is near-deterministic on the calibration pairs (votes=1 suffices), but
# voting stays available as cheap insurance / for the noisier claude backend. Applied identically to
# calibration and real grades (fair). Ties / all-empty -> ERR (calibration flags it; coverage treats
# non-YES as not-covered). JUDGE_VOTES=1 preserves the single-shot behavior for the $0 smoke path.
_grade_one() {
  local key="$1" finding="$2" n="${JUDGE_VOTES:-1}" y=0 no=0 i v
  for ((i=0; i<n; i++)); do
    v=$(_grade_once "$key" "$finding")
    case "$v" in YES) y=$((y+1));; NO) no=$((no+1));; esac
  done
  if   [[ $y -gt $no ]]; then echo YES
  elif [[ $no -gt $y ]]; then echo NO
  else echo ERR; fi
}

# --- calibration: prove the grader before trusting it ------------------------
_calibrate() {
  local bench="${1:-$BENCH_DEFAULT}"
  local n=0 agree=0 err=0
  local _bk="${JUDGE_BACKEND:-codex}" _mdl
  if [[ "$_bk" == codex ]]; then _mdl="${JUDGE_MODEL:-gpt-5.6-sol} @${JUDGE_EFFORT:-high}"; else _mdl="${JUDGE_CLI:-claude}${JUDGE_MODEL:+ --model $JUDGE_MODEL}"; fi
  echo "Grader calibration (backend=$_bk, model=$_mdl, votes=${JUDGE_VOTES:-1})"
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
