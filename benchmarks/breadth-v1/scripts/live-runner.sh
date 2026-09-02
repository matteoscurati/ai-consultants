#!/bin/bash
# Exact, evidence-gated breadth-v1 request bridge. The harness owns retry,
# accounting, and admission; this process performs exactly one adapter call.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SHA_BIN="$(command -v shasum || command -v sha256sum)"
sha_file() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then "$SHA_BIN" -a 256 "$1"; else "$SHA_BIN" "$1"; fi | awk '{print $1}'; }
request="$(cat)"
printf '%s' "$request" | jq -e '.call_id and .arm and .item_id and .requested_identity and .evidence_sha256' >/dev/null
evidence="${BREADTH_EVIDENCE_FILE:-}"
[[ -n "$evidence" && -f "$evidence" ]] || { echo "breadth-v1 live runner: reviewed evidence is required" >&2; exit 66; }
[[ "$(sha_file "$evidence")" == "$(printf '%s' "$request" | jq -r '.evidence_sha256')" ]] || { echo "breadth-v1 live runner: evidence hash mismatch" >&2; exit 67; }
[[ "${BREADTH_LIVE_RUNNER_REVIEWED:-false}" == "true" ]] || { echo "breadth-v1 live runner: action-time enablement is required" >&2; exit 68; }

entry="$(jq -ce --argjson identity "$(printf '%s' "$request" | jq -c '.requested_identity')" '
  .entries[] | select(
    .family==$identity.family and .requested_model==$identity.requested_model and
    .tier==$identity.tier and .effort==$identity.effort and .transport==$identity.transport and
    .identity.provider_backed==true and .identity.observed_model==.requested_model and
    .pricing.status=="priced" and (.pricing.reservation_cents|type)=="number")
' "$evidence")" || { echo "breadth-v1 live runner: exact identity/pricing tuple is not cleared" >&2; exit 69; }

family="$(printf '%s' "$request" | jq -r '.requested_identity.family')"; model="$(printf '%s' "$request" | jq -r '.requested_identity.requested_model')"; effort="$(printf '%s' "$request" | jq -r '.requested_identity.effort')"; arm="$(printf '%s' "$request" | jq -r '.arm')"
case "$family" in
  gemini) adapter=query_gemini.sh; adapter_env=(GEMINI_USE_API=false GEMINI_MODEL="$model" GEMINI_REASONING_EFFORT="$effort") ;;
  mistral) adapter=query_mistral.sh; adapter_env=(MISTRAL_USE_API=false MISTRAL_CLI_MODEL="$model") ;;
  kimi) adapter=query_kimi.sh; adapter_env=(KIMI_MODEL="$model") ;;
  claude) adapter=query_claude.sh; adapter_env=(CLAUDE_USE_API=false CLAUDE_MODEL="$model") ;;
  qwen) adapter=query_qwen3.sh; adapter_env=(QWEN3_USE_API=false QWEN3_MODEL="$model") ;;
  glm) adapter=query_glm.sh; adapter_env=(GLM_MODEL="$model") ;;
  grok) adapter=query_grok.sh; adapter_env=(GROK_USE_API=false GROK_MODEL="$model") ;;
  deepseek) adapter=query_deepseek.sh; adapter_env=(DEEPSEEK_MODEL="$model") ;;
  minimax) adapter=query_minimax.sh; adapter_env=(MINIMAX_USE_API=false MINIMAX_MODEL="$model") ;;
  codex) adapter=query_codex.sh; adapter_env=(CODEX_USE_API=false CODEX_MODEL="$model" CODEX_REASONING_EFFORT="$effort") ;;
  *) echo "breadth-v1 live runner: unsupported family" >&2; exit 64 ;;
esac
[[ "$arm" == "judge" || "$family" != "codex" ]] || { echo "breadth-v1 live runner: Codex is forbidden in primary arms" >&2; exit 65; }
[[ "$arm" != "judge" || "$family" == "codex" ]] || { echo "breadth-v1 live runner: judge must be Codex" >&2; exit 65; }

