#!/bin/bash
# Test-only runner. It cannot contact a provider and rejects accidental non-sentinel use.
set -euo pipefail
request="$(cat)"
printf '%s' "$request" | jq -e '.call_id and .requested_identity.family' >/dev/null
arm="$(printf '%s' "$request" | jq -r '.arm')"
identity="$(printf '%s' "$request" | jq -c '.requested_identity')"
if [[ "${BREADTH_SENTINEL_TRANSIENT_ONCE:-0}" == "1" ]]; then
  [[ -n "${BREADTH_SENTINEL_STATE_DIR:-}" ]] || { echo "sentinel requires BREADTH_SENTINEL_STATE_DIR" >&2; exit 93; }
  mkdir -p "$BREADTH_SENTINEL_STATE_DIR"
  if [[ ! -e "$BREADTH_SENTINEL_STATE_DIR/transient-used" ]]; then
    : > "$BREADTH_SENTINEL_STATE_DIR/transient-used"
    jq -n '{status:"transient",provider_reached:true,reason:"sentinel transient"}'
    exit 0
  fi
fi
if [[ "$arm" != "judge" ]]; then
  printf '%s' "$request" | jq -e '(.item | keys | sort) == ["category", "id", "prompt"] and (tostring | test("atomic_findings|high_severity_ids|source_ids|sources") | not)' >/dev/null || { echo "sentinel: primary held-out leak" >&2; exit 91; }
else
  printf '%s' "$request" | jq -e '(.arm_outputs | length == 5) and (.item.rubric != null) and (.item.sources != null)' >/dev/null || { echo "sentinel: invalid joint judge packet" >&2; exit 92; }
fi
if [[ "$arm" == "judge" ]]; then
  jq -n --argjson identity "$identity" --argjson valid "$( [[ "${BREADTH_SENTINEL_INVALID_JUDGE:-0}" == "1" ]] && echo false || echo true )" '{status:"completed",provider_reached:true,effective_identity:$identity,billing_identity:$identity,latency_ms:1,countable_cost_usd:null,tokens_measured:1,tokens_estimated:null,judge:{valid:$valid,scores:[{"arm":"A"},{"arm":"B"},{"arm":"C"},{"arm":"D"},{"arm":"E"}]},metrics:{true_positive:1,false_positive:0,false_negative:0,high_severity_hit:1,source_ids_retained:1,unique_contribution:0}}'
else
  jq -n --argjson identity "$identity" --argjson effective "$( [[ "${BREADTH_SENTINEL_BAD_IDENTITY:-0}" == "1" ]] && echo '{"family":"wrong"}' || printf '%s' "$identity" )" '{status:"completed",provider_reached:true,effective_identity:$effective,billing_identity:$identity,latency_ms:1,countable_cost_usd:null,tokens_measured:1,tokens_estimated:null,result:{findings:["sentinel finding"],source_ids:["SYN"]},metrics:{true_positive:1,false_positive:0,false_negative:0,high_severity_hit:1,source_ids_retained:1,unique_contribution:1}}'
fi
