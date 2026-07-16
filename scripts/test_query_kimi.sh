#!/bin/bash
# Regression test: query_kimi.sh must pin the configured Kimi model on the CLI.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test_query_kimi.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_KIMI="$TMP_ROOT/kimi"
ARGS_FILE="$TMP_ROOT/args"
OUTPUT_FILE="$TMP_ROOT/response.json"

cat > "$FAKE_KIMI" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$KIMI_ARGS_FILE"
printf '%s\n' '{"role":"assistant","content":"{\"summary\":\"K3 selected\",\"approach\":\"Test\",\"pros\":[],\"cons\":[],\"risks\":[],\"recommendations\":[],\"confidence\":9}"}'
EOF
chmod +x "$FAKE_KIMI"

if ! KIMI_CMD="$FAKE_KIMI" \
    KIMI_MODEL="kimi-code/k3" \
    KIMI_ARGS_FILE="$ARGS_FILE" \
    MAX_RETRIES=1 \
    "$SCRIPT_DIR/query_kimi.sh" "Test model selection" "" "$OUTPUT_FILE" >/dev/null 2>&1; then
    echo "FAIL: query_kimi.sh did not complete with the stub CLI"
    exit 1
fi

mapfile_compat=()
while IFS= read -r arg; do
    mapfile_compat+=("$arg")
done < "$ARGS_FILE"

found=false
for ((i = 0; i < ${#mapfile_compat[@]} - 1; i++)); do
    if [[ "${mapfile_compat[$i]}" == "--model" && "${mapfile_compat[$((i + 1))]}" == "kimi-code/k3" ]]; then
        found=true
        break
    fi
done

if [[ "$found" != "true" ]]; then
    echo "FAIL: expected '--model kimi-code/k3' in Kimi CLI arguments"
    printf '  %s\n' "${mapfile_compat[@]}"
    exit 1
fi

if [[ "$(jq -r '.model' "$OUTPUT_FILE")" != "kimi-code/k3" ]]; then
    echo "FAIL: response metadata does not report kimi-code/k3"
    exit 1
fi

echo "PASS: query_kimi.sh explicitly selects kimi-code/k3"
