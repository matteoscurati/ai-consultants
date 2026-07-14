#!/bin/bash
# stance.sh - Stance-based semantic consensus (v2.21, opt-in via
# ENABLE_STANCE_CONSENSUS).
#
# The lexical consensus signal (Jaccard cluster over free-text `approach`) can't
# tell that "Commit the lockfile" and "Always keep package-lock in git" AGREE --
# independently-phrased short answers share little vocabulary. This module makes
# agreement exact-matchable: one LLM call enumerates a small set of mutually-
# exclusive stance options for the question, each consultant picks ONE verbatim
# (via a prompt addendum), and consensus becomes the plurality-stance fraction.
#
# Requires common.sh (resolve_synthesis_cli, build_synthesis_args,
# strip_json_fence) sourced first. Every path degrades gracefully to "[]"/no
# addendum so the caller falls back to the cluster consensus.

# generate_stance_options <query> -- echoes a JSON array of 2..STANCE_MAX_OPTIONS
# short stance strings, or "[]" when generation is unavailable or unparseable.
generate_stance_options() {
    local query="$1"
    local cli
    cli=$(resolve_synthesis_cli 2>/dev/null || echo "")
    [[ -z "$cli" ]] && { echo "[]"; return 0; }

    local prompt
    prompt="Enumerate the distinct bottom-line POSITIONS a code reviewer could take on the question below. Output ONLY a compact JSON array of 2 to ${STANCE_MAX_OPTIONS:-5} SHORT (<=6 words each), mutually-exclusive, canonical stance strings covering the realistic answers. No prose, no markdown, no object keys -- just the array.
Example: [\"Commit the lockfile\",\"Do not commit it\",\"Depends on project type\"]

Question: ${query}"

    build_synthesis_args "$cli" "$prompt" 2>/dev/null || { echo "[]"; return 0; }
    local raw
    # run_with_timeout is mandatory here: this is a serial pre-panel step at
    # startup, so a synthesizer that BLOCKS (installed-but-unauthenticated CLI
    # dropping into an OAuth/interactive prompt) would wedge the whole run before
    # any consultant is queried. `|| true` keeps a non-zero/timeout exit from
    # aborting under `set -e` -- the empty raw then degrades to "[]" below.
    raw=$(echo "$prompt" | run_with_timeout "${STANCE_TIMEOUT:-60}" "${SYNTHESIS_ARGS[@]}" 2>/dev/null || true)
    raw=$(strip_json_fence "$raw" 2>/dev/null || printf '%s' "$raw")

    # Prefer a clean parse; if the model wrapped the array in prose, salvage the
    # first [...] substring and re-parse.
    local arr
    arr=$(_stance_clean "$raw")
    if [[ "$arr" == "[]" ]]; then
        local sub
        sub=$(printf '%s' "$raw" | grep -oE '\[[^][]*\]' | head -1)
        [[ -n "$sub" ]] && arr=$(_stance_clean "$sub")
    fi
    printf '%s' "$arr"
}

# _stance_clean <text> -- echoes a JSON array of >=2 non-empty strings, else "[]".
_stance_clean() {
    printf '%s' "$1" | jq -c '
        (if type=="array" then map(select(type=="string" and (.|length)>0)) else [] end)
        | if length>=2 then . else [] end
    ' 2>/dev/null || printf '[]'
}

# build_stance_prompt <options_json> -- echoes the prompt addendum instructing a
# consultant to pick one option verbatim. Returns 1 (no output) for <2 options.
build_stance_prompt() {
    local options_json="$1"
    local n
    n=$(printf '%s' "$options_json" | jq 'length' 2>/dev/null || echo 0)
    [[ "$n" -ge 2 ]] || return 1
    local list
    list=$(printf '%s' "$options_json" | jq -r '.[] | "- " + .' 2>/dev/null)
    printf 'STANCE (required): inside your JSON "response" object add a field "stance" set to EXACTLY ONE of the following options, copied VERBATIM -- pick the one closest to your bottom-line recommendation, do NOT invent a new one:\n%s' "$list"
}
