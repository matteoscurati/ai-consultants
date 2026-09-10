#!/bin/bash
# Offline policy and estimate checks for DeepSeek V4.1 Flash.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
unset DEEPSEEK_MODEL DEEPSEEK_REASONING_EFFORT
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/costs.sh"
[[ "$DEEPSEEK_MODEL" == deepseek-flash ]] || exit 1
for tier in maximum premium standard economy; do
    [[ $(get_model_for_tier deepseek "$tier") == deepseek-flash ]] || exit 1
done
jq -e '.consultant_fallbacks.deepseek == "deepseek-flash" and
    all(.model_tiers | to_entries[] | select(.key != "_comment"); .value.deepseek == "deepseek-flash")' \
    "$SCRIPT_DIR/../docs/cost_rates.json" >/dev/null
for model in deepseek-flash deepseek-v4-flash deepseek-v4-flash-vision-exp; do
    [[ $(estimate_query_cost "$model" 2000 1000) == 0.001800 ]] || exit 1
    COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
        [[ $(get_input_cost_per_1k "$2") == 0.0003 && $(get_output_cost_per_1k "$2") == 0.0012 ]]' _ "$SCRIPT_DIR" "$model"
done
mkdir "$TMP/responses"
printf '%s\n' '{"consultant":"DeepSeek","model":"deepseek-flash","response":{"summary":"ok"},"metadata":{"tokens_source":"measured","tokens_input":2000,"tokens_output":1000}}' > "$TMP/responses/deepseek.json"
[[ $(format_cost_caveats "$TMP/responses") == *'peak cache-miss rates'* ]] || exit 1
jq '.metadata.provider_cost_usd = 0.0009' "$TMP/responses/deepseek.json" > "$TMP/exact.json"
mv "$TMP/exact.json" "$TMP/responses/deepseek.json"
[[ $(format_cost_caveats "$TMP/responses") != *'peak cache-miss rates'* ]] || exit 1
printf '%s\n' 'DeepSeek Flash defaults, tiers, alias pricing and estimate disclosure passed'
