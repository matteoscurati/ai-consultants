#!/bin/bash
# grade.sh - Blind YES/NO grader for the panel-vs-baseline experiment.
#
# Forks the taste_elo.sh::_judge harness (pluggable CLI, stdin prompt, single-token
# verdict parse) but grades correctness against an answer-key rubric instead of taste.
#
# The grader is deliberately dumb about provenance: it never sees which arm produced
# an answer. See PREREGISTRATION.md for why (self-preference guard + blinding).
#
# Modes:
#   grade.sh --calibrate                Grade the fixed calibration pairs in the
#                                       benchmark and report grader/expected agreement.
#                                       This is the validity gate: run it, and only
#                                       trust real grades if it clears.
#   grade.sh <benchmark.json> <results.jsonl> [grades.jsonl]
#                                       Grade every {id, arm, answer} line against its
#                                       item's key. Answers are shuffled so grade order
#                                       leaks no arm information.
#
# Env:
#   JUDGE_CLI    grader CLI (default: claude). MUST differ from the arm-A/C model
#                (PREREGISTRATION.md). Invoked as: printf '%s' "$prompt" | "$JUDGE_CLI" -p
#   GRADE_CMD    optional external grader: "$GRADE_CMD" <key> <answer> -> prints YES|NO
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_DEFAULT="$SCRIPT_DIR/benchmark.json"

# One graded verdict for a (key, answer) pair. Echoes YES or NO (or ERR on no parse).
_grade_one() {
    local key="$1" answer="$2"

    if [[ -n "${GRADE_CMD:-}" ]]; then
        "$GRADE_CMD" "$key" "$answer" 2>/dev/null | tr -d '[:space:]' | grep -oiE '(YES|NO)' | head -1 | tr '[:lower:]' '[:upper:]'
        return
    fi

    local prompt verdict
    prompt="You are grading whether an answer found a specific defect. Decide ONLY against the KEY below — ignore style, extra content, and whether the answer found OTHER issues.

KEY (the defect that must be identified): $key

ANSWER: $answer

Does the ANSWER identify the defect described in the KEY? Reply with exactly one word: YES or NO."

    verdict=$(printf '%s' "$prompt" | "${JUDGE_CLI:-claude}" -p 2>/dev/null \
        | tr -d '[:space:]' | grep -oiE '(YES|NO)' | head -1 | tr '[:lower:]' '[:upper:]')
    echo "${verdict:-ERR}"
}

# --- calibration mode: prove the grader before trusting it -------------------
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
        if [[ "$got" == "ERR" ]]; then err=$((err + 1)); mark="ERR (no verdict parsed)"
        elif [[ "$got" == "$expected" ]]; then agree=$((agree + 1)); mark="ok"
        else mark="MISMATCH (expected $expected)"; fi
        printf '  %-16s got=%-3s %s\n' "$id" "$got" "$mark"
    done < <(jq -r '.grader_calibration[] | [.id, .key, .answer, .expected_grade] | @tsv' "$bench")

    echo "----------------------------------------------------"
    if [[ $n -eq 0 ]]; then echo "FAIL: no calibration pairs found"; exit 1; fi
    local pct=$(( agree * 100 / n ))
    echo "Agreement: $agree/$n (${pct}%), $err unparsed"
    # The gate: a grader that cannot clear the obvious cases cannot be trusted on
    # the real ones. 90% mirrors the post-run hand-label gate in PREREGISTRATION.md.
    if [[ $pct -lt 90 || $err -gt 0 ]]; then
        echo "GATE NOT PASSED — do not trust real grades with this grader/prompt."
        exit 1
    fi
    echo "GATE PASSED."
}

# --- grade mode --------------------------------------------------------------
_grade_run() {
    local bench="$1" results="$2" out="${3:-/dev/stdout}"
    [[ -f "$bench" && -f "$results" ]] || { echo "usage: grade.sh <benchmark.json> <results.jsonl> [grades.jsonl]" >&2; exit 1; }

    # Build id -> key once.
    local keymap; keymap=$(jq -c 'reduce .questions[] as $q ({}; .[$q.id] = $q.key)' "$bench")

    : > "$out"
    # Shuffle result lines so the grader sees answers in an order that leaks no arm.
    local shuffled; shuffled=$(mktemp)
    if command -v shuf >/dev/null 2>&1; then shuf "$results" > "$shuffled"; else sort -R "$results" > "$shuffled"; fi

    local line id arm answer key grade
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        id=$(jq -r '.id' <<<"$line")
        arm=$(jq -r '.arm' <<<"$line")
        answer=$(jq -r '.answer // ""' <<<"$line")
        key=$(jq -r --arg id "$id" '.[$id] // ""' <<<"$keymap")
        if [[ -z "$key" ]]; then echo "warn: no key for id=$id, skipping" >&2; continue; fi
        if [[ -z "$answer" ]]; then grade="NO"; else grade=$(_grade_one "$key" "$answer"); fi
        jq -nc --arg id "$id" --arg arm "$arm" --arg grade "$grade" \
            '{id: $id, arm: $arm, grade: $grade}' >> "$out"
    done < "$shuffled"
    rm -f "$shuffled"
    echo "graded -> $out" >&2
}

case "${1:-}" in
    --calibrate) shift; _calibrate "${1:-}" ;;
    ""|-h|--help) echo "usage: grade.sh --calibrate | grade.sh <benchmark.json> <results.jsonl> [grades.jsonl]" ;;
    *) _grade_run "$1" "${2:-}" "${3:-/dev/stdout}" ;;
esac
