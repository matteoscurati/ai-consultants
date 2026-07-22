#!/bin/bash
# analyze.sh - v2 COVERAGE verdict.
#
# Coverage rate per arm; the decisive comparison of DISCORDANT pairs (items W catches that
# A misses vs items A catches that W misses); cost per covered defect; and adversarial
# -verification pruning stats. Prints the pre-registered branch; decides nothing beyond
# that (the rule is frozen in PREREGISTRATION.md).
#
# Usage: analyze.sh <coverage.jsonl> <verified.jsonl>
#   coverage.jsonl  {id, arm, covered}      covered in {YES, NO}
#   verified.jsonl  {id, arm, verified:[...], pruned, tokens, consensus?}
set -euo pipefail
COV="${1:-}"; VER="${2:-}"
[[ -f "$COV" && -f "$VER" ]] || { echo "usage: analyze.sh <coverage.jsonl> <verified.jsonl>" >&2; exit 1; }

echo "=== Coverage rate per arm (verified finding contains the keyed defect) ==="
for arm in A W C; do
  jq -rs --arg arm "$arm" '
    [.[] | select(.arm==$arm)] as $g
    | ($g | map(select(.covered=="YES")) | length) as $hit
    | ($g | length) as $tot
    | "  arm \($arm): \($hit)/\($tot) covered" + (if $tot>0 then " (\((100*$hit/$tot)|floor)%)" else "" end)
  ' "$COV"
done

# Discordant-pair counts for W vs a baseline. Echoes "<W_only> <base_only> <discordant>".
_disc() {
  local base="$1"
  jq -rs --arg base "$base" '
    (reduce .[] as $r ({}; .[$r.id][$r.arm] = $r.covered)) as $m
    | [ $m | to_entries[] | .value | select(.W != null and .[$base] != null)
        | if .W=="YES" and .[$base]=="NO" then "wonly"
          elif .W=="NO" and .[$base]=="YES" then "bonly"
          else "concord" end ] as $p
    | ($p | map(select(.=="wonly")) | length) as $w
    | ($p | map(select(.=="bonly")) | length) as $b
    | "\($w) \($b) \($w+$b)"
  ' "$COV"
}
read -r WA_w WA_b WA_d < <(_disc A)
read -r WC_w WC_b WC_d < <(_disc C)

echo ""
echo "=== Uncorrelated value (discordant pairs) ==="
echo "  W vs A: W caught+A missed = $WA_w | A caught+W missed = $WA_b | discordant = $WA_d"
echo "  W vs C: W caught+C missed = $WC_w | C caught+W missed = $WC_b | discordant = $WC_d"

# W "beats" baseline when extra catches exceed the baseline's AND clear a sign-test margin
# on the discordant pairs: wins >= ceil(0.68 * discordant), wins > losses.
_beats() { # <wins> <losses> <discordant> -> yes|no
  local w="$1" l="$2" d="$3"
  [[ "$d" -eq 0 ]] && { echo no; return; }
  local need=$(( (68 * d + 99) / 100 ))
  if [[ "$w" -gt "$l" && "$w" -ge "$need" ]]; then echo yes; else echo no; fi
}
W_beats_A=$(_beats "$WA_w" "$WA_b" "$WA_d")
A_beats_W=$(_beats "$WA_b" "$WA_w" "$WA_d")
W_beats_C=$(_beats "$WC_w" "$WC_b" "$WC_d")

echo ""
echo "=== Pre-registered decision (see PREREGISTRATION.md) ==="
if [[ "$W_beats_A" == "yes" && ( "$W_beats_C" == "yes" || "$WC_w" -ge "$WC_b" ) ]]; then
  echo "  -> WORKFLOW EARNS IT: the cross-vendor union covers defects A misses, and W >= C."
  echo "     Keep fan-out + adversarial verify + union; CUT the consensus machinery"
  echo "     (voting, lexical consensus, capability weighting, panic mode)."
elif [[ "$A_beats_W" == "yes" ]]; then
  echo "  -> CODEX VINDICATED: A covers as much as W. The panel adds no coverage over one shot."
elif [[ "$W_beats_A" == "yes" && "$WC_w" -lt "$WC_b" ]]; then
  echo "  -> VOLUME, NOT DIVERSITY: W beats A but not C — self-consistency ties the panel."
  echo "     A single strong model sampled k times + verify is the cheaper equal."
else
  echo "  -> INCONCLUSIVE at this n: no arm clears the discordant-pair margin. Need more items."
fi

echo ""
echo "=== Cost (tokens per item and per covered defect) ==="
for arm in A W C; do
  tok=$(jq -rs --arg arm "$arm" '[.[]|select(.arm==$arm)|.tokens]|if length>0 then (add/length|floor) else 0 end' "$VER")
  hit=$(jq -rs --arg arm "$arm" '[.[]|select(.arm==$arm and .covered=="YES")]|length' "$COV" 2>/dev/null || echo 0)
  cnt=$(jq -rs --arg arm "$arm" '[.[]|select(.arm==$arm)]|length' "$VER")
  perdef="n/a"; [[ "$hit" -gt 0 ]] && perdef=$(( tok * cnt / hit ))
  echo "  arm $arm: ~$tok tok/item, $hit covered  -> ~$perdef tok per covered defect"
done

echo ""
echo "=== Adversarial verification pruning ==="
for arm in A W C; do
  read -r pr kp < <(jq -rs --arg arm "$arm" '
    [.[]|select(.arm==$arm)] as $g
    | "\(($g|map(.pruned)|add)//0) \(($g|map(.verified|length)|add)//0)"' "$VER")
  echo "  arm $arm: pruned ${pr:-0} findings, kept ${kp:-0}"
done

echo ""
echo "Reminder: a verdict is only valid if grade.sh --calibrate passed AND a hand-label of"
echo "10 random grader verdicts AND 10 verifier decisions each agrees >=90% (PREREGISTRATION.md)."
