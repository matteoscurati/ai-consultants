#!/bin/bash
# Test-only runner. It cannot contact a provider and rejects accidental non-sentinel use.
set -euo pipefail
request="$(cat)"
printf '%s' "$request" | jq -e '.call_id and .requested_identity.family' >/dev/null
call_number=0
if [[ -n "${BREADTH_SENTINEL_COUNTER:-}" ]]; then
  [[ "$BREADTH_SENTINEL_COUNTER" == /tmp/* || "$BREADTH_SENTINEL_COUNTER" == "${TMPDIR:-/tmp}"/* ]] || { echo "sentinel counter must be temporary" >&2; exit 94; }
  n=0; [[ -f "$BREADTH_SENTINEL_COUNTER" ]] && n="$(cat "$BREADTH_SENTINEL_COUNTER")"
  call_number=$((n + 1)); printf '%s\n' "$call_number" > "$BREADTH_SENTINEL_COUNTER"
fi
arm="$(printf '%s' "$request" | jq -r '.arm')"
identity="$(printf '%s' "$request" | jq -c '.requested_identity')"
if [[ "${BREADTH_SENTINEL_TRANSIENT_ONCE:-0}" == "1" || ( -n "${BREADTH_SENTINEL_TRANSIENT_AT:-}" && "$call_number" == "$BREADTH_SENTINEL_TRANSIENT_AT" ) ]]; then
  [[ -n "${BREADTH_SENTINEL_STATE_DIR:-}" ]] || { echo "sentinel requires BREADTH_SENTINEL_STATE_DIR" >&2; exit 93; }
  mkdir -p "$BREADTH_SENTINEL_STATE_DIR"
  if [[ ! -e "$BREADTH_SENTINEL_STATE_DIR/transient-used" ]]; then
    : > "$BREADTH_SENTINEL_STATE_DIR/transient-used"
    jq -n '{status:"transient",provider_reached:true,reason:"sentinel transient",accounted_cost_cents:0,pricing_status:"estimated"}'
    exit 0
  fi
fi
if [[ "$arm" != "judge" ]]; then
  printf '%s' "$request" | jq -e '(.item | keys | sort) == ["category", "id", "prompt"] and (tostring | test("atomic_findings|high_severity_ids|source_ids|sources") | not)' >/dev/null || { echo "sentinel: primary held-out leak" >&2; exit 91; }
else
  printf '%s' "$request" | jq -e '(.arm_outputs | length == 5) and ([.arm_outputs[].arm]|sort==["A","B","C","D","E"]) and (.item.rubric != null) and (.item.sources != null) and all(.arm_outputs[].findings[]; (.text|type)=="string" and (.source_id|type)=="string" and (.family|type)=="string")' >/dev/null || { echo "sentinel: invalid joint judge packet" >&2; exit 92; }
fi
if [[ "$arm" == "judge" ]]; then
  scores="$(printf '%s' "$request" | jq -c '[.arm_outputs[] | {item_id:$item_id,arm,tp:1,fp:0,fn:0,high_severity_hit:1,retained_source_ids:([.findings[0].source_id]|map(select(.!=null))),unique_contributions:([.findings[0].family]|map(select(.!=null))|unique|map({family:.,count:1}))}]' --arg item_id "$(printf '%s' "$request" | jq -r '.item_id')")"
  case "${BREADTH_SENTINEL_JUDGE_MUTATION:-}" in
    duplicate) scores="$(printf '%s' "$scores" | jq '.[4]=.[0]')" ;;
    missing) scores="$(printf '%s' "$scores" | jq '.[0:4]')" ;;
    unknown) scores="$(printf '%s' "$scores" | jq '.[4].arm="Z"')" ;;
    negative) scores="$(printf '%s' "$scores" | jq '.[0].tp=-1')" ;;
  esac
  jq -n --argjson identity "$identity" --argjson valid "$( [[ "${BREADTH_SENTINEL_INVALID_JUDGE:-0}" == "1" ]] && echo false || echo true )" --argjson scores "$scores" --argjson cost "${BREADTH_SENTINEL_ACCOUNTED_CENTS:-0}" '{status:"completed",provider_reached:true,effective_identity:$identity,billing_identity:$identity,identity_evidence:{provider_backed:false,source:"sentinel"},latency_ms:1,accounted_cost_cents:$cost,pricing_status:"estimated",tokens_measured:1,tokens_estimated:null,judge:{valid:$valid,scores:$scores}}'
else
  jq -n --argjson identity "$identity" --argjson effective "$( [[ "${BREADTH_SENTINEL_BAD_IDENTITY:-0}" == "1" ]] && echo '{"family":"wrong"}' || printf '%s' "$identity" )" --arg source_id "$(printf '%s' "$request" | jq -r '.call_id'):1" --argjson cost "${BREADTH_SENTINEL_ACCOUNTED_CENTS:-0}" '{status:"completed",provider_reached:true,effective_identity:$effective,billing_identity:$identity,identity_evidence:{provider_backed:false,source:"sentinel"},latency_ms:1,accounted_cost_cents:$cost,pricing_status:"estimated",tokens_measured:1,tokens_estimated:null,result:{findings:["sentinel finding"],source_ids:[$source_id]}}'
fi
