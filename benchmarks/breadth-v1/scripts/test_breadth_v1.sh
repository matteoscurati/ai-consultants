#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$ROOT/scripts/breadth.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/breadth-v1-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

bash "$HARNESS" validate
bash "$HARNESS" smoke >/dev/null
if BREADTH_SENTINEL_BAD_IDENTITY=1 bash "$HARNESS" smoke >/dev/null 2>&1; then exit 1; fi
if BREADTH_SENTINEL_INVALID_JUDGE=1 bash "$HARNESS" smoke >/dev/null 2>&1; then exit 1; fi
positive="$(bash "$HARNESS" analyze "$ROOT/fixtures/positive-run.jsonl")"
[[ "$(printf '%s' "$positive" | jq -r '.recall')" == "0.8" && "$(printf '%s' "$positive" | jq -r '.judge_valid')" == "true" ]]
negative="$(bash "$HARNESS" analyze "$ROOT/fixtures/negative-run.jsonl")"
[[ "$(printf '%s' "$negative" | jq -r '.judge_valid')" == "false" && "$(printf '%s' "$negative" | jq -r '.binding_claim')" == "false" ]]

# No confirmation must leave no run directory and never invoke the runner.
if BREADTH_RUNNER="$ROOT/scripts/sentinel-runner.sh" bash "$HARNESS" run --run-dir "$TMP/no-confirm" >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$TMP/no-confirm" ]]

bash "$HARNESS" preflight --json > "$TMP/receipt.json"
token="$(jq -r '.confirmation_token' "$TMP/receipt.json")"
jq '.dataset_sha256 = "bad"' "$TMP/receipt.json" > "$TMP/bad-receipt.json"
if BREADTH_RUNNER="$ROOT/scripts/sentinel-runner.sh" bash "$HARNESS" run --receipt "$TMP/bad-receipt.json" --confirm "$token" --run-dir "$TMP/bad" >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$TMP/bad" ]]

# A stale resumable state reaches the time cap before the sentinel receives a request.
mkdir -p "$TMP/capped/records"
jq -n --arg manifest_sha256 "$(shasum -a 256 "$ROOT/manifest.json" | awk '{print $1}')" --arg dataset_sha256 "$(shasum -a 256 "$ROOT/private/heldout-v1.json" | awk '{print $1}')" '{start_epoch:0,manifest_sha256:$manifest_sha256,dataset_sha256:$dataset_sha256}' > "$TMP/capped/state.json"
if BREADTH_RUNNER="$ROOT/scripts/sentinel-runner.sh" bash "$HARNESS" run --receipt "$TMP/receipt.json" --confirm "$token" --run-dir "$TMP/capped" >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$TMP/capped/records/breadth-v1-SEC-01-A-1.attempted.json" ]]

# A transient failure is durably attempted, retried once as a distinct call, then marked non-binding.
if BREADTH_RUNNER="$ROOT/scripts/sentinel-runner.sh" BREADTH_SENTINEL_TRANSIENT_ONCE=1 BREADTH_SENTINEL_STATE_DIR="$TMP/sentinel-state" bash "$HARNESS" run --receipt "$TMP/receipt.json" --confirm "$token" --run-dir "$TMP/retry" >/dev/null 2>&1; then exit 1; fi
[[ -f "$TMP/retry/records/breadth-v1-SEC-01-A-1.attempted.json" ]]
[[ -f "$TMP/retry/records/breadth-v1-SEC-01-A-1-retry-1.attempted.json" ]]
[[ -f "$TMP/retry/incomplete.json" ]]
echo "breadth-v1 tests passed: validation, leak sentinel, receipt, cap, and analyzer checks"
