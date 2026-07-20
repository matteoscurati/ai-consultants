#!/bin/bash
# release.sh - Automates the version-bump surfaces for an ai-consultants release.
#
# Usage:
#   scripts/release.sh <new-version> [--dry-run]
#
# Bumps the CURRENT version (read from package.json) to <new-version> across
# exactly these surfaces:
#   package.json, scripts/config.sh, SKILL.md (frontmatter + title),
#   README.md (title + badge), CLAUDE.md (**Version**), docs/cost_rates.json,
#   docs/COST_RATES.md (title)
#
# Then validates consistency (no stray CURRENT version left on those exact
# lines), runs `npm test` + `npm run lint`, and prints a reminder of the
# manual release steps this script deliberately does NOT do.
#
# Env overrides:
#   ROOT        - repo root to operate under (default: computed from script location)
#   SKIP_GATE=1 - skip npm test / npm run lint (used by the hermetic test suite)
#
# This script never commits, tags, or publishes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ROOT="${ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

DRY_RUN=false
NEW_VERSION=""

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        -h|--help)
            echo "Usage: $0 <new-version> [--dry-run]"
            exit 0
            ;;
        *)
            if [[ -z "$NEW_VERSION" ]]; then
                NEW_VERSION="$arg"
            else
                log_error "Unexpected argument: $arg"
                exit 1
            fi
            ;;
    esac
done

if [[ -z "$NEW_VERSION" ]]; then
    log_error "Missing required argument: <new-version>"
    echo "Usage: $0 <new-version> [--dry-run]"
    exit 1
fi

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version '$NEW_VERSION' — must be semver X.Y.Z (e.g. 2.21.0)"
    exit 1
fi

if [[ ! -f "$ROOT/package.json" ]]; then
    log_error "package.json not found under ROOT: $ROOT"
    exit 1
fi

CURRENT_VERSION="$(jq -r '.version' "$ROOT/package.json")"

if [[ -z "$CURRENT_VERSION" || "$CURRENT_VERSION" == "null" ]]; then
    log_error "Could not read current version from $ROOT/package.json"
    exit 1
fi

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    log_error "New version ($NEW_VERSION) is the same as the current version"
    exit 1
fi

# Escape a literal string for safe use in a sed BRE pattern (dots, slashes, etc).
esc_regex() {
    printf '%s' "$1" | sed -e 's/[.[\*^$/]/\\&/g'
}

CUR_ESC="$(esc_regex "$CURRENT_VERSION")"

# Each surface: file | sed program (anchored on the surrounding text, not a
# blanket version replace) | old-line regex (for --dry-run preview + the
# "old version gone" check) | new-line literal text (for the "new version
# present" check, matched with fixed-string grep — avoids treating '*'/'.' in
# markdown/JSON content as regex metacharacters) | human-readable label.
SURFACES=(
    "package.json|s/\"version\": \"${CUR_ESC}\"/\"version\": \"${NEW_VERSION}\"/|\"version\": \"${CUR_ESC}\"|  \"version\": \"${NEW_VERSION}\",|package.json: \"version\" field"
    "scripts/config.sh|s/AI_CONSULTANTS_VERSION=\"${CUR_ESC}\"/AI_CONSULTANTS_VERSION=\"${NEW_VERSION}\"/|AI_CONSULTANTS_VERSION=\"${CUR_ESC}\"|AI_CONSULTANTS_VERSION=\"${NEW_VERSION}\"|scripts/config.sh: AI_CONSULTANTS_VERSION"
    "SKILL.md|s/^  version: ${CUR_ESC}\$/  version: ${NEW_VERSION}/|^  version: ${CUR_ESC}\$|  version: ${NEW_VERSION}|SKILL.md: frontmatter version"
    "SKILL.md|s/^# AI Consultants v${CUR_ESC} - AI Expert Panel\$/# AI Consultants v${NEW_VERSION} - AI Expert Panel/|^# AI Consultants v${CUR_ESC} - AI Expert Panel\$|# AI Consultants v${NEW_VERSION} - AI Expert Panel|SKILL.md: title"
    "README.md|s/^# AI Consultants v${CUR_ESC}\$/# AI Consultants v${NEW_VERSION}/|^# AI Consultants v${CUR_ESC}\$|# AI Consultants v${NEW_VERSION}|README.md: title"
    "README.md|s/version-${CUR_ESC}-blue/version-${NEW_VERSION}-blue/|version-${CUR_ESC}-blue|version-${NEW_VERSION}-blue|README.md: badge"
    "CLAUDE.md|s/^\*\*Version\*\*: ${CUR_ESC}\$/**Version**: ${NEW_VERSION}/|^\*\*Version\*\*: ${CUR_ESC}\$|**Version**: ${NEW_VERSION}|CLAUDE.md: **Version**"
    "docs/cost_rates.json|s/\"version\": \"${CUR_ESC}\"/\"version\": \"${NEW_VERSION}\"/|\"version\": \"${CUR_ESC}\"|  \"version\": \"${NEW_VERSION}\",|docs/cost_rates.json: \"version\" field"
    "docs/COST_RATES.md|s/^# Cost Rates - AI Consultants v${CUR_ESC}\$/# Cost Rates - AI Consultants v${NEW_VERSION}/|^# Cost Rates - AI Consultants v${CUR_ESC}\$|# Cost Rates - AI Consultants v${NEW_VERSION}|docs/COST_RATES.md: title"
)

