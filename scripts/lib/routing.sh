#!/bin/bash
# routing.sh - Smart consultant selection based on question type
#
# Selects the most suitable consultants based on the question category.

# =============================================================================
# AFFINITY MATRIX
# =============================================================================
# The affinity matrix is loaded from references/affinity.json at first use
# and cached for the life of the shell. To override at runtime, set:
#   AFFINITY_FILE=/path/to/custom.json
# Affinity scores: 10 = perfect match, 1 = poor match.
# Prior to v2.11.0 this lived as nested case statements in this file; see
# docs/SMART_ROUTING.md for the schema and customization guide.

_ROUTING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Single source of truth for user-config dir resolution: lib/user_config.sh.
# Sourced defensively here so routing.sh works when imported standalone
# (e.g. test_routing_parity.sh). Sourcing only defines functions — no side
# effect — so repeat sources are harmless.
if ! declare -f get_user_config_dir >/dev/null 2>&1; then
    # shellcheck source=user_config.sh
    source "$_ROUTING_LIB_DIR/user_config.sh"
fi

_AFFINITY_LOADED_FILE=""
_AFFINITY_DATA=""
# Per-key result cache: each entry is " CATEGORY|CONSULTANT=score" (leading
# space delimiter). The cache string is initialized to a single space so that
# the first key is bracketed by spaces too, preventing prefix collisions
# (e.g. lookup of "DEBUG|Codex=" against cached "BUG_DEBUG|Codex=10" — the
# space in front of every key kills the false-positive substring match).
# Bash 3.2 has no associative arrays, so this string-based scheme is the
# portable workaround. At ~135 entries x ~25 chars = ~3KB, memory is a
# non-issue.
_AFFINITY_RESULT_CACHE=" "
# Parallel per-key cache for capability lookups: " CONSULTANT|AXIS=score".
# Same leading-space bracketing trick as _AFFINITY_RESULT_CACHE to avoid
# substring collisions. Reset alongside it when the affinity file changes.
_CAPABILITY_RESULT_CACHE=" "

# Resolve the affinity file path using the same search precedence as user
# config (v2.12+): explicit AFFINITY_FILE > user config dir > bundled default.
_resolve_affinity_path() {
    if [[ -n "${AFFINITY_FILE:-}" ]]; then
        echo "$AFFINITY_FILE"
        return 0
    fi
    local user_dir
    user_dir=$(get_user_config_dir)
    if [[ -n "$user_dir" && -f "$user_dir/affinity.json" ]]; then
        echo "$user_dir/affinity.json"
        return 0
    fi
    echo "$_ROUTING_LIB_DIR/../../references/affinity.json"
}

# Load (and cache) the affinity JSON. Resets the result cache if the resolved
# path changes (e.g. AFFINITY_FILE was set, or a file was added in the user
# config dir).
_load_affinity_data() {
    local file
    file=$(_resolve_affinity_path)
    if [[ "$_AFFINITY_LOADED_FILE" != "$file" ]]; then
        if [[ -r "$file" ]]; then
            _AFFINITY_DATA=$(cat "$file")
        else
            _AFFINITY_DATA=""
        fi
        _AFFINITY_LOADED_FILE="$file"
        _AFFINITY_RESULT_CACHE=" "
        _CAPABILITY_RESULT_CACHE=" "
    fi
}

# =============================================================================
# SELECTION FUNCTIONS
# =============================================================================

