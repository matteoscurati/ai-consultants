#!/bin/bash
# test_e2e.sh - Offline end-to-end integration test for the full consult_all.sh
# pipeline (classify -> route -> parallel collection -> coverage report).
#
# Drives consult_all.sh with real CLI-based consultants (Claude, Codex,
# Gemini, Mistral) whose CLI_CMD env vars are pointed at a stub "CLI"
# (test_fixtures/stub_cli.sh) that ignores its args/stdin and prints a valid
# consultant JSON envelope. Everything runs in an isolated temp HOME/XDG tree
# so nothing touches the real config, cache, or session state, and no
# network calls happen.
#
# Usage: ./scripts/test_e2e.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test_helpers.sh
source "$SCRIPT_DIR/lib/test_helpers.sh"

STUB_CLI="$SCRIPT_DIR/test_fixtures/stub_cli.sh"

TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

test_full_pipeline() {
    local run_out rc output_dir

    run_out=$(
        HOME="$TEST_TMPDIR/home" \
        XDG_CACHE_HOME="$TEST_TMPDIR/xdg/cache" \
        XDG_STATE_HOME="$TEST_TMPDIR/xdg/state" \
        XDG_DATA_HOME="$TEST_TMPDIR/xdg/data" \
        INVOKING_AGENT=none \
        ENABLE_CLAUDE=true ENABLE_CODEX=true ENABLE_GEMINI=true ENABLE_MISTRAL=true \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CLAUDE_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" GEMINI_CMD="$STUB_CLI" MISTRAL_CMD="$STUB_CLI" \
        ENABLE_SEMANTIC_CACHE=false \
        ENABLE_SYNTHESIS=false \
        ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false \
        "$SCRIPT_DIR/consult_all.sh" "How should I structure a small web service?" \
        2>"$TEST_TMPDIR/run.err"
    )
    rc=$?

    assert_eq "0" "$rc" "consult_all.sh exits 0"

    # The output directory is printed as the LAST line of stdout.
    output_dir=$(echo "$run_out" | tail -n 1)

    assert_eq "1" "$([[ -d "$output_dir" ]] && echo 1 || echo 0)" \
        "output directory exists ($output_dir)"

    local consultant_json_count=0 f
    while IFS= read -r -d '' f; do
        if jq -e 'has("consultant")' "$f" >/dev/null 2>&1; then
            ((consultant_json_count++)) || true
        fi
    done < <(find "$output_dir" -maxdepth 1 -name '*.json' -type f -print0 2>/dev/null)
    assert_eq "1" "$([[ "$consultant_json_count" -ge 3 ]] && echo 1 || echo 0)" \
        "at least 3 consultant response files present (found $consultant_json_count)"

    local report_file=""
    [[ -f "$output_dir/report.md" ]] && report_file="$output_dir/report.md"
    assert_eq "1" "$([[ -n "$report_file" ]] && echo 1 || echo 0)" \
        "report.md exists"

    assert_eq "1" "$([[ -f "$output_dir/optimization_metrics.json" ]] && echo 1 || echo 0)" \
        "optimization_metrics.json exists"

    local success_responses
    success_responses=$(jq -r '.quality_metrics.successful_responses // "MISSING"' \
        "$output_dir/optimization_metrics.json" 2>/dev/null)
    assert_eq "1" "$([[ "$success_responses" != "MISSING" && "$success_responses" != "null" ]] && echo 1 || echo 0)" \
        "optimization_metrics.json records successful_responses (got: $success_responses)"
}

