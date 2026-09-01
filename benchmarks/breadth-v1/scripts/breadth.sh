#!/bin/bash
# Frozen breadth-v1 harness. Never probes providers; execution needs an injected runner.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/manifest.json"
PREREG="$ROOT/PREREGISTRATION.md"
PRIVATE_DEFAULT="$ROOT/private/heldout-v1.json"
SYNTHETIC="$ROOT/fixtures/synthetic-dataset.json"
IS_CI_FIXTURE=false
SHA_BIN="$(command -v shasum || command -v sha256sum)"

die() { echo "breadth-v1: $*" >&2; exit 1; }
sha_file() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then "$SHA_BIN" -a 256 "$1"; else "$SHA_BIN" "$1"; fi | awk '{print $1}'; }
sha_text() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then printf '%s' "$1" | "$SHA_BIN" -a 256; else printf '%s' "$1" | "$SHA_BIN"; fi | awk '{print $1}'; }
need_json() { jq -e . "$1" >/dev/null 2>&1 || die "invalid JSON: $1"; }
use_ci_fixture() { MANIFEST="$ROOT/fixtures/ci-manifest.json"; PREREG="$ROOT/fixtures/CI-PREREGISTRATION.md"; PRIVATE_DEFAULT="$ROOT/fixtures/ci-dataset.json"; IS_CI_FIXTURE=true; }
schedule_json() {
  jq -cS '
    .contract.items as $items |
    [.arms | to_entries[] as $arm |
      $arm.value.calls_per_item as $calls |
      $arm.value.members as $members |
      range(0; $calls) as $position |
      $members[$position % ($members|length)] |
      {family,requested_model,tier,effort,transport,calls:$items}
    ] |
    sort_by(.family,.requested_model,.tier,.effort,.transport) |
    group_by([.family,.requested_model,.tier,.effort,.transport]) |
    map(.[0] + {calls:(map(.calls)|add)})
  ' "$MANIFEST"
}

schedule_hash() { sha_text "$(schedule_json)"; }

