#!/bin/bash
# orchestration.sh - Dynamic orchestration planner + shape executors (v2.16.0)
#
# Turns the fixed classify -> query -> debate(N fixed rounds) -> synth pipeline
# into an adaptive one. A planner picks an orchestration SHAPE from the
# question's category / complexity / intent, and debate becomes a CONVERGENCE
# LOOP: rounds run until the panel's answers converge (consensus target reached)
# or a guard fires (max rounds, stall, budget) -- not a hardcoded round count.
#
# Standalone bash. Reuses debate_round.sh, lib/voting.sh, peer_review.sh, and
# the synthesis CLI helpers in lib/common.sh -- no new model-invocation plumbing.
#
# Sourced by consult_all.sh AFTER common.sh/costs.sh/voting.sh, so their
# functions and the orchestration globals (SCRIPT_DIR, SUCCESS_COUNT,
# CURRENT_COST, CONTEXT_SIZE) are visible. Every public function is safe to call
# under `set -euo pipefail`.
#
# Public functions:
#   detect_intent <query>                                  advise|compare|exhaustive
#   select_orchestration_shape <cat> <complexity> <intent> quick|converge|adversarial|tournament|exhaustive|fixed
#   run_orchestration <shape> <responses_dir> <category>   executes the shape
#
# Pure decision helpers (unit-tested):
#   _convergence_should_stop <score> <prev> <target> <epsilon>
#   _approach_signature <responses_dir>

# =============================================================================
# INTENT DETECTION (heuristic, zero-dependency)
# =============================================================================

# Classify the *shape of work* the question implies, orthogonal to its topic
# category. Case-insensitive regexes over the raw query.
# Usage: detect_intent "<query>"
detect_intent() {
    local q="$1"

    # "compare / choose between approaches" -> tournament territory
    if printf '%s' "$q" | grep -qiE '(\bvs\.?\b|versus|compare|which (one|approach|option|is better)|better\?|or should i|trade-?offs? between|meglio[: ]|quale (approccio|opzione|soluzione))'; then
        echo "compare"
        return 0
    fi

    # "find/enumerate everything" -> exhaustive territory
    if printf '%s' "$q" | grep -qiE '(find all|list all|enumerate|every (bug|issue|case|problem)|all the (bugs|issues|edge cases)|exhaustive|audit (the|this|all)|trova tutti|elenca tutti|tutti i (bug|problemi|casi))'; then
        echo "exhaustive"
        return 0
    fi

    echo "advise"
}

# =============================================================================
# SHAPE SELECTION (planner)
# =============================================================================

# Decide the orchestration shape. Honors an explicit ORCHESTRATION_MODE override
# (a concrete shape or "fixed"); otherwise (auto) derives it from intent first
# (strongest signal), then category, then complexity.
# Usage: select_orchestration_shape <category> <complexity_1_10> <intent>
select_orchestration_shape() {
    local category="$1"
    local complexity="${2:-5}"
    local intent="${3:-advise}"

    case "${ORCHESTRATION_MODE:-auto}" in
        quick|converge|adversarial|tournament|exhaustive)
            echo "$ORCHESTRATION_MODE"
            return 0
            ;;
        fixed)
            echo "fixed"
            return 0
            ;;
    esac

    # auto resolution
    case "$intent" in
        exhaustive) echo "exhaustive"; return 0 ;;
        compare)    echo "tournament"; return 0 ;;
    esac

    # Mandatory-debate categories (parity with the legacy pipeline, which always
    # debated SECURITY and ARCHITECTURE). SECURITY gets the full adversarial gate;
    # ARCHITECTURE is pinned to converge (never quick) and the executor forces a
    # critique round for it (see run_orchestration), so a high-consensus
    # architecture question still gets debate -- as it did pre-2.16.
    case "$category" in
        SECURITY)     echo "adversarial"; return 0 ;;
        ARCHITECTURE) echo "converge"; return 0 ;;
    esac

    # Low-complexity questions don't need iteration.
    if [[ "${complexity:-5}" -le "${COMPLEXITY_THRESHOLD_SIMPLE:-3}" ]]; then
        echo "quick"
        return 0
    fi

    echo "converge"
}

