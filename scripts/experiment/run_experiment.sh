#!/bin/bash
# run_experiment.sh - Drive the panel-vs-baseline experiment: arms A/B/C per question.
#
# Arm A: single strong model, one shot — a DIRECT query (consult_all refuses <2 consultants).
# Arm B: the user's real working panel (their config; DEFAULT_PRESET cleared), peer review off.
# Arm C: the same strong model sampled k times + one synthesis pass (self-consistency),
#        k per question sized to match arm B's token spend (K_MAX caps it).
#
# NOTE: this is the v1 CONSENSUS harness (arm B is scored on its synthesized answer). The
# frozen PREREGISTRATION.md is now the v2 COVERAGE design; see README "Harness status" for the
# three additions v2 needs. These are the fixes the v1 pilot surfaced, preserved.
#
# Emits results.jsonl: one {id, arm, answer, tokens, consensus?} line per (item, arm).
# Grade it with grade.sh and read the verdict with analyze.sh.
#
# THIS SPENDS REAL MODEL CALLS. Read PREREGISTRATION.md and freeze it before a real run.
# Use --smoke first: it fabricates arm outputs with the shipped response builders and
# proves the plumbing (token summing, answer extraction, results emission) for $0.
#
# Usage:
#   run_experiment.sh --smoke [benchmark.json] [outdir]     # no model calls
#   run_experiment.sh --run   [benchmark.json] [outdir]     # real; needs a frozen prereg
#
# Env (real run):
#   STRONG_CONSULTANT   arm-A/C consultant name (default: Claude)
#   MAX_SESSION_COST    per-run budget guard (default: 0.50)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"          # scripts/
source "$REPO/lib/common.sh" >/dev/null 2>&1  # build_* helpers, to_upper, _is_consultant_response_file
source "$REPO/lib/costs.sh"  >/dev/null 2>&1  # _billable_response_files

STRONG_CONSULTANT="${STRONG_CONSULTANT:-Claude}"

# Sum provider/estimated token counts over the billable response files in a dir.
# Reuses _billable_response_files (which already excludes voting/synthesis/peer_review,
# includes round_N/, and drops cache hits + escalation copies). No per-run token total
# is written by the product, so this is the one arithmetic piece the experiment owns.
_sum_tokens() {
  local dir="$1" total=0 t
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    t=$(jq -r '.metadata.tokens_used // 0' "$f" 2>/dev/null)
    [[ "$t" =~ ^[0-9]+$ ]] || t=0
    total=$((total + t))
  done < <(_billable_response_files "$dir" 2>/dev/null)
  echo "$total"
}

# Pull the synthesized answer a grader reads (arms B and C).
_answer_of() {
  jq -r '.weighted_recommendation.summary // .weighted_recommendation.approach // ""' "$1" 2>/dev/null
}

# Arm A is a single model: score its OWN response, not a synthesis-of-one. A single
# -consultant synthesis pass adds a failure mode (it can degrade to "Manual review
# required" under load) that has nothing to do with the model's answer quality — the
# pilot hit exactly that. Reads the first consultant response file in the dir.
_consultant_answer_of() {
  local dir="$1" f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    jq -r '.response.summary // .response.detailed // ""' "$f" 2>/dev/null
    return
  done < <(_billable_response_files "$dir" 2>/dev/null)
}

# Arm-B consensus, from the metrics file the product already writes.
_consensus_of() {
  jq -r '.quality_metrics.consensus_score // empty' "$1/optimization_metrics.json" 2>/dev/null
}

_emit() {  # <out> <id> <arm> <answer> <tokens> [consensus]
  local out="$1" id="$2" arm="$3" ans="$4" tok="$5" cons="${6:-}"
  if [[ -n "$cons" ]]; then
    jq -nc --arg id "$id" --arg arm "$arm" --arg a "$ans" --argjson t "$tok" --argjson c "$cons" \
      '{id:$id, arm:$arm, answer:$a, tokens:$t, consensus:$c}' >> "$out"
  else
    jq -nc --arg id "$id" --arg arm "$arm" --arg a "$ans" --argjson t "$tok" \
      '{id:$id, arm:$arm, answer:$a, tokens:$t}' >> "$out"
  fi
}

