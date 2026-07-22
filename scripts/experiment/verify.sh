#!/bin/bash
# verify.sh - Adversarial verifier for the v2 coverage experiment.
#
# This is the step that makes the workflow a workflow rather than a vote: each finding is
# checked against the CODE by a model that tries to REFUTE it. A finding survives only if
# the verifier confirms it is a real defect present in the code. Hallucinated / vague
# findings are pruned. See PREREGISTRATION.md.
#
# Reads findings.jsonl ({id, arm, findings:[...], tokens, consensus?}) and the benchmark
# (for each item's `prompt`, which carries the code). Writes verified.jsonl:
#   {id, arm, verified:[surviving findings], pruned:N, tokens, consensus?}
#
# The verifier is deliberately NOT the model that produced the finding (self-refutation is
# worthless) and should be run at a capable effort — a weak verifier is as corrupting as a
# weak grader (see the pilot's grader failure).
#
# Usage: verify.sh <benchmark.json> <findings.jsonl> [verified.jsonl]
# Env:   VERIFY_CLI  verifier CLI (default: claude), invoked as: printf '%s' "$p" | CLI -p
#        VERIFY_CMD  optional external verifier: "$VERIFY_CMD" <code> <finding> -> YES|NO
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One verdict for (code, finding): is the finding a REAL defect in the code? YES|NO.
_verify_one() {
  local code="$1" finding="$2"
  if [[ -n "${VERIFY_CMD:-}" ]]; then
    "$VERIFY_CMD" "$code" "$finding" 2>/dev/null | grep -oiwE '(yes|no)' | tail -1 | tr '[:lower:]' '[:upper:]'
    return
  fi
  local prompt verdict
  prompt="You are adversarially verifying a claimed code defect. Try to REFUTE it. Reply YES only if the claimed defect is a REAL defect actually present in the code below; reply NO if it is vague, wrong, not present, or unsupported by the code.

CODE:
$code

CLAIMED DEFECT: $finding

Is the claimed defect a real defect present in this code? Answer with a single word and nothing else: YES or NO."
  verdict=$(printf '%s' "$prompt" | "${VERIFY_CLI:-claude}" -p 2>/dev/null \
    | grep -oiwE '(yes|no)' | tail -1 | tr '[:lower:]' '[:upper:]')
  echo "${verdict:-NO}"   # unparsed -> treat as not-verified (conservative: prune)
}

_main() {
  local bench="$1" findings="$2" out="${3:-/dev/stdout}"
  [[ -f "$bench" && -f "$findings" ]] || { echo "usage: verify.sh <benchmark.json> <findings.jsonl> [verified.jsonl]" >&2; exit 1; }

  # id -> code (the item prompt carries the snippet)
  local codemap; codemap=$(jq -c 'reduce .questions[] as $q ({}; .[$q.id] = $q.prompt)' "$bench")

  : > "$out"
  local line id arm code n_findings i finding v
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id=$(jq -r '.id' <<<"$line")
    arm=$(jq -r '.arm' <<<"$line")
    code=$(jq -r --arg id "$id" '.[$id] // ""' <<<"$codemap")
    n_findings=$(jq '.findings | length' <<<"$line")

    local -a survivors=(); local pruned=0
    for ((i=0; i<n_findings; i++)); do
      finding=$(jq -r --argjson i "$i" '.findings[$i]' <<<"$line")
      [[ -n "$finding" ]] || { pruned=$((pruned+1)); continue; }
      v=$(_verify_one "$code" "$finding")
      if [[ "$v" == "YES" ]]; then survivors+=("$finding"); else pruned=$((pruned+1)); fi
    done

    local varr; if [[ ${#survivors[@]} -eq 0 ]]; then varr="[]"; else varr=$(printf '%s\n' "${survivors[@]}" | jq -R . | jq -s .); fi
    jq -nc --arg id "$id" --arg arm "$arm" --argjson v "$varr" --argjson pruned "$pruned" \
           --argjson tok "$(jq '.tokens' <<<"$line")" \
           --argjson cons "$(jq '.consensus // null' <<<"$line")" \
      '{id:$id, arm:$arm, verified:$v, pruned:$pruned, tokens:$tok} + (if $cons==null then {} else {consensus:$cons} end)' >> "$out"
  done < "$findings"
  echo "verified -> $out" >&2
}

_main "${1:-}" "${2:-}" "${3:-/dev/stdout}"
