#!/bin/bash
# generate_public_docs.sh - Render public mode/preset/strategy docs from the
# side-effect-free registry. Use --check in CI to detect manual drift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${AI_CONSULTANTS_DOC_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=public_registry.sh
source "$SCRIPT_DIR/public_registry.sh"

CHECK=false
case "${1:-}" in
    "") ;;
    --check) CHECK=true ;;
    --help|-h)
        echo "Usage: $0 [--check]"
        echo "Regenerates marked public registry sections in README.md and references/details.md."
        exit 0
        ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
esac

render_section() {
    local level="$1" name aliases target tier use_case description is_default preset strategy
    printf '%s\n' '<!-- ai-consultants:public-registry:start -->'
    printf '%s\n' "<!-- ai-consultants:default-synthesis-strategy=$(registry_default_strategy) -->"
    printf '%s Public Modes\n\n' "$level"
    printf '%s\n' '| Mode | Preset | Default strategy | Use case |'
    printf '%s\n' '|---|---|---|---|'
    while IFS='|' read -r name preset strategy description; do
        printf '| `%s` | `%s` | `%s` | %s |\n' "$name" "$preset" "$strategy" "$description"
    done < <(registry_mode_rows)
    printf '\n%s Configuration Presets\n\n' "$level"
    printf '%s\n' '| Preset | Alias | Target | Tier | Use case |'
    printf '%s\n' '|---|---|---:|---|---|'
    while IFS='|' read -r name aliases target tier use_case; do
        if [[ -n "$aliases" ]]; then aliases="\`$aliases\`"; else aliases='—'; fi
        printf '| `%s` | %s | %s | %s | %s |\n' "$name" "$aliases" "$target" "$tier" "$use_case"
    done < <(registry_preset_rows)
    printf '\n%s Synthesis Strategies\n\n' "$level"
    printf '%s\n' '| Strategy | Description |'
    printf '%s\n' '|---|---|'
    while IFS='|' read -r name description is_default; do
        [[ "$is_default" == "true" ]] && description="$description **Default**"
        printf '| `%s` | %s |\n' "$name" "$description"
    done < <(registry_strategy_rows)
    printf '%s\n' '<!-- ai-consultants:public-registry:end -->'
}

replace_section() {
    local target="$1" level="$2" generated="$3" output="$4"
    local starts ends
    starts=$(grep -c '^<!-- ai-consultants:public-registry:start -->$' "$target" || true)
    ends=$(grep -c '^<!-- ai-consultants:public-registry:end -->$' "$target" || true)
    if [[ "$starts" != 1 || "$ends" != 1 ]]; then
        echo "Documentation markers invalid in $target (start=$starts, end=$ends)" >&2
        return 1
    fi
    if ! awk '
        /^<!-- ai-consultants:public-registry:start -->$/ {
            if (in_generated || saw_start) invalid=1
            saw_start=1
            in_generated=1
            next
        }
        /^<!-- ai-consultants:public-registry:end -->$/ {
            if (!in_generated || saw_end) invalid=1
            saw_end=1
            in_generated=0
            next
        }
        END { if (invalid || !saw_start || !saw_end || in_generated) exit 1 }
    ' "$target"; then
        echo "Documentation marker ordering invalid in $target" >&2
        return 1
    fi
    awk -v generated="$generated" '
        /^<!-- ai-consultants:public-registry:start -->$/ {
            while ((getline line < generated) > 0) print line
            close(generated)
            in_generated=1
            next
        }
        /^<!-- ai-consultants:public-registry:end -->$/ && in_generated { in_generated=0; next }
        !in_generated { print }
    ' "$target" > "$output"
}

check_or_write() {
    local target="$1" level="$2" generated rendered
    generated=$(mktemp "${TMPDIR:-/tmp}/ai-consultants-public-docs.XXXXXX")
    rendered=$(mktemp "${TMPDIR:-/tmp}/ai-consultants-public-docs.XXXXXX")
    trap 'rm -f "$generated" "$rendered"' RETURN
    render_section "$level" > "$generated"
    replace_section "$target" "$level" "$generated" "$rendered"
    if cmp -s "$target" "$rendered"; then
        return 0
    fi
    if [[ "$CHECK" == "true" ]]; then
        echo "Generated public registry documentation is stale: $target" >&2
        diff -u "$target" "$rendered" >&2 || true
        return 1
    fi
    mv "$rendered" "$target"
    rm -f "$generated"
    trap - RETURN
}

check_or_write "$REPO_ROOT/README.md" '###'
check_or_write "$REPO_ROOT/references/details.md" '##'
check_or_write "$REPO_ROOT/SKILL.md" '##'