# --- SMOKE MODE: fabricate arm dirs with the real builders, no model calls ---
# Proves token summing + answer extraction + results emission end to end for $0.
_smoke() {
  local bench="$1" outdir="$2"
  mkdir -p "$outdir"; local out="$outdir/results.jsonl"; : > "$out"
  echo "SMOKE: fabricating arm outputs with shipped builders (no model calls)" >&2

  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    for arm in A B C; do
      local d="$outdir/$id/$arm"; mkdir -p "$d"
      # Fabricate 1 (A), 3 (B), 2 (C) consultant responses with known token counts.
      local n=1; [[ "$arm" == B ]] && n=3; [[ "$arm" == C ]] && n=2
      local i
      for ((i=1; i<=n; i++)); do
        local inner='{"response":{"summary":"smoke answer '"$id"'/'"$arm"'/'"$i"'","approach":"a'"$i"'"},"confidence":{"score":8}}'
        build_structured_response "SmokeC$i" "smoke-model" "P" "$inner" 100 $((1000*i)) measured $((600*i)) $((400*i)) > "$d/c$i.json"
      done
      # Synthesis: reuse the real builder to stand in for synthesize.sh output shape.
      jq -nc --arg s "synth $id/$arm" '{weighted_recommendation:{summary:$s, approach:"syn"}}' > "$d/synthesis.json"
      [[ "$arm" == B ]] && jq -nc '{quality_metrics:{consensus_score:75}}' > "$d/optimization_metrics.json"

      local ans tok cons; ans=$(_answer_of "$d/synthesis.json"); tok=$(_sum_tokens "$d")
      cons=""; [[ "$arm" == B ]] && cons=$(_consensus_of "$d")
      _emit "$out" "$id" "$arm" "$ans" "$tok" "$cons"
    done
  done < <(jq -r '.questions[].id' "$bench")

  echo "SMOKE: wrote $(wc -l < "$out") result lines -> $out" >&2
  echo "$out"
}

# --- REAL MODE ---------------------------------------------------------------

# Shared per-run environment: cache OFF (else arm C's samples collapse and token
# accounting is void), budget guard ON, and an EMPTY config dir so the maintainer's
# own .env cannot change which consultants participate.
_CFG_DIR=""
_arm_run() {  # <extra env assignments...> -- <consult_all args...> ; echoes the run dir
  local -a envs=() ; while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  # INVOKING_AGENT="" so self-exclusion does not drop the strong model (Claude)
  # from arm A, where it is the ONLY consultant.
  # ${envs[@]+...}: empty-array-safe expansion — bash 3.2 (stock macOS) treats a
  # bare "${envs[@]}" on an empty array as unbound under set -u.
  env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" INVOKING_AGENT="" \
      ENABLE_SEMANTIC_CACHE=false ENABLE_BUDGET_LIMIT=true \
      MAX_SESSION_COST="${MAX_SESSION_COST:-0.50}" \
      ${envs[@]+"${envs[@]}"} \
      "$REPO/consult_all.sh" "$@" 2>/dev/null | tail -1
}


# Arm B env: the user's REAL panel with peer review OFF. We do NOT force all 11 on —
# that would re-enable consultants the user disabled (Cursor) or that are down (Qwen on
# a dead key), wasting calls and adding failures. Passing no ENABLE_* lets the user's
# config decide which consultants participate; that IS the panel being measured. Peer
# review runs after synthesis and cannot change the scored recommendation, so dropping
# it only cuts the slowest stage.
_arm_b_env() {
  # Clear the user's DEFAULT_PRESET (e.g. "balanced" caps the panel at 4 and re-enables
  # Cursor) so arm B is the full working roster, not a preset subset. Enable everyone
  # EXCEPT the consultants that are genuinely down for credential/quota reasons — forcing
  # them on only wastes a call and adds a failure. CURSOR_DOWN can list such consultants
  # (space-separated uppercase ids); default drops Cursor (usage limit).
  echo "DEFAULT_PRESET="
  local down=" ${EXPERIMENT_SKIP_CONSULTANTS:-CURSOR} "
  local a
  for a in GEMINI CODEX MISTRAL CURSOR KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK MINIMAX; do
    if [[ "$down" == *" $a "* ]]; then echo "ENABLE_$a=false"; else echo "ENABLE_$a=true"; fi
  done
  echo "ENABLE_PEER_REVIEW=false"
}

