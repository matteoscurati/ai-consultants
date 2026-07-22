#!/bin/bash
# run_experiment.sh - v2 COVERAGE experiment: does a cross-vendor fan-out, verified,
# catch defects a single model misses? See PREREGISTRATION.md.
#
# Arm A: single strong model, one shot -> its one finding (direct query; consult_all
#        refuses <2 consultants).
# Arm W: the panel as a WORKFLOW -> fan out to the working roster with debate/consensus
#        OFF, take the UNION of each consultant's independent finding. (The consensus
#        machinery is deliberately not used; the adversarial verify happens in verify.sh.)
# Arm C: the same strong model sampled k times -> the union of its k findings. k sized to
#        arm W's token spend (K_MAX caps it). Isolates diverse models from more tries.
#
# Emits findings.jsonl: one {id, arm, findings:[...], tokens, consensus?} line per (item,arm).
# Then: verify.sh (adversarial prune) -> grade.sh (coverage vs key) -> analyze.sh (verdict).
#
# THIS SPENDS REAL MODEL CALLS. --smoke fabricates findings for $0 to prove the plumbing.
#
# Usage:
#   run_experiment.sh --smoke [benchmark.json] [outdir]     # no model calls
#   run_experiment.sh --pilot [benchmark.json] [outdir]     # real, directional (not frozen)
#   run_experiment.sh --run   [benchmark.json] [outdir]     # real; needs a frozen prereg
#
# Env: STRONG_CONSULTANT (arm A/C, default Claude), K_MAX (arm C cap, default 12),
#      MAX_SESSION_COST (per-run budget guard, default 0.50),
#      EXPERIMENT_SKIP_CONSULTANTS (uppercase ids to drop from arm W, default CURSOR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO/lib/common.sh" >/dev/null 2>&1
source "$REPO/lib/costs.sh"  >/dev/null 2>&1

STRONG_CONSULTANT="${STRONG_CONSULTANT:-Claude}"

# Sum tokens over the billable response files in a dir.
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

