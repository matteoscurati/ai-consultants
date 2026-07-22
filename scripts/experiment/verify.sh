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
# Env:   VERIFY_BACKEND codex (default) | claude. The verifier must be reliable for the same reason
#                       the grader must (measured: claude is noisy both directions; codex sol-high is
#                       not — see grade.sh header). A weak verifier corrupts coverage as a weak grader does.
#        VERIFY_MODEL   backend model. codex: `-m` (default gpt-5.6-sol). claude: `--model` (e.g. opus).
#        VERIFY_EFFORT  codex reasoning effort (default high). Ignored by the claude backend.
#        VERIFY_CLI     claude-backend CLI name (default claude). Ignored by the codex backend.
#        VERIFY_VOTES   majority over N single-shots (default 1; 3 for insurance).
#        VERIFY_CMD     hard override (external: "$VERIFY_CMD" <code> <finding> -> YES|NO).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Extract a single YES|NO from model text: last standalone verdict, upper-cased (word-boundary so
# "no" inside "not"/"cannot"/"none" never matches; tail -1 takes the concluding token).
_extract_verdict() { grep -oiwE '(yes|no)' | tail -1 | tr '[:lower:]' '[:upper:]'; }

# Run ONE verifier call on the chosen backend and echo its raw verdict text.
_verify_backend_call() {  # prompt
  local prompt="$1"
  case "${VERIFY_BACKEND:-codex}" in
    codex)
      # Brief on a file (never spliced into argv); -o isolates the final message; read-only.
      local bf of; bf=$(mktemp); of=$(mktemp); printf '%s' "$prompt" > "$bf"
      codex exec -m "${VERIFY_MODEL:-gpt-5.6-sol}" \
        -c model_reasoning_effort="${VERIFY_EFFORT:-high}" -s read-only \
        "$(cat "$bf")" </dev/null -o "$of" >/dev/null 2>&1 || true
      _extract_verdict < "$of"
      rm -f "$bf" "$of" ;;
    claude|*)
      local -a vcmd=("${VERIFY_CLI:-claude}" -p)
      [[ -n "${VERIFY_MODEL:-}" ]] && vcmd+=(--model "$VERIFY_MODEL")
      printf '%s' "$prompt" | "${vcmd[@]}" 2>/dev/null | _extract_verdict ;;
  esac
}

# ONE single-shot verdict (YES|NO|empty): is the finding a REAL defect in the code?
_verify_once() {
  local code="$1" finding="$2"
  if [[ -n "${VERIFY_CMD:-}" ]]; then
    "$VERIFY_CMD" "$code" "$finding" 2>/dev/null | _extract_verdict
    return
  fi
  # Reason-then-verdict; `tail -1` grabs the concluding token. See the header for the backend note.
  local prompt="You are adversarially verifying a claimed code defect. Try to REFUTE it. Say YES only if the claimed defect is a REAL defect actually present in the code below; say NO if it is vague, wrong, not present, or unsupported by the code.

CODE:
$code

CLAIMED DEFECT: $finding

Think briefly, then on the FINAL line write your verdict as exactly YES or NO (YES if the claimed defect is real and present; otherwise NO)."
  _verify_backend_call "$prompt"
}

# One verdict for (code, finding): is the finding a REAL defect? MAJORITY over VERIFY_VOTES
# single-shots — same variance-reduction reason as the grader. Ties / all-empty -> NO (a weak
# verifier that can't confirm should prune, matching the prior conservative default).
_verify_one() {
  local code="$1" finding="$2" n="${VERIFY_VOTES:-1}" y=0 no=0 i v
  for ((i=0; i<n; i++)); do
    v=$(_verify_once "$code" "$finding")
    case "$v" in YES) y=$((y+1));; NO) no=$((no+1));; esac
  done
  [[ $y -gt $no ]] && echo YES || echo NO
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
