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
    printf '%s\n' '{"consultant":"Structured","model":"m","response":{"summary":"summary point","detailed":"detail","approach":"structured","pros":["pro point"],"cons":[],"findings":[{"id":"provider:9","kind":"evil","field":"evil","text":"MALICIOUS_PROVIDER_FINDING"},{"id":"provider:9","kind":"evil","field":"evil","text":"DUPLICATE_PROVIDER_FINDING"}]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}' > "$responses/structured.json"
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

run_custom_integrity_fixture() {
    local case_name="$1" payload="$2" strategy="${3:-coverage}"
    shift 3
    local responses="$TMP_ROOT/custom-$case_name-responses" output="$TMP_ROOT/custom-$case_name.json"
    local fake="$TMP_ROOT/custom-$case_name-claude" response_json index=0
    mkdir -p "$responses"
    for response_json in "$@"; do
        index=$((index + 1))
        printf '%s\n' "$response_json" > "$responses/response-$index.json"
    done
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
        assert_eq success failure "custom integrity fixture $case_name completes"
    fi
    printf '%s' "$output"
}

test_coverage_integrity_normalizes_and_enforces_source_ids() {
    local output
    output=$(run_integrity_fixture met '{"coverage":[{"point":"summary","source_ids":["structured:1"]},{"point":"pro","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok","detailed":"ok"}}' coverage false)

    assert_eq "structured:1,structured:2" "$(jq -r '[.response.findings[].id] | join(",")' "$TMP_ROOT/integrity-met-responses/structured.json")" \
        "normalization assigns deterministic local IDs"
    assert_eq "" "$(jq -r '.response.findings[] | select((.id == "provider:9") or (.text | test("PROVIDER_FINDING"))) | .id' "$TMP_ROOT/integrity-met-responses/structured.json")" \
        "provider IDs and malicious provider finding text are overwritten"
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

    output=$(run_integrity_fixture omitted '{"coverage":[{"point":"only one","source_ids":["structured:1"]}],"weighted_recommendation":{"summary":"comprehensive result but not comprehensive","detailed":"comprehensive detail"}}')
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "omitted expected ID degrades coverage"
    assert_eq structured:2 "$(jq -r '.coverage_integrity.missing_ids | join(",")' "$output")" \
        "omitted ID is exposed"
    assert_contains partial "$(jq -r '.weighted_recommendation.summary' "$output")" \
        "incomplete union cannot retain a positive comprehensive claim"
    assert_contains "not comprehensive" "$(jq -r '.weighted_recommendation.summary' "$output")" \
        "negated comprehensive wording remains intact"

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

    output=$(run_integrity_fixture noncoverage '{"strategy":"coverage","coverage":[{"point":"one","source_ids":["structured:1"]},{"point":"two","source_ids":["structured:2"]}],"weighted_recommendation":{"summary":"ok"}}' security_first)
    assert_eq security_first "$(jq -r '.strategy' "$output")" \
        "non-coverage strategy is preserved"
    assert_eq NOT_APPLICABLE "$(jq -r '.coverage_integrity.status' "$output")" \
        "non-coverage strategy makes no coverage-union claim"
}

