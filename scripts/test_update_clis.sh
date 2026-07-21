#!/bin/bash
# test_update_clis.sh - unit + smoke tests for update_clis.sh
#
# detect_method / _cli_meta are tested deterministically by stubbing the cached
# package listings (no real package manager is invoked). The --dry-run and
# --only paths are smoke-tested as a subprocess and asserted to change nothing.
set -uo pipefail

# Pin the log level: assertions below match on log output, which is filtered by
# LOG_LEVEL, so an inherited value would fail this suite for that environment
# only - deterministic, but easily mistaken for flakiness.
export LOG_LEVEL=INFO

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

# main() is guarded by a BASH_SOURCE==$0 check, so sourcing only loads functions.
# shellcheck source=update_clis.sh
source "$SCRIPT_DIR/update_clis.sh"

test_meta() {
    _cli_meta mmx
    assert_eq "mmx-cli" "$NPM_PKG"     "mmx npm package"
    assert_eq "update"  "$SELF_SUB"    "mmx self-update subcommand"
    _cli_meta codex
    assert_eq "codex"   "$BREW_CASK"   "codex brew cask name"
    _cli_meta vibe
    assert_eq "mistral-vibe" "$PIP_PKG" "vibe python package"
    _cli_meta agent
    assert_match "cursor.com" "$INSTALLER" "cursor has a curl installer"
    _cli_meta claude
    assert_eq "claude-code@latest" "$BREW_CASK" "claude brew cask (@latest)"
}

test_detect() {
    # Stub the cached listings; detection must pick the owning manager.
    _NPM_LS=$'/some/lib\n├── mmx-cli@1.0.16\n├── @qwen-code/qwen-code@0.19.9'
    _BREW_LS=""
    _BREW_CASK_LS=$'codex\nclaude-code@latest'
    _UV_LS=$'mistral-vibe v2.8.1\n- vibe'
    _PIPX_LS=""

    # An absent actual_cmd forces the deterministic cache path (skips realpath).
    detect_method mmx    __absent__; assert_eq "npm"       "$DETECT_METHOD" "mmx -> npm";         assert_eq "mmx-cli" "$DETECT_ARG" "mmx pkg arg"
    detect_method qwen   __absent__; assert_eq "npm"       "$DETECT_METHOD" "qwen -> npm"
    detect_method codex  __absent__; assert_eq "brew-cask" "$DETECT_METHOD" "codex -> brew-cask"; assert_eq "codex" "$DETECT_ARG" "codex cask arg"
    detect_method claude __absent__; assert_eq "brew-cask" "$DETECT_METHOD" "claude -> brew-cask"; assert_eq "claude-code@latest" "$DETECT_ARG" "claude cask arg (@latest)"
    detect_method vibe   __absent__; assert_eq "uv"        "$DETECT_METHOD" "vibe -> uv"
    detect_method agy    __absent__; assert_eq "installer" "$DETECT_METHOD" "agy -> installer"
    detect_method agent  __absent__; assert_eq "installer" "$DETECT_METHOD" "cursor -> installer"

    # Nothing owns it and there is no self/installer/manual path -> unknown.
    _NPM_LS=""; _BREW_CASK_LS=""; _UV_LS=""
    detect_method codex  __absent__; assert_eq "unknown"   "$DETECT_METHOD" "codex with empty caches -> unknown"
}

test_dry_run_changes_nothing() {
    local out rc
    out=$(bash "$SCRIPT_DIR/update_clis.sh" --dry-run 2>&1); rc=$?
    assert_eq "0" "$rc" "dry-run exits 0"
    assert_match "Dry-run complete" "$out" "dry-run prints completion line"
    local ran="no"; echo "$out" | grep -q "  running:" && ran="yes"
    assert_eq "no" "$ran" "dry-run never executes an update (no 'running:')"
}

test_only_filter() {
    local out
    out=$(bash "$SCRIPT_DIR/update_clis.sh" --dry-run --only MiniMax 2>&1)
    assert_match "MiniMax" "$out" "--only MiniMax matches by display name"
    local leaked="no"; echo "$out" | grep -qi "qwen" && leaked="yes"
    assert_eq "no" "$leaked" "--only limits output to the one CLI"

    bash "$SCRIPT_DIR/update_clis.sh" --dry-run --only nope_not_a_cli >/dev/null 2>&1
    assert_eq "2" "$?" "--only with no match exits 2"
}

run_test "meta table"                 test_meta
run_test "detect_method"              test_detect
run_test "dry-run changes nothing"    test_dry_run_changes_nothing
run_test "--only filter"              test_only_filter

test_summary "update_clis"
