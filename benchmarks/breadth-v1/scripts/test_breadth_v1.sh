#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/scripts/breadth.sh"
SHA_BIN="$(command -v shasum || command -v sha256sum)"
sha_file() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then "$SHA_BIN" -a 256 "$1"; else "$SHA_BIN" "$1"; fi | awk '{print $1}'; }
sha_text() { if [[ "$(basename "$SHA_BIN")" == "shasum" ]]; then printf '%s' "$1" | "$SHA_BIN" -a 256; else printf '%s' "$1" | "$SHA_BIN"; fi | awk '{print $1}'; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/breadth-v1-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "breadth-v1 test: $*" >&2; exit 1; }

bash "$HARNESS" validate --ci
bash "$HARNESS" smoke >/dev/null
if BREADTH_SENTINEL_BAD_IDENTITY=1 bash "$HARNESS" smoke >/dev/null 2>&1; then exit 1; fi
if BREADTH_SENTINEL_INVALID_JUDGE=1 bash "$HARNESS" smoke >/dev/null 2>&1; then exit 1; fi
positive="$(bash "$HARNESS" analyze "$ROOT/fixtures/positive-run.jsonl")"
[[ "$(printf '%s' "$positive" | jq -r '.aggregate_by_arm[]|select(.arm=="A")|.recall')" == "0.8" ]] || fail "judge-derived recall"
[[ "$(printf '%s' "$positive" | jq '.item_arm_matrix|length')" == "5" && "$(printf '%s' "$positive" | jq '.aggregate_by_arm|length')" == "5" ]] || fail "item/arm matrix"
if bash "$HARNESS" analyze "$ROOT/fixtures/negative-run.jsonl" >/dev/null 2>&1; then fail "duplicate judge arm accepted"; fi

# Public CI data can validate and preflight, but can never enter live mode.
if BREADTH_RUNNER="$ROOT/scripts/sentinel-runner.sh" bash "$HARNESS" run --ci --run-dir "$TMP/no-confirm" >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$TMP/no-confirm" ]]
bash "$HARNESS" preflight --ci --json > "$TMP/receipt.json"
[[ "$(jq -r '.runner_ready' "$TMP/receipt.json")" == "false" && "$(jq -r '.confirmation_token' "$TMP/receipt.json")" == "null" ]] || fail "CI receipt became actionable"

# Hidden receipt contract: generation and validation use identical canonical
# evidence/schedule material, while the public CI preflight above stays blocked.
schedule="$(bash "$HARNESS" schedule --ci)"; schedule_hash="$(sha_text "$schedule")"
entries="$(printf '%s' "$schedule" | jq --argjson observed "$(date +%s)" 'map(del(.calls) + {identity:{provider_backed:true,source:"provider-response",observed_model:.requested_model,observed_at_epoch:$observed},pricing:{status:"priced",reservation_cents:20}})')"
jq -n --arg manifest_sha256 "$(sha_file "$ROOT/fixtures/ci-manifest.json")" --arg schedule_sha256 "$schedule_hash" --argjson expires_at_epoch "$(( $(date +%s) + 600 ))" --argjson entries "$entries" '{schema_version:1,manifest_sha256:$manifest_sha256,schedule_sha256:$schedule_sha256,expires_at_epoch:$expires_at_epoch,entries:$entries}' > "$TMP/evidence.json"
BREADTH_TEST_ONLY=1 bash "$HARNESS" test-receipt "$TMP/evidence.json" > "$TMP/actionable-receipt.json"
token="$(jq -r '.confirmation_token' "$TMP/actionable-receipt.json")"
[[ "$(jq -r '.runner_ready' "$TMP/actionable-receipt.json")" == "true" && "$token" != "null" ]] || fail "valid evidence did not produce test receipt"
BREADTH_TEST_ONLY=1 bash "$HARNESS" test-validate-receipt "$TMP/actionable-receipt.json" "$token" "$TMP/evidence.json"
jq '.entries[0].pricing.reservation_cents=21' "$TMP/evidence.json" > "$TMP/evidence-mutated.json"
if BREADTH_TEST_ONLY=1 bash "$HARNESS" test-validate-receipt "$TMP/actionable-receipt.json" "$token" "$TMP/evidence-mutated.json" >/dev/null 2>&1; then fail "mutated evidence retained receipt"; fi
if BREADTH_LIVE_RUNNER_REVIEWED=true bash "$HARNESS" run --ci --receipt "$TMP/actionable-receipt.json" --confirm "$token" --evidence "$TMP/evidence.json" --run-dir "$TMP/forbidden-ci-run" >/dev/null 2>&1; then fail "run --ci accepted"; fi
[[ ! -e "$TMP/forbidden-ci-run" ]] || fail "run --ci created state"

