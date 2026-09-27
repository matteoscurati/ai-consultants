#!/bin/bash
# Offline Gemini 3.8 policy and promotional-rate checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
unset GEMINI_MODEL GEMINI_API_MODEL GEMINI_REASONING_EFFORT
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/costs.sh"
[[ "$GEMINI_MODEL" == 'Gemini 3.8 Flash (High)' && "$GEMINI_API_MODEL" == gemini-3.1-pro-preview ]] || exit 1
for tier in maximum premium standard economy; do
    [[ $(get_model_for_tier gemini "$tier" api) == gemini-3.1-pro-preview ]] || exit 1
    if [[ "$tier" == economy ]]; then expected='Gemini 3.8 Flash (Low)'; else expected='Gemini 3.8 Flash (High)'; fi
    [[ $(get_model_for_tier gemini "$tier" cli) == "$expected" ]] || exit 1
    [[ $(jq -r --arg tier "$tier" '.model_tiers[$tier].gemini' "$COST_RATES_FILE") == "$expected" ]] || exit 1
done
for model in 'Gemini 3.8 Flash (High)' 'Gemini 3.8 Flash (Medium)' 'Gemini 3.8 Flash (Low)' gemini-3.8-flash; do
    [[ $(estimate_query_cost "$model" 2000 1000) == 0.005250 ]] || exit 1
    COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
        [[ $(get_input_cost_per_1k "$2") == 0.00075 && $(get_output_cost_per_1k "$2") == 0.00375 ]]' _ "$SCRIPT_DIR" "$model"
done
mkdir "$TMP/responses"
printf '%s\n' '{"consultant":"Gemini","model":"Gemini 3.8 Flash (High)","response":{"summary":"ok"},"metadata":{"tokens_source":"estimated"}}' > "$TMP/responses/gemini.json"
[[ $(format_cost_caveats "$TMP/responses") == *'through 2026-12-31'* ]] || exit 1
printf '%s\n' 'Gemini 3.8 CLI tiers, separate API Pro default and promotional estimates passed'