# Get affinity for a category-consultant combination
# Usage: get_affinity <category> <consultant>
# First call per (category, consultant) invokes jq; subsequent calls hit the
# in-memory cache. ~14 calls per consultation, so ~13 cached after warm-up.
get_affinity() {
    local category="$1"
    local consultant="$2"

    _load_affinity_data

    # Fast path: cache hit (key is bracketed by leading/trailing space to
    # prevent substring collisions — see _AFFINITY_RESULT_CACHE comment).
    local key=" ${category}|${consultant}="
    case "$_AFFINITY_RESULT_CACHE" in
        *"${key}"*)
            local cached="${_AFFINITY_RESULT_CACHE#*"${key}"}"
            echo "${cached%% *}"
            return 0
            ;;
    esac

    # If JSON missing or jq unavailable, fall back to a safe default.
    if [[ -z "$_AFFINITY_DATA" ]] || ! command -v jq >/dev/null 2>&1; then
        echo "${AFFINITY_DEFAULT:-5}"
        return 0
    fi

    local score
    score=$(jq -r --arg cat "$category" --arg c "$consultant" '
        if (.known_consultants | index($c)) == null then
            .default_score
        elif (.categories[$cat] // null) == null then
            .general_score
        else
            (.categories[$cat][$c] // .default_score)
        end
    ' <<<"$_AFFINITY_DATA" 2>/dev/null)

    [[ -z "$score" || "$score" == "null" ]] && score="${AFFINITY_DEFAULT:-5}"
    _AFFINITY_RESULT_CACHE+="${key#" "}${score} "  # strip leading space (already in cache)
    echo "$score"
}

# Get a consultant's capability score on a quality/efficiency axis.
# Usage: get_capability <consultant> <axis>   (axis: intelligence|taste|cost)
# Scores are 1-10 (higher = better). A missing consultant/axis, missing
# 'capabilities' block, or missing jq falls back to capability_default (5).
# Cached per (consultant, axis), mirroring get_affinity.
get_capability() {
    local consultant="$1"
    local axis="$2"

    _load_affinity_data

    local key=" ${consultant}|${axis}="
    case "$_CAPABILITY_RESULT_CACHE" in
        *"${key}"*)
            local cached="${_CAPABILITY_RESULT_CACHE#*"${key}"}"
            echo "${cached%% *}"
            return 0
            ;;
    esac

    if [[ -z "$_AFFINITY_DATA" ]] || ! command -v jq >/dev/null 2>&1; then
        echo "${CAPABILITY_DEFAULT:-5}"
        return 0
    fi

    local score
    score=$(jq -r --arg c "$consultant" --arg ax "$axis" '
        (.capabilities[$c][$ax]) // (.capability_default // 5)
    ' <<<"$_AFFINITY_DATA" 2>/dev/null)

    [[ -z "$score" || "$score" == "null" ]] && score="${CAPABILITY_DEFAULT:-5}"
    _CAPABILITY_RESULT_CACHE+="${key#" "}${score} "
    echo "$score"
}

# Get the quality axis a question category stresses (intelligence|taste).
# Usage: get_category_axis <category>
# Unmapped categories (and missing JSON/jq) default to "intelligence".
get_category_axis() {
    local category="$1"

    _load_affinity_data

    if [[ -z "$_AFFINITY_DATA" ]] || ! command -v jq >/dev/null 2>&1; then
        echo "intelligence"
        return 0
    fi

    local axis
    axis=$(jq -r --arg cat "$category" '(.category_axis[$cat]) // "intelligence"' <<<"$_AFFINITY_DATA" 2>/dev/null)
    [[ -z "$axis" || "$axis" == "null" ]] && axis="intelligence"
    echo "$axis"
}

# Select the best consultants for a category
# Usage: select_consultants <category> [min_affinity] [max_consultants]
# Returns: list of consultants sorted by affinity
select_consultants() {
    local category="$1"
    local min_affinity="${2:-7}"
    local max_consultants="${3:-8}"

    # Include all consultants (order matches ALL_CONSULTANTS in config.sh)
    local consultants=("Gemini" "Codex" "Mistral" "Kilo" "Cursor" "Aider" "Amp" "Kimi" "Claude" "Qwen3" "GLM" "Grok" "DeepSeek" "MiniMax")
    local selected=()
    local scores=()

    # Collect affinities. When capability-aware routing is on, the ELIGIBILITY
    # filter still uses raw category affinity (same panel as before), but the
    # SORT rank is nudged by the consultant's capability on the axis this
    # category stresses — so under a max/limit the quality-axis reorders which
    # eligible consultants make the cut. Default (flag off): rank == affinity.
    local _cap_axis=""
    if [[ "${ENABLE_CAPABILITY_ROUTING:-false}" == "true" ]]; then
        _cap_axis=$(get_category_axis "$category")
    fi
    for c in "${consultants[@]}"; do
        local score=$(get_affinity "$category" "$c")
        if [[ $score -ge $min_affinity ]]; then
            local rank=$score
            if [[ -n "$_cap_axis" ]]; then
                local cap
                cap=$(get_capability "$c" "$_cap_axis")
                rank=$(( score + cap - ${CAPABILITY_DEFAULT:-5} ))
            fi
            selected+=("$c")
            scores+=("$rank")
        fi
    done

    # Sort by score (simple bubble sort)
    local n=${#selected[@]}
    for ((i=0; i<n-1; i++)); do
        for ((j=0; j<n-i-1; j++)); do
            if [[ ${scores[j]} -lt ${scores[j+1]} ]]; then
                # Swap (array indices are arithmetic context; no $/$(()) needed)
                local tmp="${selected[j]}"
                selected[j]="${selected[j+1]}"
                selected[j+1]="$tmp"

                tmp="${scores[j]}"
                scores[j]="${scores[j+1]}"
                scores[j+1]="$tmp"
            fi
        done
    done

    # Limit to maximum requested
    local count=0
    for c in ${selected[@]+"${selected[@]}"}; do
        if [[ $count -ge $max_consultants ]]; then
            break
        fi
        echo "$c"
        count=$((count + 1))
    done
}

# Get the list of consultants as JSON
# Usage: get_selected_consultants_json <category> [min_affinity]
get_selected_consultants_json() {
    local category="$1"
    local min_affinity="${2:-7}"

    local consultants
    consultants=$(select_consultants "$category" "$min_affinity")
    local json="["
    local first=true

    while IFS= read -r c; do
        if [[ -n "$c" ]]; then
            local score
            score=$(get_affinity "$category" "$c")
            if [[ "$first" == "true" ]]; then
                first=false
            else
                json+=","
            fi
            json+="{\"consultant\":\"$c\",\"affinity\":$score}"
        fi
    done <<< "$consultants"

    json+="]"
    echo "$json"
}

# Check if a consultant is recommended for a category
# Usage: is_recommended <category> <consultant> [min_affinity]
is_recommended() {
    local category="$1"
    local consultant="$2"
    local min_affinity="${3:-7}"

    local score=$(get_affinity "$category" "$consultant")
    if [[ $score -ge $min_affinity ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# SMART ROUTING MODES
# =============================================================================

# Determine the routing mode based on the category
# Usage: get_routing_mode <category>
# Returns: full|selective|single
get_routing_mode() {
    local category="$1"

    case "$category" in
        SECURITY)
            # Security: all consultants (important)
            echo "full"
            ;;
        QUICK_SYNTAX)
            # Syntax: just one needed
            echo "single"
            ;;
        CODE_REVIEW|BUG_DEBUG|ARCHITECTURE)
            # Important: at least 3
            echo "selective"
            ;;
        *)
            # Default: all
            echo "full"
            ;;
    esac
}

# Get the recommended number of consultants
# Usage: get_recommended_count <category>
get_recommended_count() {
    local category="$1"
    local mode=$(get_routing_mode "$category")

    case "$mode" in
        full)
            echo 10  # All consultants (CLI + API)
            ;;
        selective)
            echo 5  # Subset based on affinity
            ;;
        single)
            echo 1
            ;;
        *)
            echo 10
            ;;
    esac
}

