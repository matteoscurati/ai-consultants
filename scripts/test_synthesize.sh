#!/usr/bin/env bash
# Regression tests for synthesis input quality and detail preservation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_synthesize.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

run_integrity_fixture() {
    local case_name="$1" payload="$2" strategy="${3:-coverage}" include_fallback="${4:-true}"
    local responses="$TMP_ROOT/integrity-$case_name-responses"
    local output="$TMP_ROOT/integrity-$case_name.json"
    local fake="$TMP_ROOT/integrity-$case_name-claude"

    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"Structured","model":"m","response":{"summary":"summary point","detailed":"detail","approach":"structured","pros":["pro point"],"cons":[]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}' > "$responses/structured.json"
    if [[ "$include_fallback" == "true" ]]; then
        printf '%s\n' '{"consultant":"Fallback","model":"m","response":{"summary":"fallback","detailed":"fallback prose","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5,"reasoning":"format"},"metadata":{"response_quality":"fallback"}}' > "$responses/fallback.json"
    fi

    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then printf '%s\n' '--print --no-session-persistence --setting-sources --tools'; exit 0; fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
cat >/dev/null
printf '%s\n' "$SYNTH_RESULT"
EOF
    chmod +x "$fake"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude \
        INVOKING_AGENT=unknown SYNTHESIS_STRATEGY="$strategy" SYNTH_RESULT="$payload" \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "integrity fixture $case_name completes"
    fi
    printf '%s' "$output"
}

test_coverage_integrity_normalizes_and_enforces_source_ids() {
    local output
    output=$(run_integrity_fixture met '{"coverage":[{"point":"summary","source_ids":["structured:1"]},{"point":"pro","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok","detailed":"ok"}}' coverage false)

    assert_eq "structured:1,structured:2" "$(jq -r '[.response.findings[].id] | join(",")' "$TMP_ROOT/integrity-met-responses/structured.json")" \
        "normalization assigns deterministic local IDs"
    assert_eq "" "$(jq -r '.response.findings[] | select(.id == "provider:9") | .id' "$TMP_ROOT/integrity-met-responses/structured.json")" \
        "provider IDs are not trusted"
    assert_eq MET "$(jq -r '.coverage_integrity.status' "$output")" \
        "complete structured union meets integrity"
    assert_eq 2 "$(jq -r '.coverage_integrity.expected_count' "$output")" \
        "integrity counts normalized expected IDs"
    assert_eq 2 "$(jq -r '.coverage_integrity.represented_count' "$output")" \
        "integrity counts represented expected IDs"
    assert_eq "summary point" "$(jq -r '.response.summary' "$TMP_ROOT/integrity-met-responses/structured.json")" \
        "legacy response fields are preserved"

    output=$(run_integrity_fixture mixed '{"coverage":[{"point":"summary","source_ids":["structured:1"]},{"point":"pro","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok"}}')
    assert_eq 0 "$(jq -r '.response.findings | length' "$TMP_ROOT/integrity-mixed-responses/fallback.json")" \
        "fallback prose is not atomically normalized"
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "mixed structured and fallback responses degrade coverage"
    assert_eq Fallback "$(jq -r '.coverage_integrity.non_normalizable_consultants | join(",")' "$output")" \
        "fallback consultant is exposed as non-normalizable"

    output=$(run_integrity_fixture omitted '{"coverage":[{"point":"only one","source_ids":["structured:1"]}],"weighted_recommendation":{"summary":"comprehensive result","detailed":"comprehensive detail"}}')
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "omitted expected ID degrades coverage"
    assert_eq structured:2 "$(jq -r '.coverage_integrity.missing_ids | join(",")' "$output")" \
        "omitted ID is exposed"
    assert_not_contains comprehensive "$(jq -r '.weighted_recommendation.summary' "$output")" \
        "incomplete union cannot retain a comprehensive claim"

    output=$(run_integrity_fixture duplicate '{"coverage":[{"point":"one","source_ids":["structured:1"]},{"point":"again","source_ids":["structured:1","structured:2"]}],"weighted_recommendation":{"summary":"ok"}}')
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "duplicate representation degrades coverage"
    assert_eq structured:1 "$(jq -r '.coverage_integrity.duplicate_ids | join(",")' "$output")" \
        "duplicate ID is exposed"

    output=$(run_integrity_fixture unknown '{"coverage":[{"point":"one","source_ids":["structured:1","invented:9"]},{"point":"two","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok"}}')
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "invented source ID fails closed"
    assert_eq invented:9 "$(jq -r '.coverage_integrity.unknown_ids | join(",")' "$output")" \
        "invented source ID is exposed"
    assert_eq 0 "$(jq -r '[.coverage[].source_ids[] | select(. == "invented:9")] | length' "$output")" \
        "emitted coverage retains only expected local source IDs"

    output=$(run_integrity_fixture invalid '{"coverage":"not-an-array","weighted_recommendation":{"summary":"comprehensive"}}')
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "invalid synthesis coverage fails closed"
    assert_gt 0 "$(jq -r '.coverage_integrity.structural_errors | length' "$output")" \
        "invalid synthesis explains structural failure"
    assert_eq 0 "$(jq -r '.coverage | length' "$output")" \
        "invalid coverage is not published as a source-attributed item"

    output=$(run_integrity_fixture noncoverage '{"coverage":[{"point":"one","source_ids":["structured:1"]},{"point":"two","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok"}}' security_first)
    assert_eq security_first "$(jq -r '.strategy' "$output")" \
        "non-coverage strategy is preserved"
    assert_eq NOT_APPLICABLE "$(jq -r '.coverage_integrity.status' "$output")" \
        "non-coverage strategy makes no coverage-union claim"
}

