#!/usr/bin/env bash
# roster_calibrate.sh — MEASURE capability scores from consultation history,
# replacing the heuristic seeds in references/affinity.json (Tier A).
#
# The three axes are derived, not guessed — each from a signal the tool already
# records, and sliced by the SAME category_axis that consumes them:
#
#   intelligence = mean blind PEER-REVIEW score on intelligence-axis categories
#   taste        = mean blind PEER-REVIEW score on taste-axis categories
#   cost         = mean observed $/response (tokens_used x catalog rate),
#                  rank-normalized (cheapest = 10). This is cost-per-*task*
#                  (verbosity + completion), not per-token sticker price.
#
# Requires consultations run with ENABLE_PEER_REVIEW=true (peer scores) and the
# default cost tracking (tokens_used in metadata). Read-only unless --write.
#
# Usage: roster_calibrate.sh [--recent N] [--json] [--write] [dir ...]
#   dir...       consultation output dirs (each: <consultant>.json + peer_review/
#                + optimization_metrics.json). Default: N most recent under base.
#   --recent N   number of recent consultations to use (default 30)
#   --json       emit {measured_capabilities, samples} JSON
#   --write      merge measured values into references/affinity.json (backup first)
#   -h, --help   show this header
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"        # get_category_axis
COST_RATES="$SCRIPT_DIR/../docs/cost_rates.json"
AFFINITY_JSON="$SCRIPT_DIR/../references/affinity.json"

# Input/output token split convention (mirrors lib/costs.sh's 60/40 estimate)
# and the fallback rate for a model absent from the catalog (per-1K).
SPLIT_IN=0.6; SPLIT_OUT=0.4
FALLBACK_IN=0.005; FALLBACK_OUT=0.015

qacc=""; cacc=""
trap '[[ -n "$qacc" ]] && rm -f "$qacc"; [[ -n "$cacc" ]] && rm -f "$cacc"' EXIT

