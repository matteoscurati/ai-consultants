#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/api.sh"
source "$SCRIPT_DIR/lib/costs.sh"
# Use explicit assertion failures: Bash 3.2 errexit skips some compound tests.
set -euo pipefail
trap 'printf "Astra assertion failed at line %s\n" "$LINENO" >&2' ERR
[[ $(resolve_codex_effort gpt-6-astra '') == high ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
for effort in low medium high xhigh max; do
    [[ $(resolve_codex_effort gpt-6-astra "$effort") == "$effort" ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
done
for effort in none minimal invalid; do
    if resolve_codex_effort gpt-6-astra "$effort" >/dev/null 2>&1; then exit 1; fi
done
[[ -z $(resolve_codex_effort gpt-5.6-terra '') ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
# GPT-6.1 Sol: same effort range as Astra, but the provider default applies.
[[ -z $(resolve_codex_effort gpt-6.1-sol '') ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
build_codex_request hello gpt-6.1-sol 16384 '' | jq -e '.model == "gpt-6.1-sol" and (has("reasoning_effort")|not)' >/dev/null
build_codex_request hello gpt-6.1-sol 16384 xhigh | jq -e '.reasoning_effort == "xhigh"' >/dev/null
for tier in maximum premium; do
    [[ $(get_model_for_tier codex "$tier") == gpt-6-astra ]] || exit 1
done
[[ $(get_model_for_tier codex standard) == gpt-5.6-terra ]] || exit 1
[[ $(get_model_for_tier codex economy) == gpt-5.6-luna ]] || exit 1
jq -e '.model_tiers.maximum.codex == "gpt-6-astra" and .model_tiers.premium.codex == "gpt-6-astra" and .model_tiers.standard.codex == "gpt-5.6-terra" and .model_tiers.economy.codex == "gpt-5.6-luna"' "$SCRIPT_DIR/../docs/cost_rates.json" >/dev/null || exit 1
for tier in maximum economy premium standard maximum economy; do
    unset CODEX_REASONING_EFFORT
    apply_model_tier "$tier"
    [[ -z ${CODEX_REASONING_EFFORT:-} ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
    if [[ "$CODEX_MODEL" == gpt-6-astra ]]; then
        [[ $(resolve_codex_effort "$CODEX_MODEL" '') == high ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
    else
        [[ -z $(resolve_codex_effort "$CODEX_MODEL" '') ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
    fi
done
build_codex_request hello gpt-6-astra 16384 '' | jq -e '.model == "gpt-6-astra" and .reasoning_effort == "high" and .max_completion_tokens == 16384 and (has("max_tokens")|not)' >/dev/null
build_openai_request hello grok-4.6 4096 high | jq -e '.max_tokens == 4096 and (has("max_completion_tokens")|not)' >/dev/null
[[ $(estimate_query_cost gpt-6-astra 272000 1000) == 2.770000 ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
[[ $(estimate_query_cost gpt-6-astra 273000 1000) == 5.535000 ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
[[ $(estimate_query_cost gpt-6.1-sol 272000 1000) == 0.554000 ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
[[ $(estimate_query_cost gpt-6.1-sol 272001 1000) == 1.103004 ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
COST_RATES_FILE="$TMP/missing" \
    bash -c 'source "$1/lib/costs.sh"; [[ $(get_input_cost_per_1k gpt-6-astra) == 0.01 && $(get_output_cost_per_1k gpt-6-astra) == 0.05 &&
        $(get_input_cost_per_1k gpt-6.1-sol) == 0.002 && $(get_output_cost_per_1k gpt-6.1-sol) == 0.010 ]]' _ "$SCRIPT_DIR"
COST_RATES_FILE="$TMP/missing" \
    bash -c 'source "$1/lib/costs.sh"; [[ $(estimate_query_cost claude-fable-5-1 1000 1000) == 0.060000 ]]' _ "$SCRIPT_DIR"
# Failed Astra effort validation must produce an envelope and never call curl.
mkdir -p "$TMP/bin"
printf '#!/bin/bash\n: > "$DISPATCH_FILE"\nexit 99\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/curl"
for model_effort in gpt-6-astra:none gpt-6-astra:minimal gpt-6.1-sol:none gpt-6.1-sol:minimal; do
    model="${model_effort%%:*}" effort="${model_effort#*:}"
    rc=0; rm -f "$TMP/dispatched" "$TMP/error.json"
    PATH="$TMP/bin:$PATH" CODEX_USE_API=true OPENAI_API_KEY=test CODEX_MODEL="$model" \
        CODEX_REASONING_EFFORT="$effort" ENABLE_PERSONA=false DISPATCH_FILE="$TMP/dispatched" \
        bash "$SCRIPT_DIR/query_codex.sh" hello '' "$TMP/error.json" >/dev/null 2>&1 || rc=$?
    [[ $rc -ne 0 && ! -e "$TMP/dispatched" ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
    jq -e '.metadata.response_quality == "error"' "$TMP/error.json" >/dev/null
done
# The GPT-6.1 Sol estimate is disclosed until a provider cost is present.
mkdir "$TMP/responses"
jq -n '{consultant:"Codex",model:"gpt-6.1-sol",response:{summary:"ok"},metadata:{tokens_source:"measured",tokens_input:1000,tokens_output:100}}' \
    > "$TMP/responses/response.json"
[[ $(format_cost_caveats "$TMP/responses") == *'GPT-6.1 Sol'*'not an invoice'* ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
jq '.metadata.provider_cost_usd = 0.01' "$TMP/responses/response.json" > "$TMP/exact.json"
mv "$TMP/exact.json" "$TMP/responses/response.json"
[[ $(format_cost_caveats "$TMP/responses") != *'GPT-6.1 Sol'* ]] || { printf "Astra assertion failed at line %s\n" "$LINENO" >&2; exit 1; }
printf '%s\n' 'Astra and GPT-6.1 Sol effort, tier isolation, payload and pricing checks passed'