# Exercise the real evidence/mapping/prompt/normalization bridge with hermetic
# stub adapters. MAX_RETRIES=1 means one adapter attempt and zero adapter retry.
evidence_hash="$(sha_file "$TMP/evidence.json")"; gemini_identity="$(jq -c '.arms.A.members[0]' "$ROOT/fixtures/ci-manifest.json")"; codex_identity="$(jq -c '.arms.judge.members[0]' "$ROOT/fixtures/ci-manifest.json")"
primary_request="$(jq -n --argjson identity "$gemini_identity" --arg evidence "$evidence_hash" '{call_id:"live-stub-A-1",item_id:"SEC-01",arm:"A",item:{id:"SEC-01",category:"security",prompt:"synthetic primary"},requested_identity:$identity,evidence_sha256:$evidence,test_only:true}')"
primary_bridge="$(printf '%s' "$primary_request" | BREADTH_EVIDENCE_FILE="$TMP/evidence.json" BREADTH_LIVE_RUNNER_REVIEWED=true BREADTH_LIVE_RUNNER_TEST_ONLY=true BREADTH_STUB_COUNTER="$TMP/live-counter" bash "$ROOT/scripts/live-runner.sh")"
[[ "$(cat "$TMP/live-counter")" == "1" && "$(printf '%s' "$primary_bridge" | jq '.result.findings|length')" == "1" ]] || fail "primary live bridge"
judge_request="$(jq -n --argjson identity "$codex_identity" --arg evidence "$evidence_hash" '{call_id:"live-stub-judge-1",item_id:"SEC-01",arm:"judge",item:{id:"SEC-01",category:"security",prompt:"synthetic judge",rubric:{atomic_findings:[{id:"f1",text:"finding",severity:"high",source_ids:["S1"]}],high_severity_ids:["f1"],source_ids:["S1"]},sources:[{id:"S1",kind:"primary-synthetic",url:"https://example.invalid"}]},arm_outputs:(["A","B","C","D","E"]|map({arm:.,findings:[{text:"finding",source_id:(.+":1"),family:"gemini"}]})),requested_identity:$identity,evidence_sha256:$evidence,test_only:true}')"
judge_bridge="$(printf '%s' "$judge_request" | BREADTH_EVIDENCE_FILE="$TMP/evidence.json" BREADTH_LIVE_RUNNER_REVIEWED=true BREADTH_LIVE_RUNNER_TEST_ONLY=true BREADTH_STUB_COUNTER="$TMP/live-counter" bash "$ROOT/scripts/live-runner.sh")"
[[ "$(cat "$TMP/live-counter")" == "2" && "$(printf '%s' "$judge_bridge" | jq '.judge.scores|length')" == "5" ]] || fail "judge live bridge"
printf '%s\n' "$judge_request" > "$TMP/judge-request.json"; printf '%s\n' "$judge_bridge" > "$TMP/judge-response.json"
normalized_judge="$(BREADTH_TEST_ONLY=1 bash "$HARNESS" test-normalize-judge "$TMP/judge-response.json" "$TMP/judge-request.json")"
[[ "$(printf '%s' "$normalized_judge" | jq '[.judge.scores[]|select(.high_severity_total==1 and .source_ids_expected==1 and .source_ids_retained==1)]|length')" == "5" && "$(printf '%s' "$normalized_judge" | jq -r '.judge.scores[0].unique_contributions[0].family')" == "gemini" ]] || fail "local judge denominators/attribution"

# This is the non-vacuous scheduler path: the only permitted runner is the local
# sentinel, it traverses all 750 scheduled calls, and a second run proves resume
# skips completed IDs without another adapter/provider invocation.
real="$TMP/real"
counter="$TMP/sentinel-count"
BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_COUNTER="$counter" bash "$HARNESS" test-run "$real" > "$TMP/real-analysis.json"
[[ "$(cat "$counter")" == "750" ]]
[[ "$(find "$real/records" -name '*.attempted.json' -type f | wc -l | tr -d ' ')" == "750" ]]
[[ "$(find "$real/records" -name '*.completed.json' -type f | wc -l | tr -d ' ')" == "750" ]]
[[ "$(jq '.item_arm_matrix|length' "$real/analysis.json")" == "150" && "$(jq '.aggregate_by_arm|length' "$real/analysis.json")" == "5" ]] || fail "full analyzer matrix"
BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_COUNTER="$counter" bash "$HARNESS" test-run "$real" > /dev/null
[[ "$(cat "$counter")" == "750" ]]
mkdir "$real/.lock"; printf '999999\n' > "$real/.lock/pid"
BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_COUNTER="$counter" bash "$HARNESS" test-run "$real" > /dev/null
[[ "$(cat "$counter")" == "750" && "$(find "$real" -maxdepth 1 -type d -name '.lock.stale.*' | wc -l | tr -d ' ')" == "1" ]] || fail "stale lock recovery"