test_claude_host_excludes_itself_and_calls_other_consultants() {
    local run_out rc output_dir consultant

    run_out=$(
        HOME="$TEST_TMPDIR/claude-home" \
        XDG_CACHE_HOME="$TEST_TMPDIR/claude-xdg/cache" \
        XDG_STATE_HOME="$TEST_TMPDIR/claude-xdg/state" \
        XDG_DATA_HOME="$TEST_TMPDIR/claude-xdg/data" \
        INVOKING_AGENT=claude \
        ENABLE_CLAUDE=true ENABLE_CODEX=true ENABLE_GEMINI=true ENABLE_MISTRAL=true \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CLAUDE_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" GEMINI_CMD="$STUB_CLI" MISTRAL_CMD="$STUB_CLI" \
        ENABLE_SEMANTIC_CACHE=false \
        ENABLE_SYNTHESIS=false \
        ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false \
        "$SCRIPT_DIR/consult_all.sh" "Which boundary should a host agent preserve?" \
        2>"$TEST_TMPDIR/claude-host.err"
    )
    rc=$?
    output_dir=$(echo "$run_out" | tail -n 1)

    assert_eq "0" "$rc" "Claude-hosted consultation exits 0"
    assert_eq "1" "$([[ -d "$output_dir" ]] && echo 1 || echo 0)" \
        "Claude-hosted consultation produces an output directory"
    assert_eq "0" "$([[ -e "$output_dir/claude.json" || -e "$output_dir/claude.err" ]] && echo 1 || echo 0)" \
        "Claude host produces no Claude consultant artifacts"

    for consultant in gemini codex mistral; do
        assert_eq "1" "$([[ -s "$output_dir/$consultant.json" ]] && echo 1 || echo 0)" \
            "Claude host dispatches $consultant"
    done

    assert_eq "3" "$(jq -r '.quality_metrics.total_consultants' "$output_dir/optimization_metrics.json")" \
        "Claude self-exclusion leaves exactly the three other enabled consultants"
    assert_eq "3" "$(jq -r '.quality_metrics.successful_responses' "$output_dir/optimization_metrics.json")" \
        "all non-Claude consultants return successfully"
}

# M6: a hand-typed non-boolean flag (TRUE, yes) must not abort the run after
# the consultants were already billed.
test_non_boolean_flags_do_not_abort_the_report() {
    local run_out rc output_dir
    run_out=$(
        HOME="$TEST_TMPDIR/flags-home" \
        XDG_CACHE_HOME="$TEST_TMPDIR/flags-xdg/cache" \
        XDG_STATE_HOME="$TEST_TMPDIR/flags-xdg/state" \
        XDG_DATA_HOME="$TEST_TMPDIR/flags-xdg/data" \
        INVOKING_AGENT=none \
        ENABLE_CLAUDE=false ENABLE_CODEX=true ENABLE_GEMINI=true ENABLE_MISTRAL=false \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CODEX_CMD="$STUB_CLI" GEMINI_CMD="$STUB_CLI" \
        ENABLE_SEMANTIC_CACHE=TRUE ENABLE_COMPACT_REPORT=yes ENABLE_COST_AWARE_ROUTING=0 \
        SYNTHESIS_STRATEGY=compare_only \
        ENABLE_SYNTHESIS=false ENABLE_SMART_ROUTING=false ENABLE_HEALTH_GATE=false \
        LAUNCH_STAGGER_MAX_SECONDS=0 \
        "$SCRIPT_DIR/consult_all.sh" "Pick a queue for background jobs" \
        2>"$TEST_TMPDIR/flags.err"
    )
    rc=$?
    output_dir=$(echo "$run_out" | tail -n 1)
    assert_eq "0" "$rc" "non-boolean flags do not abort consult_all.sh"
    assert_eq "1" "$([[ -f "$output_dir/report.md" ]] && echo 1 || echo 0)" \
        "report is still generated with non-boolean flags"
    assert_match "Synthesis strategy: compare_only" "$(cat "$TEST_TMPDIR/flags.err")" \
        "SYNTHESIS_STRATEGY from the environment is honored"

    local rc_invalid=0
    SYNTHESIS_STRATEGY=not_a_strategy "$SCRIPT_DIR/consult_all.sh" "q" >/dev/null 2>&1 || rc_invalid=$?
    assert_eq 1 "$rc_invalid" "an unknown SYNTHESIS_STRATEGY is rejected"
}