# =============================================================================
# CONVERGENCE LOOP (the core)
# =============================================================================

# Pure stop-decision for the convergence loop. Echoes one of:
#   converged | stalled | continue
# Usage: _convergence_should_stop <score> <prev_score> <target> <epsilon>
_convergence_should_stop() {
    local score="$1" prev="$2" target="$3" epsilon="$4"

    if [[ "$score" -ge "$target" ]]; then
        echo "converged"
        return 0
    fi

    local delta=$((score - prev))
    [[ $delta -lt 0 ]] && delta=$((-delta))
    if [[ $delta -lt $epsilon ]]; then
        echo "stalled"
        return 0
    fi

    echo "continue"
}

# Record the convergence trajectory + stop reason for the report / metrics.
_write_convergence_meta() {
    local responses_dir="$1" trajectory="$2" stop_reason="$3" rounds_run="$4" shape="$5"
    jq -n \
        --argjson trajectory "$trajectory" \
        --arg stop_reason "$stop_reason" \
        --argjson rounds_run "$rounds_run" \
        --arg shape "$shape" \
        '{shape: $shape, rounds_run: $rounds_run, stop_reason: $stop_reason, consensus_trajectory: $trajectory}' \
        > "$responses_dir/orchestration.json" 2>/dev/null || true
}

