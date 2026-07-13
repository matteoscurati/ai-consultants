#!/bin/bash
# test_release.sh - Hermetic tests for scripts/release.sh (release automation).
#
# Builds a minimal temp fixture containing only the version-bearing surfaces
# (package.json, scripts/config.sh, SKILL.md, README.md, CLAUDE.md,
# docs/cost_rates.json, docs/COST_RATES.md) with representative content
# holding the real repo's current version. Runs release.sh with ROOT pointed
# at that fixture and SKIP_GATE=1 (so the hermetic run never invokes npm
# test / npm run lint or touches the real repo).
#
# IMPORTANT: this test never runs release.sh against the real repo — every
# invocation below is scoped to the temp fixture via ROOT.
#
# Usage: ./scripts/test_release.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

CURRENT="2.20.0"
NEW="9.9.9"

TMP=$(mktemp -d -t ai_consultants_release_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Build the fixture: only the version-bearing surfaces, minimal representative
# content that mirrors the real repo's anchor lines for each surface.
build_fixture() {
    rm -rf "$TMP/fixture"
    mkdir -p "$TMP/fixture/scripts" "$TMP/fixture/docs"

    cat > "$TMP/fixture/package.json" <<EOF
{
  "name": "ai-consultants",
  "version": "${CURRENT}",
  "description": "fixture package.json"
}
EOF

    cat > "$TMP/fixture/scripts/config.sh" <<EOF
#!/bin/bash
# fixture config.sh
AI_CONSULTANTS_VERSION="${CURRENT}"
EOF

    cat > "$TMP/fixture/SKILL.md" <<EOF
---
name: ai-consultants
description: fixture skill
license: MIT
metadata:
  author: matteoscurati
  version: ${CURRENT}
---

# AI Consultants v${CURRENT} - AI Expert Panel

Fixture body.
EOF

    cat > "$TMP/fixture/README.md" <<EOF
# AI Consultants v${CURRENT}

[![Version](https://img.shields.io/badge/version-${CURRENT}-blue.svg)](https://github.com/matteoscurati/ai-consultants)

Fixture body.
EOF

    cat > "$TMP/fixture/CLAUDE.md" <<EOF
# AI Consultants - Claude Code Instructions

**Version**: ${CURRENT}

## Changelog

### v${CURRENT}
- Historical changelog entry mentioning ${CURRENT} — must survive untouched.
EOF

    cat > "$TMP/fixture/docs/cost_rates.json" <<EOF
{
  "version": "${CURRENT}",
  "models": {}
}
EOF

    cat > "$TMP/fixture/docs/COST_RATES.md" <<EOF
# Cost Rates - AI Consultants v${CURRENT}

Fixture body.
EOF
}

# Assert a fixture file contains a given exact line.
assert_file_has_line() {
    local file="$1" line="$2" msg="$3"
    ((checked++)) || true
    if grep -qF -- "$line" "$file" 2>/dev/null; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: $msg"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: $msg"
        echo "         expected line in $file: '$line'"
        ((failed++)) || true
    fi
}

# Assert a fixture file does NOT contain a given exact line.
assert_file_missing_line() {
    local file="$1" line="$2" msg="$3"
    ((checked++)) || true
    if ! grep -qF -- "$line" "$file" 2>/dev/null; then
        echo -e "  ${C_GREEN}PASS${C_RESET}: $msg"
    else
        echo -e "  ${C_RED}FAIL${C_RESET}: $msg"
        echo "         did not expect line in $file: '$line'"
        ((failed++)) || true
    fi
}

test_bump_updates_all_surfaces() {
    build_fixture

    ROOT="$TMP/fixture" SKIP_GATE=1 bash "$SCRIPT_DIR/release.sh" "$NEW"

    assert_file_has_line "$TMP/fixture/package.json" "  \"version\": \"${NEW}\"," \
        "package.json shows new version"
    assert_file_missing_line "$TMP/fixture/package.json" "  \"version\": \"${CURRENT}\"," \
        "package.json no longer shows old version"

    assert_file_has_line "$TMP/fixture/scripts/config.sh" "AI_CONSULTANTS_VERSION=\"${NEW}\"" \
        "config.sh shows new version"
    assert_file_missing_line "$TMP/fixture/scripts/config.sh" "AI_CONSULTANTS_VERSION=\"${CURRENT}\"" \
        "config.sh no longer shows old version"

    assert_file_has_line "$TMP/fixture/SKILL.md" "  version: ${NEW}" \
        "SKILL.md frontmatter shows new version"
    assert_file_has_line "$TMP/fixture/SKILL.md" "# AI Consultants v${NEW} - AI Expert Panel" \
        "SKILL.md title shows new version"
    assert_file_missing_line "$TMP/fixture/SKILL.md" "  version: ${CURRENT}" \
        "SKILL.md frontmatter no longer shows old version"
    assert_file_missing_line "$TMP/fixture/SKILL.md" "# AI Consultants v${CURRENT} - AI Expert Panel" \
        "SKILL.md title no longer shows old version"

    assert_file_has_line "$TMP/fixture/README.md" "# AI Consultants v${NEW}" \
        "README.md title shows new version"
    assert_file_has_line "$TMP/fixture/README.md" \
        "[![Version](https://img.shields.io/badge/version-${NEW}-blue.svg)](https://github.com/matteoscurati/ai-consultants)" \
        "README.md badge shows new version"
    assert_file_missing_line "$TMP/fixture/README.md" "# AI Consultants v${CURRENT}" \
        "README.md title no longer shows old version"

    assert_file_has_line "$TMP/fixture/CLAUDE.md" "**Version**: ${NEW}" \
        "CLAUDE.md shows new version"
    assert_file_missing_line "$TMP/fixture/CLAUDE.md" "**Version**: ${CURRENT}" \
        "CLAUDE.md no longer shows old version on the Version line"
    assert_file_has_line "$TMP/fixture/CLAUDE.md" "### v${CURRENT}" \
        "CLAUDE.md Changelog section keeps its historical version entry"
    assert_file_has_line "$TMP/fixture/CLAUDE.md" \
        "- Historical changelog entry mentioning ${CURRENT} — must survive untouched." \
        "CLAUDE.md Changelog body text is untouched"

    assert_file_has_line "$TMP/fixture/docs/cost_rates.json" "  \"version\": \"${NEW}\"," \
        "docs/cost_rates.json shows new version"
    assert_file_missing_line "$TMP/fixture/docs/cost_rates.json" "  \"version\": \"${CURRENT}\"," \
        "docs/cost_rates.json no longer shows old version"

    assert_file_has_line "$TMP/fixture/docs/COST_RATES.md" "# Cost Rates - AI Consultants v${NEW}" \
        "docs/COST_RATES.md title shows new version"
    assert_file_missing_line "$TMP/fixture/docs/COST_RATES.md" "# Cost Rates - AI Consultants v${CURRENT}" \
        "docs/COST_RATES.md title no longer shows old version"
}

test_invalid_version_rejected() {
    build_fixture

    if ROOT="$TMP/fixture" SKIP_GATE=1 bash "$SCRIPT_DIR/release.sh" "not-a-version" \
        > /dev/null 2>&1; then
        ((checked++)) || true
        echo -e "  ${C_RED}FAIL${C_RESET}: release.sh should reject a non-semver version"
        ((failed++)) || true
    else
        ((checked++)) || true
        echo -e "  ${C_GREEN}PASS${C_RESET}: release.sh rejects a non-semver version"
    fi

    assert_file_has_line "$TMP/fixture/package.json" "  \"version\": \"${CURRENT}\"," \
        "package.json unchanged after rejected invalid version"
}

test_dry_run_changes_nothing() {
    build_fixture

    # Snapshot fixture content before the dry run.
    local before after
    before=$(find "$TMP/fixture" -type f -exec md5 -q {} \; 2>/dev/null \
        || find "$TMP/fixture" -type f -exec md5sum {} \; 2>/dev/null)

    ROOT="$TMP/fixture" SKIP_GATE=1 bash "$SCRIPT_DIR/release.sh" "$NEW" --dry-run \
        > /dev/null

    after=$(find "$TMP/fixture" -type f -exec md5 -q {} \; 2>/dev/null \
        || find "$TMP/fixture" -type f -exec md5sum {} \; 2>/dev/null)

    assert_eq "$before" "$after" "dry-run leaves every fixture file byte-identical"

    assert_file_has_line "$TMP/fixture/package.json" "  \"version\": \"${CURRENT}\"," \
        "package.json still shows current version after dry-run"
    assert_file_has_line "$TMP/fixture/SKILL.md" "  version: ${CURRENT}" \
        "SKILL.md still shows current version after dry-run"
}

run_test "Test 1: release.sh bumps every surface and leaves history intact" test_bump_updates_all_surfaces
run_test "Test 2: release.sh rejects a non-semver version and changes nothing" test_invalid_version_rejected
run_test "Test 3: release.sh --dry-run changes nothing" test_dry_run_changes_nothing

test_summary "test_release"
