#!/bin/bash
# Offline Gemini 4 Argon / 3.8 policy and rate checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
unset GEMINI_MODEL GEMINI_API_MODEL GEMINI_REASONING_EFFORT
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/api.sh"
[[ "$GEMINI_MODEL" == 'Gemini 4 Argon (High)' && "$GEMINI_API_MODEL" == gemini-4-argon \
    && "$GEMINI_API_MAX_TOKENS" == 32768 ]] || exit 1
for tier in maximum premium standard economy; do
    case "$tier" in
        maximum|premium) expected='Gemini 4 Argon (High)'; expected_api=gemini-4-argon ;;
        standard) expected='Gemini 3.8 Flash (High)'; expected_api=gemini-3.8-flash ;;
        economy) expected='Gemini 3.8 Flash (Low)'; expected_api=gemini-3.8-flash ;;
    esac
    [[ $(get_model_for_tier gemini "$tier" api) == "$expected_api" ]] || exit 1
    [[ $(get_model_for_tier gemini "$tier" cli) == "$expected" ]] || exit 1
    [[ $(jq -r --arg tier "$tier" '.model_tiers[$tier].gemini' "$COST_RATES_FILE") == "$expected" ]] || exit 1
done
for model in 'Gemini 3.8 Flash (High)' 'Gemini 3.8 Flash (Medium)' 'Gemini 3.8 Flash (Low)' gemini-3.8-flash; do
    [[ $(estimate_query_cost "$model" 2000 1000) == 0.005250 ]] || exit 1
    COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
        [[ $(get_input_cost_per_1k "$2") == 0.00075 && $(get_output_cost_per_1k "$2") == 0.00375 ]]' _ "$SCRIPT_DIR" "$model"
done
usage='{"usageMetadata":{"promptTokenCount":100,"cachedContentTokenCount":80,"candidatesTokenCount":20,"thoughtsTokenCount":30,"totalTokenCount":150}}'
[[ $(extract_token_split "$usage" google_ai) == '100 50' ]] || exit 1
[[ $(extract_token_usage "$usage" google_ai) == 150 ]] || exit 1
[[ $(extract_token_split '{"usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":20,"thoughtsTokenCount":"bad"}}' google_ai) == '100 20' ]] || exit 1
mkdir "$TMP/responses"
printf '%s\n' '{"consultant":"Gemini","model":"Gemini 3.8 Flash (High)","response":{"summary":"ok"},"metadata":{"tokens_source":"estimated"}}' > "$TMP/responses/gemini.json"
[[ $(format_cost_caveats "$TMP/responses") == *'through 2026-12-31'* ]] || exit 1
# Argon is estimated at the list rate, not the introductory one.
for model in 'Gemini 4 Argon (High)' 'Gemini 4 Argon (Medium)' 'Gemini 4 Argon (Low)' gemini-4-argon; do
    [[ $(estimate_query_cost "$model" 2000 1000) == 0.028000 ]] || exit 1
    COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
        [[ $(get_input_cost_per_1k "$2") == 0.004 && $(get_output_cost_per_1k "$2") == 0.02 ]]' _ "$SCRIPT_DIR" "$model"
done
printf '%s\n' '{"consultant":"Gemini","model":"Gemini 4 Argon (High)","response":{"summary":"ok"},"metadata":{"tokens_source":"estimated"}}' > "$TMP/responses/gemini.json"
[[ $(format_cost_caveats "$TMP/responses") == *'Gemini 4 Argon list-rate'* ]] || exit 1
printf '%s\n' 'Gemini Argon/3.8 CLI tiers, API tiers and list/promotional estimates passed'