evidence_summary() {
  local file="$1" manifest_hash schedule schedule_sha
  [[ -n "$file" && -f "$file" ]] || return 1
  need_json "$file"
  manifest_hash="$(sha_file "$MANIFEST")"
  schedule="$(schedule_json)"
  schedule_sha="$(sha_text "$schedule")"
  jq -ce --arg manifest_hash "$manifest_hash" --arg schedule_sha "$schedule_sha" --argjson schedule "$schedule" '
    def tuple: {family,requested_model,tier,effort,transport};
    (.entries // []) as $raw |
    ($raw | map(tuple) | sort_by(.family,.requested_model,.tier,.effort,.transport)) as $entry_tuples |
    ($schedule | map(tuple) | sort_by(.family,.requested_model,.tier,.effort,.transport)) as $schedule_tuples |
    select(.schema_version == 1) |
    select(.manifest_sha256 == $manifest_hash and .schedule_sha256 == $schedule_sha) |
    select((.expires_at_epoch|type) == "number" and .expires_at_epoch > now) |
    select(($raw|length) == ($entry_tuples|unique|length) and $entry_tuples == $schedule_tuples) |
    select(all($raw[];
      .tier == "premium" and
      .identity.provider_backed == true and
      (.identity.source == "provider-response" or .identity.source == "audited-provider-receipt") and
      .identity.observed_model == .requested_model and
      (.identity.observed_at_epoch|type) == "number" and .identity.observed_at_epoch <= now and
      (.pricing.status == "priced" or .pricing.status == "unpriced") and
      (if .pricing.status == "priced" then
         (.pricing.reservation_cents|type) == "number" and .pricing.reservation_cents > 0 and (.pricing.reservation_cents|floor) == .pricing.reservation_cents
       else true end))) |
    [$schedule[] as $scheduled |
      $raw[] | select(tuple == ($scheduled|tuple)) |
      . + {calls:$scheduled.calls,
           scheduled_reservation_cents:(if .pricing.status == "priced" then .pricing.reservation_cents * $scheduled.calls else null end)}
    ] as $bound |
    {entries:$bound,
     unpriced:[$bound[]|select(.pricing.status == "unpriced")|tuple],
     estimated_countable_cost_cents:([$bound[].scheduled_reservation_cents // 0]|add),
     all_provider_backed:all($bound[];.identity.provider_backed == true)}
  ' "$file" 2>/dev/null
}

validate_contract() {
  need_json "$MANIFEST"
  jq -e '
    (.version == "breadth-v1" or .version == "breadth-v1-ci") and
    (.contract.items == 30) and
    (.contract.categories.security == 10) and
    (.contract.categories["architecture-risk"] == 10) and
    (.contract.categories["operational-failure-mode"] == 10) and
    (.contract.primary_calls_per_item == 24) and .contract.judge_calls_per_item == 1 and
    (.contract.primary_dispatches == 720) and .contract.judge_dispatches == 30 and
    (.contract.planned_dispatches == 750) and .contract.dispatch_cap == 750 and
    (.contract.cost_cap_usd == 150) and .contract.elapsed_hours_cap == 24 and
    (.pricing.reservation_per_dispatch_cents == 20) and (.pricing.cost_cap_cents == 15000) and
    (.arms.A.calls_per_item == 1) and (.arms.B.calls_per_item == 9) and
    (.arms.C.calls_per_item == 2) and (.arms.D.calls_per_item == 3) and
    (.arms.E.calls_per_item == 9) and (.arms.judge.calls_per_item == 1) and
    (.arms.judge.members[0].family == "codex") and
    (.arms.judge.members[0].requested_model == "gpt-5.6-sol") and
    (.arms.judge.members[0].effort == "high") and
    (.arms.E.excluded_families | index("codex")) and
    ([.arms[]?.members[]? | select(.tier != "premium")] | length == 0) and
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
    (.version == "breadth-v1" or .version == "breadth-v1-ci") and (.items | length == 30) and
    ([.items[] | select((.id | test("^(SEC|ARC|OPS)-[0-9]{2}$")) and
      (.category == "security" or .category == "architecture-risk" or .category == "operational-failure-mode") and
      (.prompt | type == "string" and length >= 30) and
      (.rubric.atomic_findings | type == "array" and length >= 3 and
       ([.[] | (.id|type == "string" and length > 0) and (.text|type == "string" and length >= 12) and (.severity as $s | ["low","medium","high","critical"] | index($s) != null) and (.source_ids|type == "array" and length > 0 and length == (unique|length))] | all)) and
      ((.rubric.atomic_findings | [.[].id] | unique | length) == (.rubric.atomic_findings | length)) and
      (.sources | type == "array" and length >= 1 and
       ([.[] | (.id | type == "string" and length > 0) and (.kind | test("^primary-")) and (.url | type == "string" and test("^https://"))] | all) and
       ([.[].id] | length == (unique|length))) and
      (. as $item |
       ([$item.rubric.atomic_findings[] | select(.severity == "high" or .severity == "critical") | .id] | sort) == ($item.rubric.high_severity_ids | unique | sort) and
       ([$item.rubric.atomic_findings[].source_ids[]] | unique | sort) == ($item.rubric.source_ids | unique | sort) and
       all($item.rubric.atomic_findings[].source_ids[]; . as $source | ([$item.sources[].id] | index($source)) != null)))] | length == 30) and
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

receipt_material() {
  local manifest_hash="$1" prereg_hash="$2" data_hash="$3" evidence_hash="$4" schedule_sha="$5" expires="$6"
  printf 'breadth-v1|%s|%s|%s|%s|%s|750|15000|86400|%s' "$manifest_hash" "$prereg_hash" "$data_hash" "$evidence_hash" "$schedule_sha" "$expires"
}

receipt_json() {
  local dataset="$1" evidence="${2:-}" allow_test_actionable="${3:-false}" expires token material manifest_hash prereg_hash data_hash evidence_hash="" schedule_sha summary='{}' actionable=false
  manifest_hash="$(sha_file "$MANIFEST")"; prereg_hash="$(sha_file "$PREREG")"; data_hash="$(sha_file "$dataset")"
  schedule_sha="$(schedule_hash)"
  expires=$(( $(date +%s) + 600 ))
  if [[ -n "$evidence" && -f "$evidence" ]]; then
    evidence_hash="$(sha_file "$evidence")"
    if summary="$(evidence_summary "$evidence")"; then
      if { ! $IS_CI_FIXTURE || [[ "$allow_test_actionable" == "true" ]]; } && [[ -x "$ROOT/scripts/live-runner.sh" ]] &&
         [[ "$(printf '%s' "$summary" | jq '.unpriced|length')" == "0" ]] &&
         (( $(printf '%s' "$summary" | jq '.estimated_countable_cost_cents') <= $(jq '.pricing.cost_cap_cents' "$MANIFEST") )); then
        actionable=true
      fi
    else
      summary='{"entries":[],"unpriced":[{"reason":"invalid-evidence"}],"estimated_countable_cost_cents":0,"all_provider_backed":false}'
    fi
  fi
  material="$(receipt_material "$manifest_hash" "$prereg_hash" "$data_hash" "$evidence_hash" "$schedule_sha" "$expires")"
  $actionable && token="$(sha_text "$material")" || token=""
  jq -n --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson expires_at "$expires" --arg manifest_hash "$manifest_hash" --arg prereg_hash "$prereg_hash" \
    --arg dataset_hash "$data_hash" --arg evidence_hash "$evidence_hash" --arg schedule_hash "$schedule_sha" --arg confirmation_token "$token" --argjson actionable "$actionable" --argjson evidence_summary "$summary" \
    --slurpfile manifest "$MANIFEST" '{
      benchmark:"breadth-v1", generated_at:$generated_at, expires_at_epoch:$expires_at,
      manifest_sha256:$manifest_hash, preregistration_sha256:$prereg_hash, dataset_sha256:$dataset_hash,
      planned_dispatches:$manifest[0].contract.planned_dispatches, dispatch_cap:$manifest[0].contract.dispatch_cap,
      cost_cap_usd:$manifest[0].contract.cost_cap_usd, elapsed_hours_cap:$manifest[0].contract.elapsed_hours_cap,
      estimated_countable_cost_cents:$evidence_summary.estimated_countable_cost_cents,
      unpriced:$evidence_summary.unpriced, no_provider_preflight:true,
      roster:$manifest[0].arms, schedule_sha256:$schedule_hash,
      evidence_sha256:($evidence_hash | if . == "" then null else . end),
      runner_ready:$actionable, actionable_confirmation:$actionable,
      confirmation_token:($confirmation_token | if . == "" then null else . end)
    }'
}

test_receipt() {
  local evidence="$1"
  [[ "${BREADTH_TEST_ONLY:-}" == "1" ]] || die "test-receipt requires BREADTH_TEST_ONLY=1"
  [[ "$evidence" == /tmp/* || "$evidence" == "${TMPDIR:-/tmp}"/* ]] || die "test evidence must be temporary"
  use_ci_fixture; validate_dataset "$PRIVATE_DEFAULT" >/dev/null
  receipt_json "$PRIVATE_DEFAULT" "$evidence" true
}

test_validate_receipt() {
  local receipt="$1" token="$2" evidence="$3"
  [[ "${BREADTH_TEST_ONLY:-}" == "1" ]] || die "test-validate-receipt requires BREADTH_TEST_ONLY=1"
  use_ci_fixture; validate_dataset "$PRIVATE_DEFAULT" >/dev/null
  validate_receipt "$receipt" "$token" "$PRIVATE_DEFAULT" "$evidence"
}

preflight() {
  local json=false dataset="$PRIVATE_DEFAULT" evidence=""
  while (( $# > 0 )); do
    case "$1" in
      --json) json=true; shift ;;
      --evidence) [[ $# -ge 2 ]] || die "preflight --evidence requires FILE"; evidence="$2"; shift 2 ;;
      --*) die "unknown preflight option: $1" ;;
      *) [[ "$dataset" == "$PRIVATE_DEFAULT" ]] || die "preflight accepts one dataset"; dataset="$1"; shift ;;
    esac
  done
  validate_dataset "$dataset" >/dev/null
  if $json; then receipt_json "$dataset" "$evidence"; else receipt_json "$dataset" "$evidence" | jq .; fi
}

validate_receipt() {
  local receipt="$1" token="$2" dataset="$3" evidence="$4" expires material expected evidence_hash schedule_sha
  need_json "$receipt"
  expires="$(jq -r '.expires_at_epoch' "$receipt")"
  [[ "$expires" =~ ^[0-9]+$ ]] && (( expires >= $(date +%s) )) || die "receipt expired"
  [[ "$(jq -r '.manifest_sha256' "$receipt")" == "$(sha_file "$MANIFEST")" ]] || die "receipt manifest hash drift"
  [[ "$(jq -r '.preregistration_sha256' "$receipt")" == "$(sha_file "$PREREG")" ]] || die "receipt preregistration hash drift"
  [[ "$(jq -r '.dataset_sha256' "$receipt")" == "$(sha_file "$dataset")" ]] || die "receipt dataset hash drift"
  [[ "$(jq -r '.runner_ready == true and .actionable_confirmation == true' "$receipt")" == "true" ]] || die "receipt is not actionable"
  [[ -n "$evidence" && -f "$evidence" ]] || die "run requires the reviewed evidence file"
  evidence_summary "$evidence" >/dev/null || die "identity/pricing evidence is invalid or expired"
  evidence_hash="$(sha_file "$evidence")"; schedule_sha="$(schedule_hash)"
  [[ "$(jq -r '.evidence_sha256' "$receipt")" == "$evidence_hash" ]] || die "receipt evidence hash drift"
  [[ "$(jq -r '.schedule_sha256' "$receipt")" == "$schedule_sha" ]] || die "receipt schedule hash drift"
  material="$(receipt_material "$(sha_file "$MANIFEST")" "$(sha_file "$PREREG")" "$(sha_file "$dataset")" "$evidence_hash" "$schedule_sha" "$expires")"
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

reservation_for_member() {
  local member="$1" evidence="${BREADTH_EVIDENCE_FILE:-}" reservation
  if [[ -n "$evidence" && -f "$evidence" ]]; then
    reservation="$(jq -er --argjson member "$member" '.entries[]|select(.family==$member.family and .requested_model==$member.requested_model and .tier==$member.tier and .effort==$member.effort and .transport==$member.transport)|.pricing.reservation_cents' "$evidence")" || return 1
  else
    reservation="$(jq -r '.pricing.reservation_per_dispatch_cents' "$MANIFEST")"
  fi
  [[ "$reservation" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$reservation"
}

record_counts() {
  local run="$1" first
  first=$(find "$run/records" -maxdepth 1 -type f -name '*.json' -print -quit 2>/dev/null || true)
  [[ -n "$first" && -e "$first" ]] || { echo '{"attempted":0,"provider_reached":0,"completed":0,"failed":0,"retries":0,"reserved_cents":0,"accounted_cents":0,"unpriced":0}'; return; }
  jq -s '{
    attempted:(map(select(.status == "attempted"))|length),
    provider_reached:(map(select(.provider_reached == true))|length),
    completed:(map(select(.status == "completed"))|length),
    failed:(map(select(.status == "failed"))|length),
    retries:(map(select(.retry_of != null and .status == "attempted"))|length),
    reserved_cents:([.[] | select(.status == "attempted") | .reservation_countable_cost_cents? // 0] | add),
    accounted_cents:([.[] | select(.status == "completed" or .status == "failed") | .accounted_cost_cents? // 0] | add),
    unpriced:([.[] | select((.status == "completed" or .status == "failed") and .pricing_status == "unpriced")]|length)
  }' "$run/records"/*.json 2>/dev/null || die "record set is not valid JSON"
}

first_orphan_attempt() {
  local run="$1" attempted call_id
  for attempted in "$run"/records/*.attempted.json; do
    [[ -e "$attempted" ]] || return 1
    call_id="$(basename "$attempted" .attempted.json)"
    if [[ ! -e "$run/records/$call_id.completed.json" && ! -e "$run/records/$call_id.failed.json" ]]; then
      printf '%s\n' "$call_id"
      return 0
    fi
  done
  return 1
}

mark_incomplete() {
  local run="$1" reason="$2" tmp
  tmp="$(mktemp "$run/.incomplete.XXXXXX")"
  jq -n --arg reason "$reason" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{binding_status:"incomplete",reason:$reason,recorded_at:$at}' > "$tmp"
  mv "$tmp" "$run/incomplete.json"
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
  local dataset="$PRIVATE_DEFAULT" receipt="" token="" run="" evidence="" runner="$ROOT/scripts/live-runner.sh" receipt_hash orphan
  while (( $# > 0 )); do
    case "$1" in
      --dataset) dataset="$2"; shift 2 ;;
      --receipt) receipt="$2"; shift 2 ;;
      --confirm) token="$2"; shift 2 ;;
      --run-dir) run="$2"; shift 2 ;;
      --evidence) evidence="$2"; shift 2 ;;
      *) die "unknown run option: $1" ;;
    esac
  done
  [[ -n "$receipt" && -n "$token" && -n "$run" && -n "$evidence" ]] || die "run requires --receipt FILE --confirm TOKEN --evidence FILE --run-dir DIR"
  $IS_CI_FIXTURE && die "synthetic CI manifest/corpus can never enter live mode"
  [[ "$run" == /* ]] || die "run directory must be an absolute path"
  case "$run" in "$ROOT"|"$ROOT"/*) die "run directory must be outside tracked benchmark/package paths" ;; esac
  [[ -x "$runner" ]] || die "reviewed live runner is unavailable"
  [[ -z "${BREADTH_RUNNER:-}" || "$BREADTH_RUNNER" == "$runner" ]] || die "binding run rejects alternate runners"
  validate_dataset "$dataset" >/dev/null
  validate_receipt "$receipt" "$token" "$dataset" "$evidence"
  receipt_hash="$(sha_file "$receipt")"
  if [[ -e "$run" ]]; then
    [[ -f "$run/state.json" && -d "$run/records" ]] || die "existing run directory is not a breadth-v1 state"
    [[ "$(jq -r '.manifest_sha256' "$run/state.json")" == "$(sha_file "$MANIFEST")" ]] || die "resume manifest hash drift"
    [[ "$(jq -r '.dataset_sha256' "$run/state.json")" == "$(sha_file "$dataset")" ]] || die "resume dataset hash drift"
    [[ "$(jq -r '.receipt_sha256' "$run/state.json")" == "$receipt_hash" ]] || die "resume receipt hash drift"
    [[ "$(jq -r '.evidence_sha256' "$run/state.json")" == "$(sha_file "$evidence")" ]] || die "resume evidence hash drift"
    [[ ! -f "$run/incomplete.json" ]] || die "run is already marked incomplete"
    if orphan="$(first_orphan_attempt "$run")"; then die "uncertain attempted call blocks resume: $orphan"; fi
  else
    mkdir -p "$run/records" || die "cannot create run directory"
  fi
  mkdir "$run/.lock" || die "run lock is held"
  trap 'rmdir "${run:-}/.lock" 2>/dev/null || true' EXIT
  if [[ ! -f "$run/state.json" ]]; then
    jq -n --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson start_epoch "$(date +%s)" \
      --arg manifest_sha256 "$(sha_file "$MANIFEST")" --arg dataset_sha256 "$(sha_file "$dataset")" \
      --arg preregistration_sha256 "$(sha_file "$PREREG")" --arg schedule_sha256 "$(schedule_hash)" \
      --arg receipt_sha256 "$receipt_hash" --arg evidence_sha256 "$(sha_file "$evidence")" \
      '{started_at:$started,start_epoch:$start_epoch,manifest_sha256:$manifest_sha256,dataset_sha256:$dataset_sha256,
        preregistration_sha256:$preregistration_sha256,schedule_sha256:$schedule_sha256,
        receipt_sha256:$receipt_sha256,evidence_sha256:$evidence_sha256,test_only:false}' > "$run/state.json"
  fi
  BREADTH_EVIDENCE_FILE="$evidence" dispatch_dataset "$dataset" "$run" "$runner" \
    "$(jq '.contract.dispatch_cap' "$MANIFEST")" "$(jq '.pricing.cost_cap_cents' "$MANIFEST")"
  local state_tmp
  state_tmp="$(mktemp "$run/.state.XXXXXX")"; jq --argjson completed_epoch "$(date +%s)" '.completed_epoch=$completed_epoch' "$run/state.json" > "$state_tmp"; mv "$state_tmp" "$run/state.json"
  rmdir "$run/.lock"
  trap - EXIT
}

# Internal-only test entrypoint. It deliberately cannot select a live runner,
# corpus, evidence file, or non-temporary state path. `run --ci` remains refused.
run_test_only() {
  local run="${1:-}" sentinel="$ROOT/scripts/sentinel-runner.sh" cap cost_cap orphan
  [[ -n "$run" ]] || die "test-run requires a temporary run directory"
  case "$run" in /tmp/*|"${TMPDIR:-/tmp}"/*) ;; *) die "test-run state must be under TMPDIR" ;; esac
  [[ "${BREADTH_TEST_ONLY:-}" == "1" ]] || die "test-run requires BREADTH_TEST_ONLY=1"
  [[ -z "${BREADTH_RUNNER:-}" || "${BREADTH_RUNNER}" == "$sentinel" ]] || die "test-run rejects non-sentinel runner"
  [[ -z "${BREADTH_EVIDENCE_FILE:-}" ]] || die "test-run rejects evidence/live readiness"
  use_ci_fixture
  validate_dataset "$PRIVATE_DEFAULT" >/dev/null
  cap="${BREADTH_TEST_DISPATCH_CAP:-$(jq '.contract.dispatch_cap' "$MANIFEST")}"; cost_cap="${BREADTH_TEST_COST_CAP_CENTS:-$(jq '.pricing.cost_cap_cents' "$MANIFEST")}"
  [[ "$cap" =~ ^[1-9][0-9]*$ && "$cost_cap" =~ ^[1-9][0-9]*$ ]] || die "invalid test-only cap override"
  if [[ -e "$run" ]]; then
    [[ -f "$run/state.json" && -d "$run/records" ]] || die "invalid test-run state"
    [[ "$(jq -r '.test_only' "$run/state.json")" == "true" ]] || die "test-run refuses non-test state"
    [[ ! -f "$run/incomplete.json" ]] || die "test-run is already incomplete"
    if orphan="$(first_orphan_attempt "$run")"; then die "uncertain attempted call blocks resume: $orphan"; fi
  else
    mkdir -p "$run/records"
    jq -n --argjson start_epoch "${BREADTH_TEST_START_EPOCH:-$(date +%s)}" --arg manifest "$(sha_file "$MANIFEST")" --arg dataset "$(sha_file "$PRIVATE_DEFAULT")" --arg prereg "$(sha_file "$PREREG")" --arg schedule "$(schedule_hash)" --arg runner "sentinel-runner" '{start_epoch:$start_epoch,manifest_sha256:$manifest,dataset_sha256:$dataset,preregistration_sha256:$prereg,schedule_sha256:$schedule,runner_identity:$runner,test_only:true}' > "$run/state.json"
  fi
  mkdir "$run/.lock" || die "test-run lock is held"
  trap 'rmdir "${run:-}/.lock" 2>/dev/null || true' EXIT
  dispatch_dataset "$PRIVATE_DEFAULT" "$run" "$sentinel" "$cap" "$cost_cap"
  local state_tmp
  state_tmp="$(mktemp "$run/.state.XXXXXX")"; jq --argjson completed_epoch "$(date +%s)" '.completed_epoch=$completed_epoch' "$run/state.json" > "$state_tmp"; mv "$state_tmp" "$run/state.json"
  rmdir "$run/.lock"; trap - EXIT
  [[ -f "$run/analysis.json" ]] && cat "$run/analysis.json"
}

dispatch_dataset() {
  local dataset="$1" run="$2" runner="$3" cap="$4" cost_cap_cents="$5" start_epoch now elapsed calls item id category arm pos call_id member request response record counts orphan reserve base_spend retry_id retry_request retry_response retry_record
  start_epoch="$(jq -r '.start_epoch' "$run/state.json")"
  if orphan="$(first_orphan_attempt "$run")"; then die "uncertain attempted call blocks dispatch: $orphan"; fi
  while IFS=$'\t' read -r id category; do
    for arm in A B C D E judge; do
      calls="$(jq -r --arg arm "$arm" '.arms[$arm].calls_per_item' "$MANIFEST")"
      for ((pos=1; pos<=calls; pos++)); do
        call_id="breadth-v1-${id}-${arm}-${pos}"
        [[ -f "$run/records/$call_id.completed.json" ]] && continue
        [[ ! -f "$run/records/$call_id.failed.json" ]] || die "failed call blocks continuation: $call_id"
        member="$(member_for "$arm" "$pos")"; reserve="$(reservation_for_member "$member")" || die "missing priced reservation for $call_id"
        now="$(date +%s)"; elapsed=$((now - start_epoch))
        (( elapsed < 86400 )) || die "elapsed-time cap reached before dispatch"
        counts="$(record_counts "$run")"
        (( $(printf '%s' "$counts" | jq -r '.attempted') < cap )) || die "dispatch cap reached before dispatch"
        base_spend="$(printf '%s' "$counts" | jq '[.reserved_cents,.accounted_cents]|max')"
        (( base_spend + reserve <= cost_cap_cents )) || die "cost reservation would exceed cap before dispatch"
        item="$(jq -c --arg id "$id" '.items[] | select(.id == $id) | {id,category,prompt}' "$dataset")"
        if [[ "$arm" == "judge" ]]; then
          # The only rubric-bearing payload is the one joint Codex judge request.
          item="$(jq -c --arg id "$id" '.items[] | select(.id == $id)' "$dataset")"
          local arms_packet
          arms_packet="$(jq -s --arg id "$id" '[.[] | select(.item_id == $id and (.arm == "A" or .arm == "B" or .arm == "C" or .arm == "D" or .arm == "E") and .status == "completed") | {arm:.arm, findings:(.result.findings // []), source_ids:(.result.source_ids // [])}] | group_by(.arm) | map({arm:.[0].arm, findings:([.[].findings[]] | unique), source_ids:([.[].source_ids[]] | unique)})' "$run/records"/*.json)"
          [[ "$(printf '%s' "$arms_packet" | jq 'length')" == "5" ]] || die "judge blocked: all five deterministic arm packets are required"
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$item" --argjson arm_outputs "$arms_packet" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" --arg evidence "$(jq -r '.evidence_sha256 // "test-only"' "$run/state.json")" --arg receipt "$(jq -r '.receipt_sha256 // "test-only"' "$run/state.json")" --arg schedule "$(jq -r '.schedule_sha256' "$run/state.json")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,arm_outputs:$arm_outputs,requested_identity:$requested_identity,evidence_sha256:$evidence,receipt_sha256:$receipt,schedule_sha256:$schedule}')"
        else
          request="$(jq -n --arg call_id "$call_id" --arg item_id "$id" --arg category "$category" --arg arm "$arm" --argjson position "$pos" --argjson item "$item" --argjson requested_identity "$member" --arg key "$(sha_text "$call_id")" --arg evidence "$(jq -r '.evidence_sha256 // "test-only"' "$run/state.json")" --arg receipt "$(jq -r '.receipt_sha256 // "test-only"' "$run/state.json")" --arg schedule "$(jq -r '.schedule_sha256' "$run/state.json")" '{call_id:$call_id,idempotency_key:$key,item_id:$item_id,category:$category,arm:$arm,position:$position,item:$item,requested_identity:$requested_identity,evidence_sha256:$evidence,receipt_sha256:$receipt,schedule_sha256:$schedule}')"
        fi
        # Admission is durable before a runner sees the request. Reservation makes cap enforcement pre-dispatch.
        append_record "$run" "$call_id" "$(jq -n --arg call_id "$call_id" --arg arm "$arm" --arg item_id "$id" --arg category "$category" --argjson position "$pos" --argjson requested_identity "$member" --argjson reservation "$reserve" --arg admitted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{call_id:$call_id,arm:$arm,item_id:$item_id,category:$category,position:$position,status:"attempted",provider_reached:false,requested_identity:$requested_identity,reservation_countable_cost_cents:$reservation,admitted_at:$admitted_at}')"
        if ! response="$(printf '%s\n' "$request" | "$runner")"; then
          append_record "$run" "$call_id" "$(jq -n --arg call_id "$call_id" --arg arm "$arm" --arg item_id "$id" --arg category "$category" --argjson requested_identity "$member" '{call_id:$call_id,arm:$arm,item_id:$item_id,category:$category,status:"failed",provider_reached:false,requested_identity:$requested_identity,accounted_cost_cents:0,pricing_status:"estimated",failure_kind:"transport"}')"
          mark_incomplete "$run" "transport failure: $call_id"
          die "transport failure recorded; run is incomplete"
        fi
        if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
          append_record "$run" "$call_id" "$(jq -n --arg call_id "$call_id" --arg arm "$arm" --arg item_id "$id" --arg category "$category" --argjson requested_identity "$member" '{call_id:$call_id,arm:$arm,item_id:$item_id,category:$category,status:"failed",provider_reached:true,requested_identity:$requested_identity,accounted_cost_cents:0,pricing_status:"unpriced",failure_kind:"malformed-response"}')"
          mark_incomplete "$run" "malformed response: $call_id"
          die "malformed runner response recorded"
        fi
        if [[ "$(printf '%s' "$response" | jq -r '.status // empty')" == "transient" ]]; then
          append_record "$run" "$call_id" "$(jq -n --argjson request "$request" --argjson response "$response" '$response + {call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,category:$request.category,position:$request.position,status:"failed",retryable:true,failure_kind:"transient",requested_identity:$request.requested_identity,accounted_cost_cents:($response.accounted_cost_cents // 0),pricing_status:($response.pricing_status // "estimated")}')"
          # The one preregistered retry is admitted like every other attempt.
          retry_id="$call_id-retry-1"; retry_request="$(printf '%s' "$request" | jq --arg id "$retry_id" --arg key "$(sha_text "$retry_id")" '.call_id=$id | .idempotency_key=$key')"
          counts="$(record_counts "$run")"; now="$(date +%s)"; elapsed=$((now - start_epoch)); base_spend="$(printf '%s' "$counts" | jq '[.reserved_cents,.accounted_cents]|max')"
          if (( $(printf '%s' "$counts" | jq '.attempted') >= cap || base_spend + reserve > cost_cap_cents || elapsed >= 86400 )); then
            mark_incomplete "$run" "transient retry not admitted by cap: $call_id"
            die "transient retry not admitted; run is incomplete"
          fi
          append_record "$run" "$retry_id" "$(jq -n --arg retry_of "$call_id" --argjson request "$retry_request" --argjson reserve "$reserve" '{call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,category:$request.category,position:$request.position,status:"attempted",provider_reached:false,retry_of:$retry_of,requested_identity:$request.requested_identity,reservation_countable_cost_cents:$reserve}')"
          if ! retry_response="$(printf '%s\n' "$retry_request" | "$runner")"; then
            append_record "$run" "$retry_id" "$(jq -n --arg retry_of "$call_id" --argjson request "$retry_request" '{call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,category:$request.category,position:$request.position,status:"failed",provider_reached:false,retry_of:$retry_of,requested_identity:$request.requested_identity,accounted_cost_cents:0,pricing_status:"estimated",failure_kind:"retry-transport"}')"
            mark_incomplete "$run" "transient retry transport failure: $call_id"
            die "transient retry failed; run is incomplete"
          fi
          retry_record="$(jq -n --argjson request "$retry_request" --argjson response "$retry_response" '$response + {call_id:$request.call_id,arm:$request.arm,item_id:$request.item_id,requested_identity:$request.requested_identity}')"
          if ! validate_response "$retry_record" "$arm"; then
            append_record "$run" "$retry_id" "$(printf '%s' "$retry_record" | jq '.status="failed" | .failure_kind="retry-schema-or-identity" | .accounted_cost_cents=(.accounted_cost_cents // 0) | .pricing_status=(.pricing_status // "unpriced")')"
            mark_incomplete "$run" "invalid transient retry response: $call_id"
            die "invalid retry response; run is incomplete"
          fi
          append_record "$run" "$retry_id" "$retry_record"
          mark_incomplete "$run" "cap-consuming transient retry: $call_id"
          die "transient retry recorded; binding run is incomplete and must not continue"
        fi
        record="$(jq -n --argjson request "$request" --argjson response "$response" --arg attempted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
          $response + {call_id:$request.call_id,idempotency_key:$request.idempotency_key,arm:$request.arm,item_id:$request.item_id,category:$request.category,position:$request.position,requested_identity:$request.requested_identity,attempted_at:$attempted_at}
        ')"
        if ! validate_response "$record" "$arm"; then
          append_record "$run" "$call_id" "$(printf '%s' "$record" | jq '.status="failed" | .failure_kind="schema-or-identity" | .accounted_cost_cents=(.accounted_cost_cents // 0) | .pricing_status=(.pricing_status // "unpriced")')"
          mark_incomplete "$run" "invalid response: $call_id"
          die "identity, accounting, or response schema failure"
        fi
        append_record "$run" "$call_id" "$record"
        counts="$(record_counts "$run")"
        (( $(printf '%s' "$counts" | jq '.accounted_cents') <= cost_cap_cents )) || { mark_incomplete "$run" "actual accounted cost exceeded cap: $call_id"; die "actual accounted cost exceeded cap"; }
        (( $(date +%s) - start_epoch <= 86400 )) || { mark_incomplete "$run" "elapsed cap exceeded after response: $call_id"; die "elapsed cap exceeded"; }
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
    (.identity_evidence | type == "object") and
    ((.identity_evidence.provider_backed == true) or (.identity_evidence.source == "sentinel")) and
    (.latency_ms | type == "number" and . >= 0) and
    (.accounted_cost_cents | type == "number" and . >= 0 and floor == .) and
    (.pricing_status == "measured" or .pricing_status == "estimated" or .pricing_status == "unpriced") and
    ((.tokens_measured == null) or (.tokens_measured | type == "number" and . >= 0)) and
    ((.tokens_estimated == null) or (.tokens_estimated | type == "number" and . >= 0))
  ' >/dev/null || return 1
  if [[ "$arm" == "judge" ]]; then
    printf '%s' "$record" | jq -e '
      .judge.valid == true and (.judge.scores | type == "array" and length == 5) and
      ([.judge.scores[].arm] | sort == ["A","B","C","D","E"]) and
      (. as $record | [.judge.scores[] | . as $s | select(
        $s.item_id == $record.item_id and
        ($s.tp|type == "number" and . >= 0 and floor == .) and
        ($s.fp|type == "number" and . >= 0 and floor == .) and
        ($s.fn|type == "number" and . >= 0 and floor == .) and
        ($s.high_severity_hit|type == "number" and . >= 0 and floor == .) and
        ($s.high_severity_total|type == "number" and . >= $s.high_severity_hit and floor == .) and
        ($s.source_ids_retained|type == "number" and . >= 0 and floor == .) and
        ($s.source_ids_expected|type == "number" and . >= $s.source_ids_retained and floor == .) and
        ($s.unique_contributions|type == "array") and
        ([ $s.unique_contributions[] | select((.family|type)=="string" and (.count|type)=="number" and .count >= 0 and (.count|floor)==.count) ] | length == ($s.unique_contributions|length)) and
        ([ $s.unique_contributions[].family ] | length == (unique|length))
      )] | length == 5)
    ' >/dev/null || return 1
  else
    printf '%s' "$record" | jq -e '(.result.findings | type == "array") and (.result.source_ids | type == "array") and (.result.source_ids|length == (unique|length))' >/dev/null || return 1
  fi
}

analyze_records() {
  local input="$1" output="${2:-}"
  local report judge_file
  local -a files
  if [[ -f "$input" ]]; then
    files=("$input")
  else
    [[ -d "$input" ]] || die "analyze input does not exist: $input"
    files=("$input"/*.json)
    [[ -e "${files[0]}" ]] || die "analyze input has no records"
  fi
  # Validate every completed judge before aggregation. A malformed judge makes
  # the analysis invalid rather than silently contributing zeros.
  for judge_file in "${files[@]}"; do
    if [[ "$(jq -r 'select(.status=="completed" and .arm=="judge") | .arm' "$judge_file" 2>/dev/null || true)" == "judge" ]]; then
      validate_response "$(cat "$judge_file")" judge || die "analyzer rejected invalid judge: $(basename "$judge_file")"
    fi
  done
  report="$(jq -s '
    def div0($a;$b): if $b == 0 then null else $a / $b end;
    def tokens: (.tokens_measured // .tokens_estimated // 0);
    def item_scores:
      [.[] | select(.status=="completed" and .arm=="judge") as $judge |
       $judge.judge.scores[] |
       {item_id:$judge.item_id,category:$judge.category,arm,
        tp,fp,fn,high_severity_hit,high_severity_total,
        source_ids_retained,source_ids_expected,unique_contributions,
        recall:div0(.tp; .tp+.fn),precision:div0(.tp; .tp+.fp),
        high_severity_capture:div0(.high_severity_hit;.high_severity_total),
        source_id_retention:div0(.source_ids_retained;.source_ids_expected)}];
    item_scores as $matrix |
    ([.[]|select(.status=="completed")]|group_by(.arm)|map(
      {arm:.[0].arm,calls:length,accounted_cost_cents:([.[].accounted_cost_cents//0]|add),
       measured_tokens:([.[]|.tokens_measured//0]|add),estimated_tokens:([.[]|.tokens_estimated//0]|add),
       mean_latency_ms:(if length==0 then null else ([.[].latency_ms]|add)/length end)})) as $accounting |
    ($matrix|group_by(.arm)|map(
      ([.[].tp]|add) as $tp | ([.[].fp]|add) as $fp | ([.[].fn]|add) as $fn |
      ([.[].high_severity_hit]|add) as $hh | ([.[].high_severity_total]|add) as $ht |
      ([.[].source_ids_retained]|add) as $sr | ([.[].source_ids_expected]|add) as $se |
      {arm:.[0].arm,items:length,tp:$tp,fp:$fp,fn:$fn,
       recall:div0($tp;$tp+$fn),precision:div0($tp;$tp+$fp),
       high_severity_hit:$hh,high_severity_total:$ht,high_severity_capture:div0($hh;$ht),
       source_ids_retained:$sr,source_ids_expected:$se,source_id_retention:div0($sr;$se)})) as $aggregates |
    {schema_version:1,records:length,
     attempted:([.[]|select(.status=="attempted")]|length),
     completed:([.[]|select(.status=="completed")]|length),
     failed:([.[]|select(.status=="failed")]|length),
     provider_reached:([.[]|select(.provider_reached==true)]|length),
     retries:([.[]|select(.retry_of!=null and .status=="attempted")]|length),
     judge_valid:(($matrix|length)>0),item_arm_matrix:$matrix,aggregate_by_arm:$aggregates,
     accounting_by_arm:$accounting,
     total_accounted_cost_cents:([.[]|select(.status=="completed" or .status=="failed")|.accounted_cost_cents//0]|add),
     unpriced_call_ids:[.[]|select((.status=="completed" or .status=="failed") and .pricing_status=="unpriced")|.call_id],
     unique_contribution_by_consultant:([$matrix[].unique_contributions[]]|sort_by(.family)|group_by(.family)|map({family:.[0].family,unique_findings:([.[].count]|add)})),
     binding_claim:false,binding_reason:"manual-audit eligibility is a separate gate"}
  ' "${files[@]}")" || die "analyzer failed"
  if [[ -n "$output" ]]; then printf '%s\n' "$report" > "$output"; else printf '%s\n' "$report"; fi
}

expected_call_ids_json() {
  local dataset="$1" id arm calls pos
  {
    while IFS= read -r id; do
      for arm in A B C D E judge; do
        calls="$(jq -r --arg arm "$arm" '.arms[$arm].calls_per_item' "$MANIFEST")"
        for ((pos=1; pos<=calls; pos++)); do printf 'breadth-v1-%s-%s-%s\n' "$id" "$arm" "$pos"; done
      done
    done < <(jq -r '.items[].id' "$dataset")
  } | jq -Rsc 'split("\n")|map(select(length>0))|sort'
}

records_hash() {
  local records="$1" material="" file
  while IFS= read -r file; do
    material="${material}$(basename "$file"):$(sha_file "$file")\n"
  done < <(find "$records" -maxdepth 1 -type f -name '*.json' | LC_ALL=C sort)
  sha_text "$material"
}

eligibility() {
  local run="$1" audit="$2" records counts expected attempted_ids completed_ids judges identities exact_ids cost_ok elapsed_ok audit_ok hashes_ok incomplete=false eligible=false rec_hash analysis_hash
  [[ -f "$run/state.json" && -d "$run/records" && -f "$run/analysis.json" && -f "$audit" ]] || die "eligibility requires completed RUN_DIR, analysis, and manual audit attestation"
  # Synthetic state is always ineligible, but its diagnostics must remain
  # reproducible on clean CI where the private corpus intentionally is absent.
  [[ "$(jq -r '.test_only // false' "$run/state.json")" == "true" ]] && use_ci_fixture
  need_json "$audit"
  records="$run/records"; counts="$(record_counts "$run")"; expected="$(expected_call_ids_json "$PRIVATE_DEFAULT")"
  attempted_ids="$(jq -cS -s '[.[]|select(.status=="attempted")|.call_id]|sort' "$records"/*.json)"
  completed_ids="$(jq -cS -s '[.[]|select(.status=="completed")|.call_id]|sort' "$records"/*.json)"
  [[ "$attempted_ids" == "$expected" && "$completed_ids" == "$expected" ]] && exact_ids=true || exact_ids=false
  judges="$(jq -s '[.[]|select(.status=="completed" and .arm=="judge" and .judge.valid==true)]|length' "$records"/*.json)"
  identities="$(jq -s '[.[]|select(.status=="completed")|(.requested_identity==.effective_identity and .requested_identity==.billing_identity and .identity_evidence.provider_backed==true and .identity_evidence.source!="sentinel")]|all' "$records"/*.json)"
  (( $(printf '%s' "$counts" | jq '.accounted_cents') <= $(jq '.pricing.cost_cap_cents' "$MANIFEST") )) && [[ "$(printf '%s' "$counts" | jq '.unpriced')" == "0" ]] && cost_ok=true || cost_ok=false
  [[ "$(jq -r '(.completed_epoch // 0) > 0 and ((.completed_epoch-.start_epoch) <= 86400)' "$run/state.json")" == "true" ]] && elapsed_ok=true || elapsed_ok=false
  [[ ! -f "$run/incomplete.json" ]] || incomplete=true
  rec_hash="$(records_hash "$records")"; analysis_hash="$(sha_file "$run/analysis.json")"
  hashes_ok="$(jq -r --arg manifest "$(sha_file "$MANIFEST")" --arg prereg "$(sha_file "$PREREG")" --arg dataset "$(sha_file "$PRIVATE_DEFAULT")" --arg schedule "$(schedule_hash)" '.manifest_sha256==$manifest and .preregistration_sha256==$prereg and .dataset_sha256==$dataset and .schedule_sha256==$schedule' "$run/state.json")"
  audit_ok="$(jq -r --arg manifest "$(sha_file "$MANIFEST")" --arg prereg "$(sha_file "$PREREG")" --arg dataset "$(sha_file "$PRIVATE_DEFAULT")" --arg evidence "$(jq -r '.evidence_sha256 // ""' "$run/state.json")" --arg schedule "$(schedule_hash)" --arg records "$rec_hash" --arg analysis "$analysis_hash" '
    .approved==true and .scope=="breadth-v1-manual-audit" and
    (.auditor|type=="string" and length>0) and (.timestamp|type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and
    .manifest_sha256==$manifest and .preregistration_sha256==$prereg and .dataset_sha256==$dataset and
    .evidence_sha256==$evidence and .schedule_sha256==$schedule and .records_sha256==$records and .analysis_sha256==$analysis
  ' "$audit")"
  if $exact_ids && [[ "$judges" == "30" && "$identities" == "true" && "$(printf '%s' "$counts" | jq '.attempted')" == "750" && "$(printf '%s' "$counts" | jq '.completed')" == "750" && "$(printf '%s' "$counts" | jq '.failed')" == "0" && "$(printf '%s' "$counts" | jq '.retries')" == "0" ]] && $cost_ok && $elapsed_ok && ! $incomplete && [[ "$hashes_ok" == "true" && "$audit_ok" == "true" && "$(jq -r '.test_only' "$run/state.json")" == "false" ]]; then eligible=true; fi
  jq -n --argjson eligible "$eligible" --argjson counts "$counts" --argjson exact_ids "$exact_ids" --argjson judges "$judges" --arg identities "$identities" --argjson cost_ok "$cost_ok" --argjson elapsed_ok "$elapsed_ok" --argjson incomplete "$incomplete" --arg hashes_ok "$hashes_ok" --arg audit_ok "$audit_ok" --arg records_sha256 "$rec_hash" --arg analysis_sha256 "$analysis_hash" '{binding_claim_eligible:$eligible,counts:$counts,exact_expected_call_ids:$exact_ids,valid_judges:$judges,exact_provider_backed_identities:($identities=="true"),cost_cap_met:$cost_ok,elapsed_cap_met:$elapsed_ok,incomplete_marker:$incomplete,frozen_hashes_match:($hashes_ok=="true"),manual_audit_bound:($audit_ok=="true"),records_sha256:$records_sha256,analysis_sha256:$analysis_sha256}'
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
  validate) shift; [[ "${1:-}" == "--ci" ]] && use_ci_fixture && shift; validate_dataset "${1:-$PRIVATE_DEFAULT}" ;;
  preflight) shift; [[ "${1:-}" == "--ci" ]] && use_ci_fixture && shift; preflight "$@" ;;
  smoke) smoke ;;
  run) shift; [[ "${1:-}" == "--ci" ]] && use_ci_fixture && shift; run_live "$@" ;;
  test-run) shift; run_test_only "${1:-}" ;;
  test-receipt) shift; [[ $# -eq 1 ]] || die "test-receipt requires EVIDENCE"; test_receipt "$1" ;;
  test-validate-receipt) shift; [[ $# -eq 3 ]] || die "test-validate-receipt requires RECEIPT TOKEN EVIDENCE"; test_validate_receipt "$1" "$2" "$3" ;;
  schedule) shift; [[ "${1:-}" == "--ci" ]] && use_ci_fixture && shift; [[ $# -eq 0 ]] || die "schedule accepts only --ci"; schedule_json ;;
  analyze) shift; [[ $# -ge 1 ]] || die "analyze requires records directory"; analyze_records "$1" "${2:-}" ;;
  eligibility) shift; [[ $# -eq 2 ]] || die "eligibility requires RUN_DIR MANUAL_AUDIT.json"; eligibility "$1" "$2" ;;
  *) echo "usage: breadth.sh validate [dataset] | preflight [--json] [--evidence FILE] [dataset] | schedule | smoke | run --receipt FILE --confirm TOKEN --evidence FILE --run-dir DIR [--dataset FILE] | analyze RECORDS_DIR [OUT] | eligibility RUN_DIR AUDIT.json" >&2; exit 2 ;;
esac
