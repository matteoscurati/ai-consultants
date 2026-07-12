#!/usr/bin/env bash
# taste_elo.sh — Tier-B taste calibration via pairwise LLM-as-judge Elo.
#
# Taste has no ground truth, so it is measured RELATIVE to a chosen judge. On
# taste-axis consultations (API_DESIGN / ARCHITECTURE / CODE_REVIEW / GENERAL),
# every pair of consultant answers is shown to a judge that picks the better one
# on DESIGN TASTE only (clarity, API shape, structure, naming) — not correctness.
# Pairwise wins feed an Elo ranking, normalized to 1-10. Removes the panel's
# self-scoring bias that Tier-A peer review carries.
#
# The judge is pluggable:
#   TASTE_JUDGE_CMD=/path/to/cmd   external judge: called as `cmd <ctx> <A.json>
#                                  <B.json>`, must print "A" or "B" (used by tests)
#   else the built-in judge asks JUDGE_CLI (default: claude) `-p` with a taste-only
#   prompt and parses A/B from the reply.
#
# Read-only unless --write. Usage:
#   taste_elo.sh [--recent N] [--json] [--write] [dir ...]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"     # get_category_axis
AFFINITY_JSON="$SCRIPT_DIR/../references/affinity.json"

ELO_K=32
ELO_START=1500

# Elo ratings held in parallel indexed arrays (bash 3.2: no associative arrays).
_names=(); _rats=()
_idx() { local i; for i in "${!_names[@]}"; do [[ "${_names[$i]}" == "$1" ]] && { echo "$i"; return; }; done; echo -1; }
_get() { local i; i=$(_idx "$1"); [[ "$i" -ge 0 ]] && echo "${_rats[$i]}" || echo "$ELO_START"; }
_set() { local i; i=$(_idx "$1"); if [[ "$i" -ge 0 ]]; then _rats[$i]="$2"; else _names+=("$1"); _rats+=("$2"); fi; }

# Apply one Elo result: <winner> <loser>.
_update() {
    local w="$1" l="$2" rw rl nw nl
    rw=$(_get "$w"); rl=$(_get "$l")
    read -r nw nl < <(awk -v rw="$rw" -v rl="$rl" -v k="$ELO_K" 'BEGIN{
        ew = 1/(1 + 10^((rl-rw)/400));
        el = 1/(1 + 10^((rw-rl)/400));
        printf "%d %d", rw + k*(1-ew) + 0.5, rl + k*(0-el) + 0.5
    }')
    _set "$w" "$nw"; _set "$l" "$nl"
}

