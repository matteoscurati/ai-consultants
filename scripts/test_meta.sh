#!/bin/bash
# Offline Meta (Muse Code CLI / Meta Model API) adapter, tier and rate checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export AI_CONSULTANTS_CONFIG_DIR="$TMP/config"
unset META_MODEL META_REASONING_EFFORT META_USE_API META_API_KEY META_CMD META_API_MAX_TOKENS \
    META_TIMEOUT ENABLE_META
fail() { printf 'Meta assertion failed at line %s\n' "$1" >&2; exit 1; }
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/costs.sh"
source "$SCRIPT_DIR/lib/api.sh"
source "$SCRIPT_DIR/lib/personas.sh"

# --- Defaults, roster, tiers ---
[[ "$META_MODEL" == muse-wonder-1.0 && "$META_REASONING_EFFORT" == high && "$META_USE_API" == false \
    && "$ENABLE_META" == false && "$META_API_MAX_TOKENS" == 32768 ]] || fail $LINENO
[[ " ${ALL_CONSULTANTS[*]} " == *" Meta "* ]] || fail $LINENO
[[ $(get_persona_name Meta) == 'The Systems Thinker' ]] || fail $LINENO
[[ $(INVOKING_AGENT=muse get_self_consultant_name) == META ]] || fail $LINENO
[[ $(registry_preset_target max_quality) == 11 ]] || fail $LINENO
for tier in maximum premium standard economy; do
    case "$tier" in
        maximum|premium) expected=muse-wonder-1.0 ;;
        *) expected=muse-spark-1.3 ;;
    esac
    [[ $(get_model_for_tier meta "$tier") == "$expected" ]] || fail $LINENO
    [[ $(jq -r --arg tier "$tier" '.model_tiers[$tier].meta' "$COST_RATES_FILE") == "$expected" ]] || fail $LINENO
done
# Maximum sets max effort; a later tier restores the configured value.
apply_model_tier maximum
[[ "$META_MODEL" == muse-wonder-1.0 && "$META_REASONING_EFFORT" == max ]] || fail $LINENO
apply_model_tier economy
[[ "$META_MODEL" == muse-spark-1.3 && "$META_REASONING_EFFORT" == high ]] || fail $LINENO
# A key with no explicit transport selects the API; an explicit false wins.
[[ $(META_API_KEY=k bash -c 'unset META_USE_API; source "$1/config.sh"; echo "$META_USE_API"' _ "$SCRIPT_DIR") == true ]] || fail $LINENO
[[ $(META_API_KEY=k META_USE_API=false bash -c 'source "$1/config.sh"; echo "$META_USE_API"' _ "$SCRIPT_DIR") == false ]] || fail $LINENO

# --- Rates: catalog and built-in fallback agree ---
[[ $(estimate_query_cost muse-wonder-1.0 2000 1000) == 0.028000 ]] || fail $LINENO
[[ $(estimate_query_cost muse-spark-1.3 2000 1000) == 0.006750 ]] || fail $LINENO
[[ $(estimate_query_cost muse-spark-1.3-contributor 2000 1000) == 0.000400 ]] || fail $LINENO
COST_RATES_FILE="$TMP/missing" bash -c 'source "$1/lib/costs.sh";
    [[ $(get_input_cost_per_1k muse-wonder-1.0) == 0.004 && $(get_output_cost_per_1k muse-wonder-1.0) == 0.02 ]] &&
    [[ $(get_input_cost_per_1k muse-spark-1.3) == 0.00125 && $(get_output_cost_per_1k muse-spark-1.3) == 0.00425 ]]' \
    _ "$SCRIPT_DIR" || fail $LINENO

# --- API request shape ---
build_meta_request hello muse-wonder-1.0 32768 max | jq -e '
    .model == "muse-wonder-1.0" and .reasoning_effort == "max"
    and .max_completion_tokens == 32768 and (has("max_tokens") | not)
    and .messages == [{role: "user", content: "hello"}]' >/dev/null || fail $LINENO
if build_meta_request hello muse-spark-1.3 32768 none >/dev/null 2>&1; then fail $LINENO; fi