# Final-call transient: start from 749 completed calls, make call 750 transient,
# and prove no retry/call 751 is admitted.
final="$TMP/final-transient"; cp -R "$real" "$final"; rm -f "$final/analysis.json"; jq 'del(.completed_epoch)' "$final/state.json" > "$final/state.next"; mv "$final/state.next" "$final/state.json"
rm -f "$final/records/breadth-v1-OPS-10-judge-1.attempted.json" "$final/records/breadth-v1-OPS-10-judge-1.completed.json"
printf '749\n' > "$TMP/final-count"
if BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_COUNTER="$TMP/final-count" BREADTH_SENTINEL_TRANSIENT_AT=750 BREADTH_SENTINEL_STATE_DIR="$TMP/final-state" bash "$HARNESS" test-run "$final" >/dev/null 2>&1; then fail "final transient completed"; fi
[[ "$(cat "$TMP/final-count")" == "750" && ! -e "$final/records/breadth-v1-OPS-10-judge-1-retry-1.attempted.json" && -f "$final/incomplete.json" ]] || fail "call 751 admitted"

# An early transient is retried once, recorded with a distinct ID, and makes
# the run incomplete. The reduced test cap is available only in test-run.
if BREADTH_TEST_ONLY=1 BREADTH_TEST_DISPATCH_CAP=3 BREADTH_TEST_COST_CAP_CENTS=60 BREADTH_SENTINEL_COUNTER="$TMP/retry-count" BREADTH_SENTINEL_TRANSIENT_AT=1 BREADTH_SENTINEL_STATE_DIR="$TMP/retry-state" bash "$HARNESS" test-run "$TMP/retry" >/dev/null 2>&1; then fail "retry run became binding"; fi
[[ "$(cat "$TMP/retry-count")" == "2" && -f "$TMP/retry/records/breadth-v1-SEC-01-A-1-retry-1.attempted.json" && -f "$TMP/retry/incomplete.json" ]] || fail "single retry not recorded"

# Resume, elapsed, and cost gates must fail before the sentinel receives a call.
mkdir -p "$TMP/orphan/records"; cp "$real/state.json" "$TMP/orphan/state.json"; jq 'del(.completed_epoch)' "$TMP/orphan/state.json" > "$TMP/orphan/state.next"; mv "$TMP/orphan/state.next" "$TMP/orphan/state.json"; cp "$real/records/breadth-v1-SEC-01-A-1.attempted.json" "$TMP/orphan/records/"
if BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_COUNTER="$TMP/orphan-count" bash "$HARNESS" test-run "$TMP/orphan" >/dev/null 2>&1; then fail "orphan resume accepted"; fi
[[ ! -e "$TMP/orphan-count" ]] || fail "orphan resume called sentinel"
if BREADTH_TEST_ONLY=1 BREADTH_TEST_START_EPOCH=0 BREADTH_SENTINEL_COUNTER="$TMP/time-count" bash "$HARNESS" test-run "$TMP/time-cap" >/dev/null 2>&1; then fail "elapsed cap accepted"; fi
[[ ! -e "$TMP/time-count" && -f "$TMP/time-cap/incomplete.json" ]] || fail "elapsed cap called sentinel or lacked marker"
if BREADTH_TEST_ONLY=1 BREADTH_TEST_COST_CAP_CENTS=19 BREADTH_SENTINEL_COUNTER="$TMP/cost-count" bash "$HARNESS" test-run "$TMP/cost-cap" >/dev/null 2>&1; then fail "cost cap accepted"; fi
[[ ! -e "$TMP/cost-count" && -f "$TMP/cost-cap/incomplete.json" ]] || fail "cost cap called sentinel or lacked marker"

# Identity and each judge mutation reach the real validator and become durable
# failed/incomplete states.
if BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_BAD_IDENTITY=1 BREADTH_SENTINEL_COUNTER="$TMP/id-count" bash "$HARNESS" test-run "$TMP/bad-id" >/dev/null 2>&1; then fail "bad identity accepted"; fi
[[ "$(cat "$TMP/id-count")" == "1" && -f "$TMP/bad-id/incomplete.json" ]] || fail "bad identity not recorded"
for mutation in duplicate missing unknown negative; do
  case_dir="$TMP/judge-$mutation"; case_count="$TMP/judge-$mutation-count"
  if BREADTH_TEST_ONLY=1 BREADTH_SENTINEL_JUDGE_MUTATION="$mutation" BREADTH_SENTINEL_COUNTER="$case_count" bash "$HARNESS" test-run "$case_dir" >/dev/null 2>&1; then fail "judge mutation accepted: $mutation"; fi
  [[ "$(cat "$case_count")" == "25" && -f "$case_dir/incomplete.json" ]] || fail "judge mutation not exercised: $mutation"
done

# Synthetic state can never satisfy binding eligibility, even with 750 exact IDs.
jq -n '{approved:false,scope:"breadth-v1-manual-audit",auditor:"fixture",timestamp:"2026-09-02T00:00:00Z"}' > "$TMP/audit.json"
eligibility="$(bash "$HARNESS" eligibility "$real" "$TMP/audit.json")"
[[ "$(printf '%s' "$eligibility" | jq -r '.binding_claim_eligible')" == "false" && "$(printf '%s' "$eligibility" | jq -r '.exact_expected_call_ids')" == "true" ]] || fail "eligibility gate"

echo "breadth-v1 tests passed: 750-call scheduler, resume, retry/caps, judge mutations, analyzer, and eligibility"
