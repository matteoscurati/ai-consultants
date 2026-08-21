#!/usr/bin/env bash
# Regression tests for synthesis input quality and detail preservation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_synthesize.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

test_synthesis_excludes_errors_and_keeps_fallback_detail() {
    local responses="$TMP_ROOT/responses" fake="$TMP_ROOT/claude"
    local prompt_file="$TMP_ROOT/prompt" output="$TMP_ROOT/synthesis.json"
    mkdir -p "$responses"

    printf '%s\n' '{"consultant":"Structured","model":"m","response":{"summary":"good","detailed":"GOOD_DETAIL_SENTINEL","approach":"structured","pros":[],"cons":[]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}' > "$responses/structured.json"
    printf '%s\n' '{"consultant":"Fallback","model":"m","response":{"summary":"fallback","detailed":"FALLBACK_DETAIL_SENTINEL","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5,"reasoning":"format"},"metadata":{"response_quality":"fallback"}}' > "$responses/fallback.json"
    printf '%s\n' '{"consultant":"Failed","model":"m","response":{"summary":"error","detailed":"ERROR_DETAIL_SENTINEL","approach":"error"},"confidence":{"score":0},"metadata":{"response_quality":"error","error":"boom"}}' > "$responses/error.json"

    printf '%s\n' \
        '#!/bin/bash' \
        'if [[ "${1:-}" == "--help" ]]; then printf "%s\n" "--print --no-session-persistence --setting-sources --tools"; exit 0; fi' \
        'if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf "%s\n" '"'"'{"loggedIn":true}'"'"'; exit 0; fi' \
        'prompt=$(cat)' \
        'printf "%s" "$prompt" > "$SYNTH_PROMPT_FILE"' \
        'printf "%s\n" '"'"'{"consultants_analyzed":2,"weighted_recommendation":{"summary":"ok"}}'"'"'' \
        > "$fake"
    chmod +x "$fake"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD=claude SYNTHESIS_CMD=claude \
        INVOKING_AGENT=unknown SYNTH_PROMPT_FILE="$prompt_file" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "synthesis fixture completes"
        return
    fi

    assert_eq 2 "$(jq -r '.consultants_analyzed' "$output")" \
        "synthesis counts only successful consultant envelopes"
    assert_eq claude "$(jq -r '.synthesis_provider' "$output")" \
        "successful synthesis records its provider"
    assert_match GOOD_DETAIL_SENTINEL "$(cat "$prompt_file")" \
        "structured response detail reaches synthesis"
    assert_match FALLBACK_DETAIL_SENTINEL "$(cat "$prompt_file")" \
        "valid unstructured provider detail reaches synthesis"
    assert_eq 0 "$(grep -c ERROR_DETAIL_SENTINEL "$prompt_file" || true)" \
        "error envelope is excluded from synthesis input"
}

test_synthesis_skips_unready_clis_and_uses_bounded_codex() {
    local responses="$TMP_ROOT/fallback-responses" output="$TMP_ROOT/codex-synthesis.json"
    local claude="$TMP_ROOT/claude" agy="$TMP_ROOT/agy" codex="$TMP_ROOT/codex"
    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"A","model":"m","response":{"summary":"a","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/a.json"

    cat > "$claude" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then printf '%s\n' '--print --no-session-persistence --setting-sources --tools'; exit 0; fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
cat >/dev/null
exit 42
EOF
    printf '%s\n' '#!/bin/bash' 'exit 1' > "$agy"
    cat > "$codex" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then printf '%s\n' 'codex test'; exit 0; fi
printf '%s\n' "$@" > "$CODEX_SYNTH_ARGS_FILE"
payload=""
previous=""
for arg in "$@"; do
  [[ "$previous" != "-o" ]] || payload="$arg"
  previous="$arg"
done
cat >/dev/null
printf '%s\n' '{"consultants_analyzed":1,"weighted_recommendation":{"summary":"codex"}}' > "$payload"
EOF
    chmod +x "$claude" "$agy" "$codex"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD=claude GEMINI_CMD=agy CODEX_CMD=codex \
        SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        CODEX_SYNTH_ARGS_FILE="$TMP_ROOT/codex-args" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "synthesis falls back to ready Codex"
        return
    fi

    assert_eq codex "$(jq -r '.weighted_recommendation.summary' "$output")" \
        "Codex payload becomes the synthesis"
    assert_eq codex "$(jq -r '.synthesis_provider' "$output")" \
        "runtime synthesis failure records the successful fallback provider"
    assert_match '(^|[[:space:]])exec($|[[:space:]])' "$(tr '\n' ' ' < "$TMP_ROOT/codex-args")" \
        "Codex synthesis uses non-interactive exec"
    assert_match 'read-only' "$(tr '\n' ' ' < "$TMP_ROOT/codex-args")" \
        "Codex synthesis is read-only"
    assert_match '--ephemeral' "$(tr '\n' ' ' < "$TMP_ROOT/codex-args")" \
        "Codex synthesis is ephemeral"
}

test_synthesis_with_no_ready_cli_uses_local_fallback() {
    local responses="$TMP_ROOT/no-cli-responses" output="$TMP_ROOT/local-fallback.json"
    local cmd
    mkdir -p "$responses" "$TMP_ROOT/no-cli-bin"
    printf '%s\n' '{"consultant":"A","model":"m","response":{"summary":"a","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/a.json"
    for cmd in claude agy codex; do
        printf '%s\n' '#!/bin/bash' 'exit 1' > "$TMP_ROOT/no-cli-bin/$cmd"
        chmod +x "$TMP_ROOT/no-cli-bin/$cmd"
    done

    if ! PATH="$TMP_ROOT/no-cli-bin:$PATH" CLAUDE_CMD=claude GEMINI_CMD=agy CODEX_CMD=codex \
        SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "local synthesis fallback completes with no ready CLI"
        return
    fi

    assert_eq local-fallback "$(jq -r '.synthesis_provider' "$output")" \
        "no-ready-CLI path records local fallback"
    assert_eq 1 "$(jq -r '.consultants_analyzed' "$output")" \
        "local fallback counts successful responses"
}

run_test "Synthesis filters errors and preserves usable detail" test_synthesis_excludes_errors_and_keeps_fallback_detail
run_test "Synthesis skips unready CLIs and uses bounded Codex" test_synthesis_skips_unready_clis_and_uses_bounded_codex
run_test "Synthesis with no ready CLI uses local fallback" test_synthesis_with_no_ready_cli_uses_local_fallback
test_summary "synthesize"