test_coverage_integrity_edge_contracts() {
    local output zero_response good_response custom_response scale_response scale_coverage duplicate_coverage
    zero_response='{"consultant":"Zero","model":"m","response":{"summary":" ","detailed":"ZERO_DETAIL_ONLY","approach":"structured","pros":[],"cons":[],"alternatives":[null," ",{}]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}'
    good_response='{"consultant":"Good","model":"m","response":{"summary":"good","detailed":"detail","approach":"structured","pros":[],"cons":[]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}'

    output=$(run_custom_integrity_fixture empty-source '{"coverage":[{"point":"good","source_ids":["good:1"]},{"point":"bad","source_ids":[]}]}' coverage "$good_response")
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "empty source_ids fails closed even when all expected IDs are otherwise represented"
    assert_eq 0 "$(jq -r '.coverage | length' "$output")" \
        "empty source_ids item is not published"

    output=$(run_custom_integrity_fixture all-zero '{"coverage":[],"weighted_recommendation":{"summary":"comprehensive"}}' coverage "$zero_response")
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "all-zero successful response cannot produce MET 0/0"
    assert_eq Zero "$(jq -r '.coverage_integrity.non_normalizable_consultants | join(",")' "$output")" \
        "zero-finding structured response is recorded as non-normalizable"

    output=$(run_custom_integrity_fixture mixed-zero '{"coverage":[{"point":"good","source_ids":["good:1"]}]}' coverage "$good_response" "$zero_response")
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "mixed zero-finding response degrades a complete represented union"

    custom_response='{"consultant":"My_agent","model":"m","response":{"summary":"custom summary","detailed":"detail","approach":"structured","pros":[],"cons":[],"alternatives":[null,"   ",{}, {"name":" ","reason_not_chosen":" "}, "plain alternative", {"name":"Named","reason_not_chosen":"reason"}]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}'
    output=$(run_custom_integrity_fixture custom-alternatives '{"coverage":[{"point":"summary","source_ids":["my_agent:1"]},{"point":"plain","source_ids":["my_agent:2"]},{"point":"named","source_ids":["my_agent:3"]}]}' coverage "$custom_response")
    assert_eq "my_agent:1,my_agent:2,my_agent:3" "$(jq -r '[.response.findings[].id] | join(",")' "$TMP_ROOT/custom-custom-alternatives-responses/response-1.json")" \
        "custom underscore consultant uses the shared deterministic slug"
    assert_eq "plain alternative,Named: reason" "$(jq -r '[.response.findings[] | select(.field == "alternatives") | .text] | join(",")' "$TMP_ROOT/custom-custom-alternatives-responses/response-1.json")" \
        "only meaningful string/object alternatives become findings"
    assert_eq MET "$(jq -r '.coverage_integrity.status' "$output")" \
        "custom slug IDs validate end-to-end"

    output=$(run_custom_integrity_fixture array-top-level '[]' coverage "$good_response")
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "array synthesis output is replaced by a failed-closed artifact"
    assert_eq coverage "$(jq -r '.strategy' "$output")" \
        "array synthesis artifact pins the local strategy"
    output=$(run_custom_integrity_fixture null-top-level 'null' coverage "$good_response")
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "null synthesis output is replaced by a failed-closed artifact"
    output=$(run_custom_integrity_fixture boolean-top-level 'false' coverage "$good_response")
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$output")" \
        "boolean non-object synthesis output is replaced by a failed-closed artifact"

    scale_response=$(jq -cn '{consultant:"Scale",model:"m",response:{summary:"summary",detailed:"detail",approach:"structured",pros:[range(1;21) | ("pro-" + tostring)],cons:[]},confidence:{score:8,reasoning:"ok"},metadata:{response_quality:"structured"}}')
    scale_coverage=$(jq -cn '[range(1;22) | {point:("p" + tostring),source_ids:[("scale:" + tostring)]}]')
    output=$(run_custom_integrity_fixture scale-met "{\"coverage\":$scale_coverage}" coverage "$scale_response")
    assert_eq MET "$(jq -r '.coverage_integrity.status' "$output")" \
        "twenty-plus expected IDs can meet integrity"
    assert_eq 21 "$(jq -r '.coverage_integrity.expected_count' "$output")" \
        "twenty-plus expected IDs are counted exactly"
    assert_eq 21 "$(jq -r '.coverage_integrity.represented_count' "$output")" \
        "twenty-plus represented IDs are counted uniquely"
    duplicate_coverage=$(jq -cn --argjson coverage "$scale_coverage" '$coverage + [{point:"duplicate",source_ids:["scale:1"]}]')
    output=$(run_custom_integrity_fixture scale-duplicate "{\"coverage\":$duplicate_coverage}" coverage "$scale_response")
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "duplicate detection remains correct beyond two source IDs"
    assert_eq scale:1 "$(jq -r '.coverage_integrity.duplicate_ids | join(",")' "$output")" \
        "large fixture exposes the duplicate ID"
}

