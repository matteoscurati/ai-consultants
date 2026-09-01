#!/bin/bash
# Offline contract for README's documented synthesis default.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
README="$REPO_ROOT/README.md"
CONFIG="$SCRIPT_DIR/config.sh"
# shellcheck source=public_registry.sh
source "$SCRIPT_DIR/public_registry.sh"

source "$SCRIPT_DIR/lib/test_helpers.sh"

test_readme_synthesis_default_matches_runtime() {
    local runtime_defaults runtime_default documented_markers documented_default
    local strategy_section table_defaults table_default_count

    runtime_defaults=$(sed -n 's/^DEFAULT_STRATEGY="${DEFAULT_STRATEGY:-\$(registry_default_strategy)}"$/registry/p' "$CONFIG")
    assert_eq 1 "$(printf '%s\n' "$runtime_defaults" | sed '/^$/d' | wc -l | tr -d ' ')" \
        "config delegates its DEFAULT_STRATEGY runtime default to the registry"
    runtime_default=$(registry_default_strategy)

    documented_markers=$(sed -n \
        's/^<!--[[:space:]]*ai-consultants:default-synthesis-strategy=\([a-z_][a-z_]*\)[[:space:]]*-->$/\1/p' \
        "$README")
    assert_eq 1 "$(printf '%s\n' "$documented_markers" | sed '/^$/d' | wc -l | tr -d ' ')" \
        "README declares exactly one synthesis-default contract marker"
    documented_default=$(printf '%s\n' "$documented_markers" | sed -n '1p')
    assert_eq "$runtime_default" "$documented_default" \
        "README contract marker matches DEFAULT_STRATEGY"

    strategy_section=$(awk '
        /^### Synthesis Strategies$/ { in_section=1; next }
        in_section && /^### / { exit }
        in_section { print }
    ' "$README")
    table_defaults=$(printf '%s\n' "$strategy_section" | awk -F '|' '
        $2 ~ /`[a-z_][a-z_]*`/ && $3 ~ /\*\*Default\*\*/ {
            strategy=$2
            gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", strategy)
            print strategy
        }
    ')
    table_default_count=$(printf '%s\n' "$table_defaults" | sed '/^$/d' | wc -l | tr -d ' ')
    assert_eq 1 "$table_default_count" \
        "Synthesis-strategy table marks exactly one default"
    assert_eq "$runtime_default" "$(printf '%s\n' "$table_defaults" | sed -n '1p')" \
        "Synthesis-strategy table default matches DEFAULT_STRATEGY"
}

run_test "README synthesis default contract" test_readme_synthesis_default_matches_runtime
test_summary "documentation contract"
