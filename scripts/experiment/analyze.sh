#!/bin/bash
# analyze.sh - Compute the verdict for the panel-vs-baseline experiment.
#
# Joins grades (correctness per item/arm) with results (tokens + arm-B consensus),
# computes per-arm hit rate and the paired sign tests B-vs-A and B-vs-C, then prints
# which pre-registered decision branch fires. It does NOT decide anything beyond
# printing that branch — the decision rule is frozen in PREREGISTRATION.md.
#
# Usage: analyze.sh <grades.jsonl> <results.jsonl>
#
# Inputs:
#   grades.jsonl   {id, arm, grade}          grade in {YES, NO, ERR}
#   results.jsonl  {id, arm, tokens, consensus?}
set -euo pipefail

GRADES="${1:-}"; RESULTS="${2:-}"
[[ -f "$GRADES" && -f "$RESULTS" ]] || { echo "usage: analyze.sh <grades.jsonl> <results.jsonl>" >&2; exit 1; }

# A grade of ERR is a grader failure, not a wrong answer — exclude those items from
# the pair rather than silently scoring them NO, and report how many were dropped.
errs=$(jq -rs '[.[] | select(.grade=="ERR")] | length' "$GRADES")

echo "=== Per-arm hit rate ==="
for arm in A B C; do
  jq -rs --arg arm "$arm" '
    [.[] | select(.arm==$arm)] as $g
    | ($g | map(select(.grade=="YES")) | length) as $hit
    | ($g | map(select(.grade=="YES" or .grade=="NO")) | length) as $dec
    | "  arm \($arm): \($hit)/\($dec) correct" + (if $dec==0 then " (no decided items)" else " (\((100*$hit/$dec)|floor)%)" end)
  ' "$GRADES"
done
[[ "$errs" -gt 0 ]] && echo "  ($errs item(s) dropped: grader returned ERR)"

# Paired sign test: for each id, B vs X. win = B correct & X wrong; loss = reverse.
# Ties and any ERR-involving pair are undecided and excluded.
_sign() {
  local other="$1"
  jq -rs --arg other "$other" '
    (reduce .[] as $r ({}; .[$r.id][$r.arm] = $r.grade)) as $m
    | [ $m | to_entries[] | .value | select(.B != null and .[$other] != null)
        | select(.B != "ERR" and .[$other] != "ERR")
        | if .B=="YES" and .[$other]=="NO" then "win"
          elif .B=="NO" and .[$other]=="YES" then "loss"
          else "tie" end ] as $p
    | ($p | map(select(.=="win")) | length) as $w
    | ($p | map(select(.=="loss")) | length) as $l
    | "\($w) \($l) \(($w+$l))"
  ' "$GRADES"
}

read -r BA_w BA_l BA_d < <(_sign A)
read -r BC_w BC_l BC_d < <(_sign C)

echo ""
echo "=== Paired sign test (B vs baseline) ==="
echo "  B vs A: $BA_w wins, $BA_l losses, $BA_d decided pairs"
echo "  B vs C: $BC_w wins, $BC_l losses, $BC_d decided pairs"

# Pre-registered margin: B "beats" X when wins exceed losses AND wins clear a sign-test
# threshold. For ~30 decided pairs a two-sided sign test at alpha~0.05 needs ~21/30;
# generalize as wins >= ceil(0.68 * decided) with wins > losses. Below that margin the
# two arms are "roughly equal" (B ~= X), which is the load-bearing B~=C outcome.
_beats() {  # <wins> <losses> <decided>  -> "yes" | "no"
  local w="$1" l="$2" d="$3"
  [[ "$d" -eq 0 ]] && { echo no; return; }
  local need=$(( (68 * d + 99) / 100 ))   # ceil(0.68*d)
  if [[ "$w" -gt "$l" && "$w" -ge "$need" ]]; then echo yes; else echo no; fi
}

B_beats_A=$(_beats "$BA_w" "$BA_l" "$BA_d")
B_beats_C=$(_beats "$BC_w" "$BC_l" "$BC_d")
A_beats_B=$(_beats "$BA_l" "$BA_w" "$BA_d")   # is A better than B?

echo ""
echo "=== Pre-registered decision (see PREREGISTRATION.md) ==="
if [[ "$B_beats_A" == "yes" && "$B_beats_C" == "yes" ]]; then
  echo "  -> INVEST: B beats both A and C. The deliberation machinery earns its complexity."
elif [[ "$A_beats_B" == "yes" ]]; then
  echo "  -> CODEX VINDICATED: A beats B. The machinery subtracts value."
else
  echo "  -> CUT TO MINIMAL CORE: B does not clear both baselines (B ~= C). Model diversity"
  echo "     may be real but multi-round deliberation is not — candidate for removal:"
  echo "     voting, lexical consensus, panic mode, convergence loops, capability weighting."
fi

# --- Secondary metric: does arm-B consensus predict when arm A is wrong? ------
echo ""
echo "=== Secondary: arm-B consensus vs arm-A correctness ==="
# Join: for each id, arm-A grade (from grades) and arm-B consensus (from results).
join_tmp=$(mktemp)
jq -rs '[.[] | select(.arm=="A")] | map({(.id): .grade}) | add // {}' "$GRADES" > "$join_tmp.ag"
jq -rs '[.[] | select(.arm=="B" and (.consensus!=null))] | map({(.id): .consensus}) | add // {}' "$RESULTS" > "$join_tmp.bc"
jq -rn --slurpfile ag "$join_tmp.ag" --slurpfile bc "$join_tmp.bc" '
  ($ag[0]) as $A | ($bc[0]) as $C
  | [ $C | to_entries[] | select($A[.key] != null) | {id:.key, cons:.value, a:$A[.key]} ] as $rows
  | ($rows | map(select(.a=="YES")) | map(.cons)) as $right
  | ($rows | map(select(.a=="NO"))  | map(.cons)) as $wrong
  | "  mean arm-B consensus when A correct: " + (if ($right|length)>0 then ((($right|add)/($right|length))|floor|tostring) else "n/a" end)
    + "  (n=\($right|length))",
    "  mean arm-B consensus when A wrong:   " + (if ($wrong|length)>0 then ((($wrong|add)/($wrong|length))|floor|tostring) else "n/a" end)
    + "  (n=\($wrong|length))",
    "  (if the second is meaningfully lower, the panel is worth keeping as an uncertainty meter)"
'
rm -f "$join_tmp" "$join_tmp.ag" "$join_tmp.bc"

# --- Token-spend check: confirm arms were actually matched -------------------
echo ""
echo "=== Token spend per arm (should be roughly matched B vs C) ==="
for arm in A B C; do
  jq -rs --arg arm "$arm" '
    [.[] | select(.arm==$arm and (.tokens!=null)) | .tokens] as $t
    | if ($t|length)>0 then "  arm \($arm): mean \((($t|add)/($t|length))|floor) tokens/item (n=\($t|length))"
      else "  arm \($arm): no token data" end
  ' "$RESULTS"
done

echo ""
echo "Reminder: a verdict is only valid if grade.sh --calibrate passed AND the post-run"
echo "hand-label of 10 random verdicts agrees >=90% (PREREGISTRATION.md)."