test_report_renders_coverage_integrity_status() {
    local run_out output_dir report zero_cli
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
    assert_contains "**Audited Fields**:" "$(cat "$report" 2>/dev/null)" \
        "report qualifies coverage integrity with its audited fields"

    zero_cli="$TMP_ROOT/zero-report-cli"
    cat > "$zero_cli" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then printf '%s\n' '--print --model --output-format --no-session-persistence --setting-sources --tools --strict-mcp-config --mcp-config --permission-mode --prompt --output --agent --workdir --max-turns' '  auth status' 'builtin: default, plan' 'VIBE_*'; exit 0; fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
for arg in "$@"; do
  if [[ "$arg" == "--output-format" || "$arg" == "--output" ]]; then
    printf '%s\n' '{"consultant":"Zero","model":"m","response":{"summary":" ","detailed":"detail","approach":"structured","pros":[],"cons":[]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}'
    exit 0
  fi
done
cat >/dev/null
printf '%s\n' '{"coverage":[],"weighted_recommendation":{"summary":"manual"}}'
EOF
    chmod +x "$zero_cli"
    run_out=$(HOME="$TMP_ROOT/zero-report-home" XDG_CACHE_HOME="$TMP_ROOT/zero-report-cache" \
        XDG_STATE_HOME="$TMP_ROOT/zero-report-state" XDG_DATA_HOME="$TMP_ROOT/zero-report-data" \
        INVOKING_AGENT=none ENABLE_CLAUDE=true ENABLE_CODEX=false ENABLE_GEMINI=false ENABLE_MISTRAL=true \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CLAUDE_CMD="$zero_cli" MISTRAL_CMD="$zero_cli" ENABLE_SEMANTIC_CACHE=false ENABLE_SYNTHESIS=true \
        ENABLE_SMART_ROUTING=false ENABLE_HEALTH_GATE=false SYNTHESIS_CMD=claude SYNTH_DETAIL_MAX_CHARS=1 \
        "$SCRIPT_DIR/consult_all.sh" "Render zero coverage integrity" 2>/dev/null)
    output_dir=$(printf '%s\n' "$run_out" | tail -n 1)
    report="$output_dir/report.md"
    assert_contains "**Coverage Integrity**: DEGRADED" "$(cat "$report" 2>/dev/null)" \
        "report exposes all-zero non-normalizable coverage as degraded"
    assert_contains "**Coverage Input Truncated**: true" "$(cat "$report" 2>/dev/null)" \
        "report renders the locally authoritative truncation flag"
    assert_contains "**Truncated Consultants**: Mistral" "$(cat "$report" 2>/dev/null)" \
        "report renders the affected consultant list"
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
    assert_not_contains GOOD_DETAIL_SENTINEL "$(cat "$prompt_file")" \
        "coverage prompt excludes unaudited structured detail"
    assert_match FALLBACK_DETAIL_SENTINEL "$(cat "$prompt_file")" \
        "fallback prose remains visible only as context"
    assert_contains "Context-only fallback prose" "$(cat "$prompt_file")" \
        "prompt labels fallback prose as non-attributable context"
    assert_eq 0 "$(grep -c ERROR_DETAIL_SENTINEL "$prompt_file" || true)" \
        "error envelope is excluded from synthesis input"
    assert_match '"coverage"' "$(cat "$prompt_file")" \
        "live synthesis prompt requests the coverage union"
    assert_eq 0 "$(grep -cE '"consensus"|debate_evolution|comparison_table' "$prompt_file" || true)" \
        "live synthesis prompt excludes removed consensus and debate fields"
}