# Per-response cost in dollars from a model + total token count. Rate looked up
# case-insensitively (callers/consultants vary case); falls back if absent.
_response_cost() {
    local model="$1" tokens="$2" rin rout
    read -r rin rout < <(jq -r --arg m "$model" '
        (.models | to_entries
         | map(select(.key | ascii_downcase == ($m | ascii_downcase)))
         | .[0].value) as $r
        | if $r then "\($r.input) \($r.output)" else "NA NA" end
    ' "$COST_RATES" 2>/dev/null)
    if [[ "$rin" == "NA" || -z "${rin:-}" ]]; then rin=$FALLBACK_IN; rout=$FALLBACK_OUT; fi
    awk -v t="$tokens" -v i="$rin" -v o="$rout" -v si="$SPLIT_IN" -v so="$SPLIT_OUT" \
        'BEGIN{ printf "%.8f", (t/1000)*(si*i + so*o) }'
}

# Locate a peer-review aggregate file in <dir>/peer_review by SHAPE (an array of
# {consultant, average_peer_score}) — robust to its exact filename.
_find_peer_file() {
    local pdir="$1/peer_review" pf
    [[ -d "$pdir" ]] || return 1
    for pf in "$pdir"/*.json; do
        [[ -f "$pf" ]] || continue
        if jq -e 'type=="array" and length>0 and (.[0]|has("average_peer_score") and has("consultant"))' \
            "$pf" >/dev/null 2>&1; then
            echo "$pf"; return 0
        fi
    done
    return 1
}

main() {
    local recent=30 as_json=0 do_write=0
    local dirs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --recent) recent="${2:-30}"; shift 2 ;;
            --json)   as_json=1; shift ;;
            --write)  do_write=1; shift ;;
            -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
            -*)       echo "unknown option: $1" >&2; exit 2 ;;
            *)        dirs+=("$1"); shift ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "roster_calibrate: jq is required" >&2; exit 2; }
    command -v awk >/dev/null 2>&1 || { echo "roster_calibrate: awk is required" >&2; exit 2; }

    if [[ ${#dirs[@]} -eq 0 ]]; then
        # shellcheck source=config.sh
        source "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || true
        local base="${DEFAULT_OUTPUT_DIR_BASE:-/tmp/ai_consultations}"
        [[ -d "$base" ]] || { echo "roster_calibrate: no dirs given and base '$base' not found" >&2; exit 1; }
        while IFS= read -r d; do dirs+=("$d"); done < <(
            find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n "$recent"
        )
    fi

    qacc="$(mktemp "${TMPDIR:-/tmp}/rc_quality.XXXXXX")"   # lines: "consultant axis score"
    cacc="$(mktemp "${TMPDIR:-/tmp}/rc_cost.XXXXXX")"      # lines: "consultant cost"

    local used=0 dir
    for dir in ${dirs[@]+"${dirs[@]}"}; do
        [[ -d "$dir" ]] || continue

        # Category -> quality axis (intelligence|taste) for this consultation.
        local cat axis
        cat=$(jq -r '.quality_metrics.category // empty' "$dir/optimization_metrics.json" 2>/dev/null)
        [[ -z "$cat" ]] && cat="GENERAL"
        axis=$(get_category_axis "$cat")

        # Peer-review quality scores (blind) -> quality accumulator.
        local peer_file
        if peer_file=$(_find_peer_file "$dir"); then
            while read -r c s; do
                [[ -z "$c" || "$c" == "unknown" ]] && continue
                echo "$c $axis $s" >> "$qacc"
            done < <(jq -r '.[] | "\(.consultant) \(.average_peer_score)"' "$peer_file" 2>/dev/null)
            used=$((used+1))
        fi

        # Observed cost per response -> cost accumulator.
        local f
        for f in "$dir"/*.json; do
            [[ -f "$f" && -s "$f" ]] || continue
            local c model tokens
            c=$(jq -r '.consultant // empty' "$f" 2>/dev/null)
            [[ -z "$c" ]] && continue
            model=$(jq -r '.model // "unknown"' "$f" 2>/dev/null)
            tokens=$(jq -r '.metadata.tokens_used // empty' "$f" 2>/dev/null)
            [[ -z "$tokens" || ! "$tokens" =~ ^[0-9]+$ ]] && continue
            echo "$c $(_response_cost "$model" "$tokens")" >> "$cacc"
        done
    done

    if [[ $used -eq 0 ]]; then
        # No peer-review data -> intelligence/taste can't be measured. But cost
        # (from tokens_used) still can, so only abort when there is no cost data
        # either; otherwise fall through and emit the cost axis alone.
        if [[ ! -s "$cacc" ]]; then
            echo "roster_calibrate: no usable data (peer-review empty AND no token metadata)" >&2
            exit 1
        fi
        echo "roster_calibrate: no peer-review data — measuring COST only (intelligence/taste need reviewer responses; check peer-review output)" >&2
    fi

    # --- Aggregate quality per (consultant, axis): mean, rounded, clamped 1-10 ---
    # Emits: "consultant intelligence <score|-> <n>  taste <score|-> <n>"
    local quality_rows
    quality_rows=$(awk '
        { key=$1 SUBSEP $2; sum[key]+=$3; n[key]++; seen[$1]=1 }
        END {
            for (c in seen) {
                ik=c SUBSEP "intelligence"; tk=c SUBSEP "taste"
                iv=(ik in sum)?int(sum[ik]/n[ik]+0.5):-1; ic=(ik in n)?n[ik]:0
                tv=(tk in sum)?int(sum[tk]/n[tk]+0.5):-1; tc=(tk in n)?n[tk]:0
                if (iv>10) iv=10; if (iv!=-1 && iv<1) iv=1
                if (tv>10) tv=10; if (tv!=-1 && tv<1) tv=1
                printf "%s %s %d %s %d\n", c, (iv==-1?"-":iv), ic, (tv==-1?"-":tv), tc
            }
        }' "$qacc" | sort)

    # --- Aggregate cost per consultant: mean, then rank-normalize (cheapest=10) ---
    # Emits: "consultant <costscore> <n>"
    local cost_rows
    cost_rows=$(awk '
        { sum[$1]+=$2; n[$1]++ }
        END { for (c in sum) printf "%s %.10f %d\n", c, sum[c]/n[c], n[c] }
    ' "$cacc" | sort -k2,2g | awk '
        { c[NR]=$1; mean[NR]=$2; cnt[NR]=$3 }
        END {
            N=NR
            for (r=1; r<=N; r++) {
                if (N==1) score=5
                else score=int(1 + 9*(N-r)/(N-1) + 0.5)   # rank 1 (cheapest) -> 10
                print c[r], score, cnt[r]
            }
        }' | sort)

    # --- Assemble measured_capabilities + samples JSON ---
    local caps='{}' samples='{}' c iv ic tv tc
    while read -r c iv ic tv tc; do
        [[ -z "$c" ]] && continue
        caps=$(jq -c --arg c "$c" \
            --argjson iv "$([[ "$iv" == "-" ]] && echo null || echo "$iv")" \
            --argjson tv "$([[ "$tv" == "-" ]] && echo null || echo "$tv")" \
            '.[$c] = ((.[$c] // {}) + (if $iv==null then {} else {intelligence:$iv} end)
                                   + (if $tv==null then {} else {taste:$tv} end))' <<<"$caps")
        samples=$(jq -c --arg c "$c" --argjson ic "$ic" --argjson tc "$tc" \
            '.[$c] = ((.[$c] // {}) + {intelligence_n:$ic, taste_n:$tc})' <<<"$samples")
    done <<< "$quality_rows"

    while read -r c score cnt; do
        [[ -z "$c" ]] && continue
        caps=$(jq -c --arg c "$c" --argjson v "$score" '.[$c] = ((.[$c] // {}) + {cost:$v})' <<<"$caps")
        samples=$(jq -c --arg c "$c" --argjson n "$cnt" '.[$c] = ((.[$c] // {}) + {cost_n:$n})' <<<"$samples")
    done <<< "$cost_rows"

    local result
    result=$(jq -n --argjson caps "$caps" --argjson samples "$samples" \
        '{measured_capabilities:$caps, samples:$samples}')

    if [[ "$do_write" -eq 1 ]]; then
        cp "$AFFINITY_JSON" "${AFFINITY_JSON}.bak"
        jq --argjson m "$caps" '.capabilities = ((.capabilities // {}) * $m)' "$AFFINITY_JSON" \
            > "${AFFINITY_JSON}.tmp" && mv "${AFFINITY_JSON}.tmp" "$AFFINITY_JSON"
        echo "Merged measured capabilities into $AFFINITY_JSON (backup: ${AFFINITY_JSON}.bak)"
        echo "Measured $(echo "$caps" | jq 'length') consultant(s) from $used consultation(s)."
    elif [[ "$as_json" -eq 1 ]]; then
        echo "$result"
    else
        echo "Measured capabilities from $used consultation(s) with peer-review data:"
        echo "(intelligence/taste = mean blind peer score on that axis's categories; cost = rank, cheapest=10)"
        echo
        echo "$result" | jq -r '
            .measured_capabilities as $c | .samples as $s
            | ($c | keys[]) as $k
            | "  \($k): intelligence=\($c[$k].intelligence // "n/a") taste=\($c[$k].taste // "n/a") cost=\($c[$k].cost // "n/a")"
              + "   (n: int=\($s[$k].intelligence_n // 0) taste=\($s[$k].taste_n // 0) cost=\($s[$k].cost_n // 0))"'
        echo
        echo "Apply with --write (merges into affinity.json, keeping unmeasured cells), or --json for raw."
    fi
}

main "$@"
