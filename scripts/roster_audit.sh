#!/usr/bin/env bash
# roster_audit.sh — "uncorrelated value" audit for the consultant roster.
#
# A consultant earns its seat only if it contributes signal the others DON'T —
# a distinct approach, not an echo of the panel. This is the diversity-not-
# redundancy bar from the model-routing "before a new model earns a row" test
# (catch >=1 thing both incumbents miss), applied to a consultation panel
# instead of a review lane.
#
# For each past consultation, a consultant's approach is DISTINCT if its keyword
# set has low Jaccard overlap (< threshold) with EVERY other consultant that
# round. Aggregated across consultations, a consultant that is rarely distinct
# is correlated with the rest — a candidate to drop or down-weight; one that is
# often distinct is pulling its weight on diversity.
#
# Reuses the voting.sh keyword/Jaccard machinery. Read-only; no live API calls.
#
# Usage: roster_audit.sh [--recent N] [--threshold PCT] [--json] [dir ...]
#   dir...         consultation output dirs (each holds <consultant>.json files)
#   --recent N     if no dirs given, audit the N most recent under the base (20)
#   --threshold P  Jaccard %% at/above which two approaches count as correlated (20)
#   --json         emit JSON instead of a table
#   -h, --help     show this header
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/voting.sh
source "$SCRIPT_DIR/lib/voting.sh"

MIN_SAMPLE=3        # participations below which a verdict is "insufficient-data"
acc=""              # temp accumulator file (cleaned on EXIT)
trap '[[ -n "$acc" ]] && rm -f "$acc"' EXIT

# Verdict from participation count + distinctiveness percentage.
# Usage: _verdict <participated> <pct>
_verdict() {
    local p="$1" pct="$2"
    if [[ "$p" -lt "$MIN_SAMPLE" ]]; then echo "insufficient-data"; return; fi
    if [[ "$pct" -ge 50 ]]; then echo "unique-value"
    elif [[ "$pct" -ge 20 ]]; then echo "some-value"
    else echo "redundant?"; fi
}

_render_table() { # <audited> <threshold> <rows>
    local audited="$1" threshold="$2" rows="$3" redundant="" c p d pct v
    printf 'Roster uncorrelated-value audit  (%d consultations, correlated >= %d%%)\n\n' "$audited" "$threshold"
    printf '%-12s  %12s  %8s  %9s  %s\n' CONSULTANT PARTICIPATED DISTINCT "DISTINCT%" VERDICT
    while read -r c p d pct; do
        [[ -z "$c" ]] && continue
        v=$(_verdict "$p" "$pct")
        printf '%-12s  %12d  %8d  %8d%%  %s\n' "$c" "$p" "$d" "$pct" "$v"
        [[ "$v" == "redundant?" ]] && redundant="${redundant:+$redundant, }$c"
    done <<< "$rows"
    echo
    if [[ -n "$redundant" ]]; then
        printf 'Possibly redundant (>=%d samples, <20%% distinct): %s\n' "$MIN_SAMPLE" "$redundant"
        echo '  -> consider dropping or down-weighting these in references/affinity.json.'
    else
        echo 'No consultant flagged redundant on this sample.'
    fi
}

_render_json() { # <audited> <threshold> <rows>
    local audited="$1" threshold="$2" rows="$3" items="[]" c p d pct v
    while read -r c p d pct; do
        [[ -z "$c" ]] && continue
        v=$(_verdict "$p" "$pct")
        items=$(jq -c --arg c "$c" --argjson p "$p" --argjson d "$d" --argjson pct "$pct" --arg v "$v" \
            '. + [{consultant:$c, participated:$p, distinct:$d, distinct_pct:$pct, verdict:$v}]' <<<"$items")
    done <<< "$rows"
    jq -n --argjson audited "$audited" --argjson threshold "$threshold" --argjson roster "$items" \
        '{consultations_audited:$audited, correlated_threshold_pct:$threshold, roster:$roster}'
}

main() {
    local recent=20 threshold=20 as_json=0
    local dirs=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --recent)    recent="${2:-20}"; shift 2 ;;
            --threshold) threshold="${2:-20}"; shift 2 ;;
            --json)      as_json=1; shift ;;
            -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
            -*)          echo "unknown option: $1" >&2; exit 2 ;;
            *)           dirs+=("$1"); shift ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "roster_audit: jq is required" >&2; exit 2; }

    # No dirs given -> the N most recent consultation dirs under the base.
    if [[ ${#dirs[@]} -eq 0 ]]; then
        # shellcheck source=config.sh
        source "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || true
        local base="${DEFAULT_OUTPUT_DIR_BASE:-/tmp/ai_consultations}"
        if [[ ! -d "$base" ]]; then
            echo "roster_audit: no dirs given and base '$base' not found" >&2
            exit 1
        fi
        while IFS= read -r d; do dirs+=("$d"); done < <(
            find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n "$recent"
        )
    fi

    acc="$(mktemp "${TMPDIR:-/tmp}/roster_audit.XXXXXX")"

    local audited=0 dir f
    for dir in ${dirs[@]+"${dirs[@]}"}; do
        [[ -d "$dir" ]] || continue
        local names=() kw=()
        for f in "$dir"/*.json; do
            [[ -f "$f" && -s "$f" ]] || continue
            local c a al
            c=$(jq -r '.consultant // empty' "$f" 2>/dev/null)
            [[ -z "$c" ]] && continue                       # not a consultant response file
            a=$(jq -r '.response.approach? // "unknown"' "$f" 2>/dev/null)
            al=$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')
            case "$al" in unknown|""|n/a|none|"not available") continue ;; esac
            names+=("$c"); kw+=("$(_extract_keywords "$a")")
        done
        local n=${#names[@]}
        [[ $n -lt 2 ]] && continue                          # need >=2 to assess correlation
        audited=$((audited+1))
        local i j
        for ((i=0; i<n; i++)); do
            local maxsim=0 s
            for ((j=0; j<n; j++)); do
                [[ $i -eq $j ]] && continue
                s=$(_jaccard_similarity "${kw[$i]}" "${kw[$j]}")
                [[ $s -gt $maxsim ]] && maxsim=$s
            done
            local distinct=0
            [[ $maxsim -lt $threshold ]] && distinct=1
            printf '%s %d\n' "${names[$i]}" "$distinct" >> "$acc"
        done
    done

    if [[ $audited -eq 0 ]]; then
        echo "roster_audit: no consultations with >=2 responders found (nothing to audit)" >&2
        exit 1
    fi

    # Aggregate: "consultant participated distinct pct", sorted by pct then distinct desc.
    local rows
    rows=$(awk '
        { part[$1]++; dist[$1]+=$2 }
        END { for (c in part){ p=part[c]; d=dist[c]; pct=(p>0)?int(d*100/p):0; printf "%s %d %d %d\n", c, p, d, pct } }
    ' "$acc" | sort -k4,4nr -k3,3nr)

    if [[ "$as_json" -eq 1 ]]; then
        _render_json "$audited" "$threshold" "$rows"
    else
        _render_table "$audited" "$threshold" "$rows"
    fi
}

main "$@"