test_synthesis_truncation_is_explicit_and_atomic_findings_are_complete() {
    local responses="$TMP_ROOT/truncation-responses" output="$TMP_ROOT/truncation.json"
    local prompt_file="$TMP_ROOT/truncation-prompt" fake="$TMP_ROOT/truncation-claude"
    local clean_responses="$TMP_ROOT/truncation-clean-responses" clean_output="$TMP_ROOT/truncation-clean.json"
    local failed_output="$TMP_ROOT/truncation-failed.json" noncoverage_output="$TMP_ROOT/truncation-noncoverage.json"
    local portable_record
    mkdir -p "$responses" "$clean_responses"

    # This is the exact jq-1.6-compatible primitive used by synthesize.sh.
    # Keep it explicit so a parser/runtime incompatibility cannot silently turn
    # fallback input into a missing artifact.
    if ! portable_record=$(jq -nr --arg detail 'éxZ' --argjson limit 2 '
        ($detail) as $detail
        | {text: $detail[0:$limit], truncated: (($detail | length) > $limit)}
        | [.text, (.truncated | tostring)] | join(",")
    '); then
        assert_eq success failure "jq portable Unicode truncation primitive runs"
        return
    fi
    assert_eq 'éx,true' "$portable_record" \
        "jq portable Unicode truncation primitive keeps whole code points and detects overflow"

    # Filename order is deliberate: the public list keeps first occurrence
    # order while remaining reproducible across filesystems.
    printf '%s\n' '{"consultant":"Zulu","model":"m","response":{"summary":"fallback","detailed":"éxZ","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5},"metadata":{"response_quality":"fallback"}}' > "$responses/01-zulu.json"
    printf '%s\n' '{"consultant":"Alpha","model":"m","response":{"summary":"fallback","detailed":"abc","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5},"metadata":{"response_quality":"fallback"}}' > "$responses/02-alpha.json"
    printf '%s\n' '{"consultant":"Zulu","model":"m","response":{"summary":"fallback","detailed":"123","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5},"metadata":{"response_quality":"fallback"}}' > "$responses/03-zulu-again.json"
    printf '%s\n' '{"consultant":"Structured","model":"m","response":{"summary":"ATOMIC_FINDING_LONGER_THAN_LIMIT","detailed":"structured detail","approach":"structured","pros":[],"cons":[]},"confidence":{"score":8},"metadata":{"response_quality":"structured"}}' > "$responses/04-structured.json"
    printf '%s\n' '{"consultant":"Short","model":"m","response":{"summary":"fallback","detailed":"é","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5},"metadata":{"response_quality":"fallback"}}' > "$clean_responses/01-short.json"
    printf '%s\n' '{"consultant":"Exact","model":"m","response":{"summary":"fallback","detailed":"éx","approach":"unstructured-provider-response","pros":[],"cons":[]},"confidence":{"score":5},"metadata":{"response_quality":"fallback"}}' > "$clean_responses/02-exact.json"

    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then printf '%s\n' '--print --no-session-persistence --setting-sources --tools'; exit 0; fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
prompt=$(cat)
printf '%s' "$prompt" > "$SYNTH_PROMPT_FILE"
printf '%s\n' "$SYNTH_RESULT"
EOF
    chmod +x "$fake"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        SYNTH_DETAIL_MAX_CHARS=2 SYNTH_PROMPT_FILE="$prompt_file" \
        SYNTH_RESULT='{"coverage":[{"point":"atomic","source_ids":["structured:1"]}],"weighted_recommendation":{"summary":"comprehensive synthesis","detailed":"comprehensive details"},"coverage_input_truncated":false,"truncated_consultants":["Forged"]}' \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "truncation fixture completes"
        return
    fi

    assert_contains ATOMIC_FINDING_LONGER_THAN_LIMIT "$(cat "$prompt_file")" \
        "atomic normalized finding longer than the fallback limit reaches the prompt intact"
    assert_contains $'\néx\n---' "$(cat "$prompt_file")" \
        "over-limit fallback text is shortened once at a Unicode-code-point boundary"
    assert_not_contains éxZ "$(cat "$prompt_file")" \
        "over-limit fallback suffix is absent from the prompt"
    assert_eq true "$(jq -r '.coverage_input_truncated' "$output")" \
        "local truncation flag overwrites model-supplied metadata"
    assert_eq 'Zulu,Alpha' "$(jq -r '.truncated_consultants | join(",")' "$output")" \
        "truncated consultants are first-occurrence unique and stable"
    assert_eq DEGRADED "$(jq -r '.coverage_integrity.status' "$output")" \
        "truncated non-normalizable context degrades coverage union"
    assert_contains 'truncated at the configured Unicode-code-point limit' "$(jq -r '.coverage_integrity.disclosure' "$output")" \
        "coverage disclosure names the local truncation condition"
    assert_not_contains comprehensive "$(jq -r '.weighted_recommendation.summary + " " + .weighted_recommendation.detailed' "$output")" \
        "truncated coverage cannot retain positive comprehensive wording"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        SYNTH_DETAIL_MAX_CHARS=2 SYNTH_PROMPT_FILE="$TMP_ROOT/truncation-clean-prompt" \
        SYNTH_RESULT='{"coverage":[],"weighted_recommendation":{"summary":"manual"}}' \
        "$SCRIPT_DIR/synthesize.sh" "$clean_responses" "$clean_output" test >/dev/null 2>&1; then
        assert_eq success failure "short and exact-boundary fixture completes"
        return
    fi
    assert_eq false "$(jq -r '.coverage_input_truncated' "$clean_output")" \
        "short and exact Unicode-code-point boundary fallback text is not flagged"
    assert_eq 0 "$(jq -r '.truncated_consultants | length' "$clean_output")" \
        "untruncated fallback input has no affected consultants"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        SYNTH_DETAIL_MAX_CHARS=2 SYNTH_PROMPT_FILE="$TMP_ROOT/truncation-failed-prompt" \
        SYNTH_RESULT='[]' "$SCRIPT_DIR/synthesize.sh" "$responses" "$failed_output" test >/dev/null 2>&1; then
        assert_eq success failure "failed-closed truncation fixture completes"
        return
    fi
    assert_eq FAILED "$(jq -r '.coverage_integrity.status' "$failed_output")" \
        "failed-closed synthesis artifact preserves integrity failure"
    assert_eq true "$(jq -r '.coverage_input_truncated' "$failed_output")" \
        "failed-closed synthesis artifact retains truncation metadata"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        SYNTHESIS_STRATEGY=security_first SYNTH_DETAIL_MAX_CHARS=2 SYNTH_PROMPT_FILE="$TMP_ROOT/truncation-noncoverage-prompt" \
        SYNTH_RESULT='{"coverage":[{"point":"atomic","source_ids":["structured:1"]}],"weighted_recommendation":{"summary":"comprehensive synthesis"}}' \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$noncoverage_output" test >/dev/null 2>&1; then
        assert_eq success failure "non-coverage truncation fixture completes"
        return
    fi
    assert_eq NOT_APPLICABLE "$(jq -r '.coverage_integrity.status' "$noncoverage_output")" \
        "non-coverage strategy remains explicitly not applicable"
    assert_eq true "$(jq -r '.coverage_input_truncated' "$noncoverage_output")" \
        "non-coverage artifact still exposes truncation metadata"
    assert_contains 'Detail: éx' "$(cat "$TMP_ROOT/truncation-noncoverage-prompt")" \
        "non-coverage strategy receives the same capped fallback context"
    assert_not_contains éxZ "$(cat "$TMP_ROOT/truncation-noncoverage-prompt")" \
        "non-coverage strategy never receives the truncated fallback suffix"
    assert_contains 'not a coverage-union claim' "$(jq -r '.coverage_integrity.disclosure' "$noncoverage_output")" \
        "non-coverage disclosure avoids a false coverage claim"
}

test_whitespace_synthesis_payload_fails_closed() {
    local responses="$TMP_ROOT/whitespace-responses" output="$TMP_ROOT/whitespace-synthesis.json"
    local fake="$TMP_ROOT/whitespace-claude"
    mkdir -p "$responses"
    printf '%s\n' '{"consultant":"Whitespace","model":"m","response":{"summary":"point","detailed":"detail","approach":"structured","pros":[],"cons":[]},"confidence":{"score":8,"reasoning":"ok"},"metadata":{"response_quality":"structured"}}' > "$responses/whitespace.json"
    cat > "$fake" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--help" ]]; then printf '%s\n' '--print --no-session-persistence --setting-sources --tools'; exit 0; fi
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
cat >/dev/null
printf ' \n\t '
EOF
    chmod +x "$fake"

    if ! PATH="$TMP_ROOT:$PATH" CLAUDE_CMD="$fake" SYNTHESIS_CMD=claude INVOKING_AGENT=unknown \
        "$SCRIPT_DIR/synthesize.sh" "$responses" "$output" test >/dev/null 2>&1; then
        assert_eq success failure "whitespace provider payload recovers to local artifact"
        return
    fi

    assert_eq 1 "$([[ -s "$output" ]] && echo 1 || echo 0)" \
        "whitespace provider payload never publishes an empty artifact"
    assert_exit_success "whitespace recovery artifact is valid JSON" jq empty "$output"
    assert_eq local-fallback "$(jq -r '.synthesis_provider' "$output")" \
        "whitespace recovery records explicit local fallback provenance"
    assert_ne MET "$(jq -r '.coverage_integrity.status // "UNKNOWN"' "$output")" \
        "whitespace recovery cannot claim MET"
    assert_ne UNKNOWN "$(jq -r '.coverage_integrity.status // "UNKNOWN"' "$output")" \
        "whitespace recovery records coverage integrity"
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
    printf '%s\n' '{"consultant":"A","model":"m","response":{"summary":"a","detailed":"detail","approach":"unstructured-provider-response"},"confidence":{"score":8},"metadata":{"response_quality":"fallback"}}' > "$responses/a.json"
    for cmd in claude agy codex; do
        printf '%s\n' '#!/bin/bash' 'exit 1' > "$TMP_ROOT/no-cli-bin/$cmd"
        chmod +x "$TMP_ROOT/no-cli-bin/$cmd"
    done

    if ! PATH="$TMP_ROOT/no-cli-bin:$PATH" CLAUDE_CMD=claude GEMINI_CMD=agy CODEX_CMD=codex \
        SYNTHESIS_CMD=claude SYNTHESIS_STRATEGY=security_first SYNTH_DETAIL_MAX_CHARS=1 INVOKING_AGENT=unknown \
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
    assert_eq true "$(jq -r '.coverage_input_truncated' "$output")" \
        "local fallback retains locally detected truncation metadata"
    assert_eq A "$(jq -r '.truncated_consultants | join(",")' "$output")" \
        "local fallback retains the affected consultant"
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
run_test "Synthesis makes fallback truncation explicit without clipping atomic findings" test_synthesis_truncation_is_explicit_and_atomic_findings_are_complete
run_test "Whitespace synthesis payload fails closed" test_whitespace_synthesis_payload_fails_closed
run_test "Coverage integrity normalizes and audits local source IDs" test_coverage_integrity_normalizes_and_enforces_source_ids
run_test "Coverage integrity closes edge contracts" test_coverage_integrity_edge_contracts
run_test "Report renders coverage integrity status" test_report_renders_coverage_integrity_status
run_test "Synthesis skips unready CLIs and uses bounded Codex" test_synthesis_skips_unready_clis_and_uses_bounded_codex
run_test "Synthesis with no ready CLI uses local fallback" test_synthesis_with_no_ready_cli_uses_local_fallback
run_test "Claude invoker never uses Claude for synthesis" test_claude_invoker_never_uses_claude_for_synthesis
run_test "Codex invoker never uses Codex for synthesis" test_codex_invoker_never_uses_codex_for_synthesis
run_test "Gemini invoker never uses Gemini for synthesis" test_gemini_invoker_never_uses_gemini_for_synthesis
test_summary "synthesize"