test_report_renders_coverage_integrity_status() {
    local run_out output_dir report
    run_out=$(HOME="$TMP_ROOT/report-home" \
        XDG_CACHE_HOME="$TMP_ROOT/report-xdg/cache" \
        XDG_STATE_HOME="$TMP_ROOT/report-xdg/state" \
        XDG_DATA_HOME="$TMP_ROOT/report-xdg/data" \
        INVOKING_AGENT=none \
        ENABLE_CLAUDE=true ENABLE_CODEX=true ENABLE_GEMINI=false ENABLE_MISTRAL=false \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CLAUDE_CMD="$SCRIPT_DIR/test_fixtures/stub_cli.sh" CODEX_CMD="$SCRIPT_DIR/test_fixtures/stub_cli.sh" \
        ENABLE_SEMANTIC_CACHE=false ENABLE_SYNTHESIS=true ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false SYNTHESIS_CMD=claude \
        "$SCRIPT_DIR/consult_all.sh" "Render coverage integrity" 2>/dev/null)
    output_dir=$(printf '%s\n' "$run_out" | tail -n 1)
    report="$output_dir/report.md"

    assert_eq 1 "$([[ -f "$report" ]] && echo 1 || echo 0)" \
        "report is produced with synthesis enabled"
    assert_contains "**Coverage Integrity**: FAILED" "$(cat "$report" 2>/dev/null)" \
        "report renders the locally enforced integrity status"
    assert_contains "Coverage attribution is unusable" "$(cat "$report" 2>/dev/null)" \
        "report renders the integrity disclosure"
}

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
run_test "Coverage integrity normalizes and audits local source IDs" test_coverage_integrity_normalizes_and_enforces_source_ids
run_test "Report renders coverage integrity status" test_report_renders_coverage_integrity_status
run_test "Synthesis skips unready CLIs and uses bounded Codex" test_synthesis_skips_unready_clis_and_uses_bounded_codex
run_test "Synthesis with no ready CLI uses local fallback" test_synthesis_with_no_ready_cli_uses_local_fallback
run_test "Claude invoker never uses Claude for synthesis" test_claude_invoker_never_uses_claude_for_synthesis
run_test "Codex invoker never uses Codex for synthesis" test_codex_invoker_never_uses_codex_for_synthesis
run_test "Gemini invoker never uses Gemini for synthesis" test_gemini_invoker_never_uses_gemini_for_synthesis
test_summary "synthesize"
