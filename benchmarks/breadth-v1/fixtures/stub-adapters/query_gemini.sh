#!/bin/bash
set -euo pipefail
[[ "${MAX_RETRIES:-}" == "1" && "${GEMINI_USE_API:-}" == "false" && "${GEMINI_REASONING_EFFORT:-}" == "high" ]]
[[ "${AI_CONSULTANTS_CONFIG_DIR:-}" == /tmp/* || "${AI_CONSULTANTS_CONFIG_DIR:-}" == "${TMPDIR:-/tmp}"/* ]]
[[ -z "${XAI_API_KEY:-}" && -z "${GROK_API_KEY:-}" ]]
[[ -n "${BREADTH_STUB_COUNTER:-}" ]]
n=0; [[ -f "$BREADTH_STUB_COUNTER" ]] && n="$(cat "$BREADTH_STUB_COUNTER")"; printf '%s\n' "$((n+1))" > "$BREADTH_STUB_COUNTER"
jq -n --arg model "$GEMINI_MODEL" '{model:$model,response:{summary:"stub",detailed:"stub",approach:"breadth-v1-primary",pros:[],cons:[],caveats:[],findings:[{text:"stub finding",kind:"finding"}]},confidence:{score:8,reasoning:"stub",uncertainty_factors:[]},metadata:{latency_ms:1,tokens_used:1,tokens_source:"measured"}}' > "$3"