# =============================================================================
# TIMEOUT ADJUSTMENTS
# =============================================================================

# Get recommended timeout for a category
# Usage: get_category_timeout <category>
get_category_timeout() {
    local category="$1"
    case "$category" in
        QUICK_SYNTAX)  echo 60 ;;
        BUG_DEBUG)     echo 180 ;;
        ARCHITECTURE)  echo 240 ;;
        SECURITY)      echo 240 ;;
        CODE_REVIEW)   echo 180 ;;
        ALGORITHM)     echo 180 ;;
        DATABASE)      echo 120 ;;
        API_DESIGN)    echo 180 ;;
        TESTING)       echo 120 ;;
        GENERAL|*)     echo 180 ;;
    esac
}

# =============================================================================
# COST-AWARE ROUTING (v2.3)
# =============================================================================

# Ensure costs.sh is sourced (lazy loading helper)
_ensure_costs_sourced() {
    if ! type get_economic_model &>/dev/null; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        source "$script_dir/costs.sh" 2>/dev/null || true
    fi
}

# Select consultants based on cost efficiency
# Usage: select_consultants_cost_aware <category> <complexity> [min_affinity]
# Returns: list of consultants optimized for cost/quality balance
select_consultants_cost_aware() {
    local category="$1"
    local complexity="${2:-5}"
    local min_affinity="${3:-7}"

    # Check if cost-aware routing is enabled
    if [[ "${ENABLE_COST_AWARE_ROUTING:-false}" != "true" ]]; then
        # Fall back to standard selection
        select_consultants "$category" "$min_affinity"
        return
    fi

    _ensure_costs_sourced

    local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"
    local medium_threshold="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

    # Simple queries: only economic models, fewer consultants
    if [[ $complexity -le $simple_threshold ]]; then
        # For simple queries, use only 2 consultants with economic models
        select_consultants "$category" "$min_affinity" 2
        return
    fi

    # Medium complexity: balanced selection
    if [[ $complexity -le $medium_threshold ]]; then
        # Use standard selection but limit to 3-4 consultants
        select_consultants "$category" "$min_affinity" 4
        return
    fi

    # Complex queries: full selection
    select_consultants "$category" "$min_affinity"
}

