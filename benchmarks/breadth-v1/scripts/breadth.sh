#!/bin/bash
# Frozen breadth-v1 harness. Never probes providers; execution needs an injected runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/manifest.json"
PREREG="$ROOT/PREREGISTRATION.md"
PRIVATE_DEFAULT="$ROOT/private/heldout-v1.json"
SYNTHETIC="$ROOT/fixtures/synthetic-dataset.json"
SHA_BIN="$(command -v shasum || command -v sha256sum)"

die() { echo "breadth-v1: $*" >&2; exit 1; }
sha_file() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then "$SHA_BIN" -a 256 "$1"; else "$SHA_BIN" "$1"; fi | awk '{print $1}'; }
sha_text() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then printf '%s' "$1" | "$SHA_BIN" -a 256; else printf '%s' "$1" | "$SHA_BIN"; fi | awk '{print $1}'; }
need_json() { jq -e . "$1" >/dev/null 2>&1 || die "invalid JSON: $1"; }

validate_contract() {
  need_json "$MANIFEST"
  jq -e '
    .version == "breadth-v1" and
    (.contract.items == 30) and
    (.contract.categories.security == 10) and
    (.contract.categories["architecture-risk"] == 10) and
    (.contract.categories["operational-failure-mode"] == 10) and
    (.contract.primary_calls_per_item == 24) and .contract.judge_calls_per_item == 1 and
    (.contract.primary_dispatches == 720) and .contract.judge_dispatches == 30 and
    (.contract.planned_dispatches == 750) and .contract.dispatch_cap == 750 and
    (.contract.cost_cap_usd == 150) and .contract.elapsed_hours_cap == 24 and
    (.arms.A.calls_per_item == 1) and (.arms.B.calls_per_item == 9) and
    (.arms.C.calls_per_item == 2) and (.arms.D.calls_per_item == 3) and
    (.arms.E.calls_per_item == 9) and (.arms.judge.calls_per_item == 1) and
    (.arms.judge.members[0].family == "codex") and
    (.arms.judge.members[0].requested_model == "gpt-5.6-sol") and
    (.arms.judge.members[0].effort == "high") and
    (.arms.E.excluded_families | index("codex")) and
    (.items | length == 30) and
    ([.items[].category] | map(select(. == "security")) | length == 10) and
    ([.items[].category] | map(select(. == "architecture-risk")) | length == 10) and
    ([.items[].category] | map(select(. == "operational-failure-mode")) | length == 10) and
    ([.items[].id] | unique | length == 30) and
    ([.items[] | select((.item_sha256 | test("^[0-9a-f]{64}$")) and (.source_id | type == "string"))] | length == 30)
  ' "$MANIFEST" >/dev/null || die "frozen manifest contract is invalid"
}

validate_dataset() {
  local dataset="${1:-$PRIVATE_DEFAULT}" count
  validate_contract
  need_json "$dataset"
  [[ "$(sha_file "$dataset")" == "$(jq -r '.dataset_sha256' "$MANIFEST")" ]] || die "dataset hash drift"
  [[ "$(sha_file "$PREREG")" == "$(jq -r '.preregistration_sha256' "$MANIFEST")" ]] || die "preregistration hash drift"
  jq -e '
    .version == "breadth-v1" and (.items | length == 30) and
    ([.items[] | select((.id | test("^(SEC|ARC|OPS)-[0-9]{2}$")) and
      (.category == "security" or .category == "architecture-risk" or .category == "operational-failure-mode") and
      (.prompt | type == "string" and length >= 30) and
      (.rubric.atomic_findings | type == "array" and length >= 3) and
      (.rubric.high_severity_ids | type == "array" and length >= 1) and
      (.rubric.source_ids | type == "array" and length >= 1) and
      (.sources | type == "array" and length >= 1 and
       ([.[] | (.id | type == "string" and length > 0) and (.kind | test("^primary-")) and (.url | type == "string" and test("^https://"))] | all)))] | length == 30) and
    ([.items[].category] | map(select(. == "security")) | length == 10) and
    ([.items[].category] | map(select(. == "architecture-risk")) | length == 10) and
    ([.items[].category] | map(select(. == "operational-failure-mode")) | length == 10)
  ' "$dataset" >/dev/null || die "dataset does not satisfy held-out schema contract"
  while IFS=$'\t' read -r id hash source_id; do
    local actual expected manifest_source
    # jq compact output is the frozen item bytes; no prompt/rubric content leaves this process.
    actual="$(sha_text "$(jq -c --arg id "$id" '.items[] | select(.id == $id)' "$dataset")")"
    expected="$hash"
    manifest_source="$source_id"
    [[ "$actual" == "$expected" ]] || die "item hash drift: $id"
    jq -e --arg id "$id" --arg source "$manifest_source" '.items[] | select(.id == $id) | (.sources | map(.id) | index($source))' "$dataset" >/dev/null || die "source metadata drift: $id"
  done < <(jq -r '.items[] | [.id, .item_sha256, .source_id] | @tsv' "$MANIFEST")
  count="$(jq '.items | length' "$dataset")"
  echo "validated held-out dataset: $count items, sha256=$(sha_file "$dataset")"
}