# Judge which of two answers has better design taste -> "A" or "B".
_judge() { # <context> <fileA> <fileB>
    if [[ -n "${TASTE_JUDGE_CMD:-}" ]]; then
        "$TASTE_JUDGE_CMD" "$1" "$2" "$3" 2>/dev/null | tr -d '[:space:]' | grep -oE '[AB]' | head -1
        return
    fi
    local a b prompt
    a=$(jq -r '.response.summary // .response.detailed // ""' "$2" 2>/dev/null)
    b=$(jq -r '.response.summary // .response.detailed // ""' "$3" 2>/dev/null)
    prompt="Context: $1

Two answers (A and B). Judge ONLY design taste — clarity, API shape, structure, naming, elegance — NOT correctness. Reply with exactly one character: A or B.

--- A ---
$a

--- B ---
$b"
    printf '%s' "$prompt" | "${JUDGE_CLI:-claude}" -p 2>/dev/null | tr -d '[:space:]' | grep -oE '[AB]' | head -1
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

    command -v jq >/dev/null 2>&1 || { echo "taste_elo: jq is required" >&2; exit 2; }

    if [[ ${#dirs[@]} -eq 0 ]]; then
        # shellcheck source=config.sh
        source "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || true
        local base="${DEFAULT_OUTPUT_DIR_BASE:-/tmp/ai_consultations}"
        [[ -d "$base" ]] || { echo "taste_elo: no dirs given and base '$base' not found" >&2; exit 1; }
        while IFS= read -r d; do dirs+=("$d"); done < <(
            find "$base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -n "$recent"
        )
    fi

    local pairs=0 dir
    for dir in ${dirs[@]+"${dirs[@]}"}; do
        [[ -d "$dir" ]] || continue
        # taste-axis consultations only
        local cat axis
        cat=$(jq -r '.quality_metrics.category // empty' "$dir/optimization_metrics.json" 2>/dev/null)
        [[ -z "$cat" ]] && cat="GENERAL"
        axis=$(get_category_axis "$cat")
        [[ "$axis" != "taste" ]] && continue

        # Collect responder files (those with a consultant).
        local files=() f c
        for f in "$dir"/*.json; do
            [[ -f "$f" && -s "$f" ]] || continue
            c=$(jq -r '.consultant // empty' "$f" 2>/dev/null)
            [[ -z "$c" ]] && continue
            files+=("$f")
        done
        local n=${#files[@]}
        [[ $n -lt 2 ]] && continue

        local a b ca cb w
        for ((a=0; a<n; a++)); do
            for ((b=a+1; b<n; b++)); do
                ca=$(jq -r '.consultant' "${files[$a]}" 2>/dev/null)
                cb=$(jq -r '.consultant' "${files[$b]}" 2>/dev/null)
                w=$(_judge "$cat" "${files[$a]}" "${files[$b]}")
                [[ -z "$w" ]] && continue     # judge gave no verdict -> skip pair
                if [[ "$w" == "A" ]]; then _update "$ca" "$cb"; else _update "$cb" "$ca"; fi
                pairs=$((pairs+1))
            done
        done
    done

    if [[ $pairs -eq 0 ]]; then
        echo "taste_elo: no taste-axis consultations with >=2 responders found (nothing to rank)" >&2
        exit 1
    fi

    # Elo -> 1-10 via linear min-max (highest Elo = 10).
    local minr=999999 maxr=-999999 i r
    for i in "${!_names[@]}"; do
        r=${_rats[$i]}
        [[ $r -lt $minr ]] && minr=$r
        [[ $r -gt $maxr ]] && maxr=$r
    done

    local elo='{}' scores='{}' name score
    for i in "${!_names[@]}"; do
        name="${_names[$i]}"; r=${_rats[$i]}
        if [[ $maxr -eq $minr ]]; then score=5
        else score=$(awk -v r="$r" -v lo="$minr" -v hi="$maxr" 'BEGIN{ printf "%d", 1 + 9*(r-lo)/(hi-lo) + 0.5 }'); fi
        elo=$(jq -c --arg n "$name" --argjson v "$r" '.[$n]=$v' <<<"$elo")
        scores=$(jq -c --arg n "$name" --argjson v "$score" '.[$n]=$v' <<<"$scores")
    done

    local result
    result=$(jq -n --argjson elo "$elo" --argjson scores "$scores" --argjson pairs "$pairs" \
        '{taste_elo:$elo, taste_scores:$scores, pairs_judged:$pairs}')

    if [[ "$do_write" -eq 1 ]]; then
        cp "$AFFINITY_JSON" "${AFFINITY_JSON}.bak"
        jq --argjson s "$scores" '
            reduce ($s|to_entries[]) as $e (.; .capabilities[$e.key].taste = $e.value)
        ' "$AFFINITY_JSON" > "${AFFINITY_JSON}.tmp" && mv "${AFFINITY_JSON}.tmp" "$AFFINITY_JSON"
        echo "Wrote taste scores for $(echo "$scores" | jq 'length') consultant(s) into $AFFINITY_JSON (backup: ${AFFINITY_JSON}.bak)"
    elif [[ "$as_json" -eq 1 ]]; then
        echo "$result"
    else
        echo "Taste Elo from $pairs pairwise judgments (higher = better design taste):"
        echo "$result" | jq -r '.taste_elo as $e | .taste_scores as $s | ($e|keys[])
            | "  \(.): elo=\($e[.])  taste=\($s[.])"' | sort -t= -k2 -rn
        echo
        echo "Apply with --write (updates taste cells in affinity.json), or --json for raw."
    fi
}

main "$@"