# Stub for Codex/Gemini that records the requested model and answers with low
# confidence (4) on an economy model and high confidence (9) otherwise.
make_model_echo_stub() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/bin/bash
if [[ ! -t 0 ]]; then cat >/dev/null; fi
if [[ "${1:-}" == "models" ]]; then
    printf '%s\n' 'Gemini 4 Argon (High)' 'Gemini 3.8 Flash (High)' 'Gemini 3.8 Flash (Low)'
    exit 0
fi
model=""; payload=""; prev=""
for arg in "$@"; do
    [[ "$prev" == "-m" || "$prev" == "--model" ]] && model="$arg"
    [[ "$prev" == "-o" ]] && payload="$arg"
    prev="$arg"
done
printf '%s\n' "$model" >> "$STUB_MODEL_LOG"
score=9
case "$model" in *luna*|*Low*) score=4 ;; esac
answer=$(jq -n --argjson s "$score" --arg m "$model" \
    '{response:{summary:("answer from " + $m),detailed:"d",approach:"a",pros:[],cons:[],caveats:[]},confidence:{score:$s,reasoning:"r"}}')
if [[ -n "$payload" ]]; then
    # Codex: the answer goes to the -o file, JSON events to stdout.
    printf '%s\n' "$answer" > "$payload"
    if [[ " $* " == *" --json "* ]]; then
        printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":10,"output_tokens":5,"cached_input_tokens":0}}'
    else
        printf '%s\n' 'codex stub completed'
    fi
    exit 0
fi
printf '%s\n' "$answer"
EOF
    chmod +x "$path"
}