if [[ "$arm" == "judge" ]]; then
  prompt="$(jq -n --argjson request "$request" '{instruction:"Return exactly one standard AI Consultants JSON envelope. Put the benchmark grade in response.judge. It must contain valid:true and scores with exactly A,B,C,D,E once. Every score must contain item_id, arm, non-negative integer tp/fp/fn/high_severity_hit, retained_source_ids (a unique subset of that arm packet source_ids), and unique_contributions:[{family,count}] using only families explicitly attached to that arm packet. The harness supplies high_severity_total/source_ids_expected/source_ids_retained from frozen local data; do not invent denominators. A retained source ID means its attributed atomic finding is represented as a supported true-positive in the graded arm union. Grade all five arms in this single call against the supplied atomic rubric.",required_outer_shape:{response:{summary:"string",detailed:"string",approach:"breadth-v1-joint-judge",pros:[],cons:[],caveats:[],judge:"object"},confidence:{score:10,reasoning:"string",uncertainty_factors:[]}},item:$request.item,arm_outputs:$request.arm_outputs}')"
else
  prompt="$(jq -n --argjson request "$request" '{instruction:"Analyze independently. Return exactly one standard AI Consultants JSON envelope. response.findings must be a non-empty array of atomic objects with text and kind. Do not invent benchmark rubric/source IDs; the harness assigns local source IDs.",required_outer_shape:{response:{summary:"string",detailed:"string",approach:"breadth-v1-primary",pros:[],cons:[],caveats:[],findings:[{text:"string",kind:"finding"}]},confidence:{score:8,reasoning:"string",uncertainty_factors:[]}},item:$request.item}')"
fi

out="$(mktemp "${TMPDIR:-/tmp}/breadth-live.XXXXXX.json")"; runtime="$(mktemp -d "${TMPDIR:-/tmp}/breadth-live-runtime.XXXXXX")"; trap 'rm -f "$out"; rm -rf "$runtime"' EXIT
adapter_root="$ROOT/scripts"
if [[ "${BREADTH_LIVE_RUNNER_TEST_ONLY:-false}" == "true" ]]; then
  printf '%s' "$request" | jq -e '.test_only == true' >/dev/null || { echo "breadth-v1 live runner: test adapter requires test-only request" >&2; exit 75; }
  adapter_root="$ROOT/benchmarks/breadth-v1/fixtures/stub-adapters"
else
  printf '%s' "$request" | jq -e '(.test_only // false) == false' >/dev/null || { echo "breadth-v1 live runner: test-only request rejected" >&2; exit 75; }
fi
if env -u XAI_API_KEY -u GROK_API_KEY -u CLAUDE_REASONING_EFFORT -u QWEN3_REASONING_EFFORT -u GLM_REASONING_EFFORT -u GROK_REASONING_EFFORT -u DEEPSEEK_REASONING_EFFORT -u MINIMAX_REASONING_EFFORT \
  -u GEMINI_TIMEOUT_SECONDS -u MISTRAL_TIMEOUT_SECONDS -u KIMI_TIMEOUT_SECONDS -u CLAUDE_TIMEOUT_SECONDS -u QWEN3_TIMEOUT_SECONDS -u GLM_TIMEOUT_SECONDS -u GROK_TIMEOUT_SECONDS -u DEEPSEEK_TIMEOUT_SECONDS -u MINIMAX_TIMEOUT_SECONDS -u CODEX_TIMEOUT_SECONDS -u GROK_OAUTH_MODE \
  "${adapter_env[@]}" AI_CONSULTANTS_CONFIG_DIR="$runtime/config" XDG_CONFIG_HOME="$runtime/xdg" MAX_RETRIES=1 ENABLE_SEMANTIC_CACHE=false ENABLE_BUDGET_LIMIT=false ENABLE_PERSONA=false ENABLE_SMART_ROUTING=false ENABLE_HEALTH_CHECKS=false "$adapter_root/$adapter" "$prompt" "" "$out" >/dev/null; then
  adapter_rc=0