# Union of independent findings in a dir: each consultant response's summary/detailed,
# as a JSON array. This is arm W's fan-out and arm A/C's finding set.
_findings_of() {
  local dir="$1"
  local -a arr=()
  local f txt
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    txt=$(jq -r '.response.summary // .response.detailed // ""' "$f" 2>/dev/null)
    [[ -n "$txt" ]] && arr+=("$txt")
  done < <(_billable_response_files "$dir" 2>/dev/null)
  if [[ ${#arr[@]} -eq 0 ]]; then echo "[]"; else printf '%s\n' "${arr[@]}" | jq -R . | jq -s .; fi
}

# Arm-W consensus (informative only; NOT used for coverage scoring).
_consensus_of() {
  jq -r '.quality_metrics.consensus_score // empty' "$1/optimization_metrics.json" 2>/dev/null
}

_emit() {  # <out> <id> <arm> <findings_json> <tokens> [consensus]
  local out="$1" id="$2" arm="$3" findings="$4" tok="$5" cons="${6:-}"
  if [[ -n "$cons" ]]; then
    jq -nc --arg id "$id" --arg arm "$arm" --argjson f "$findings" --argjson t "$tok" --argjson c "$cons" \
      '{id:$id, arm:$arm, findings:$f, tokens:$t, consensus:$c}' >> "$out"
  else
    jq -nc --arg id "$id" --arg arm "$arm" --argjson f "$findings" --argjson t "$tok" \
      '{id:$id, arm:$arm, findings:$f, tokens:$t}' >> "$out"
  fi
}

# --- SMOKE: fabricate findings with the shipped builders, no model calls ($0) ---
_smoke() {
  local bench="$1" outdir="$2"
  mkdir -p "$outdir"; local out="$outdir/findings.jsonl"; : > "$out"
  echo "SMOKE: fabricating findings (no model calls)" >&2
  local id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    # Arm A: 1 finding. Arm W: 3 distinct (one "correct"). Arm C: 2 findings.
    for arm in A W C; do
      local d="$outdir/$id/$arm"; mkdir -p "$d"
      local n=1; [[ "$arm" == W ]] && n=3; [[ "$arm" == C ]] && n=2
      local i
      for ((i=1; i<=n; i++)); do
        local summ="smoke finding $id/$arm/$i"
        [[ "$arm" == W && $i -eq 2 ]] && summ="the keyed defect for $id"   # W includes a correct one
        local inner='{"response":{"summary":"'"$summ"'","approach":"a'"$i"'"},"confidence":{"score":8}}'
        build_structured_response "SmokeC$i" "smoke-model" "P" "$inner" 100 $((1000*i)) measured $((600*i)) $((400*i)) > "$d/c$i.json"
      done
      local cons=""; [[ "$arm" == W ]] && { jq -nc '{quality_metrics:{consensus_score:40}}' > "$d/optimization_metrics.json"; cons=$(_consensus_of "$d"); }
      _emit "$out" "$id" "$arm" "$(_findings_of "$d")" "$(_sum_tokens "$d")" "$cons"
    done
  done < <(jq -r '.questions[].id' "$bench")
  echo "SMOKE: wrote $(wc -l < "$out") lines -> $out" >&2
  echo "$out"
}

# --- REAL MODE ---------------------------------------------------------------
_CFG_DIR=""
_arm_run() {  # <env...> -- <consult_all args...> ; echoes the run dir
  local -a envs=() ; while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done; shift
  env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" INVOKING_AGENT="" \
      ENABLE_SEMANTIC_CACHE=false ENABLE_BUDGET_LIMIT=true \
      MAX_SESSION_COST="${MAX_SESSION_COST:-0.50}" \
      ${envs[@]+"${envs[@]}"} \
      "$REPO/consult_all.sh" "$@" 2>/dev/null | tail -1
}

# Arm W env: the user's real working roster, as a pure FAN-OUT — debate and orchestration
# OFF (that machinery is the consensus part we do NOT measure), peer review OFF. Clear
# DEFAULT_PRESET (e.g. "balanced" caps the panel at 4). Drop down consultants.
_arm_w_env() {
  echo "DEFAULT_PRESET="
  echo "ENABLE_DEBATE=false"
  echo "ORCHESTRATION_MODE=fixed"
  echo "DEBATE_ROUNDS=0"
  echo "ENABLE_PEER_REVIEW=false"
  local down=" ${EXPERIMENT_SKIP_CONSULTANTS:-CURSOR} "
  local a
  for a in GEMINI CODEX MISTRAL CURSOR KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK MINIMAX; do
    if [[ "$down" == *" $a "* ]]; then echo "ENABLE_$a=false"; else echo "ENABLE_$a=true"; fi
  done
}

_run() {
  local bench="$1" outdir="$2" mode="${3:-run}"
  mkdir -p "$outdir"; local out="$outdir/findings.jsonl"; : > "$out"

  if [[ "$mode" != "pilot" && ! -f "$SCRIPT_DIR/.frozen" ]]; then
    echo "REFUSING: PREREGISTRATION.md is not frozen (scripts/experiment/.frozen absent)." >&2
    echo "Freeze it, or use --pilot for a non-binding shakedown." >&2
    exit 1
  fi
  [[ "$mode" == "pilot" ]] && echo "PILOT MODE — directional only, NOT the pre-registered verdict." >&2

  local strong_query="$REPO/query_$(to_lower "$STRONG_CONSULTANT").sh"
  [[ -x "$strong_query" ]] || { echo "REFUSING: no query script for STRONG_CONSULTANT=$STRONG_CONSULTANT ($strong_query)" >&2; exit 1; }

  # Use the user's REAL config (keys + transport); arms control composition via env.
  _CFG_DIR="${AI_CONSULTANTS_CONFIG_DIR:-$HOME/.config/ai-consultants}"

  local id q ctx
  while IFS= read -r id; do
    q=$(jq -r --arg id "$id" '.questions[] | select(.id==$id) | .prompt' "$bench")
    ctx=$(mktemp); printf '%s\n' "$q" > "$ctx"
    echo "== $id ==" >&2

    # Arm A: single strong model, one shot (direct query) -> one finding.
    local dirA="$outdir/$id/A"; mkdir -p "$dirA"
    env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" INVOKING_AGENT="" ENABLE_SEMANTIC_CACHE=false \
      "$strong_query" "" "$ctx" "$dirA/response.json" >/dev/null 2>&1 || true
    _emit "$out" "$id" A "$(_findings_of "$dirA")" "$(_sum_tokens "$dirA")"

    # Arm W: fan-out union (debate/consensus off). Its token total sizes arm C.
    local -a we=(); local wl
    while IFS= read -r wl; do we+=("$wl"); done < <(_arm_w_env)
    local dirW; dirW=$(_arm_run "${we[@]}" -- --query-file "$ctx" || true)
    local tokW=0 consW=""
    if [[ -d "$dirW" ]]; then
      tokW=$(_sum_tokens "$dirW"); consW=$(_consensus_of "$dirW")
      _emit "$out" "$id" W "$(_findings_of "$dirW")" "$tokW" "$consW"
    else echo "  arm W produced no dir" >&2; fi

    # Arm C: same model x k -> union of k findings. k matches arm W's spend.
    local dirC="$outdir/$id/C"; mkdir -p "$dirC"
    env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" ENABLE_SEMANTIC_CACHE=false \
      "$strong_query" "" "$ctx" "$dirC/sample_1.json" >/dev/null 2>&1 || true
    local per; per=$(_sum_tokens "$dirC"); [[ "$per" -gt 0 ]] || per=1
    local k=2; [[ "$tokW" -gt 0 ]] && k=$(( (tokW + per/2) / per )); [[ "$k" -lt 2 ]] && k=2
    local kmax="${K_MAX:-12}"; [[ "$k" -gt "$kmax" ]] && k=$kmax
    local i
    for ((i=2; i<=k; i++)); do
      env AI_CONSULTANTS_CONFIG_DIR="$_CFG_DIR" ENABLE_SEMANTIC_CACHE=false \
        "$strong_query" "" "$ctx" "$dirC/sample_$i.json" >/dev/null 2>&1 || true
    done
    _emit "$out" "$id" C "$(_findings_of "$dirC")" "$(_sum_tokens "$dirC")"
    echo "  arm C: k=$k samples" >&2

    rm -f "$ctx"
  done < <(jq -r '.questions[].id' "$bench")

  echo "findings -> $out" >&2
  echo "$out"
}

case "${1:-}" in
  --smoke) shift; _smoke "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" ;;
  --run)   shift; _run   "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" run ;;
  --pilot) shift; _run   "${1:-$SCRIPT_DIR/benchmark.json}" "${2:-$SCRIPT_DIR/out}" pilot ;;
  *) echo "usage: run_experiment.sh --smoke|--pilot|--run [benchmark.json] [outdir]" >&2; exit 1 ;;
esac
