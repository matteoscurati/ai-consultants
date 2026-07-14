#!/usr/bin/env bash
# update_clis.sh - Check and update the CLIs behind ai-consultants' CLI-based
# consultants.
#
# For each supported CLI this:
#   1. checks whether the CLI is installed,
#   2. detects HOW it was installed (brew formula / brew cask / npm / uv /
#      pipx / pip / self-updating binary / curl-installer), and
#   3. updates it via the matching method.
#
# Usage: update_clis.sh [--dry-run] [--only <cli>] [-h|--help]
#   --dry-run     Report each CLI's status, install method, and the exact update
#                 command that WOULD run -- change nothing.
#   --only <cli>  Limit to one CLI, matched by consultant name or binary
#                 (e.g. "MiniMax", "mmx", "qwen").
#   -h, --help    Show this help.
#
# With no flags it updates every installed supported CLI, best-effort: a failure
# on one CLI is reported and the rest still run. Some updates run the CLI's
# official installer (curl | bash) -- use --dry-run first to see what will run.
# API-only consultants (GLM, Grok, DeepSeek) have no CLI and are not listed here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"   # logging helpers + config.sh (*_CMD overrides)

DRY_RUN=false
ONLY=""

# Canonical registry: "Display|CONFIG_CMD_VAR|default_binary". The command that
# actually gets checked is the CONFIG_CMD_VAR value (honoring user overrides),
# falling back to default_binary; package metadata is keyed by default_binary.
_CLI_ENTRIES=(
    "Gemini|GEMINI_CMD|agy"
    "Codex|CODEX_CMD|codex"
    "Mistral|MISTRAL_CMD|vibe"
    "Kilo|KILO_CMD|kilocode"
    "Cursor|CURSOR_CMD|agent"
    "Aider|AIDER_CMD|aider"
    "Amp|AMP_CMD|amp"
    "Kimi|KIMI_CMD|kimi"
    "Claude|CLAUDE_CMD|claude"
    "Qwen3|QWEN3_CMD|qwen"
    "MiniMax|MINIMAX_CMD|mmx"
    "Ollama|OLLAMA_CMD|ollama"
)

# Cached global package listings (filled once by _load_caches; tests may set them
# directly). Detection is then a cheap grep, not a per-CLI fork into a slow
# package manager.
_NPM_LS=""; _BREW_LS=""; _BREW_CASK_LS=""; _UV_LS=""; _PIPX_LS=""

# Result of the last detect_method call.
DETECT_METHOD=""   # brew|brew-cask|npm|uv|pipx|pip3|pip|self|installer|manual|unknown
DETECT_ARG=""      # package / cask / tool name to feed the update command

# _cli_meta <default_binary> -- populate package/update metadata. Empty = N/A.
#   NPM_PKG / PIP_PKG / BREW_FORMULA / BREW_CASK -- names for those managers
#   SELF_SUB   -- self-update subcommand (invoked as "<cli> <SELF_SUB>")
#   INSTALLER  -- runnable official installer (curl | bash)
#   MANUAL     -- human hint when there is no automated update path
_cli_meta() {
    NPM_PKG=""; PIP_PKG=""; BREW_FORMULA=""; BREW_CASK=""; SELF_SUB=""; INSTALLER=""; MANUAL=""
    case "$1" in
        agy)      INSTALLER="curl -fsSL https://antigravity.google/cli/install.sh | bash" ;;
        codex)    NPM_PKG="@openai/codex"; BREW_CASK="codex" ;;
        vibe)     PIP_PKG="mistral-vibe" ;;
        kilocode) NPM_PKG="@kilocode/cli" ;;
        agent)    INSTALLER="curl https://cursor.com/install -fsS | bash" ;;
        aider)    PIP_PKG="aider-chat" ;;
        amp)      SELF_SUB="update";  INSTALLER="curl -fsSL https://ampcode.com/install.sh | bash" ;;
        kimi)     SELF_SUB="upgrade"; INSTALLER="curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash" ;;
        claude)   BREW_CASK="claude-code@latest"; NPM_PKG="@anthropic-ai/claude-code"; SELF_SUB="update" ;;
        qwen)     NPM_PKG="@qwen-code/qwen-code" ;;
        mmx)      NPM_PKG="mmx-cli"; SELF_SUB="update" ;;
        ollama)   BREW_FORMULA="ollama"; INSTALLER="curl -fsSL https://ollama.com/install.sh | sh" ;;
    esac
}