# Run consult_all.sh with Codex + Gemini on the model-echo stub; extra
# VAR=value settings come first, the remaining arguments go to consult_all.sh.
run_model_echo_panel() {
    local home="$1"; shift
    local -a settings=()
    while [[ $# -gt 0 && "$1" == *=* && "$1" != -* ]]; do settings+=("$1"); shift; done
    env HOME="$home" XDG_CACHE_HOME="$home/cache" XDG_STATE_HOME="$home/state" \
        XDG_DATA_HOME="$home/data" AI_CONSULTANTS_CONFIG_DIR="$home/config" \
        INVOKING_AGENT=none DEFAULT_PRESET= \
        ENABLE_CLAUDE=false ENABLE_CODEX=true ENABLE_GEMINI=true ENABLE_MISTRAL=false \
        ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false \
        ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false CODEX_USE_API=false GEMINI_USE_API=false \
        CODEX_CMD="$MODEL_ECHO_STUB" GEMINI_CMD="$MODEL_ECHO_STUB" \
        ENABLE_SYNTHESIS=false ENABLE_CLASSIFICATION=false ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false LAUNCH_STAGGER_MAX_SECONDS=0 MAX_RETRIES=1 \
        ${settings[@]+"${settings[@]}"} "$SCRIPT_DIR/consult_all.sh" "$@" </dev/null
}

# Cost-aware routing runs a simple question on economy models inside the
# launch subshell only. Escalation must compare against the model that
# answered (not the configured premium variable), and the cache must key the
# override so a later run that asks the configured model is never served the
# economy answer.
test_cost_aware_escalation_and_cache_identity() {
    local home="$TEST_TMPDIR/cost-aware" out dir
    MODEL_ECHO_STUB="$TEST_TMPDIR/model-echo-stub"
    make_model_echo_stub "$MODEL_ECHO_STUB"
    mkdir -p "$home"
    export STUB_MODEL_LOG="$home/models.log"
    : > "$STUB_MODEL_LOG"

    out=$(run_model_echo_panel "$home" ENABLE_COST_AWARE_ROUTING=true ENABLE_SEMANTIC_CACHE=false \
        "Pick a queue" 2>"$home/escalation.err")
    dir=$(printf '%s\n' "$out" | tail -n 1)
    assert_eq "gpt-6.1-sol|9" "$(jq -r '"\(.metadata.requested_model)|\(.confidence.score)"' "$dir/codex.json" 2>/dev/null)" \
        "a low-confidence economy Codex answer is re-asked on the premium model"
    assert_eq "Gemini 4 Argon (High)|9" "$(jq -r '"\(.metadata.requested_model)|\(.confidence.score)"' "$dir/gemini.json" 2>/dev/null)" \
        "a low-confidence economy Gemini answer is re-asked on the premium model"

    : > "$STUB_MODEL_LOG"
    run_model_echo_panel "$home" ENABLE_COST_AWARE_ROUTING=true ENABLE_SEMANTIC_CACHE=true \
        FALLBACK_CONFIDENCE_THRESHOLD=1 "Pick a cache key" >/dev/null 2>&1
    out=$(run_model_echo_panel "$home" ENABLE_COST_AWARE_ROUTING=false ENABLE_SEMANTIC_CACHE=true \
        "Pick a cache key" 2>"$home/cache.err")
    dir=$(printf '%s\n' "$out" | tail -n 1)
    assert_eq "gpt-6.1-sol|Gemini 4 Argon (High)" \
        "$(jq -rs 'map(.metadata.requested_model) | join("|")' "$dir/codex.json" "$dir/gemini.json" 2>/dev/null)" \
        "a cached cost-aware economy answer is not served to a premium run"
    assert_eq "2" "$(grep -cE '^(gpt-6\.1-sol|Gemini 4 Argon \(High\))$' "$STUB_MODEL_LOG")" \
        "the premium run queries the configured models"
    unset STUB_MODEL_LOG
}

# Host runs build the context from --context-root: a pointed category must
# still omit the caller's project tree, and a relative output base must still
# resolve against the directory consult_all.sh was started from.
test_host_context_category_and_relative_output() {
    local home="$TEST_TMPDIR/host-context" project out dir rc
    MODEL_ECHO_STUB="$TEST_TMPDIR/model-echo-stub"
    make_model_echo_stub "$MODEL_ECHO_STUB"
    project="$home/project"
    mkdir -p "$project/src" "$home/cwd"
    printf 'print(1)\n' > "$project/src/payments.py"
    export STUB_MODEL_LOG="$home/models.log"

    out=$(run_model_echo_panel "$home" ENABLE_CLASSIFICATION=true ENABLE_SEMANTIC_CACHE=false \
        FALLBACK_CONFIDENCE_THRESHOLD=1 --context-root "$project" \
        "Is our JWT password handling secure against injection?" 2>"$home/security.err")
    dir=$(printf '%s\n' "$out" | tail -n 1)
    assert_match "Category: SECURITY" "$(cat "$home/security.err")" "the question is classified as SECURITY"
    assert_eq "0" "$(grep -c 'payments.py' "$dir/context.md" 2>/dev/null || true)" \
        "a SECURITY consultation omits the caller's project tree"

    rc=0
    out=$(cd "$home/cwd" && run_model_echo_panel "$home" ENABLE_SEMANTIC_CACHE=false \
        FALLBACK_CONFIDENCE_THRESHOLD=1 DEFAULT_OUTPUT_DIR_BASE=relative-out \
        --context-root "$project" "Pick a queue" 2>"$home/relative.err") || rc=$?
    dir=$(printf '%s\n' "$out" | tail -n 1)
    assert_eq "0" "$rc" "a relative output base works with --context-root"
    local expected_base actual_base
    expected_base=$(cd "$home/cwd/relative-out" 2>/dev/null && pwd -P)
    actual_base=$(cd "$dir/.." 2>/dev/null && pwd -P)
    assert_eq "1" "$([[ -n "$expected_base" && "$actual_base" == "$expected_base" && -s "$dir/context.md" ]] && echo 1 || echo 0)" \
        "the context is written under the starting directory, not the caller's project"
    assert_eq "0" "$([[ -e "$project/relative-out" ]] && echo 1 || echo 0)" \
        "nothing is written into the caller's project"
    assert_contains "**Directory**: $(cd "$project" && pwd -P)" "$(cat "$dir/report.md" 2>/dev/null)" \
        "the report names the caller's project, not the skill root"
    unset STUB_MODEL_LOG
}

# A consultant CLI that answers capability probes but never finishes a real
# query. It records "<its pid> <sleep pid>" so a test can prove that host
# control stops the whole process tree, not only the adapter. With
# "dies-on-int" it restores the default SIGINT action, as Node and Go CLIs do,
# so a terminal Ctrl-C ends it; otherwise it inherits the ignored SIGINT of a
# background job, as curl does.
make_never_answering_stub() {
    local path="$1" pid_log="$2" sleeper="sleep 600"
    [[ "${3:-}" != dies-on-int ]] || sleeper="perl -e '\$SIG{INT} = \"DEFAULT\"; sleep 600'"
    cat > "$path" <<EOF
#!/bin/bash
for arg in "\$@"; do
    case "\$arg" in --help|--version) exec "$STUB_CLI" "\$@" ;; esac
done
[[ "\${1:-}" != models ]] || exec "$STUB_CLI" "\$@"
[[ -t 0 ]] || cat >/dev/null
$sleeper &
printf '%s %s\n' "\$\$" "\$!" >> "$pid_log"
wait
EOF
    chmod +x "$path"
}

# Usage: wait_until <seconds> <command...>
wait_until() {
    local deadline=$(( $(date +%s) + $1 ))
    shift
    until "$@"; do
        (( $(date +%s) < deadline )) || return 1
        sleep 0.2
    done
}

# Start a no-timeout consultation in the background. Sets HC_PID, HC_OUT, HC_ERR.
start_host_controlled_panel() {
    local home="$1"; shift
    HC_OUT="$home/run.out"; HC_ERR="$home/run.err"
    mkdir -p "$home"
    env HOME="$home" XDG_CACHE_HOME="$home/cache" XDG_STATE_HOME="$home/state" \
        XDG_DATA_HOME="$home/data" AI_CONSULTANTS_CONFIG_DIR="$home/config" \
        INVOKING_AGENT=none DEFAULT_PRESET= \
        ENABLE_CLAUDE=false ENABLE_KIMI=false ENABLE_QWEN3=false ENABLE_GLM=false \
        ENABLE_GROK=false ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
        CODEX_USE_API=false GEMINI_USE_API=false MISTRAL_USE_API=false \
        ENABLE_SEMANTIC_CACHE=false ENABLE_CLASSIFICATION=false ENABLE_SMART_ROUTING=false \
        ENABLE_HEALTH_GATE=false LAUNCH_STAGGER_MAX_SECONDS=0 MAX_RETRIES=1 \
        WAIT_HEARTBEAT_SECONDS=1 "$@" \
        "$SCRIPT_DIR/consult_all.sh" "Pick a queue" </dev/null >"$HC_OUT" 2>"$HC_ERR" &
    HC_PID=$!
}

# Clean up a run that did not finish, so a failing test cannot leak processes.
stop_background_run() {
    ( source "$SCRIPT_DIR/lib/common.sh" && kill_process_tree "$HC_PID" ) >/dev/null 2>&1
    wait "$HC_PID" 2>/dev/null || true
}

host_output_dir() { sed -n 's/.*Output: //p' "$HC_ERR" | head -n 1; }
log_mentions() { grep -q -- "$1" "$HC_ERR" 2>/dev/null; }
pid_log_has_entry() { [[ -s "$1" ]]; }
pid_log_has_entries() { [[ $(wc -l < "$1" 2>/dev/null || echo 0) -ge $2 ]]; }
run_finished() { ! kill -0 "$HC_PID" 2>/dev/null; }

# Every recorded stub process (adapter shell and its sleep) must be gone.
stub_processes_alive() {
    local pid_log="$1" p alive=0
    for p in $(cat "$pid_log" 2>/dev/null); do
        kill -0 "$p" 2>/dev/null && alive=$((alive + 1))
    done
    printf '%s' "$alive"
}

test_host_proceed_stops_a_consultant_that_never_answers() {
    local home="$TEST_TMPDIR/host-proceed" slow pid_log dir rc
    slow="$TEST_TMPDIR/never_answers_proceed.sh"; pid_log="$TEST_TMPDIR/never_answers_proceed.pids"
    make_never_answering_stub "$slow" "$pid_log"
    start_host_controlled_panel "$home" ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true \
        GEMINI_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" MISTRAL_CMD="$slow" ENABLE_SYNTHESIS=false
    if ! wait_until 60 pid_log_has_entry "$pid_log" || ! wait_until 60 log_mentions "Still waiting after"; then
        stop_background_run
        assert_eq ready timeout "the slow consultant started and the run reported it was waiting"
        return
    fi
    assert_contains "Mistral" "$(grep 'Still waiting after' "$HC_ERR" | tail -n 1)" "the heartbeat names the consultant still running"
    dir=$(host_output_dir)
    touch "$dir/.proceed"
    if ! wait_until 30 run_finished; then
        stop_background_run
        assert_eq finished hung "a proceed request lets the run finish"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    assert_eq 0 "$rc" "the run completes after a proceed request"
    assert_eq "$dir" "$(tail -n 1 "$HC_OUT")" "the output directory is still printed last"
    assert_eq 0 "$(stub_processes_alive "$pid_log")" "the stopped consultant's whole process tree is gone"
    assert_eq false "$([[ -e "$dir/mistral.json" ]] && echo true || echo false)" "no partial envelope is left for synthesis or cost"
    assert_contains "| Mistral | stopped |" "$(cat "$dir/report.md")" "the report marks the consultant as stopped"
    assert_contains "stopped by the host" "$(cat "$dir/report.md")" "the report explains why it is missing"
    assert_contains "**Outcome**: DEGRADED (2/3 responded" "$(cat "$dir/report.md")" "the answers received still meet quorum"
    assert_eq 0 "$(grep -c 'Terminated' "$HC_ERR" || true)" "stopping leaves no job-termination noise in the log"
}

test_host_abort_ends_the_run_and_its_children() {
    local home="$TEST_TMPDIR/host-abort" slow pid_log dir rc
    slow="$TEST_TMPDIR/never_answers_abort.sh"; pid_log="$TEST_TMPDIR/never_answers_abort.pids"
    make_never_answering_stub "$slow" "$pid_log"
    start_host_controlled_panel "$home" ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true \
        GEMINI_CMD="$STUB_CLI" CODEX_CMD="$STUB_CLI" MISTRAL_CMD="$slow" ENABLE_SYNTHESIS=false
    if ! wait_until 60 pid_log_has_entry "$pid_log"; then
        stop_background_run
        assert_eq ready timeout "the slow consultant started"
        return
    fi
    dir=$(host_output_dir)
    touch "$dir/.abort"
    if ! wait_until 30 run_finished; then
        stop_background_run
        assert_eq finished hung "an abort request ends the run"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    assert_eq 130 "$rc" "an aborted run exits 130"
    assert_eq 0 "$(stub_processes_alive "$pid_log")" "abort stops every running consultant"
    assert_eq false "$([[ -e "$dir/report.md" ]] && echo true || echo false)" "an aborted run writes no report"
}

test_host_proceed_during_synthesis_skips_it() {
    local home="$TEST_TMPDIR/host-synthesis" slow pid_log dir rc
    slow="$TEST_TMPDIR/never_answers_synthesis.sh"; pid_log="$TEST_TMPDIR/never_answers_synthesis.pids"
    make_never_answering_stub "$slow" "$pid_log"
    start_host_controlled_panel "$home" ENABLE_GEMINI=true ENABLE_CODEX=false ENABLE_MISTRAL=true \
        GEMINI_CMD="$STUB_CLI" MISTRAL_CMD="$STUB_CLI" CODEX_CMD="$slow" \
        ENABLE_SYNTHESIS=true SYNTHESIS_CMD=codex
    if ! wait_until 60 pid_log_has_entry "$pid_log" || ! wait_until 30 log_mentions "for: synthesis"; then
        stop_background_run
        assert_eq ready timeout "the synthesis started and the run reported it was waiting"
        return
    fi
    kill -USR1 "$HC_PID"
    if ! wait_until 30 run_finished; then
        stop_background_run
        assert_eq finished hung "SIGUSR1 lets the run finish"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    dir=$(host_output_dir)
    assert_eq 0 "$rc" "the run completes when the host skips synthesis"
    assert_eq 0 "$(stub_processes_alive "$pid_log")" "the synthesis process tree is gone"
    assert_eq false "$([[ -e "$dir/synthesis.json" ]] && echo true || echo false)" "no partial synthesis is presented"
    assert_contains "Stopped by the host before it finished" "$(cat "$dir/report.md")" "the report says the synthesis was stopped"
    assert_contains "| Gemini | " "$(cat "$dir/report.md")" "the answers are still reported"
}

# A consultant CLI that answers capability probes but cannot reach its
# provider, printing a config warning before the real error (as Kimi did).
make_offline_stub() {
    local path="$1"
    cat > "$path" <<EOF
#!/bin/bash
for arg in "\$@"; do
    case "\$arg" in --help|--version) exec "$STUB_CLI" "\$@" ;; esac
done
[[ "\${1:-}" != models ]] || exec "$STUB_CLI" "\$@"
[[ -t 0 ]] || cat >/dev/null
echo "Warning: [loop_control] 'max_retries_per_step' is deprecated; rename it" >&2
echo "error: failed to run prompt: getaddrinfo ENOTFOUND api.provider.example" >&2
exit 1
EOF
    chmod +x "$path"
}

