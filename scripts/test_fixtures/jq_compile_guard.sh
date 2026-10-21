#!/bin/bash
# jq_compile_guard.sh - Installed as `jq` on PATH by test_all.sh.
#
# Production code often runs jq with `2>/dev/null` and a fallback, so a filter
# that does not compile degrades silently: the report's Coverage Union never
# rendered until 5.3.1 because of one escaped quote. This shim runs the real
# jq, passes stdout and stderr through unchanged, and appends any compile
# error to $JQ_GUARD_LOG even when the caller discards stderr. test_all.sh
# fails the gate when that log is not empty.
#
# Runtime errors (invalid JSON input, iterating over null) are not recorded:
# callers handle them on purpose. Only errors in the filter itself are.

real="${JQ_GUARD_REAL:?JQ_GUARD_REAL must point at the real jq}"
log="${JQ_GUARD_LOG:?JQ_GUARD_LOG must name the compile-error log}"

# stdout goes straight through fd 3; only stderr is captured.
{ err=$("$real" "$@" 2>&1 1>&3 3>&-); rc=$?; } 3>&1

if [[ -n "$err" ]]; then
    printf '%s\n' "$err" >&2
    if [[ "$err" == *"jq: error: syntax error"* || "$err" == *" compile error"* \
          || "$err" == *"is not defined at <top-level>"* ]]; then
        {
            printf -- '--- rc=%s caller=%s\nargs:' "$rc" "${JQ_GUARD_CALLER:-$PWD}"
            for arg in "$@"; do printf ' [%s]' "${arg:0:300}"; done
            printf '\n%s\n' "$err"
        } >> "$log"
    fi
fi
exit "$rc"
