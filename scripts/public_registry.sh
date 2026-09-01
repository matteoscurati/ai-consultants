#!/bin/bash
# public_registry.sh - Side-effect-free public CLI contract registry.
#
# This file is deliberately safe to source: it does not load config.sh, user
# configuration, adapters, or providers.  Keep public mode/preset/strategy
# metadata here so CLI listings, validation, and generated docs cannot drift.

# name|aliases (space separated)|target|tier|use case
registry_preset_rows() {
    cat <<'EOF'
minimal||2|base|Quick questions
balanced||3|base|Standard coverage
thorough||3|base|Comprehensive analysis
high-stakes||4|premium|Critical decisions
security||3|base|Security reviews
cost-capped||3|economy|Budget-conscious options
max_quality|max-quality|10|maximum|Maximum coverage for critical decisions
medium||3|standard|General questions
fast||2|economy|Quick checks
EOF
}

# name|description|is_default
registry_strategy_rows() {
    cat <<'EOF'
coverage|Union of every distinct point across the panel|true
compare_only|Present each consultant side-by-side, without a synthesized union|false
majority|Produce one blended recommendation, weighting all equally|false
risk_averse|Weight conservative responses higher|false
security_first|Prioritize security-focused insights|false
cost_capped|Prefer cheaper consultant opinions within budget|false
EOF
}

# name|preset|default strategy|description
registry_mode_rows() {
    cat <<'EOF'
fast-check|fast|coverage|Fast economy panel for a quick coverage check
coverage-review|balanced|coverage|Balanced panel for a general coverage review
max-coverage|max_quality|coverage|Maximum-quality panel for the broadest coverage
EOF
}

registry_canonical_preset() {
    local requested="$1" name aliases alias
    while IFS='|' read -r name aliases _; do
        [[ "$requested" == "$name" ]] && { printf '%s\n' "$name"; return 0; }
        for alias in $aliases; do
            [[ "$requested" == "$alias" ]] && { printf '%s\n' "$name"; return 0; }
        done
    done < <(registry_preset_rows)
    return 1
}

registry_preset_metadata() {
    local canonical
    canonical=$(registry_canonical_preset "$1") || return 1
    registry_preset_rows | while IFS= read -r row; do
        [[ "${row%%|*}" == "$canonical" ]] && { printf '%s\n' "$row"; return 0; }
    done
}

registry_preset_target() {
    local row
    row=$(registry_preset_metadata "$1") || return 1
    IFS='|' read -r _ _ target _ _ <<EOF
$row
EOF
    printf '%s\n' "$target"
}

registry_strategy_metadata() {
    local requested="$1" name rest
    while IFS='|' read -r name rest; do
        [[ "$requested" == "$name" ]] && { printf '%s|%s\n' "$name" "$rest"; return 0; }
    done < <(registry_strategy_rows)
    return 1
}

registry_default_strategy() {
    local name description is_default
    while IFS='|' read -r name description is_default; do
        [[ "$is_default" == "true" ]] && { printf '%s\n' "$name"; return 0; }
    done < <(registry_strategy_rows)
    return 1
}

registry_mode_metadata() {
    local requested="$1" name rest
    while IFS='|' read -r name rest; do
        [[ "$requested" == "$name" ]] && { printf '%s|%s\n' "$name" "$rest"; return 0; }
    done < <(registry_mode_rows)
    return 1
}

registry_mode_preset() {
    local row
    row=$(registry_mode_metadata "$1") || return 1
    IFS='|' read -r _ preset _ _ <<EOF
$row
EOF
    printf '%s\n' "$preset"
}

registry_mode_strategy() {
    local row
    row=$(registry_mode_metadata "$1") || return 1
    IFS='|' read -r _ _ strategy _ <<EOF
$row
EOF
    printf '%s\n' "$strategy"
}

# Resolve a public mode to its canonical preset and effective strategy.
# An explicit strategy is validated and takes precedence over the mode default.
# Output: preset|strategy
registry_resolve_mode() {
    local mode="$1" explicit_strategy="${2:-}" preset strategy
    preset=$(registry_mode_preset "$mode") || return 1
    strategy=$(registry_mode_strategy "$mode") || return 1
    if [[ -n "$explicit_strategy" ]]; then
        registry_strategy_metadata "$explicit_strategy" >/dev/null || return 1
        strategy="$explicit_strategy"
    fi
    printf '%s|%s\n' "$preset" "$strategy"
}

registry_list_presets() {
    local name aliases target tier use_case alias_text
    echo "Available presets:"
    echo
    while IFS='|' read -r name aliases target tier use_case; do
        alias_text=""
        [[ -n "$aliases" ]] && alias_text=" (alias: $aliases)"
        printf '  %-12s %2s consultants, %-7s — %s%s\n' "$name" "$target" "$tier" "$use_case" "$alias_text"
    done < <(registry_preset_rows)
    echo
    echo 'Usage: ./consult_all.sh --preset <name> "Your question"'
}

registry_list_strategies() {
    local name description is_default suffix
    echo "Available synthesis strategies:"
    echo
    while IFS='|' read -r name description is_default; do
        suffix=""
        [[ "$is_default" == "true" ]] && suffix=" (default)"
        printf '  %-14s %s%s\n' "$name" "$description" "$suffix"
    done < <(registry_strategy_rows)
    echo
    echo 'Usage: ./consult_all.sh --strategy <name> "Your question"'
}

registry_list_modes() {
    local name preset strategy description
    echo "Available public modes:"
    echo
    while IFS='|' read -r name preset strategy description; do
        printf '  %-16s preset=%-11s strategy=%-10s %s\n' "$name" "$preset" "$strategy" "$description"
    done < <(registry_mode_rows)
    echo
    echo 'Usage: ./consult_all.sh --mode <name> "Your question"'
}

registry_render_help_options() {
    cat <<'EOF'
  --mode <name>        Use a public mode (preset + default strategy)
  --preset <name>      Use a configuration preset
  --strategy <name>    Use a synthesis strategy (overrides a mode default)
  --list-modes         List public modes
  --list-presets       List available presets
  --list-strategies    List available synthesis strategies
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --list-presets) registry_list_presets ;;
        --list-strategies) registry_list_strategies ;;
        --list-modes) registry_list_modes ;;
        --default-strategy) registry_default_strategy ;;
        --help|-h)
            echo "Usage: $0 --list-modes|--list-presets|--list-strategies|--default-strategy"
            ;;
        *)
            echo "Unknown registry command: ${1:-}" >&2
            exit 64
            ;;
    esac
fi
