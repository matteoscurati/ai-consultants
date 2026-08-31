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
    # Two the repo still ships, plus two it dropped (the v2.10.0 consolidation).
    for c in consult help; do
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
    assert_eq "2" "$(find "$TMP/installed" -name 'ai-consultants:*.md' | wc -l | tr -d ' ')" \
        "leaves exactly the two current commands"
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

# ---------------------------------------------------------------------------
test_installer_banner_is_version_neutral() {
    local banner
    banner="$(print_header)"

    assert_eq "1" "$(printf '%s\n' "$banner" | grep -cF 'AI Consultants - Installation')" \
        "installer banner identifies the installer"
    assert_eq "0" "$(printf '%s\n' "$banner" | grep -cE 'AI Consultants v[0-9]+\.[0-9]+' || true)" \
        "installer banner never advertises a stale package version"
}

# ---------------------------------------------------------------------------
test_shipped_surfaces_exclude_removed_cursor_consultant() {
    local project_root command_file host_dir host_name invoking
    project_root="$(cd "$SCRIPT_DIR/.." && pwd)"

    for command_file in \
        "$project_root/.claude/commands/ai-consultants:consult.md" \
        "$project_root/.codex/commands/ai-consultants:consult.md" \
        "$project_root/.gemini/commands/ai-consultants:consult.md"; do
        assert_eq "0" "$(grep -c 'Cursor' "$command_file" || true)" \
            "installed command description excludes the removed Cursor consultant"
    done

    assert_eq "0" "$(grep -cE 'CURSOR_|cursor\.json|Cursor - The Integrator' \
        "$project_root/templates/consultation_report.md" || true)" \
        "packaged report template excludes Cursor placeholders and artifacts"
    assert_eq "0" "$(grep -cE 'Consensus|Debate|voting\.json|Weighted Recommendation' \
        "$project_root/templates/consultation_report.md" || true)" \
        "packaged report template reflects coverage-only architecture"
    assert_eq "0" "$(awk '/^## Changelog/{exit} {print}' "$project_root/README.md" | \
        grep -c 'cursor\.json' || true)" \
        "current README output tree excludes cursor.json"

    local claude_command="$project_root/.claude/commands/ai-consultants:consult.md"
    assert_eq "1" "$(grep -c 'INVOKING_AGENT=claude ./scripts/consult_all.sh' "$claude_command")" \
        "Claude consultation command marks the invoking host"
    assert_eq "0" "$(grep -c "consult_all\.sh.*'<question>'" "$claude_command" || true)" \
        "Claude command never interpolates raw question text into shell argv"
    assert_eq "1" "$(grep -c 'single-quoted heredoc delimiter' "$claude_command")" \
        "Claude command requires non-expanding query-file handoff"
    assert_eq "0" "$(grep -c "followup\.sh.*'<follow-up question>'" "$claude_command" || true)" \
        "Claude follow-up never interpolates raw question text into shell argv"
    assert_eq "1" "$(grep -c 'Claude host produces no Claude consultant artifacts\|claude.json.*must not exist' "$claude_command" || true)" \
        "Claude command documents the self-exclusion artifact invariant"
    assert_eq "0" "$(grep -c 'ai-consultants:debate' "$project_root/.claude/commands/ai-consultants:help.md" || true)" \
        "Claude help does not advertise the removed debate command"

    for host_name in claude codex gemini; do
        host_dir="$project_root/.${host_name}/commands"
        assert_eq "2" "$(find "$host_dir" -maxdepth 1 -name 'ai-consultants:*.md' -type f | wc -l | tr -d ' ')" \
            "$host_name ships only consult and help commands"
        assert_eq "0" "$(grep -R -hE 'ai-consultants:(debate|roster-audit)' "$host_dir" 2>/dev/null | wc -l | tr -d ' ')" \
            "$host_name commands do not advertise removed workflows"

        invoking="$host_name"
        [[ "$host_name" != "gemini" ]] || invoking=gemini
        assert_eq "1" "$(grep -c "INVOKING_AGENT=${invoking} ./scripts/consult_all.sh" "$host_dir/ai-consultants:consult.md")" \
            "$host_name consultation command marks its invoking host"
        assert_eq "1" "$(grep -c -- '--query-file "<private-question-file>"' "$host_dir/ai-consultants:consult.md")" \
            "$host_name command uses private query-file handoff"
        assert_eq "1" "$(grep -c 'Install a shell trap' "$host_dir/ai-consultants:consult.md")" \
            "$host_name command removes its private query file"
        assert_eq "1" "$(grep -c -- 'followup.sh --query-file "<private-follow-up-file>"' "$host_dir/ai-consultants:consult.md")" \
            "$host_name follow-up uses private query-file handoff"
    done

    assert_eq "0" "$(grep -cE 'ai-consultants:debate|weighted recommendations|Multi-agent debate|Anonymous peer review|kilocode' \
        "$project_root/AGENTS.md" || true)" \
        "active AGENTS instructions exclude removed workflows and providers"
    assert_eq "0" "$(grep -c -- '-name "consult\*\.md"' "$SCRIPT_DIR/install.sh" || true)" \
        "uninstall never targets another tool's generic consult commands"
    assert_eq "1" "$(grep -c -- '-name "ai-consultants:\*\.md"' "$SCRIPT_DIR/install.sh" || true)" \
        "uninstall is positively scoped to the ai-consultants command namespace"
}

# ---------------------------------------------------------------------------
test_package_excludes_release_archive() {
    local project_root manifest release_count test_count release_script_count setup_count
    project_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    manifest=$(cd "$project_root" && npm pack --dry-run --json 2>/dev/null)
    release_count=$(jq '[.[0].files[].path | select(startswith("docs/releases/"))] | length' <<< "$manifest")
    test_count=$(jq '[.[0].files[].path | select(startswith("scripts/test_"))] | length' <<< "$manifest")
    release_script_count=$(jq '[.[0].files[].path | select(. == "scripts/release.sh")] | length' <<< "$manifest")
    setup_count=$(jq '[.[0].files[].path | select(. == "docs/SETUP.md")] | length' <<< "$manifest")

    assert_eq "0" "$release_count" "npm package excludes the GitHub release-note archive"
    assert_eq "0" "$test_count" "npm package excludes test suites"
    assert_eq "0" "$release_script_count" "npm package excludes maintainer release tooling"
    assert_eq "1" "$setup_count" "npm package keeps active setup documentation"
}

run_test "Test 1: prunes commands removed upstream" test_prunes_commands_removed_upstream
run_test "Test 2: leaves other tools' commands alone" test_leaves_other_tools_commands_alone
run_test "Test 3: fresh install is a clean no-op" test_no_installed_commands_is_a_clean_no_op
run_test "Test 4: missing commands dir is a clean no-op" test_missing_commands_dir_is_a_clean_no_op
run_test "Test 5: define-only hook exposes helpers without installing" test_define_only_hook_runs_no_installer_work
run_test "Test 6: installer banner is version-neutral" test_installer_banner_is_version_neutral
run_test "Test 7: shipped surfaces exclude removed Cursor consultant" test_shipped_surfaces_exclude_removed_cursor_consultant
run_test "Test 8: npm package excludes release-note archive" test_package_excludes_release_archive

test_summary "install"