# Run one debate round and merge its output back into the main responses.
# Extracted from the legacy debate loop. With promote=false the MERGE is
# identical to the legacy path (grafts only the debate critique); error handling
# is intentionally more lenient than the original (a failed debate_round.sh is
# swallowed via `|| true` instead of aborting the whole run under set -e). With
# promote=true (the dynamic loops) it ALSO adopts the round file's post-debate
# .response/.confidence -- critical, because the round file's top-level
# .response.approach is the consultant's *updated* stance, and the convergence
# stop signal (calculate_consensus_score) reads .response.approach. Without
# promotion the approaches never change across rounds, so consensus is invariant
# and the loop can never converge (it stalls after one round every time).
# Usage: _apply_debate_round <responses_dir> <round> <category> [promote]
_apply_debate_round() {
    local responses_dir="$1" round="$2" category="$3" promote="${4:-false}"
    local round_dir="$responses_dir/round_$round"

    "$SCRIPT_DIR/debate_round.sh" "$responses_dir" "$round" "$round_dir" "$category" >/dev/null 2>&1 || true

    [[ -d "$round_dir" ]] || return 0
    local f consultant
    for f in "$round_dir"/*.json; do
        [[ -f "$f" && "$f" != *"summary"* ]] || continue
        consultant=$(basename "$f" .json)
        [[ -f "$responses_dir/${consultant}.json" ]] || continue
        if [[ "$promote" == "true" ]]; then
            jq -s '.[0] * {
                response: (.[1].response // .[0].response),
                confidence: (.[1].confidence // .[0].confidence),
                debate: (.[1].debate // .[0].debate)
            }' \
                "$responses_dir/${consultant}.json" "$f" \
                > "$responses_dir/${consultant}.json.tmp" 2>/dev/null && \
                mv "$responses_dir/${consultant}.json.tmp" "$responses_dir/${consultant}.json"
        else
            jq -s '.[0] * {debate: .[1].debate}' \
                "$responses_dir/${consultant}.json" "$f" \
                > "$responses_dir/${consultant}.json.tmp" 2>/dev/null && \
                mv "$responses_dir/${consultant}.json.tmp" "$responses_dir/${consultant}.json"
        fi
    done
}

# Convergence loop: debate until consensus >= target, or a guard fires.
# min_rounds gates the early-convergence stop: the loop won't honor a converged/
# stalled signal until `round-1 >= min_rounds`, i.e. it forces (min_rounds - 1)
# debate rounds first. So min_rounds=1 may stop with NO debate when the fan-out
# already agrees (converge default); min_rounds=2 always runs >=1 critique round
# (the adversarial gate and mandatory-debate categories).
# Usage: run_convergence_loop <responses_dir> <category> <shape> [min_rounds]
run_convergence_loop() {
    local responses_dir="$1" category="$2" shape="$3"
    local min_rounds="${4:-1}"
    local max_rounds="${CONVERGENCE_MAX_ROUNDS:-4}"
    local target="${CONVERGENCE_TARGET_CONSENSUS:-75}"
    local epsilon="${CONVERGENCE_STALL_EPSILON:-5}"

    local prev_score
    prev_score=$(calculate_consensus_score "$responses_dir" 2>/dev/null || echo 0)
    [[ "$prev_score" =~ ^[0-9]+$ ]] || prev_score=0
    local trajectory="[$prev_score"
    local stop_reason="max_rounds"
    local rounds_run=1
    local round

    for ((round=2; round<=max_rounds+1; round++)); do
        # Already good enough AND we've met the minimum critique quota -> stop.
        # forced = round-1: equals min_rounds exactly when (min_rounds-1) debate
        # rounds have already run (round 2 = 0 rounds run, round 3 = 1, ...).
        local forced=$((round - 1))
        if [[ "$prev_score" -ge "$target" && $forced -ge $min_rounds ]]; then
            stop_reason="converged"
            break
        fi

        if is_budget_enabled; then
            local est
            est=$(estimate_phase_cost "debate" "${SUCCESS_COUNT:-2}" "${CONTEXT_SIZE:-0}" 2>/dev/null || echo 0)
            if ! enforce_budget "${CURRENT_COST:-0}" "$est" "convergence round $round" 2>/dev/null; then
                stop_reason="budget"
                break
            fi
        fi

        log_info "  Convergence round $round (consensus ${prev_score}/${target}, shape: ${shape})..."
        _apply_debate_round "$responses_dir" "$round" "$category" "true"
        rounds_run=$round

        local score
        score=$(calculate_consensus_score "$responses_dir" 2>/dev/null || echo "$prev_score")
        [[ "$score" =~ ^[0-9]+$ ]] || score="$prev_score"
        trajectory="$trajectory,$score"

        local decision
        decision=$(_convergence_should_stop "$score" "$prev_score" "$target" "$epsilon")
        prev_score="$score"
        # Respect the minimum critique quota before honoring a stop signal.
        if [[ "$decision" != "continue" && $((round - 1)) -ge $min_rounds ]]; then
            stop_reason="$decision"
            break
        fi
    done

    trajectory="$trajectory]"
    _write_convergence_meta "$responses_dir" "$trajectory" "$stop_reason" "$rounds_run" "$shape"
    log_info "  Convergence stopped: ${stop_reason} (final consensus ${prev_score}, ${rounds_run} round(s))"
}

# =============================================================================
# EXHAUSTIVE (loop-until-dry)
# =============================================================================

# Signature of the distinct approaches currently on the table (sorted, unique).
# Used as the loop-until-dry stop signal: when a round adds no new approach, the
# panel has stopped surfacing fresh angles.
# Usage: _approach_signature <responses_dir>
_approach_signature() {
    local responses_dir="$1"
    local f
    for f in "$responses_dir"/*.json; do
        [[ -f "$f" && "$f" != *"summary"* && "$f" != *"voting"* && "$f" != *"orchestration"* ]] || continue
        jq -r '.response.approach // empty' "$f" 2>/dev/null
    done | grep -v '^$' | sort -u | tr '\n' '|'
}

# Loop until a round surfaces no new distinct approach (or guards fire). Unlike
# converge, the stop signal is approach novelty, not consensus -- the goal is
# breadth of coverage, not agreement.
# Usage: run_exhaustive_loop <responses_dir> <category> <shape>
run_exhaustive_loop() {
    local responses_dir="$1" category="$2" shape="$3"
    local max_rounds="${CONVERGENCE_MAX_ROUNDS:-4}"

    local prev_sig
    prev_sig=$(_approach_signature "$responses_dir")
    local stop_reason="max_rounds"
    local rounds_run=1
    local round

    for ((round=2; round<=max_rounds+1; round++)); do
        if is_budget_enabled; then
            local est
            est=$(estimate_phase_cost "debate" "${SUCCESS_COUNT:-2}" "${CONTEXT_SIZE:-0}" 2>/dev/null || echo 0)
            if ! enforce_budget "${CURRENT_COST:-0}" "$est" "exhaustive round $round" 2>/dev/null; then
                stop_reason="budget"
                break
            fi
        fi

        log_info "  Exhaustive round $round (seeking new angles, shape: ${shape})..."
        _apply_debate_round "$responses_dir" "$round" "$category" "true"
        rounds_run=$round

        local sig
        sig=$(_approach_signature "$responses_dir")
        if [[ "$sig" == "$prev_sig" ]]; then
            stop_reason="dry"
            break
        fi
        prev_sig="$sig"
    done

    local count
    # grep -c already prints "0" (and exits 1) when there are no matches; use
    # `|| true` to swallow that exit, NOT `|| echo 0` which would append a second
    # line and make $count "0\n0" -> invalid --argjson.
    count=$(printf '%s' "$prev_sig" | tr '|' '\n' | grep -cv '^$' || true)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    jq -n \
        --arg stop_reason "$stop_reason" \
        --argjson rounds_run "$rounds_run" \
        --argjson distinct_approaches "$count" \
        --arg shape "$shape" \
        '{shape: $shape, rounds_run: $rounds_run, stop_reason: $stop_reason, distinct_approaches: $distinct_approaches}' \
        > "$responses_dir/orchestration.json" 2>/dev/null || true
    log_info "  Exhaustive stopped: ${stop_reason} (${count} distinct approaches, ${rounds_run} round(s))"
}

# =============================================================================
# TOURNAMENT (winner selection)
# =============================================================================

# Converge first, then direct synthesis to pick a single winning approach with
# explicit pairwise reasoning. Reuses the synthesis stage rather than building a
# separate bracket engine: exports ORCHESTRATION_SELECT_WINNER=true, which
# synthesize.sh appends as a "declare one winner" directive to the prompt.
# Usage: run_tournament <responses_dir> <category> <shape>
run_tournament() {
    local responses_dir="$1" category="$2" shape="$3"
    run_convergence_loop "$responses_dir" "$category" "$shape" 1
    # Signal the synthesis stage to declare a single winner among the approaches.
    export ORCHESTRATION_SELECT_WINNER=true
}

# =============================================================================
# DISPATCHER
# =============================================================================

# Execute the chosen shape. quick = no extra rounds (single fan-out already done
# by the caller). fixed is handled by the caller's legacy path, not here.
# Usage: run_orchestration <shape> <responses_dir> <category>
run_orchestration() {
    local shape="$1" responses_dir="$2" category="$3"

    # Need at least 2 successful responses for any multi-round shape.
    if [[ "${SUCCESS_COUNT:-0}" -le 1 ]]; then
        log_info "  Orchestration: single response, skipping multi-round shape (${shape})"
        return 0
    fi

    case "$shape" in
        quick)
            log_info "  Orchestration shape: quick (single pass)"
            ;;
        converge)
            # Mandatory-debate categories must run >=1 critique round even if the
            # fan-out already agrees (legacy parity); min_rounds=2 enforces that.
            local conv_min=1
            case "$category" in SECURITY|ARCHITECTURE) conv_min=2 ;; esac
            run_convergence_loop "$responses_dir" "$category" "$shape" "$conv_min"
            ;;
        adversarial)
            # Force >=1 critique round even on early consensus, then peer review
            # acts as the refutation gate (enabled by the caller).
            run_convergence_loop "$responses_dir" "$category" "$shape" 2
            ;;
        tournament)
            run_tournament "$responses_dir" "$category" "$shape"
            ;;
        exhaustive)
            run_exhaustive_loop "$responses_dir" "$category" "$shape"
            ;;
        *)
            log_warn "  Unknown orchestration shape '${shape}', falling back to converge"
            run_convergence_loop "$responses_dir" "$category" "converge" 1
            ;;
    esac
}