log_info "Release: $CURRENT_VERSION -> $NEW_VERSION (ROOT: $ROOT)"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "DRY RUN — no files will be changed."
    echo ""
fi

for surface in "${SURFACES[@]}"; do
    IFS='|' read -r rel_file sed_prog old_regex new_literal label <<< "$surface"
    file="$ROOT/$rel_file"

    if [[ ! -f "$file" ]]; then
        log_error "Surface file not found: $file"
        exit 1
    fi

    matched_line="$(grep -nE -m1 -- "$old_regex" "$file" 2>/dev/null || true)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [$label]"
        echo "    file: $rel_file"
        if [[ -n "$matched_line" ]]; then
            echo "    old:  ${matched_line#*:}"
        else
            echo "    old:  (no match found — see WARNING below)"
        fi
        echo "    new version: $NEW_VERSION"
        if [[ -z "$matched_line" ]]; then
            log_warn "No match for [$label] in $rel_file — this surface would not be updated"
        fi
        continue
    fi

    if [[ -z "$matched_line" ]]; then
        log_error "No match for [$label] in $rel_file — refusing to proceed"
        exit 1
    fi

    sed -i.bak -e "$sed_prog" "$file"
    rm -f "${file}.bak"
    log_success "Updated $label"
done

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "Dry run complete. No files were changed."
    exit 0
fi

# -----------------------------------------------------------------------------
# Consistency validation: each surface's anchor line must now show NEW and
# must NOT still show CURRENT. Checked line-by-line against the same anchors
# used for the edit (not a whole-file grep), so legitimate historical
# mentions of CURRENT elsewhere (CHANGELOG.md, docs/releases/*.md, CLAUDE.md's
# `## Changelog` section) are correctly excluded from this check.
# -----------------------------------------------------------------------------
log_info "Validating consistency..."

validation_failed=false
for surface in "${SURFACES[@]}"; do
    IFS='|' read -r rel_file sed_prog old_regex new_literal label <<< "$surface"
    file="$ROOT/$rel_file"

    if grep -qE -- "$old_regex" "$file" 2>/dev/null; then
        log_error "[$label] still shows the old version ($CURRENT_VERSION) in $rel_file"
        validation_failed=true
    fi

    if ! grep -qF -- "$new_literal" "$file" 2>/dev/null; then
        log_error "[$label] missing expected new version ($NEW_VERSION) in $rel_file"
        validation_failed=true
    fi
done

if [[ "$validation_failed" == "true" ]]; then
    log_error "Consistency validation FAILED. Fix the surfaces above before releasing."
    exit 1
fi

log_success "Consistency validation passed: all surfaces show $NEW_VERSION, no stray $CURRENT_VERSION."

# -----------------------------------------------------------------------------
# Gate: full test suite + lint (skippable for the hermetic test harness)
# -----------------------------------------------------------------------------
if [[ "${SKIP_GATE:-}" == "1" ]]; then
    log_warn "SKIP_GATE=1 set — skipping npm test / npm run lint"
else
    log_info "Running npm test..."
    if ! (cd "$ROOT" && npm test); then
        log_error "npm test FAILED — release aborted. Fix tests before releasing."
        exit 1
    fi
    log_success "npm test passed."

    log_info "Running npm run lint..."
    if ! (cd "$ROOT" && npm run lint); then
        log_error "npm run lint FAILED — release aborted. Fix lint issues before releasing."
        exit 1
    fi
    log_success "npm run lint passed."
fi

echo ""
echo "======================================================================"
echo " Version bumped: $CURRENT_VERSION -> $NEW_VERSION"
echo "======================================================================"
echo ""
echo "NEXT — this script owns the version surfaces only. Still to do:"
echo "  1. Add a '## [$NEW_VERSION] - $(date +%Y-%m-%d)' entry to CHANGELOG.md"
echo "  2. Add a '### v$NEW_VERSION' entry to CLAUDE.md's '## Changelog' section"
echo "  3. Create docs/releases/v${NEW_VERSION}.md (see CLAUDE.md's release note template)"
echo "  4. Update ../CLAUDE.md (workspace guide: last-sync version + release line)"
echo "  5. Commit, tag and push:"
echo "       ~/.claude/skills/ai-consultants-release/scripts/finalize.sh $NEW_VERSION \\"
echo "           --message-file <path> --tag-message-file <path>"
echo "  6. After publish.yml goes green, sync the site:"
echo "       ~/.claude/skills/ai-consultants-release/scripts/sync_site.sh $NEW_VERSION --message-file <path>"
echo ""
echo "The maintainer 'ai-consultants-release' skill (/ai-consultants-release $NEW_VERSION) drives all of the above."
echo "This script did NOT commit, tag, or publish anything."
echo ""