test_offline_panel_reports_the_network_cause() {
    local home="$TEST_TMPDIR/offline" offline dir report rc
    offline="$TEST_TMPDIR/offline_cli.sh"
    make_offline_stub "$offline"
    start_host_controlled_panel "$home" ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true \
        GEMINI_CMD="$offline" CODEX_CMD="$offline" MISTRAL_CMD="$offline" ENABLE_SYNTHESIS=false
    if ! wait_until 60 run_finished; then
        stop_background_run
        assert_eq finished hung "an offline panel finishes"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    dir=$(host_output_dir)
    report=$(cat "$dir/report.md" 2>/dev/null)
    assert_eq 0 "$rc" "an offline panel still writes its report"
    assert_contains "| Gemini | error: failed to run prompt: getaddrinfo ENOTFOUND api.provider.example |" "$report" \
        "the report gives the CLI's error, not the warning printed before it"
    assert_eq 0 "$(grep -c 'max_retries_per_step' <<< "$report" || true)" "no warning is presented as a reason"
    assert_contains "Every failure is a network error" "$report" "the report says the network is unreachable"
    assert_contains "Every failure is a network error" "$(cat "$HC_ERR")" "so does the console"
}

# A terminal Ctrl-C signals the whole foreground process group. Start the run
# as its own group (job control), so SIGINT is not ignored as in a plain
# background job, and signal the group as the terminal would.
start_panel_as_foreground_group() {
    set -m
    start_host_controlled_panel "$@"
    set +m
}
terminal_ctrl_c() { kill -INT -- "-$HC_PID" 2>/dev/null || true; }

