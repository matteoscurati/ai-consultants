#!/bin/bash
# shellcheck disable=SC2329
# (test_*/assert_eq are invoked indirectly via `run_test "$@"`)
#
# test_bin.sh - Tests for the bin/ai-consultants entry point (v2.12+)
#
# Covers:
#   - `version`: dynamic resolution from config.sh, semver validation,
#     fallback to "unknown" when config.sh is malformed
#   - `init`: scaffolds .env (chmod 600!) and config.sh, refuses symlinks,
#     respects AI_CONSULTANTS_CONFIG_DIR, --force overwrites, idempotent
#     without --force
#
# Usage: ./scripts/test_bin.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin/ai-consultants"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP=$(mktemp -d -t ai_consultants_bin_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# -----------------------------------------------------------------------------
# version
# -----------------------------------------------------------------------------

test_version_matches_config() {
    local out config_version
    out=$("$BIN" version)
    config_version=$(grep -E '^AI_CONSULTANTS_VERSION=' "$PROJECT_ROOT/scripts/config.sh" \
        | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    assert_eq "ai-consultants v$config_version" "$out" \
        "version subcommand matches config.sh AI_CONSULTANTS_VERSION"
}

test_version_is_semver() {
    local out
    out=$("$BIN" version)
    assert_match '^ai-consultants v[0-9]+\.[0-9]+\.[0-9]+' "$out" \
        "version output is semver-shaped"
}

# v2.12 fix: a config.sh without quotes around the version (or any other
# malformed shape) must yield "unknown", not the raw "AI_CONSULTANTS_VERSION=..."
# string that the sed pipeline would otherwise pass through verbatim.
test_version_unknown_on_malformed_config() {
    local fake_root="$TMP/fake_project"
    mkdir -p "$fake_root/bin" "$fake_root/scripts"
    echo 'AI_CONSULTANTS_VERSION=2.12.0' > "$fake_root/scripts/config.sh"  # no quotes!
    cp "$BIN" "$fake_root/bin/ai-consultants"
    chmod +x "$fake_root/bin/ai-consultants"
    local out
    out=$("$fake_root/bin/ai-consultants" version 2>&1 || true)
    assert_eq "ai-consultants vunknown" "$out" \
        "malformed (unquoted) version line yields 'unknown', not raw garbage"
}

# -----------------------------------------------------------------------------
# init
# -----------------------------------------------------------------------------

# v2.12 contract: .env contains API keys → MUST be chmod 600.
test_init_chmod_600_on_env() {
    local cfg="$TMP/init1"
    AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init >/dev/null 2>&1
    local perms
    # GNU stat accepts `-f` with different semantics (filesystem report) and
    # exits successfully, so probing the BSD form first pollutes the result on
    # Linux. Try GNU `-c` first; macOS/BSD rejects it and falls back to `-f`.
    perms=$(stat -c '%a' "$cfg/.env" 2>/dev/null || stat -f '%Lp' "$cfg/.env" 2>/dev/null || echo "?")
    assert_eq "600" "$perms" ".env created with chmod 600 (contains API keys)"
}

test_init_creates_both_files() {
    local cfg="$TMP/init2"
    AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init >/dev/null 2>&1
    local has_env has_config
    has_env=$([[ -f "$cfg/.env" ]] && echo "yes" || echo "no")
    has_config=$([[ -f "$cfg/config.sh" ]] && echo "yes" || echo "no")
    assert_eq "yes" "$has_env" "init created .env"
    assert_eq "yes" "$has_config" "init created config.sh"
}

# v2.12 contract: idempotent without --force (won't overwrite existing files).
test_init_preserves_without_force() {
    local cfg="$TMP/init3"
    mkdir -p "$cfg"
    echo 'SENTINEL_DO_NOT_OVERWRITE=keep_me' > "$cfg/.env"
    chmod 600 "$cfg/.env"
    AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init >/dev/null 2>&1
    local content
    content=$(cat "$cfg/.env")
    assert_eq "SENTINEL_DO_NOT_OVERWRITE=keep_me" "$content" \
        "existing .env preserved without --force"
}

# v2.12 contract: --force overwrites.
test_init_force_overwrites() {
    local cfg="$TMP/init4"
    mkdir -p "$cfg"
    echo 'SENTINEL=will_be_overwritten' > "$cfg/.env"
    AI_CONSULTANTS_CONFIG_DIR="$cfg" "$BIN" init --force >/dev/null 2>&1
    local content
    content=$(cat "$cfg/.env")
    if [[ "$content" == *"SENTINEL=will_be_overwritten"* ]]; then
        assert_eq "OVERWRITTEN" "PRESERVED" "--force should overwrite existing .env"
    else
        assert_eq "OVERWRITTEN" "OVERWRITTEN" "--force overwrote existing .env"
    fi
}

# v2.12 fix: refuse to scaffold into a symlinked dir (root + hostile symlink
# scenario). Tests that the security check fires.
test_init_refuses_symlink() {
    local target="$TMP/init5_target"
    local link="$TMP/init5_link"
    mkdir -p "$target"
    ln -s "$target" "$link"
    local rc=0
    AI_CONSULTANTS_CONFIG_DIR="$link" "$BIN" init >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "init exits 1 when config dir is a symlink"
    local has_env
    has_env=$([[ -f "$target/.env" ]] && echo "yes" || echo "no")
    assert_eq "no" "$has_env" "init did NOT write .env into the symlink target"
}

run_test "Test 1: version matches config.sh"           test_version_matches_config
run_test "Test 2: version is semver-shaped"            test_version_is_semver
run_test "Test 3: version=unknown on malformed config" test_version_unknown_on_malformed_config
run_test "Test 4: init creates .env with chmod 600"    test_init_chmod_600_on_env
run_test "Test 5: init creates both files"             test_init_creates_both_files
run_test "Test 6: init preserves existing without --force" test_init_preserves_without_force
run_test "Test 7: init --force overwrites"             test_init_force_overwrites
run_test "Test 8: init refuses symlinked dir"          test_init_refuses_symlink

test_summary "bin"