receipt_json() {
  local dataset="$1" expires token material manifest_hash prereg_hash data_hash
  manifest_hash="$(sha_file "$MANIFEST")"; prereg_hash="$(sha_file "$PREREG")"; data_hash="$(sha_file "$dataset")"
  expires=$(( $(date +%s) + 600 ))
  material="breadth-v1|$manifest_hash|$prereg_hash|$data_hash|750|150|$expires"
  token="$(sha_text "$material")"
  jq -n --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson expires_at "$expires" --arg manifest_hash "$manifest_hash" --arg prereg_hash "$prereg_hash" \
    --arg dataset_hash "$data_hash" --arg confirmation_token "$token" \
    --slurpfile manifest "$MANIFEST" '{
      benchmark:"breadth-v1", generated_at:$generated_at, expires_at_epoch:$expires_at,
      manifest_sha256:$manifest_hash, preregistration_sha256:$prereg_hash, dataset_sha256:$dataset_hash,
      planned_dispatches:$manifest[0].contract.planned_dispatches, dispatch_cap:$manifest[0].contract.dispatch_cap,
      cost_cap_usd:$manifest[0].contract.cost_cap_usd, elapsed_hours_cap:$manifest[0].contract.elapsed_hours_cap,
      estimated_countable_cost_usd:$manifest[0].pricing.estimated_countable_cost_usd, pricing_status:$manifest[0].pricing.status, no_provider_preflight:true,
      roster:$manifest[0].arms, confirmation_token:$confirmation_token
    }'
}

preflight() {
  local json=false dataset="$PRIVATE_DEFAULT"
  [[ "${1:-}" == "--json" ]] && json=true && shift
  [[ -n "${1:-}" ]] && dataset="$1"
  validate_dataset "$dataset" >/dev/null
  if $json; then receipt_json "$dataset"; else receipt_json "$dataset" | jq .; fi
}

validate_receipt() {
  local receipt="$1" token="$2" dataset="$3" expires material expected
  need_json "$receipt"
  expires="$(jq -r '.expires_at_epoch' "$receipt")"
  [[ "$expires" =~ ^[0-9]+$ ]] && (( expires >= $(date +%s) )) || die "receipt expired"
  [[ "$(jq -r '.manifest_sha256' "$receipt")" == "$(sha_file "$MANIFEST")" ]] || die "receipt manifest hash drift"
  [[ "$(jq -r '.preregistration_sha256' "$receipt")" == "$(sha_file "$PREREG")" ]] || die "receipt preregistration hash drift"
  [[ "$(jq -r '.dataset_sha256' "$receipt")" == "$(sha_file "$dataset")" ]] || die "receipt dataset hash drift"
  material="breadth-v1|$(sha_file "$MANIFEST")|$(sha_file "$PREREG")|$(sha_file "$dataset")|750|150|$expires"
  expected="$(sha_text "$material")"
  [[ "$token" == "$expected" && "$token" == "$(jq -r '.confirmation_token' "$receipt")" ]] || die "action-time confirmation token does not bind this receipt"
}

member_for() {
  local arm="$1" position="$2"
  if [[ "$arm" == "judge" ]]; then jq -c '.arms.judge.members[0]' "$MANIFEST"; return; fi
  jq -c --arg arm "$arm" --argjson p "$position" '
    .arms[$arm].members[(($p - 1) % (.arms[$arm].members | length))]
  ' "$MANIFEST"
}