else
  adapter_rc=$?
fi
if (( adapter_rc != 0 )); then
  error_text="$(jq -r '.metadata.error // .response.detailed // empty' "$out" 2>/dev/null || true)"
  if printf '%s' "$error_text" | grep -Eqi '(^|[^0-9])429([^0-9]|$)|rate.?limit|temporar|timeout|timed out|overload|unavailable'; then
    jq -n --arg reason "$error_text" --argjson cost "$(printf '%s' "$entry" | jq '.pricing.reservation_cents')" '{status:"transient",provider_reached:true,reason:$reason,accounted_cost_cents:$cost,pricing_status:"estimated"}'
    exit 0
  fi
  echo "breadth-v1 live runner: non-transient adapter failure" >&2
  exit "$adapter_rc"
fi
jq -e '.metadata and .response and (.metadata.error? == null)' "$out" >/dev/null || { echo "breadth-v1 live runner: adapter response is invalid" >&2; exit 70; }
[[ "$(jq -r '.model' "$out")" == "$(printf '%s' "$entry" | jq -r '.identity.observed_model')" ]] || { echo "breadth-v1 live runner: observed model mismatch" >&2; exit 71; }
if [[ "$family" == "grok" && "$(jq -r '.metadata.transport // empty' "$out")" != "cli" ]]; then echo "breadth-v1 live runner: Grok transport fallback detected" >&2; exit 74; fi

identity="$(printf '%s' "$entry" | jq '{family,requested_model,tier,effort,transport}')"; provider_cost="$(jq -r '.metadata.provider_cost_usd // empty' "$out")"
if [[ -n "$provider_cost" ]]; then accounted_cents="$(jq -n --argjson usd "$provider_cost" '$usd*100|ceil')"; pricing_status=measured; else accounted_cents="$(printf '%s' "$entry" | jq '.pricing.reservation_cents')"; pricing_status=estimated; fi
tokens_source="$(jq -r '.metadata.tokens_source // "unknown"' "$out")"; tokens="$(jq -r '.metadata.tokens_used // 0' "$out")"; tokens_measured=null; tokens_estimated=null
[[ "$tokens_source" == "measured" ]] && tokens_measured="$tokens" || tokens_estimated="$tokens"
common="$(jq -n --argjson identity "$identity" --argjson evidence "$(printf '%s' "$entry" | jq '.identity')" --argjson raw "$(cat "$out")" --argjson latency "$(jq '.metadata.latency_ms // 0' "$out")" --argjson cost "$accounted_cents" --arg pricing "$pricing_status" --argjson measured "$tokens_measured" --argjson estimated "$tokens_estimated" '{status:"completed",provider_reached:true,effective_identity:$identity,billing_identity:$identity,identity_evidence:$evidence,latency_ms:$latency,accounted_cost_cents:$cost,pricing_status:$pricing,tokens_measured:$measured,tokens_estimated:$estimated,raw_adapter_response:$raw}')"
if [[ "$arm" == "judge" ]]; then
  judge="$(jq -ce '.response.judge' "$out")" || { echo "breadth-v1 live runner: judge payload missing" >&2; exit 72; }
  jq -n --argjson common "$common" --argjson judge "$judge" '$common + {judge:$judge}'
else
  normalized="$(jq -ce --arg call_id "$(printf '%s' "$request" | jq -r '.call_id')" '[.response.findings[] | if type=="object" then (.text // empty) elif type=="string" then . else empty end | select(type=="string" and test("\\S"))] as $findings | select(($findings|length)>0) | {findings:$findings,source_ids:[$findings|to_entries[]|($call_id+":"+((.key+1)|tostring))]}' "$out")" || { echo "breadth-v1 live runner: atomic primary findings missing" >&2; exit 73; }
  jq -n --argjson common "$common" --argjson result "$normalized" '$common + {result:$result}'
fi
