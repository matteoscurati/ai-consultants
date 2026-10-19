#!/bin/bash
# agy_exit_guard.sh - Run agy and keep its answer if the process never exits.
#
# agy (Antigravity CLI 1.4) can stay alive after it printed its whole answer:
# on 2026-10-19 a synthesis closed its conversation stream ("Stream goroutine
# exited") and the process then idled for 16 minutes without exiting. With no
# generation timeout the consultation would wait for it forever. Once stdout
# holds one complete JSON object that has not changed for <grace_seconds>,
# end the process and keep the answer. Any other output (prose, a partial
# object, nothing yet) waits for agy to exit, exactly as without the guard.
#
# Usage: agy_exit_guard.sh <grace_seconds> <command> [args...]
#   stdin goes to the command and its stdout is copied to ours once it ends.
#   Exit status: the command's, or 0 when the guard ended it after a complete
#   answer. grace_seconds=0 runs the command directly.

set -u

grace="${1:-0}"
shift
[[ "$grace" =~ ^[0-9]+$ ]] || grace=0
(( grace > 0 )) || exec "$@"

out=$(mktemp "${TMPDIR:-/tmp}/ai-consultants-agy.XXXXXX") || exec "$@"
child=""

_end_child() {
    local waited=0
    [[ -n "$child" ]] || return 0
    pkill -TERM -P "$child" 2>/dev/null
    kill -TERM "$child" 2>/dev/null
    while kill -0 "$child" 2>/dev/null && (( waited < 50 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    pkill -KILL -P "$child" 2>/dev/null
    kill -KILL "$child" 2>/dev/null
    wait "$child" 2>/dev/null
    child=""
}

# Stopped by a timeout or the host: never leave agy running without us.
trap '_end_child; rm -f "$out"' EXIT
trap 'exit 143' TERM
trap 'exit 129' HUP

# One JSON object, optionally inside a Markdown code fence.
_answer_is_complete() {
    sed -e '1{/^[[:space:]]*```[[:alnum:]]*[[:space:]]*$/d;}' \
        -e '${/^[[:space:]]*```[[:space:]]*$/d;}' "$out" \
        | jq -e 'type == "object"' >/dev/null 2>&1
}

"$@" <&0 >"$out" &
child=$!

last_size=-1
stable=0
while kill -0 "$child" 2>/dev/null; do
    size=$(wc -c <"$out" | tr -d ' ')
    if [[ "$size" == "$last_size" ]]; then
        stable=$((stable + 1))
    else
        last_size="$size"
        stable=0
    fi
    if (( size > 0 && stable >= grace )) && _answer_is_complete; then
        echo "agy printed a complete answer but had not exited ${stable}s later; ending it and keeping the answer" >&2
        _end_child
        cat "$out"
        exit 0
    fi
    sleep 1
done

rc=0
wait "$child" || rc=$?
child=""
cat "$out"
exit "$rc"
