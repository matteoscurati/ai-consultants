#!/usr/bin/env bash
# run_calibration.sh — data-collection harness for roster_calibrate.sh.
#
# Runs each benchmark question (references/calibration_benchmark.json) through
# the full panel with ENABLE_PEER_REVIEW=true, collects the output dirs, then
# calibrates measured intelligence/taste/cost scores.
#
# WARNING: this makes real consultant calls for EVERY question — it costs money
# and takes time (dozens of consultations). Use --limit to sample first and
# --dry-run to preview without running anything.
#
# Usage: run_calibration.sh [--limit N] [--dry-run] [--write]
#   --limit N    only run the first N benchmark questions
#   --dry-run    print the plan; execute nothing
#   --write      after collecting, merge measured scores into affinity.json
#   -h, --help   show this header
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="$SCRIPT_DIR/../references/calibration_benchmark.json"

main() {
    local limit=0 dry=0 do_write=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --limit)   limit="${2:-0}"; shift 2 ;;
            --dry-run) dry=1; shift ;;
            --write)   do_write=1; shift ;;
            -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
            *)         echo "unknown option: $1" >&2; exit 2 ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "run_calibration: jq is required" >&2; exit 2; }
    [[ -f "$BENCH" ]] || { echo "run_calibration: benchmark not found: $BENCH" >&2; exit 1; }

    local total
    total=$(jq '.questions | length' "$BENCH")
    [[ "$limit" -gt 0 && "$limit" -lt "$total" ]] && total="$limit"

    echo "Calibration run: $total question(s) x full panel, ENABLE_PEER_REVIEW=true."
    [[ "$dry" -eq 1 ]] && echo "(dry run — nothing will be executed)"
    echo

    local dirs=() i=0 q qcat outdir
    while IFS= read -r q; do
        [[ "$limit" -gt 0 && "$i" -ge "$limit" ]] && break
        i=$((i+1))
        qcat=$(jq -r ".questions[$((i-1))].category" "$BENCH")
        printf '[%d/%d] %-12s %.70s\n' "$i" "$total" "$qcat" "$q"
        [[ "$dry" -eq 1 ]] && continue
        outdir=$(ENABLE_PEER_REVIEW=true "$SCRIPT_DIR/consult_all.sh" "$q" 2>/dev/null | tail -1)
        if [[ -n "$outdir" && -d "$outdir" ]]; then
            dirs+=("$outdir")
        else
            echo "     ! consultation produced no output dir — skipped"
        fi
    done < <(jq -r '.questions[].q' "$BENCH")

    if [[ "$dry" -eq 1 ]]; then
        echo; echo "Dry run complete. Re-run without --dry-run to collect data."
        exit 0
    fi

    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo "No consultations succeeded — nothing to calibrate. Check ./scripts/doctor.sh --live." >&2
        exit 1
    fi

    echo; echo "Collected ${#dirs[@]} consultation(s). Calibrating..."
    local calib_args=()
    [[ "$do_write" -eq 1 ]] && calib_args+=(--write)
    "$SCRIPT_DIR/roster_calibrate.sh" ${calib_args[@]+"${calib_args[@]}"} "${dirs[@]}"
}

main "$@"
