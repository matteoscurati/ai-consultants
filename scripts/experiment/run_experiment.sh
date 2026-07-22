#!/bin/bash
# run_experiment.sh - Drive the panel-vs-baseline experiment: arms A/B/C per question.
#
# Arm A: single strong model, one shot (all consultants disabled except STRONG).
# Arm B: full panel, default deliberation (--preset max_quality).
# Arm C: the same strong model sampled k times + one synthesis pass (self-consistency),
#        k per question sized to match arm B's token spend.
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

# Pull the synthesized answer a grader reads.
_answer_of() {
  jq -r '.weighted_recommendation.summary // .weighted_recommendation.approach // ""' "$1" 2>/dev/null
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
  env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" \
      ENABLE_SEMANTIC_CACHE=false ENABLE_BUDGET_LIMIT=true \
      MAX_SESSION_COST="${MAX_SESSION_COST:-0.50}" \
      "${envs[@]}" \
      "$REPO/consult_all.sh" "$@" 2>/dev/null | tail -1
}

# Env string that disables every consultant except the strong one (arm A / arm C base).
_only_strong() {
  local up; up=$(to_upper "$STRONG_CONSULTANT")
  local a
  for a in GEMINI CODEX MISTRAL CURSOR KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK MINIMAX; do
    if [[ "$a" == "$up" ]]; then echo "ENABLE_$a=true"; else echo "ENABLE_$a=false"; fi
  done
  echo "ENABLE_DEBATE=false"
}

_run() {
  local bench="$1" outdir="$2"
  mkdir -p "$outdir"; local out="$outdir/results.jsonl"; : > "$out"

  if [[ ! -f "$SCRIPT_DIR/.frozen" ]]; then
    echo "REFUSING: PREREGISTRATION.md is not frozen (scripts/experiment/.frozen absent)." >&2
    echo "Freeze the pre-registration and 'touch scripts/experiment/.frozen' before a real run." >&2
    exit 1
  fi

  local strong_query="$REPO/query_$(to_lower "$STRONG_CONSULTANT").sh"
  [[ -x "$strong_query" ]] || { echo "REFUSING: no query script for STRONG_CONSULTANT=$STRONG_CONSULTANT ($strong_query)" >&2; exit 1; }

  _CFG_DIR=$(mktemp -d); trap 'rm -rf "$_CFG_DIR"' RETURN

  local id q ctx
  while IFS= read -r id; do
    q=$(jq -r --arg id "$id" '.questions[] | select(.id==$id) | .prompt' "$bench")
    ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"
    echo "== $id ==" >&2

    # Arm A: single strong model, one shot.
    local -a only=(); local ln
    while IFS= read -r ln; do only+=("$ln"); done < <(_only_strong)
    local dirA; dirA=$(_arm_run "${only[@]}" -- --query-file "$ctx")
    if [[ -d "$dirA" ]]; then
      _emit "$out" "$id" A "$(_answer_of "$dirA/synthesis.json")" "$(_sum_tokens "$dirA")"
    else echo "  arm A produced no dir" >&2; fi

    # Arm B: full panel. Its token total sizes arm C.
    local dirB; dirB=$(_arm_run -- --preset max_quality --query-file "$ctx")
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
  --run)   shift; _run   "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" ;;
  *) echo "usage: run_experiment.sh --smoke|--run [benchmark.json] [outdir]" >&2; exit 1 ;;
esac
