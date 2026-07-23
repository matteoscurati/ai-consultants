#!/bin/bash
# test_install.sh - Hermetic tests for scripts/install.sh helpers.
#
# Only the pure helpers are exercised. install.sh is sourced with
# AI_CONSULTANTS_INSTALL_DEFINE_ONLY=1, which returns before any top-level
# work, so nothing here clones, writes outside its temp dirs, or touches the
# user's real ~/.claude/commands.
#
# Usage: ./scripts/test_install.sh
# Exit:  0 on full pass, 1 on any failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

# shellcheck source=install.sh
AI_CONSULTANTS_INSTALL_DEFINE_ONLY=1 source "$SCRIPT_DIR/install.sh"

TMP=$(mktemp -d -t ai_consultants_install_test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Build a fresh pair of dirs: the user's installed commands, and what the repo
# currently ships. Returns with both populated per the caller's fixtures.
setup_dirs() {
    rm -rf "$TMP/installed" "$TMP/repo"
    mkdir -p "$TMP/installed" "$TMP/repo"
}

# ---------------------------------------------------------------------------
test_prunes_commands_removed_upstream() {
    setup_dirs
    # Three the repo still ships, plus two it dropped (the v2.10.0 consolidation).
    for c in consult debate help; do
        touch "$TMP/repo/ai-consultants:${c}.md" "$TMP/installed/ai-consultants:${c}.md"
    done
    touch "$TMP/installed/ai-consultants:config-features.md" \
          "$TMP/installed/ai-consultants:config-wizard.md"

    prune_removed_commands "$TMP/installed" "$TMP/repo"

    assert_eq "2" "$PRUNED_COUNT" "reports the number pruned"
    assert_eq "false" "$([[ -e "$TMP/installed/ai-consultants:config-features.md" ]] && echo true || echo false)" \
        "removes a command the repo no longer ships"
    assert_eq "true" "$([[ -f "$TMP/installed/ai-consultants:consult.md" ]] && echo true || echo false)" \
        "keeps a command the repo still ships"
    assert_eq "3" "$(find "$TMP/installed" -name 'ai-consultants:*.md' | wc -l | tr -d ' ')" \
        "leaves exactly the three current commands"
}

# ---------------------------------------------------------------------------
test_leaves_other_tools_commands_alone() {
    setup_dirs
    touch "$TMP/repo/ai-consultants:consult.md" "$TMP/installed/ai-consultants:consult.md"
    # Commands belonging to other tools must never be considered, even though
    # they are equally absent from this repo's command directory.
    touch "$TMP/installed/some-other-tool:deploy.md" \
          "$TMP/installed/unrelated.md" \
          "$TMP/installed/ai-consultants-lookalike.md"

    prune_removed_commands "$TMP/installed" "$TMP/repo"

    assert_eq "0" "$PRUNED_COUNT" "nothing outside the namespace is counted"
    for f in some-other-tool:deploy.md unrelated.md ai-consultants-lookalike.md; do
        assert_eq "true" "$([[ -f "$TMP/installed/$f" ]] && echo true || echo false)" \
            "leaves $f untouched"
    done
}

# ---------------------------------------------------------------------------
test_no_installed_commands_is_a_clean_no_op() {
    setup_dirs
    touch "$TMP/repo/ai-consultants:consult.md"

    # The glob matches nothing here; under `set -euo pipefail` a naive loop
    # would iterate over the literal pattern and try to stat it.
    prune_removed_commands "$TMP/installed" "$TMP/repo"

    assert_eq "0" "$PRUNED_COUNT" "fresh install prunes nothing"
}

# ---------------------------------------------------------------------------
test_missing_commands_dir_is_a_clean_no_op() {
    setup_dirs
    rm -rf "$TMP/installed"
    touch "$TMP/repo/ai-consultants:consult.md"

    prune_removed_commands "$TMP/installed" "$TMP/repo"

    assert_eq "0" "$PRUNED_COUNT" "absent commands dir prunes nothing"
}

# ---------------------------------------------------------------------------
test_define_only_hook_runs_no_installer_work() {
    # The suite itself is the proof — it sourced install.sh above and reached
    # here without cloning or writing. Assert the guard is still in place so a
    # refactor that drops it fails loudly rather than making `npm test` clone.
    # Match the guard itself, not every mention of the variable (its own
    # explanatory comment names it too).
    assert_eq "1" "$(grep -cE '^if \[\[ -n "\$\{AI_CONSULTANTS_INSTALL_DEFINE_ONLY:-\}" \]\]; then$' \
        "$SCRIPT_DIR/install.sh" | tr -d ' ')" \
        "install.sh still carries exactly one define-only guard"
    assert_eq "true" "$(declare -F prune_removed_commands >/dev/null && echo true || echo false)" \
        "sourcing define-only exposes prune_removed_commands"
}

run_test "Test 1: prunes commands removed upstream" test_prunes_commands_removed_upstream
run_test "Test 2: leaves other tools' commands alone" test_leaves_other_tools_commands_alone
run_test "Test 3: fresh install is a clean no-op" test_no_installed_commands_is_a_clean_no_op
run_test "Test 4: missing commands dir is a clean no-op" test_missing_commands_dir_is_a_clean_no_op
run_test "Test 5: define-only hook exposes helpers without installing" test_define_only_hook_runs_no_installer_work

test_summary "install"