# Get model override for cost-aware routing
# Usage: get_cost_aware_model <consultant> <complexity>
# Returns: model name to use, or empty for default
get_cost_aware_model() {
    local consultant="$1"
    local complexity="${2:-5}"

    # Check if cost-aware routing is enabled
    if [[ "${ENABLE_COST_AWARE_ROUTING:-false}" != "true" ]]; then
        echo ""
        return
    fi

    # Check if we should use economic models for simple queries
    if [[ "${USE_ECONOMIC_MODELS_FOR_SIMPLE:-true}" != "true" ]]; then
        echo ""
        return
    fi

    local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"

    # Simple queries: use economic model
    if [[ $complexity -le $simple_threshold ]]; then
        _ensure_costs_sourced
        local economic_model
        economic_model=$(get_economic_model "$consultant" 2>/dev/null || echo "")
        echo "$economic_model"
        return
    fi

    # Complex queries: use default model
    echo ""
}

# Check if cost-aware routing is enabled
# Usage: is_cost_aware_routing_enabled
is_cost_aware_routing_enabled() {
    [[ "${ENABLE_COST_AWARE_ROUTING:-false}" == "true" ]]
}

# Get routing summary for logging
# Usage: get_routing_summary <category> <complexity> <num_consultants>
get_routing_summary() {
    local category="$1"
    local complexity="${2:-5}"
    local num_consultants="${3:-5}"

    local mode="standard"
    if is_cost_aware_routing_enabled; then
        local simple_threshold="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"
        local medium_threshold="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

        if [[ $complexity -le $simple_threshold ]]; then
            mode="economic"
        elif [[ $complexity -le $medium_threshold ]]; then
            mode="balanced"
        else
            mode="comprehensive"
        fi
    fi

    echo "{\"category\":\"$category\",\"complexity\":$complexity,\"mode\":\"$mode\",\"consultants\":$num_consultants}"
}

# =============================================================================
# FALLBACK ESCALATION (v2.3 Quality Review)
# =============================================================================

# Fallback escalation threshold - escalate to premium if confidence below this
FALLBACK_CONFIDENCE_THRESHOLD="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

# Check if response needs escalation based on confidence
# Usage: needs_escalation <response_file>
# Returns: 0 if escalation needed, 1 otherwise
needs_escalation() {
    local response_file="$1"

    if [[ ! -f "$response_file" || ! -s "$response_file" ]]; then
        return 0  # No response = needs escalation
    fi

    local confidence
    confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)

    if [[ ! "$confidence" =~ ^[0-9]+$ ]]; then
        confidence=5
    fi

    local threshold="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

    if [[ $confidence -lt $threshold ]]; then
        return 0  # Needs escalation
    fi

    return 1  # No escalation needed
}

# Get premium model for escalation
# Delegates to get_model_for_tier() in config.sh (single source of truth)
# Usage: get_premium_model <consultant>
get_premium_model() {
    local consultant="$1"
    if type get_model_for_tier &>/dev/null; then
        get_model_for_tier "$consultant" "premium"
    else
        echo ""
    fi
}

# Check if escalation is enabled
# Usage: is_escalation_enabled
is_escalation_enabled() {
    # Escalation is enabled when cost-aware routing is on
    [[ "${ENABLE_COST_AWARE_ROUTING:-false}" == "true" ]]
}

# Get escalation summary for a response
# Usage: get_escalation_summary <response_file> <consultant>
get_escalation_summary() {
    local response_file="$1"
    local consultant="$2"

    local needs_it="false"
    local confidence=0
    local threshold="${FALLBACK_CONFIDENCE_THRESHOLD:-7}"

    if [[ -f "$response_file" && -s "$response_file" ]]; then
        confidence=$(jq -r '.confidence.score // 5' "$response_file" 2>/dev/null)
        [[ ! "$confidence" =~ ^[0-9]+$ ]] && confidence=5
    fi

    if [[ $confidence -lt $threshold ]]; then
        needs_it="true"
    fi

    local premium_model
    premium_model=$(get_premium_model "$consultant")

    cat << EOF
{
  "consultant": "$consultant",
  "confidence": $confidence,
  "threshold": $threshold,
  "needs_escalation": $needs_it,
  "premium_model": "$premium_model"
}
EOF
}
