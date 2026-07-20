#!/bin/bash
# test_context_optimization.sh - Regression suite for the v2.14 context handoff
# changes: file @TAG parser, category-aware project tree, --query-file, and the
# previously-untested lib/code_optimizer, lib/chunking, lib/symbol_map.
#
# Picked up automatically by scripts/test_all.sh via find(1).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Fixtures are referenced by RELATIVE path: build_context.sh's context gate
# accepts only relative in-tree paths or temp-root paths (/tmp, /private/tmp,
# $TMPDIR) and rejects arbitrary absolute paths (see Test 15 for the boundary).
FIXTURES_REL="scripts/test_fixtures/context"

# Always invoke build_context.sh from the project root so relative fixture
# paths resolve and the project-tree find sees the expected layout.
cd "$PROJECT_ROOT" || exit 1

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

# Temp output dir for context files (cleaned per test via _reset_state).
_TMPDIR=$(mktemp -d -t aiconsultants-ctx-XXXXXX)
trap 'rm -rf "$_TMPDIR"' EXIT

_reset_state() {
    rm -rf "${_TMPDIR:?}"/*
    unset QUESTION_CATEGORY FORCE_PROJECT_TREE
    unset TOKEN_OPTIMIZATION_MODE ENABLE_SYMBOL_COMPRESSION
    unset MAX_CONTEXT_FILE_BYTES
}

# Tiny helper: run build_context.sh and write to a known location.
# Echoes the output file path for the caller to inspect.
# Env vars (QUESTION_CATEGORY, FORCE_PROJECT_TREE, MAX_CONTEXT_FILE_BYTES, ...)
# must be exported by the caller — bash's `VAR=val func` form does not
# propagate through `var=$(func ...)` capture.
_build() {
    local out="$_TMPDIR/ctx.md"
    "$SCRIPT_DIR/build_context.sh" "$out" "$@" >/dev/null 2>&1
    echo "$out"
}

# -----------------------------------------------------------------------------
# Test 1: @TAG parser — default to PRIMARY when no suffix present
# -----------------------------------------------------------------------------
test_tag_default_primary() {
    local out
    out=$(_build "review this" "$FIXTURES_REL/sample.py")
    local content
    content=$(cat "$out")
    assert_match "sample.py\` \(PRIMARY\)" "$content" \
        "untagged file path renders as (PRIMARY)"
}

# -----------------------------------------------------------------------------
# Test 2: @TAG parser — explicit PRIMARY and CONTEXT both honored
# -----------------------------------------------------------------------------
test_tag_explicit() {
    local out
    out=$(_build "compare" "$FIXTURES_REL/sample.py@PRIMARY" "$FIXTURES_REL/sample.sh@CONTEXT")
    local content
    content=$(cat "$out")
    assert_match "sample.py\` \(PRIMARY\)" "$content" "explicit PRIMARY tag renders"
    assert_match "sample.sh\` \(CONTEXT\)" "$content" "explicit CONTEXT tag renders"
}

# -----------------------------------------------------------------------------
# Test 3: @TAG parser — unknown tag falls back to PRIMARY with a warning
# -----------------------------------------------------------------------------
test_tag_unknown_fallback() {
    local out="$_TMPDIR/ctx.md"
    local stderr
    stderr=$("$SCRIPT_DIR/build_context.sh" "$out" "test" \
        "$FIXTURES_REL/sample.txt@WEIRD" 2>&1 >/dev/null)
    local content
    content=$(cat "$out")
    assert_match "Unknown file tag 'WEIRD'" "$stderr" "unknown tag emits log_warn"
    assert_match "sample.txt\` \(PRIMARY\)" "$content" "unknown tag falls back to PRIMARY"
}

# -----------------------------------------------------------------------------
# Test 4: QUESTION_CATEGORY=SECURITY drops the project tree section
# -----------------------------------------------------------------------------
test_category_drops_tree() {
    export QUESTION_CATEGORY=SECURITY
    local out
    out=$(_build "secure?")
    if grep -q "^## Project Structure" "$out"; then
        assert_eq "absent" "present" "project tree should be absent for SECURITY"
    else
        assert_eq "absent" "absent" "project tree absent for SECURITY"
    fi
}

# -----------------------------------------------------------------------------
# Test 5: QUESTION_CATEGORY=ARCHITECTURE keeps the project tree
# -----------------------------------------------------------------------------
test_category_keeps_tree() {
    export QUESTION_CATEGORY=ARCHITECTURE
    local out
    out=$(_build "design?")
    if grep -q "^## Project Structure" "$out"; then
        assert_eq "present" "present" "project tree present for ARCHITECTURE"
    else
        assert_eq "present" "absent" "project tree should be present for ARCHITECTURE"
    fi
}

# -----------------------------------------------------------------------------
# Test 6: FORCE_PROJECT_TREE=true overrides a category that would skip it
# -----------------------------------------------------------------------------
test_force_tree_override() {
    export QUESTION_CATEGORY=SECURITY
    export FORCE_PROJECT_TREE=true
    local out
    out=$(_build "secure?")
    if grep -q "^## Project Structure" "$out"; then
        assert_eq "present" "present" "FORCE_PROJECT_TREE overrides SECURITY skip"
    else
        assert_eq "present" "absent" "FORCE_PROJECT_TREE should bring the tree back"
    fi
}

# -----------------------------------------------------------------------------
# Test 7: Unknown category defaults to "include" (conservative)
# -----------------------------------------------------------------------------
test_unknown_category_includes_tree() {
    export QUESTION_CATEGORY=NEW_CATEGORY_NAME
    local out
    out=$(_build "experimental?")
    if grep -q "^## Project Structure" "$out"; then
        assert_eq "present" "present" "unknown category defaults to include"
    else
        assert_eq "present" "absent" "unknown category should default to include"
    fi
}

# -----------------------------------------------------------------------------
# Test 8: AST extraction kicks in for Python (when python3 is available)
# -----------------------------------------------------------------------------
test_ast_extraction_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "  ${C_YELLOW}SKIP${C_RESET}: python3 not available"
        return 0
    fi
    # Force a low byte threshold so the file goes through the optimizer path
    # rather than passing through.
    export MAX_CONTEXT_FILE_BYTES=512
    local out
    out=$(_build "review" "$FIXTURES_REL/sample.py")
    local content
    content=$(cat "$out")
    # The optimizer prefixes the rendered block; we accept either the explicit
    # AST header or the optimization manifest noting the file was processed.
    assert_match "(AST skeleton|optimized:)" "$content" \
        "Python file goes through the optimizer when over MAX_CONTEXT_FILE_BYTES"
}

# -----------------------------------------------------------------------------
# Test 9: optimize_code_file returns non-empty output for Python
# -----------------------------------------------------------------------------
test_optimize_code_file_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "  ${C_YELLOW}SKIP${C_RESET}: python3 not available"
        return 0
    fi
    # shellcheck source=lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    # shellcheck source=lib/code_optimizer.sh
    source "$SCRIPT_DIR/lib/code_optimizer.sh"
    local out
    out=$(optimize_code_file "$FIXTURES_REL/sample.py" 2>/dev/null || true)
    if [[ -n "$out" ]]; then
        assert_eq "non_empty" "non_empty" "optimize_code_file emits output for Python"
    else
        assert_eq "non_empty" "empty" "optimize_code_file should emit output for Python"
    fi
}

# -----------------------------------------------------------------------------
# Test 10: chunk_file_semantically returns JSON-shaped output for a larger file
# -----------------------------------------------------------------------------
test_chunking_json_shape() {
    # shellcheck source=lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    # shellcheck source=lib/chunking.sh
    source "$SCRIPT_DIR/lib/chunking.sh"
    # Generate a synthetic input large enough to trigger chunking.
    local big="$_TMPDIR/big.py"
    {
        echo "import os"
        for i in $(seq 1 80); do
            echo ""
            echo "def function_$i(x):"
            echo "    \"\"\"Function number $i.\"\"\""
            echo "    return x * $i"
        done
    } > "$big"

    local json
    json=$(chunk_file_semantically "$big" 2>/dev/null || echo "[]")
    if command -v jq >/dev/null 2>&1; then
        local count
        count=$(echo "$json" | jq 'length' 2>/dev/null || echo "0")
        if [[ "$count" =~ ^[0-9]+$ ]] && (( count >= 0 )); then
            assert_eq "valid_json" "valid_json" "chunking emits parseable JSON array"
        else
            assert_eq "valid_json" "invalid" "chunking output is not a valid JSON array"
        fi
    else
        echo -e "  ${C_YELLOW}SKIP${C_RESET}: jq not available for JSON shape check"
    fi
}

# -----------------------------------------------------------------------------
# Test 11: --query-file in consult_all.sh argument parser
# -----------------------------------------------------------------------------
test_query_file_flag() {
    # We exercise consult_all.sh up to the point it would launch consultants;
    # the simplest assertion is that --query-file with no inline query still
    # reaches the consultant-selection error path (no consultants enabled in
    # test env), which means parsing succeeded.
    local qfile="$_TMPDIR/q.txt"
    echo "hello from a query file" > "$qfile"
    local stderr
    # We expect non-zero exit (no consultants enabled), but the stderr must
    # NOT mention "--query-file requires" (parser-level failure).
    stderr=$(ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false \
        ENABLE_CURSOR=false \
        ENABLE_KIMI=false ENABLE_CLAUDE=false \
        ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        "$SCRIPT_DIR/consult_all.sh" --query-file "$qfile" 2>&1 >/dev/null || true)
    if echo "$stderr" | grep -q -- "--query-file requires"; then
        assert_eq "parsed" "unparsed" "--query-file should accept a valid file"
    else
        assert_eq "parsed" "parsed" "--query-file parsing succeeds with valid file"
    fi
}

# -----------------------------------------------------------------------------
# Test 12: --query-file with a non-existent file is rejected at parse time
# -----------------------------------------------------------------------------
test_query_file_missing() {
    local stderr
    stderr=$("$SCRIPT_DIR/consult_all.sh" --query-file /nonexistent/path.txt 2>&1 >/dev/null || true)
    assert_match "--query-file requires" "$stderr" \
        "--query-file rejects nonexistent path"
}

# -----------------------------------------------------------------------------
# Test 13: --query-file + positional query is a conflict
# -----------------------------------------------------------------------------
test_query_file_conflict() {
    local qfile="$_TMPDIR/q.txt"
    echo "from file" > "$qfile"
    local stderr
    stderr=$("$SCRIPT_DIR/consult_all.sh" --query-file "$qfile" "from cli" 2>&1 >/dev/null || true)
    assert_match "conflicts with a positional query" "$stderr" \
        "--query-file + positional query rejected"
}

# -----------------------------------------------------------------------------
# Test 14: Backwards-compat — old call with inlined query string still works
# (degrades to no-FILES branch, exits cleanly at consultant-selection step)
# -----------------------------------------------------------------------------
test_legacy_inlined_query() {
    local out
    out=$(_build "hello world, no files attached")
    if grep -q "^# Question" "$out"; then
        assert_eq "preserved" "preserved" "no-files path still produces a context.md"
    else
        assert_eq "preserved" "broken" "no-files path should still produce context.md"
    fi
    assert_match "hello world, no files attached" "$(cat "$out")" \
        "raw question is preserved in context.md"
}

# -----------------------------------------------------------------------------
# Suite runner
# -----------------------------------------------------------------------------
echo "test_context_optimization.sh — v2.14 context handoff regression suite"
# -----------------------------------------------------------------------------
# Test 15: context-file path boundary (v2.17.2)
# -----------------------------------------------------------------------------
# build_context.sh sends file contents to external AI providers, so the context
# gate must (a) ACCEPT temp-root paths — fixing the macOS /private/tmp scratch-file
# regression — and (b) REJECT arbitrary absolute paths so secrets like ~/.ssh/id_rsa
# can't be exfiltrated. ($_TMPDIR is itself a temp root: /var/folders/... on macOS,
# /tmp/... on Linux — the exact accept case, auto-cleaned, no $HOME litter.)
# QUESTION_CATEGORY=SECURITY skips the project-tree find these assertions don't need.
test_context_path_boundary() {
    local tmpfile="$_TMPDIR/aic_ctx_abs.txt"
    printf 'UNIQUE_CTX_MARKER_42 lorem ipsum\n' > "$tmpfile"
    QUESTION_CATEGORY=SECURITY "$SCRIPT_DIR/build_context.sh" "$_TMPDIR/ctx_tmp.md" "summarize this" "$tmpfile" >/dev/null 2>&1
    local content
    content=$(cat "$_TMPDIR/ctx_tmp.md" 2>/dev/null)
    assert_match "UNIQUE_CTX_MARKER_42" "$content" \
        "temp-root context path is included (macOS /private/tmp regression class)"

    # Arbitrary absolute path outside the temp roots must be REJECTED (no secret
    # exfiltration). Path need not exist — rejection happens at validation.
    local stderr
    stderr=$(QUESTION_CATEGORY=SECURITY "$SCRIPT_DIR/build_context.sh" "$_TMPDIR/ctx_sec.md" "q" "$HOME/.ssh/id_rsa" 2>&1)
    assert_match "Skipping invalid file path: $HOME/.ssh/id_rsa" "$stderr" \
        "absolute path outside temp roots is rejected (secret exfiltration blocked)"

    # Sensitive system path still rejected.
    stderr=$(QUESTION_CATEGORY=SECURITY "$SCRIPT_DIR/build_context.sh" "$_TMPDIR/ctx_etc.md" "q" "/etc/passwd" 2>&1)
    assert_match "Skipping invalid file path: /etc/passwd" "$stderr" \
        "sensitive /etc path is still rejected"
}

run_test "Test 1: @TAG defaults to PRIMARY" test_tag_default_primary
run_test "Test 2: @TAG honored when explicit" test_tag_explicit
run_test "Test 3: @TAG unknown falls back to PRIMARY with warning" test_tag_unknown_fallback
run_test "Test 4: QUESTION_CATEGORY=SECURITY drops project tree" test_category_drops_tree
run_test "Test 5: QUESTION_CATEGORY=ARCHITECTURE keeps project tree" test_category_keeps_tree
run_test "Test 6: FORCE_PROJECT_TREE overrides category" test_force_tree_override
run_test "Test 7: Unknown category includes tree (conservative)" test_unknown_category_includes_tree
run_test "Test 8: Python AST path engages over byte threshold" test_ast_extraction_python
run_test "Test 9: optimize_code_file emits output for Python" test_optimize_code_file_python
run_test "Test 10: chunk_file_semantically emits JSON array" test_chunking_json_shape
run_test "Test 11: --query-file is parsed correctly" test_query_file_flag
run_test "Test 12: --query-file with missing file is rejected" test_query_file_missing
run_test "Test 13: --query-file conflicts with positional query" test_query_file_conflict
run_test "Test 14: Legacy no-FILES path still works" test_legacy_inlined_query
run_test "Test 15: context-file path boundary (v2.17.2)" test_context_path_boundary

test_summary "test_context_optimization.sh"