test_terminal_ctrl_c_continues_with_the_answers() {
    local home="$TEST_TMPDIR/ctrl-c-proceed" ignores dies pid_log dir rc report
    ignores="$TEST_TMPDIR/never_answers_ignores_int.sh"; dies="$TEST_TMPDIR/never_answers_dies_on_int.sh"
    pid_log="$TEST_TMPDIR/never_answers_ctrl_c.pids"
    make_never_answering_stub "$ignores" "$pid_log"
    make_never_answering_stub "$dies" "$pid_log" dies-on-int
    start_panel_as_foreground_group "$home" ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true \
        GEMINI_CMD="$STUB_CLI" CODEX_CMD="$ignores" MISTRAL_CMD="$dies" ENABLE_SYNTHESIS=false
    if ! wait_until 60 log_mentions "Gemini: OK" || ! wait_until 60 log_mentions "Still waiting after" \
        || ! wait_until 30 pid_log_has_entries "$pid_log" 2; then
        stop_background_run
        assert_eq ready timeout "both slow consultants started after the first answer"
        return
    fi
    terminal_ctrl_c
    if ! wait_until 30 run_finished; then
        stop_background_run
        assert_eq finished hung "a first Ctrl-C lets the run finish"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    dir=$(host_output_dir)
    report=$(cat "$dir/report.md" 2>/dev/null)
    assert_eq 0 "$rc" "a first Ctrl-C continues instead of ending the run"
    assert_eq 0 "$(stub_processes_alive "$pid_log")" "no consultant CLI survives the Ctrl-C"
    assert_contains "| Codex | stopped |" "$report" "a CLI that ignores SIGINT is stopped by the run"
    assert_contains "| Mistral | stopped |" "$report" "a CLI that SIGINT ended is reported as stopped, not failed"
    assert_contains "| Gemini | " "$report" "the answer received is reported"
}

