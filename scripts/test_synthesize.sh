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
    assert_match '"coverage"' "$(cat "$prompt_file")" \
        "live synthesis prompt requests the coverage union"
    assert_eq 0 "$(grep -cE '"consensus"|debate_evolution|comparison_table' "$prompt_file" || true)" \
        "live synthesis prompt excludes removed consensus and debate fields"
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
        SYNTHESIS_CMD=claude SYNTHESIS_STRATEGY=security_first INVOKING_AGENT=unknown \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "local synthesis fallback completes with no ready CLI"
        return
    fi

    assert_eq local-fallback "$(jq -r '.synthesis_provider' "$output")" \
        "no-ready-CLI path records local fallback"
    assert_eq 1 "$(jq -r '.consultants_analyzed' "$output")" \
        "local fallback counts successful responses"
    assert_eq security_first "$(jq -r '.strategy' "$output")" \
        "local fallback reports the requested strategy"
    assert_eq false "$(jq -r 'has("consensus") or has("debate_evolution")' "$output")" \
        "local fallback excludes removed consensus and debate fields"
}

test_claude_invoker_never_uses_claude_for_synthesis() {
    local responses="$TMP_ROOT/claude-invoker-responses" output="$TMP_ROOT/claude-invoker-synthesis.json"
    local claude="$TMP_ROOT/claude" agy="$TMP_ROOT/agy" codex="$TMP_ROOT/codex"
    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"Codex","model":"m","response":{"summary":"a","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/codex.json"

    cat > "$claude" <<'EOF'
#!/bin/bash
touch "$CLAUDE_SYNTH_CALLED"
exit 97
EOF
    printf '%s\n' '#!/bin/bash' 'exit 1' > "$agy"
    cat > "$codex" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then printf '%s\n' 'codex test'; exit 0; fi
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
        SYNTHESIS_CMD=claude INVOKING_AGENT=claude \
        CLAUDE_SYNTH_CALLED="$TMP_ROOT/claude-synthesis-called" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "Claude-invoked synthesis falls back to a non-Claude provider"
        return
    fi

    assert_eq codex "$(jq -r '.synthesis_provider' "$output")" \
        "Claude invoker uses Codex for synthesis"
    assert_eq "0" "$([[ -e "$TMP_ROOT/claude-synthesis-called" ]] && echo 1 || echo 0)" \
        "Claude synthesis CLI is never invoked by a Claude host"
}

test_codex_invoker_never_uses_codex_for_synthesis() {
    local responses="$TMP_ROOT/codex-invoker-responses" output="$TMP_ROOT/codex-invoker-synthesis.json"
    local codex="$TMP_ROOT/codex-self" agy="$TMP_ROOT/agy-for-codex-host"
    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"Gemini","model":"m","response":{"summary":"a","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/gemini.json"

    cat > "$codex" <<'EOF'
#!/bin/bash
touch "$CODEX_SYNTH_CALLED"
exit 97
EOF
    cat > "$agy" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "models" ]]; then printf '%s\n' 'Gemini 3.7 Flash (High)'; exit 0; fi
printf '%s\n' '{"consultants_analyzed":1,"weighted_recommendation":{"summary":"gemini"}}'
EOF
    chmod +x "$codex" "$agy"

    if ! PATH="$TMP_ROOT:$PATH" CODEX_CMD="$codex" GEMINI_CMD="$agy" \
        SYNTHESIS_CMD=codex INVOKING_AGENT=codex \
        CODEX_SYNTH_CALLED="$TMP_ROOT/codex-synthesis-called" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "Codex-invoked synthesis falls back to a non-Codex provider"
        return
    fi

    assert_eq gemini "$(jq -r '.synthesis_provider' "$output")" \
        "Codex invoker uses Gemini for synthesis"
    assert_eq "0" "$([[ -e "$TMP_ROOT/codex-synthesis-called" ]] && echo 1 || echo 0)" \
        "Codex synthesis CLI is never invoked by a Codex host"
}

test_gemini_invoker_never_uses_gemini_for_synthesis() {
    local responses="$TMP_ROOT/gemini-invoker-responses" output="$TMP_ROOT/gemini-invoker-synthesis.json"
    local agy="$TMP_ROOT/agy-self" codex="$TMP_ROOT/codex-for-gemini-host"
    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"Codex","model":"m","response":{"summary":"a","detailed":"detail","approach":"x"},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/codex.json"

    cat > "$agy" <<'EOF'
#!/bin/bash
touch "$GEMINI_SYNTH_CALLED"
exit 97
EOF
    cat > "$codex" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then printf '%s\n' 'codex test'; exit 0; fi
payload=""
previous=""
for arg in "$@"; do
  [[ "$previous" != "-o" ]] || payload="$arg"
  previous="$arg"
done
cat >/dev/null
printf '%s\n' '{"consultants_analyzed":1,"weighted_recommendation":{"summary":"codex"}}' > "$payload"
EOF
    chmod +x "$agy" "$codex"

    if ! PATH="$TMP_ROOT:$PATH" GEMINI_CMD="$agy" CODEX_CMD="$codex" \
        SYNTHESIS_CMD=gemini INVOKING_AGENT=gemini \
        GEMINI_SYNTH_CALLED="$TMP_ROOT/gemini-synthesis-called" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "Gemini-invoked synthesis falls back to a non-Gemini provider"
        return
    fi

    assert_eq codex "$(jq -r '.synthesis_provider' "$output")" \
        "Gemini invoker uses Codex for synthesis"
    assert_eq "0" "$([[ -e "$TMP_ROOT/gemini-synthesis-called" ]] && echo 1 || echo 0)" \
        "Gemini synthesis CLI is never invoked by a Gemini host"
}

run_test "Synthesis filters errors and preserves usable detail" test_synthesis_excludes_errors_and_keeps_fallback_detail
run_test "Synthesis skips unready CLIs and uses bounded Codex" test_synthesis_skips_unready_clis_and_uses_bounded_codex
run_test "Synthesis with no ready CLI uses local fallback" test_synthesis_with_no_ready_cli_uses_local_fallback
run_test "Claude invoker never uses Claude for synthesis" test_claude_invoker_never_uses_claude_for_synthesis
run_test "Codex invoker never uses Codex for synthesis" test_codex_invoker_never_uses_codex_for_synthesis
run_test "Gemini invoker never uses Gemini for synthesis" test_gemini_invoker_never_uses_gemini_for_synthesis
test_summary "synthesize"