_run() {
  local bench="$1" outdir="$2" mode="${3:-run}"
  mkdir -p "$outdir"; local out="$outdir/results.jsonl"; : > "$out"

  # A binding run requires the pre-registration frozen. A --pilot is explicitly
  # NOT the binding run (underpowered n, directional only), so it skips the guard
  # but must never be reported as the pre-registered verdict.
  if [[ "$mode" != "pilot" && ! -f "$SCRIPT_DIR/.frozen" ]]; then
    echo "REFUSING: PREREGISTRATION.md is not frozen (scripts/experiment/.frozen absent)." >&2
    echo "Freeze the pre-registration and 'touch scripts/experiment/.frozen' before a real run." >&2
    echo "For a non-binding shakedown on the seed set, use --pilot." >&2
    exit 1
  fi
  [[ "$mode" == "pilot" ]] && echo "PILOT MODE — directional only, NOT the pre-registered verdict." >&2

  local strong_query="$REPO/query_$(to_lower "$STRONG_CONSULTANT").sh"
  [[ -x "$strong_query" ]] || { echo "REFUSING: no query script for STRONG_CONSULTANT=$STRONG_CONSULTANT ($strong_query)" >&2; exit 1; }

  # Use the user's REAL config, not an isolated/empty one. The experiment measures
  # the user's actual system: arm B must be their real working panel (their keys,
  # their Qwen transport, their disabled consultants), so we do NOT override its
  # AI_CONSULTANTS_CONFIG_DIR. Arm composition is still controlled where it matters —
  # arm A/C pass explicit ENABLE_* on the command line, which wins over the file
  # (load_user_config lets the environment override .env). An earlier cut isolated to
  # an empty dir for hermeticity and silently stripped the credentials + Qwen Token
  # Plan transport, collapsing arm B; measuring the real system is the right call here,
  # not test-style hermeticity.
  _CFG_DIR="${AI_CONSULTANTS_CONFIG_DIR:-$HOME/.config/ai-consultants}"

  local id q ctx
  while IFS= read -r id; do
    q=$(jq -r --arg id "$id" '.questions[] | select(.id==$id) | .prompt' "$bench")
    ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"
    echo "== $id ==" >&2

    # Arm A: single strong model, one shot.
    # Arm A: single strong model, one shot — a DIRECT query, not consult_all.
    # consult_all refuses to run with fewer than 2 consultants ("At least 2
    # consultants required"), so a single-model arm cannot go through it; and a
    # one-model consult_all would only re-synthesize one answer anyway. Score the
    # model's own response.
    local dirA="$outdir/$id/A"; mkdir -p "$dirA"
    env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" INVOKING_AGENT="" ENABLE_SEMANTIC_CACHE=false \
      "$strong_query" "" "$ctx" "$dirA/response.json" >/dev/null 2>&1 || true
    if [[ -s "$dirA/response.json" ]]; then
      _emit "$out" "$id" A "$(_consultant_answer_of "$dirA")" "$(_sum_tokens "$dirA")"
    else echo "  arm A produced no response" >&2; fi

    # Arm B: the user's real panel, peer review off. Its token total sizes arm C.
    local -a fp=(); local fpl
    while IFS= read -r fpl; do fp+=("$fpl"); done < <(_arm_b_env)
    local dirB; dirB=$(_arm_run "${fp[@]}" -- --query-file "$ctx" || true)
    local tokB=0 consB=""
    if [[ -d "$dirB" ]]; then
      tokB=$(_sum_tokens "$dirB"); consB=$(_consensus_of "$dirB")
      _emit "$out" "$id" B "$(_answer_of "$dirB/synthesis.json")" "$tokB" "$consB"
    else echo "  arm B produced no dir" >&2; fi

    # Arm C: same model sampled k times + synthesize. k matches arm B's spend.
    local dirC="$outdir/$id/C"; mkdir -p "$dirC"
    # One sample first to size k, then the rest.
    env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" ENABLE_SEMANTIC_CACHE=false \
      "$strong_query" "" "$ctx" "$dirC/sample_1.json" >/dev/null 2>&1 || true
    local per; per=$(_sum_tokens "$dirC"); [[ "$per" -gt 0 ]] || per=1
    local k=2; [[ "$tokB" -gt 0 ]] && k=$(( (tokB + per/2) / per )); [[ "$k" -lt 2 ]] && k=2
    # Hard cap: a failed sample makes per~0 and would explode k to tokB. Bound it.
    local kmax="${K_MAX:-12}"; [[ "$k" -gt "$kmax" ]] && k=$kmax
    local i
    for ((i=2; i<=k; i++)); do
      env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" ENABLE_SEMANTIC_CACHE=false \
        "$strong_query" "" "$ctx" "$dirC/sample_$i.json" >/dev/null 2>&1 || true
    done
    env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" \
      "$REPO/synthesize.sh" "$dirC" "$dirC/synthesis.json" "$q" >/dev/null 2>&1 || true
    _emit "$out" "$id" C "$(_answer_of "$dirC/synthesis.json")" "$(_sum_tokens "$dirC")"
    echo "  arm C: k=$k samples" >&2

    rm -f "$ctx"
  done < <(jq -r '.questions[].id' "$bench")

  echo "results -> $out" >&2
  echo "$out"
}

case "${1:-}" in
  --smoke) shift; _smoke "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" ;;
  --run)   shift; _run   "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" run ;;
  --pilot) shift; _run   "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" pilot ;;
  *) echo "usage: run_experiment.sh --smoke|--pilot|--run [benchmark.json] [outdir]" >&2; exit 1 ;;
esac
