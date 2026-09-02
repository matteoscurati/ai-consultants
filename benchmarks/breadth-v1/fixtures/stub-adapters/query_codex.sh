#!/bin/bash
set -euo pipefail
[[ "${MAX_RETRIES:-}" == "1" && "${CODEX_USE_API:-}" == "false" && "${CODEX_REASONING_EFFORT:-}" == "high" ]]
[[ -n "${BREADTH_STUB_COUNTER:-}" ]]
n=0; [[ -f "$BREADTH_STUB_COUNTER" ]] && n="$(cat "$BREADTH_STUB_COUNTER")"; printf '%s\n' "$((n+1))" > "$BREADTH_STUB_COUNTER"
scores="$(printf '%s' "$1" | jq -c '. as $p | [$p.arm_outputs[] | {item_id:$p.item.id,arm,tp:1,fp:0,fn:0,high_severity_hit:1,retained_source_ids:([.findings[0].source_id] | map(select(.!=null))),unique_contributions:([.findings[0].family] | map(select(.!=null)) | unique | map({family:.,count:1}))}]')"
jq -n --arg model "$CODEX_MODEL" --argjson scores "$scores" '{model:$model,response:{summary:"stub judge",detailed:"stub judge",approach:"breadth-v1-joint-judge",pros:[],cons:[],caveats:[],judge:{valid:true,scores:$scores}},confidence:{score:10,reasoning:"stub",uncertainty_factors:[]},metadata:{latency_ms:1,tokens_used:1,tokens_source:"measured"}}' > "$3"