# --- API transport through a fake curl ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/bash
out=""; headers=""; body=""; request_headers=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) shift; out="$1" ;;
        -D) shift; headers="$1" ;;
        -H) shift; request_headers=$(cat "${1#@}") ;;
        --data-binary) shift; body=$(cat "${1#@}") ;;
        -X) shift; printf '%s\n' "$1" > "$URL_FILE.method" ;;
        http*) printf '%s\n' "$1" > "$URL_FILE" ;;
    esac
    shift
done
printf 'call\n' >> "$CALLS_FILE"
printf '%s' "$body" > "$BODY_FILE"
printf '%s\n' "$request_headers" > "$HEADERS_FILE"
: > "$headers"
case "${CURL_FAKE_MODE:-success}" in
    success)
        printf '%s\n' '{"model":"muse-wonder-1.0","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"{\"response\":{\"summary\":\"ok\",\"approach\":\"API\"},\"confidence\":{\"score\":8}}","reasoning_content":""}}],"usage":{"prompt_tokens":30,"completion_tokens":20,"completion_tokens_details":{"reasoning_tokens":12}}}' > "$out"
        printf 200 ;;
    gateway_timeout)
        printf '%s\n' '{"error":{"message":"Request exceeded the non-streaming server time limit before a response was produced.","type":"server_error","param":null,"code":"gateway_timeout"}}' > "$out"
        printf 504 ;;
esac
EOF
chmod +x "$TMP/bin/curl"
# apply_model_tier exported tier values above; pin the defaults for the transports.
api_env=(PATH="$TMP/bin:$PATH" META_API_KEY=LLM_1_test META_USE_API=true ENABLE_PERSONA=true
    META_MODEL=muse-wonder-1.0 META_REASONING_EFFORT=high
    URL_FILE="$TMP/url" BODY_FILE="$TMP/body.json" HEADERS_FILE="$TMP/headers" CALLS_FILE="$TMP/calls"
    RATE_LIMIT_DIR="$TMP/rate" MAX_RETRIES=3 RETRY_DELAY_SECONDS=0 API_BASE_BACKOFF=0)
env "${api_env[@]}" bash "$SCRIPT_DIR/query_meta.sh" "Is this design sound?" "" "$TMP/api.json" >/dev/null 2>&1 || fail $LINENO
[[ $(cat "$TMP/url") == https://api.meta.ai/v1/chat/completions ]] || fail $LINENO
grep -qx 'Authorization: Bearer LLM_1_test' "$TMP/headers" || fail $LINENO
jq -e '.model == "muse-wonder-1.0" and .reasoning_effort == "high" and .max_completion_tokens == 32768
    and (has("max_tokens") | not) and (.messages[0].content | contains("The Systems Thinker"))' "$TMP/body.json" >/dev/null || fail $LINENO
jq -e '.consultant == "Meta" and .model == "muse-wonder-1.0" and .metadata.response_quality == "structured"
    and .metadata.model_identity_source == "provider-reported" and .response.summary == "ok"' "$TMP/api.json" >/dev/null || fail $LINENO
# A non-streaming time-limit 504 is not retried: the same request would time out again.
rm -f "$TMP/calls"
if env "${api_env[@]}" CURL_FAKE_MODE=gateway_timeout \
        bash "$SCRIPT_DIR/query_meta.sh" "Is this design sound?" "" "$TMP/api-504.json" >/dev/null 2>&1; then
    fail $LINENO
fi
[[ $(wc -l < "$TMP/calls" | tr -d ' ') == 1 ]] || fail $LINENO
jq -e '.metadata.response_quality == "error"' "$TMP/api-504.json" >/dev/null || fail $LINENO
# none is rejected before anything is billed.
rm -f "$TMP/calls"
if env "${api_env[@]}" META_REASONING_EFFORT=none \
        bash "$SCRIPT_DIR/query_meta.sh" "q" "" "$TMP/api-none.json" >/dev/null 2>&1; then
    fail $LINENO
fi
[[ ! -e "$TMP/calls" ]] || fail $LINENO
# A pinned Contributor-mode model is warned about.
err=$(env "${api_env[@]}" META_MODEL=muse-spark-1.3-contributor \
    bash "$SCRIPT_DIR/query_meta.sh" "q" "" "$TMP/api-contrib.json" 2>&1 >/dev/null) || fail $LINENO
[[ "$err" == *"Contributor mode"* ]] || fail $LINENO

# --- CLI transport through a fake muse ---
cat > "$TMP/bin/muse" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == --version ]]; then echo "muse 9.9.9"; exit 0; fi
if [[ "${1:-}" == exec && "${2:-}" == --help ]]; then
    [[ "${MUSE_FAKE_HELP:-full}" == full ]] && flags="--prompt-file --model --reasoning-effort --contributor-mode --no-session-log --sandbox-network --disable-approval --workspace --disable-shell --disable-write --disable-web-tools --disable-request-user-input --no-foreign-personal-context --json" \
        || flags="--prompt-file --model --reasoning-effort"
    printf 'Usage: muse exec [options] [prompt]\n%s\n' "$flags"
    exit 0
