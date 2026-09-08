#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/grok_sandbox.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
grok_sandbox_preflight "$TMP/absent"
: > "$TMP/file"
grok_sandbox_preflight "$TMP/file"
ln -s "$TMP/missing" "$TMP/dangling"
if grok_sandbox_preflight "$TMP/dangling" > "$TMP/diagnostic"; then exit 1; fi
grep -q "$TMP/dangling" "$TMP/diagnostic"
python3 - "$TMP/socket" <<'PY'
import socket,sys
s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.close()
PY
grok_sandbox_preflight "$TMP/socket"
ln -s "$TMP/socket" "$TMP/link"
if grok_sandbox_preflight "$TMP/link"; then exit 1; fi
for message in sandbox_profile_refused 'Warning: sandbox not applied'; do
    printf '%s\n' "$message" > "$TMP/message"
    for status in 0 1; do
        cat > "$TMP/fake" <<'STUB'
#!/bin/bash
printf 'call\n' >> "$CALLS"
cat "$MESSAGE" >&2
printf 'partial response\n'
exit "$STATUS"
STUB
        chmod +x "$TMP/fake"
        : > "$TMP/calls"
        rc=0
        CALLS="$TMP/calls" MESSAGE="$TMP/message" STATUS="$status" MAX_RETRIES=3 \
            run_query Grok "$TMP/out" 10 "$TMP/fake" </dev/null >/dev/null 2>&1 || rc=$?
        [[ $rc -eq 78 && $(wc -l < "$TMP/calls" | tr -d ' ') == 1 ]]
    done
done
# Adapter and doctor both stop before even probing the binary.
mkdir -p "$TMP/home/.docker/run" "$TMP/config" "$TMP/bin"
ln -s "$TMP/missing" "$TMP/home/.docker/run/docker.sock"
printf '#!/bin/bash\n: > "$DISPATCH_FILE"\nexit 99\n' > "$TMP/bin/grok"
cp "$TMP/bin/grok" "$TMP/bin/curl"
chmod +x "$TMP/bin/"*
rc=0
env HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" AI_CONSULTANTS_CONFIG_DIR="$TMP/config" \
    PATH="$TMP/bin:$PATH" GROK_CMD="$TMP/bin/grok" GROK_USE_API=false GROK_API_KEY=test \
    DISPATCH_FILE="$TMP/dispatched" ENABLE_PERSONA=false \
    bash "$SCRIPT_DIR/query_grok.sh" hello '' "$TMP/error.json" >/dev/null 2>&1 || rc=$?
[[ $rc -eq 78 && ! -e "$TMP/dispatched" ]]
jq -e '.metadata.response_quality == "error"' "$TMP/error.json" >/dev/null
rc=0
env HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config" AI_CONSULTANTS_CONFIG_DIR="$TMP/config" \
    PATH="$TMP/bin:$PATH" GROK_CMD="$TMP/bin/grok" GROK_USE_API=false ENABLE_GROK=true \
    ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false ENABLE_KIMI=false \
    ENABLE_CLAUDE=false ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false \
    DISPATCH_FILE="$TMP/dispatched" \
    bash "$SCRIPT_DIR/doctor.sh" --json --quick > "$TMP/doctor.json" 2>/dev/null || rc=$?
[[ $rc -ne 0 && ! -e "$TMP/dispatched" ]]
jq -e 'any(.doctor.issues[]; .description | contains("sandbox_runtime_socket_symlink"))' "$TMP/doctor.json" >/dev/null
printf '%s\n' 'Grok socket and sandbox refusal checks passed' 
