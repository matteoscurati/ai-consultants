#!/bin/bash
# Offline model policy, request compatibility and cost-boundary regressions.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
unset GROK_MODEL CLAUDE_MODEL CLAUDE_REASONING_EFFORT GROK_REASONING_EFFORT
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/api.sh"
source "$SCRIPT_DIR/lib/costs.sh"
[[ "$GROK_MODEL" == grok-4.7 && "$CLAUDE_MODEL" == claude-fable-5-1 ]] || exit 1
for tier in maximum premium; do
    [[ $(get_model_for_tier grok "$tier") == grok-4.7 ]] || exit 1
    [[ $(get_model_for_tier claude "$tier") == claude-fable-5-1 ]] || exit 1
done
[[ $(get_model_for_tier claude standard) == claude-opus-5-5 ]] || exit 1
[[ $(get_model_for_tier claude economy) == claude-haiku-4-5 ]] || exit 1
for tier in standard economy; do
    [[ $(get_model_for_tier grok "$tier") == grok-4.5 ]] || exit 1
done
jq -e '.consultant_fallbacks.grok == "grok-4.7" and
    .model_tiers.maximum.grok == "grok-4.7" and .model_tiers.premium.grok == "grok-4.7" and
    .model_tiers.standard.claude == "claude-opus-5-5"' "$SCRIPT_DIR/../docs/cost_rates.json" >/dev/null
[[ $(estimate_query_cost grok-4.7 200000 1000) == 0.406000 ]] || exit 1
[[ $(estimate_query_cost grok-4.7 200001 1000) == 0.812004 ]] || exit 1
[[ $(estimate_query_cost claude-opus-5-5 2000 1000) == 0.028000 ]] || exit 1
COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
    [[ $(get_input_cost_per_1k grok-4.7) == 0.002 && $(get_output_cost_per_1k grok-4.7) == 0.006 &&
       $(get_input_cost_per_1k claude-opus-5-5) == 0.004 && $(get_output_cost_per_1k claude-opus-5-5) == 0.020 ]]' _ "$SCRIPT_DIR"
build_anthropic_request hello claude-opus-5-5 16384 | jq -e '
    .model == "claude-opus-5-5" and .max_tokens == 16384 and
    (has("thinking") or has("tools") or has("tool_choice") or has("temperature") or has("top_p") | not)' >/dev/null
[[ $(parse_anthropic_response '{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"visible"}]}') == visible ]] || exit 1
build_openai_request hello grok-4.7 16384 xhigh | jq -e '.model == "grok-4.7" and .reasoning_effort == "xhigh" and .max_tokens == 16384' >/dev/null
printf '%s\n' '{"type":"assistant","message":{"id":"m","model":"claude-opus-5-5","content":[{"type":"thinking","thinking":""},{"type":"text","text":"visible"}],"stop_reason":"end_turn"}}' \
    '{"type":"result","subtype":"success","is_error":false,"result":"visible","modelUsage":{"claude-haiku-4-5":{"costUSD":0.001}},"total_cost_usd":0.01}' |
    jq -Rse -f "$SCRIPT_DIR/lib/claude_stream.jq" | jq -e '.success and .content_model == "claude-opus-5-5" and .cost == 0.01' >/dev/null
mkdir "$TMP/responses"
for model in grok-4.7 claude-opus-5-5; do
    jq -n --arg model "$model" '{consultant:(if $model == "claude-opus-5-5" then "Claude" else "Grok" end),model:$model,response:{summary:"ok"},metadata:{tokens_source:"measured",tokens_input:200001,tokens_output:1000}}' > "$TMP/responses/response.json"
    [[ $(format_cost_caveats "$TMP/responses") == *'not an invoice'* ]] || exit 1
    jq '.metadata.provider_cost_usd = 0.1' "$TMP/responses/response.json" > "$TMP/exact.json"
    mv "$TMP/exact.json" "$TMP/responses/response.json"
    [[ $(format_cost_caveats "$TMP/responses") != *'not an invoice'* ]] || exit 1
done
printf '%s\n' 'Grok 4.7 / Opus 5.5 policy, pricing boundaries and transport contracts passed'