record_counts() {
  local run="$1"
  jq -s '{attempted:map(select(.status == "attempted"))|length, provider_reached:map(select(.provider_reached == true))|length, completed:map(select(.status == "completed"))|length, retries:map(select(.retry_of != null and .status == "attempted"))|length, cost:([.[] | select(.status == "attempted") | .reservation_countable_cost_usd? // 0] | add)}' "$run/records"/*.json 2>/dev/null || echo '{"attempted":0,"provider_reached":0,"completed":0,"retries":0,"cost":0}'
}

append_record() {
  local run="$1" call_id="$2" record="$3" tmp state
  state="$(printf '%s' "$record" | jq -r '.status')"
  [[ "$state" == "attempted" || "$state" == "completed" || "$state" == "failed" ]] || die "record state must be attempted, completed, or failed"
  tmp="$(mktemp "$run/.record.XXXXXX")"
  printf '%s\n' "$record" > "$tmp"
  [[ ! -e "$run/records/$call_id.$state.json" ]] || die "append-only record already exists: $call_id.$state"
  mv "$tmp" "$run/records/$call_id.$state.json"
}

run_live() {
  local dataset="$PRIVATE_DEFAULT" receipt="" token="" run="" runner="${BREADTH_RUNNER:-}"
  while (( $# > 0 )); do
    case "$1" in
      --dataset) dataset="$2"; shift 2 ;;
      --receipt) receipt="$2"; shift 2 ;;
      --confirm) token="$2"; shift 2 ;;
      --run-dir) run="$2"; shift 2 ;;
      *) die "unknown run option: $1" ;;
    esac
  done
  [[ -n "$receipt" && -n "$token" && -n "$run" ]] || die "run requires --receipt FILE --confirm TOKEN --run-dir DIR"
  case "$run" in "$ROOT"/*) die "run directory must be outside tracked benchmark/package paths" ;; esac
  [[ -n "$runner" && -x "$runner" ]] || die "no enabled live runner; inject an executable BREADTH_RUNNER after receipt review"
  validate_dataset "$dataset" >/dev/null
  validate_receipt "$receipt" "$token" "$dataset"
  if [[ -e "$run" ]]; then
    [[ -f "$run/state.json" && -d "$run/records" ]] || die "existing run directory is not a breadth-v1 state"
    [[ "$(jq -r '.manifest_sha256' "$run/state.json")" == "$(sha_file "$MANIFEST")" ]] || die "resume manifest hash drift"
    [[ "$(jq -r '.dataset_sha256' "$run/state.json")" == "$(sha_file "$dataset")" ]] || die "resume dataset hash drift"
  else
    mkdir -p "$run/records" || die "cannot create run directory"
  fi
  mkdir "$run/.lock" || die "run lock is held"
  trap 'rmdir "${run:-}/.lock" 2>/dev/null || true' EXIT
  if [[ ! -f "$run/state.json" ]]; then
    jq -n --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson start_epoch "$(date +%s)" \
      --arg manifest_sha256 "$(sha_file "$MANIFEST")" --arg dataset_sha256 "$(sha_file "$dataset")" \
      '{started_at:$started,start_epoch:$start_epoch,manifest_sha256:$manifest_sha256,dataset_sha256:$dataset_sha256}' > "$run/state.json"
  fi
  dispatch_dataset "$dataset" "$run" "$runner"
  rmdir "$run/.lock"
  trap - EXIT
}

dispatch_dataset() {
  local dataset="$1" run="$2" runner="$3" start_epoch now elapsed cap calls item id category arm pos call_id member request response record counts
  start_epoch="$(jq -r '.start_epoch' "$run/state.json")"; cap="$(jq -r '.contract.dispatch_cap' "$MANIFEST")"
  while IFS=$'\t' read -r id category; do
    for arm in A B C D E judge; do
      calls="$(jq -r --arg arm "$arm" '.arms[$arm].calls_per_item' "$MANIFEST")"
      for ((pos=1; pos<=calls; pos++)); do
        call_id="breadth-v1-${id}-${arm}-${pos}"
        [[ -f "$run/records/$call_id.completed.json" ]] && continue
        now="$(date +%s)"; elapsed=$((now - start_epoch))
        (( elapsed < 86400 )) || die "elapsed-time cap reached before dispatch"
        counts="$(record_counts "$run")"
        (( $(printf '%s' "$counts" | jq -r '.attempted') < cap )) || die "dispatch cap reached before dispatch"
        jq -ne --argjson used "$(printf '%s' "$counts" | jq '.cost')" --argjson reserve "$(jq '.pricing.reservation_per_dispatch_usd' "$MANIFEST")" '$used + $reserve <= 150' >/dev/null || die "cost reservation would exceed cap before dispatch"
        member="$(member_for "$arm" "$pos")"
        item="$(jq -c --arg id "$id" '.items[] | select(.id == $id) | {id,category,prompt}' "$dataset")"
        if [[ "$arm" == "judge" ]]; then
          # The only rubric-bearing payload is the one joint Codex judge request.
          item="$(jq -c --arg id "$id" '.items[] | select(.id == $id)' "$dataset")"
          local arms_packet
          arms_packet="$(jq -s --arg id "$id" '[.[] | select(.item_id == $id and (.arm == "A" or .arm == "B" or .arm == "C" or .arm == "D" or .arm == "E") and .status == "completed") | {arm:.arm, findings:(.result.findings // []), source_ids:(.result.source_ids // [])}] | group_by(.arm) | map({arm:.[0].arm, findings:([.[].findings[]] | unique), source_ids:([.[].source_ids[]] | unique)})' "$run/records"/*.json)"
          [[ "$(printf '%s' "$arms_packet" | jq 'length')" == "5" ]] || die "judge blocked: all five deterministic arm packets are required"
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$item" --argjson arm_outputs "$arms_packet" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,arm_outputs:$arm_outputs,requested_identity:$requested_identity}')"
        else
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$item" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,requested_identity:$requested_identity}')"
        fi
        # Admission is durable before a runner sees the request. Reservation makes cap enforcement pre-dispatch.
        append_record "$run" "$call_id" "$(jq -n --arg call_id "$call_id" --arg arm "$arm" --arg item_id "$id" --argjson requested_identity "$member" --argjson reservation "$(jq -r '.pricing.reservation_per_dispatch_usd' "$MANIFEST")" '{call_id:$call_id,arm:$arm,item_id:$item_id,status:"attempted",provider_reached:false,requested_identity:$requested_identity,reservation_countable_cost_usd:$reservation}')"
        response="$(printf '%s\n' "$request" | "$runner")" || die "transport failure is durably attempted; retry is not admitted at the 750-call binding cap"
        if [[ "$(printf '%s' "$response" | jq -r '.status // empty')" == "transient" ]]; then
          append_record "$run" "$call_id" "$(jq -n --argjson request "$request" --argjson response "$response" '$response + {call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,status:"failed",retryable:true,requested_identity:$request.requested_identity}')"
          # One retry is preregistered. It is a distinct durable attempt and irrevocably makes this binding run incomplete.
          local retry_id retry_request retry_response retry_record
          retry_id="$call_id-retry-1"; retry_request="$(printf '%s' "$request" | jq --arg id "$retry_id" --arg key "$(sha_text "$retry_id")" '.call_id=$id | .idempotency_key=$key')"
          append_record "$run" "$retry_id" "$(jq -n --arg retry_of "$call_id" --argjson request "$retry_request" --argjson reserve "$(jq -r '.pricing.reservation_per_dispatch_usd' "$MANIFEST")" '{call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,status:"attempted",provider_reached:false,retry_of:$retry_of,requested_identity:$request.requested_identity,reservation_countable_cost_usd:$reserve}')"
          retry_response="$(printf '%s\n' "$retry_request" | "$runner")" || die "transient retry transport failed; run is incomplete"
          retry_record="$(jq -n --argjson request "$retry_request" --argjson response "$retry_response" '$response + {call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,requested_identity:$request.requested_identity}')"
          validate_response "$retry_record" "$arm"; append_record "$run" "$retry_id" "$retry_record"
          printf '{"binding_status":"incomplete","reason":"cap-consuming transient retry"}\n' > "$run/incomplete.json"
          die "transient retry recorded; binding run is incomplete and must not continue"
        fi
        printf '%s' "$response" | jq -e . >/dev/null || die "malformed runner response for $call_id"
        record="$(jq -n --argjson request "$request" --argjson response "$response" --arg attempted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
          $response + {call_id:$request.call_id,idempotency_key:$request.idempotency_key,arm:$request.arm,item_id:$request.item_id,requested_identity:$request.requested_identity,attempted_at:$attempted_at}
        ')"
        validate_response "$record" "$arm"
        append_record "$run" "$call_id" "$record"
        [[ "$(printf '%s' "$record" | jq -r '.status')" == "completed" ]] || die "incomplete sample recorded; no retry dispatched because it would exceed the binding 750-call plan"
      done
    done
  done < <(jq -r '.items[] | [.id, .category] | @tsv' "$dataset")
  analyze_records "$run/records" "$run/analysis.json"
}

validate_response() {
  local record="$1" arm="$2"
  printf '%s' "$record" | jq -e '
    (.status == "completed") and (.provider_reached == true) and
    (.effective_identity != null) and (.billing_identity != null) and
    (.requested_identity == .effective_identity) and
    (.requested_identity == .billing_identity) and
    (.latency_ms | type == "number") and
    ((.countable_cost_usd == null) or (.countable_cost_usd | type == "number")) and
    ((.tokens_measured == null) or (.tokens_measured | type == "number")) and
    ((.tokens_estimated == null) or (.tokens_estimated | type == "number"))
  ' >/dev/null || die "identity, accounting, or response schema failure"
  if [[ "$arm" == "judge" ]]; then
    printf '%s' "$record" | jq -e '.judge.valid == true and (.judge.scores | type == "array") and (.judge.scores | length == 5)' >/dev/null || die "invalid structured judge response"
  else
    printf '%s' "$record" | jq -e '(.result.findings | type == "array") and (.result.source_ids | type == "array")' >/dev/null || die "invalid primary response"
  fi
}

analyze_records() {
  local input="$1" output="${2:-}"
  local report
  if [[ -f "$input" ]]; then
    report="$(jq -s '
    def div0(a;b): if b == 0 then null else a / b end;
    def metric($name): ([.[] | .metrics? | select(. != null) | .[$name]] | add // 0);
    {records:length, attempted:length, completed:map(select(.status == "completed"))|length,
     provider_reached:map(select(.provider_reached == true))|length,
     retries:map(select(.retry_of != null))|length,
     countable_cost_usd:([.[] | .countable_cost_usd? // 0] | add),
     measured_tokens:([.[] | .tokens_measured? // 0] | add), estimated_tokens:([.[] | .tokens_estimated? // 0] | add),
     mean_latency_ms:(([.[] | .latency_ms? // empty] | add) / (map(select(.latency_ms != null)) | length)),
     judge_valid:([.[] | select(.arm == "judge") | .judge.valid] | all),
     recall:div0(metric("true_positive"); metric("true_positive") + metric("false_negative")),
     precision:div0(metric("true_positive"); metric("true_positive") + metric("false_positive")),
     high_severity_capture:metric("high_severity_hit"), source_id_retention:metric("source_ids_retained"), binding_claim:false,
     binding_reason:"manual-audit gate and full-run verification are required",
     unique_contribution_by_consultant:(group_by(.effective_identity.family) | map({family:.[0].effective_identity.family, unique_findings:([.[].metrics?.unique_contribution // 0] | add)}))}
  ' "$input")"
  else
  report="$(jq -s '
    def div0(a;b): if b == 0 then null else a / b end;
    def metric($name): ([.[] | .metrics? | select(. != null) | .[$name]] | add // 0);
    {records:length, attempted:length, completed:map(select(.status == "completed"))|length,
     provider_reached:map(select(.provider_reached == true))|length,
     retries:map(select(.retry_of != null))|length,
     countable_cost_usd:([.[] | .countable_cost_usd? // 0] | add),
     measured_tokens:([.[] | .tokens_measured? // 0] | add), estimated_tokens:([.[] | .tokens_estimated? // 0] | add),
     mean_latency_ms:(([.[] | .latency_ms? // empty] | add) / (map(select(.latency_ms != null)) | length)),
     judge_valid:([.[] | select(.arm == "judge") | .judge.valid] | all),
     recall:div0(metric("true_positive"); metric("true_positive") + metric("false_negative")),
     precision:div0(metric("true_positive"); metric("true_positive") + metric("false_positive")),
     high_severity_capture:metric("high_severity_hit"), source_id_retention:metric("source_ids_retained"), binding_claim:false,
     binding_reason:"manual-audit gate and full-run verification are required",
     unique_contribution_by_consultant:(group_by(.effective_identity.family) | map({family:.[0].effective_identity.family, unique_findings:([.[].metrics?.unique_contribution // 0] | add)}))}
  ' "$input"/*.json 2>/dev/null || jq -n '[]')"
  fi
  if [[ -n "$output" ]]; then printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
}

eligibility() {
  local run="$1" audit="$2" records counts complete judges identities hashes eligible=false
  [[ -f "$run/state.json" && -d "$run/records" && -f "$audit" ]] || die "eligibility requires RUN_DIR and manual audit attestation"
  need_json "$audit"
  records="$run/records"; counts="$(record_counts "$run")"
  complete="$(jq -s '[.[] | select(.status == "completed")] | length' "$records"/*.json)"
  judges="$(jq -s '[.[] | select(.status == "completed" and .arm == "judge" and .judge.valid == true)] | length' "$records"/*.json)"
  identities="$(jq -s '[.[] | select(.status == "completed") | (.requested_identity == .effective_identity and .requested_identity == .billing_identity)] | all' "$records"/*.json)"
  hashes="$(jq -r '.manifest_sha256' "$run/state.json")|$(jq -r '.dataset_sha256' "$run/state.json")"
  if [[ "$complete" == "750" && "$judges" == "30" && "$identities" == "true" && \
        "$(printf '%s' "$counts" | jq -r '.attempted')" == "750" && "$(printf '%s' "$counts" | jq -r '.retries')" == "0" && \
        "$(printf '%s' "$counts" | jq -r '.cost')" == "150" && "$hashes" == "$(sha_file "$MANIFEST")|$(sha_file "$PRIVATE_DEFAULT")" && \
        "$(jq -r '.approved == true and .scope == "breadth-v1-manual-audit"' "$audit")" == "true" ]]; then eligible=true; fi
  jq -n --argjson eligible "$eligible" --argjson attempted "$(printf '%s' "$counts" | jq '.attempted')" --argjson completed "$complete" --argjson valid_judges "$judges" --arg identities "$identities" '{binding_claim_eligible:$eligible,attempted:$attempted,completed:$completed,valid_judges:$valid_judges,exact_identity_evidence:($identities == "true"),manual_audit_required:true}'
}

smoke() {
  local tmp runner="$ROOT/scripts/sentinel-runner.sh" items calls
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/breadth-v1-smoke.XXXXXX")"
  trap 'rm -rf "${tmp:-}"' EXIT
  need_json "$SYNTHETIC"
  items="$(jq '.items | length' "$SYNTHETIC")"; calls=$((items * 25))
  # Schedule/account/analyzer path with synthetic records only; no run directory survives.
  mkdir -p "$tmp/records"
  local id category arm pos call_id member request response record
  while IFS=$'\t' read -r id category; do
    for arm in A B C D E judge; do
      for ((pos=1; pos<=$(jq -r --arg arm "$arm" '.arms[$arm].calls_per_item' "$MANIFEST"); pos++)); do
        call_id="smoke-${id}-${arm}-${pos}"; member="$(member_for "$arm" "$pos")"
        if [[ "$arm" == "judge" ]]; then
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$(jq -c --arg id "$id" '.items[] | select(.id == $id)' "$SYNTHETIC")" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,arm_outputs:[{arm:"A",findings:[],source_ids:[]},{arm:"B",findings:[],source_ids:[]},{arm:"C",findings:[],source_ids:[]},{arm:"D",findings:[],source_ids:[]},{arm:"E",findings:[],source_ids:[]}],requested_identity:$requested_identity}')"
        else
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$(jq -c --arg id "$id" '.items[] | select(.id == $id) | {id,category,prompt}' "$SYNTHETIC")" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,requested_identity:$requested_identity}')"
        fi
        response="$(printf '%s\n' "$request" | "$runner")"
        record="$(jq -n --argjson request "$request" --argjson response "$response" '$response + {call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,requested_identity:$request.requested_identity}')"
        validate_response "$record" "$arm"; append_record "$tmp" "$call_id" "$record"
      done
    done
  done < <(jq -r '.items[] | [.id,.category] | @tsv' "$SYNTHETIC")
  analyze_records "$tmp/records"
  echo "smoke passed: synthetic_items=$items simulated_dispatches=$calls provider_calls=0 persistent_live_state=0" >&2
  rm -rf "$tmp"
  trap - EXIT
}

case "${1:-}" in
  validate) shift; validate_dataset "${1:-$PRIVATE_DEFAULT}" ;;
  preflight) shift; preflight "$@" ;;
  smoke) smoke ;;
  run) shift; run_live "$@" ;;
  analyze) shift; [[ $# -ge 1 ]] || die "analyze requires records directory"; analyze_records "$1" "${2:-}" ;;
  eligibility) shift; [[ $# -eq 2 ]] || die "eligibility requires RUN_DIR MANUAL_AUDIT.json"; eligibility "$1" "$2" ;;
  *) echo "usage: breadth.sh validate [dataset] | preflight [--json] [dataset] | smoke | run --receipt FILE --confirm TOKEN --run-dir DIR [--dataset FILE] | analyze RECORDS_DIR [OUT]" >&2; exit 2 ;;
esac