fi
printf '%s\n' "$@" > "$ARGS_FILE"
pwd > "$CWD_FILE"
prompt_file=""
while [[ $# -gt 0 ]]; do
    [[ "$1" == --prompt-file ]] && { prompt_file="$2"; shift; }
    shift
done
cp "$prompt_file" "$PROMPT_COPY"
ls -A > "$CWD_LIST"
printf '%s\n' '{"response":{"summary":"cli ok","approach":"CLI"},"confidence":{"score":7}}'
EOF
chmod +x "$TMP/bin/muse"
cli_env=(PATH="$TMP/bin:$PATH" META_USE_API=false META_MODEL=muse-wonder-1.0 META_REASONING_EFFORT=high
    ARGS_FILE="$TMP/args" CWD_FILE="$TMP/cwd"
    PROMPT_COPY="$TMP/prompt" CWD_LIST="$TMP/cwd-list" ENABLE_PERSONA=true)
env "${cli_env[@]}" bash "$SCRIPT_DIR/query_meta.sh" "Secret-free question" "" "$TMP/cli.json" >/dev/null 2>&1 || fail $LINENO
args=$(tr '\n' ' ' < "$TMP/args")
for expected in 'exec --prompt-file ' '--model muse-wonder-1.0 ' '--contributor-mode off ' '--no-session-log ' \
    '--sandbox-network restricted ' '--disable-approval ' '--reasoning-effort high ' '--workspace ' \
    '--disable-shell ' '--disable-write ' '--disable-web-tools ' '--disable-request-user-input ' \
    '--no-foreign-personal-context '; do
    [[ "$args" == *"$expected"* ]] || fail $LINENO
done
[[ "$args" != *"Secret-free question"* ]] || fail $LINENO
grep -q 'Secret-free question' "$TMP/prompt" || fail $LINENO
grep -q 'The Systems Thinker' "$TMP/prompt" || fail $LINENO
[[ $(cat "$TMP/cwd") == *ai-consultants-meta.* && ! -s "$TMP/cwd-list" ]] || fail $LINENO
[[ ! -e "$(cat "$TMP/cwd")" ]] || fail $LINENO
jq -e '.consultant == "Meta" and .model == "muse-wonder-1.0" and .metadata.response_quality == "structured"
    and .metadata.cli_version == "muse 9.9.9" and .metadata.cli_compatibility == "capability-probed"
    and .response.summary == "cli ok"' "$TMP/cli.json" >/dev/null || fail $LINENO
# An empty effort leaves the CLI's own level.
env "${cli_env[@]}" META_REASONING_EFFORT= bash "$SCRIPT_DIR/query_meta.sh" "q" "" "$TMP/cli-noeffort.json" >/dev/null 2>&1 || fail $LINENO
[[ $(tr '\n' ' ' < "$TMP/args") != *--reasoning-effort* ]] || fail $LINENO
# A CLI without the required headless flags is never dispatched.
rm -f "$TMP/args"
if env "${cli_env[@]}" MUSE_FAKE_HELP=partial bash "$SCRIPT_DIR/query_meta.sh" "q" "" "$TMP/cli-old.json" >/dev/null 2>&1; then
    fail $LINENO
fi
[[ ! -e "$TMP/args" ]] || fail $LINENO
if env "${cli_env[@]}" META_REASONING_EFFORT=none bash "$SCRIPT_DIR/query_meta.sh" "q" "" "$TMP/cli-none.json" >/dev/null 2>&1; then
    fail $LINENO
fi
[[ ! -e "$TMP/args" ]] || fail $LINENO

printf '%s\n' 'Meta CLI/API transports, tiers, Contributor-mode guard and rates passed'