_have() { command -v "$1" >/dev/null 2>&1; }

_load_caches() {
    _have npm  && _NPM_LS="$(npm ls -g --depth=0 2>/dev/null || true)"
    _have brew && _BREW_LS="$(brew list --formula 2>/dev/null || true)"
    _have brew && _BREW_CASK_LS="$(brew list --cask 2>/dev/null || true)"
    _have uv   && _UV_LS="$(uv tool list 2>/dev/null || true)"
    _have pipx && _PIPX_LS="$(pipx list 2>/dev/null || true)"
    return 0
}

# _pip_owner <pkg> -- which Python-tool manager owns it? Echoes uv|pipx|pip3|pip|"".
_pip_owner() {
    local pkg="$1"
    grep -qiF "$pkg" <<<"$_UV_LS"   && { echo "uv";   return; }
    grep -qiF "$pkg" <<<"$_PIPX_LS" && { echo "pipx"; return; }
    _have pip3 && pip3 show "$pkg" >/dev/null 2>&1 && { echo "pip3"; return; }
    _have pip  && pip  show "$pkg" >/dev/null 2>&1 && { echo "pip";  return; }
    echo ""
}

# detect_method <default_binary> [actual_cmd] -- sets DETECT_METHOD + DETECT_ARG.
# The resolved binary PATH is the most reliable signal (it names the manager and
# the exact package, e.g. a cask literally called "claude-code@latest"); the
# cached package lists are the fallback when the path is unrevealing. Tests pass
# an absent actual_cmd to force the deterministic cache path.
detect_method() {
    local default_bin="$1" actual_cmd="${2:-$1}"
    _cli_meta "$default_bin"
    DETECT_METHOD="unknown"; DETECT_ARG=""

    local rp=""
    _have "$actual_cmd" && rp="$(realpath "$(command -v "$actual_cmd")" 2>/dev/null || true)"
    case "$rp" in
        */Caskroom/*) DETECT_METHOD="brew-cask"; DETECT_ARG="$(sed -E 's#.*/Caskroom/([^/]+)/.*#\1#' <<<"$rp")"; return ;;
        */uv/tools/*) DETECT_METHOD="uv";        DETECT_ARG="$(sed -E 's#.*/uv/tools/([^/]+)/.*#\1#' <<<"$rp")"; return ;;
        */pipx/*)     DETECT_METHOD="pipx";       DETECT_ARG="${PIP_PKG:-$default_bin}"; return ;;
    esac

    if [[ -n "$BREW_FORMULA" ]] && grep -qxF "$BREW_FORMULA" <<<"$_BREW_LS"; then DETECT_METHOD="brew"; DETECT_ARG="$BREW_FORMULA"; return; fi
    if [[ -n "$BREW_CASK" ]] && grep -qxF "$BREW_CASK" <<<"$_BREW_CASK_LS"; then DETECT_METHOD="brew-cask"; DETECT_ARG="$BREW_CASK"; return; fi
    if [[ -n "$NPM_PKG" ]] && grep -qF "${NPM_PKG}@" <<<"$_NPM_LS"; then DETECT_METHOD="npm"; DETECT_ARG="$NPM_PKG"; return; fi
    if [[ -n "$PIP_PKG" ]]; then
        local owner; owner="$(_pip_owner "$PIP_PKG")"
        [[ -n "$owner" ]] && { DETECT_METHOD="$owner"; DETECT_ARG="$PIP_PKG"; return; }
    fi
    [[ -n "$SELF_SUB" ]]  && { DETECT_METHOD="self"; return; }
    [[ -n "$INSTALLER" ]] && { DETECT_METHOD="installer"; return; }
    [[ -n "$MANUAL" ]]    && { DETECT_METHOD="manual"; return; }
}

# _run "<human description>" cmd args...  -- respects --dry-run; returns cmd status.
_run() {
    local desc="$1"; shift
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "  would run: $desc"
        return 0
    fi
    log_info "  running: $desc"
    "$@"
}

# update_one <cmd> <default_binary> -- acts on DETECT_METHOD/DETECT_ARG. Returns
# 0 updated/attempted, 1 failed, 2 no automated action (manual/unknown).
update_one() {
    local cmd="$1" metabin="$2"
    _cli_meta "$metabin"   # for SELF_SUB / INSTALLER / MANUAL
    case "$DETECT_METHOD" in
        brew)      _run "brew upgrade $DETECT_ARG" brew upgrade "$DETECT_ARG" ;;
        brew-cask) _run "brew upgrade --cask $DETECT_ARG" brew upgrade --cask "$DETECT_ARG" ;;
        npm)       _run "npm install -g ${DETECT_ARG}@latest" npm install -g "${DETECT_ARG}@latest" ;;
        uv)        _run "uv tool upgrade $DETECT_ARG" uv tool upgrade "$DETECT_ARG" ;;
        pipx)      _run "pipx upgrade $DETECT_ARG" pipx upgrade "$DETECT_ARG" ;;
        pip3)      _run "pip3 install --upgrade $DETECT_ARG" pip3 install --upgrade "$DETECT_ARG" ;;
        pip)       _run "pip install --upgrade $DETECT_ARG" pip install --upgrade "$DETECT_ARG" ;;
        self)
            if _run "$cmd $SELF_SUB" "$cmd" "$SELF_SUB" </dev/null; then
                return 0
            fi
            log_warn "  '$cmd $SELF_SUB' failed"
            # Some self-updaters bail on this platform and point at the installer.
            if [[ -n "$INSTALLER" ]]; then
                _run "$INSTALLER" bash -c "$INSTALLER" </dev/null
            else
                return 1
            fi ;;
        installer) _run "$INSTALLER" bash -c "$INSTALLER" </dev/null ;;
        manual)    log_warn "  manual update: $MANUAL"; return 2 ;;
        *)         log_warn "  no automated update path known -- reinstall manually"; return 2 ;;
    esac
}

# Print only the leading header comment block (stop at the first non-comment
# line) so internal implementation comments don't leak into --help output.
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --only)    ONLY="${2:-}"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *)         log_error "unknown option: $1"; usage; exit 2 ;;
        esac
    done

    log_info "Scanning supported consultant CLIs$([[ "$DRY_RUN" == "true" ]] && echo " (dry-run: nothing will change)")..."
    _load_caches

    local n_updated=0 n_failed=0 n_missing=0 n_manual=0 matched=0
    local entry display cmd_var default_bin cmd ver
    for entry in "${_CLI_ENTRIES[@]}"; do
        IFS='|' read -r display cmd_var default_bin <<<"$entry"

        if [[ -n "$ONLY" ]]; then
            local o dlow blow
            o="$(to_lower "$ONLY")"; dlow="$(to_lower "$display")"; blow="$(to_lower "$default_bin")"
            [[ "$o" == "$dlow" || "$o" == "$blow" ]] || continue
        fi
        matched=$((matched + 1))

        cmd="${!cmd_var:-$default_bin}"
        if ! _have "$cmd"; then
            log_warn "$display ($cmd): not installed -- skipping"
            n_missing=$((n_missing + 1))
            continue
        fi

        ver="$(run_with_timeout 8 "$cmd" --version </dev/null 2>/dev/null | head -1 || true)"
        detect_method "$default_bin" "$cmd"
        log_info "$display ($cmd): installed [${ver:-version n/a}] -- install method: $DETECT_METHOD"

        local rc=0
        update_one "$cmd" "$default_bin" || rc=$?
        case "$rc" in
            0) n_updated=$((n_updated + 1)) ;;
            2) n_manual=$((n_manual + 1)) ;;
            *) n_failed=$((n_failed + 1)); log_warn "$display: update failed" ;;
        esac
    done

    if [[ -n "$ONLY" && "$matched" -eq 0 ]]; then
        log_error "no supported CLI matches --only '$ONLY'"
        exit 2
    fi

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run complete. $n_missing not installed. Re-run without --dry-run to apply."
    else
        log_success "Done. Updated/attempted: $n_updated | manual: $n_manual | failed: $n_failed | not installed: $n_missing"
    fi
    [[ "$n_failed" -eq 0 ]]
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