test_second_terminal_ctrl_c_aborts_during_synthesis() {
    local home="$TEST_TMPDIR/ctrl-c-abort" slow pid_log dir rc
    slow="$TEST_TMPDIR/never_answers_ctrl_c_abort.sh"; pid_log="$TEST_TMPDIR/never_answers_ctrl_c_abort.pids"
    make_never_answering_stub "$slow" "$pid_log"
    start_panel_as_foreground_group "$home" ENABLE_GEMINI=true ENABLE_CODEX=false ENABLE_MISTRAL=true \
        GEMINI_CMD="$STUB_CLI" MISTRAL_CMD="$slow" CODEX_CMD="$slow" \
        ENABLE_SYNTHESIS=true SYNTHESIS_CMD=codex
    if ! wait_until 60 pid_log_has_entry "$pid_log" || ! wait_until 60 log_mentions "Gemini: OK"; then
        stop_background_run
        assert_eq ready timeout "the slow consultant started after the first answer"
        return
    fi
    terminal_ctrl_c
    if ! wait_until 30 log_mentions "for: synthesis"; then
        stop_background_run
        assert_eq synthesis missing "a first Ctrl-C moves on to the synthesis"
        return
    fi
    terminal_ctrl_c
    if ! wait_until 30 run_finished; then
        stop_background_run
        assert_eq finished hung "a second Ctrl-C ends the run"
        return
    fi
    rc=0; wait "$HC_PID" || rc=$?
    dir=$(host_output_dir)
    assert_eq 130 "$rc" "a second Ctrl-C aborts with 130"
    assert_eq 0 "$(stub_processes_alive "$pid_log")" "abort leaves no consultant or synthesis CLI running"
    assert_contains "second interrupt" "$(cat "$HC_ERR")" "the log says why the run ended"
    assert_eq false "$([[ -e "$dir/report.md" ]] && echo true || echo false)" "an aborted run writes no report"
}

run_test "Test 1: full offline consult_all.sh pipeline with stubbed CLIs" test_full_pipeline
run_test "Test 2: Claude host excludes itself and dispatches other consultants" test_claude_host_excludes_itself_and_calls_other_consultants
run_test "Test 3: non-boolean flags do not abort the report" test_non_boolean_flags_do_not_abort_the_report
run_test "Test 4: cost-aware escalation and cache identity" test_cost_aware_escalation_and_cache_identity
run_test "Test 5: host context category and relative output base" test_host_context_category_and_relative_output
run_test "Test 6: host proceed stops a consultant that never answers" test_host_proceed_stops_a_consultant_that_never_answers
run_test "Test 7: host abort ends the run and its children" test_host_abort_ends_the_run_and_its_children
run_test "Test 8: host proceed during synthesis skips it" test_host_proceed_during_synthesis_skips_it
run_test "Test 9: a terminal Ctrl-C continues with the answers received" test_terminal_ctrl_c_continues_with_the_answers
run_test "Test 10: a second terminal Ctrl-C aborts during synthesis" test_second_terminal_ctrl_c_aborts_during_synthesis
run_test "Test 11: an offline panel reports the network cause" test_offline_panel_reports_the_network_cause

test_summary "test_e2e"
