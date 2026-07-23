#!/bin/bash
# doctor.sh - Comprehensive diagnostic command for AI Consultants
#
# Performs in-depth health checks with specific fix suggestions:
# - Checks all CLI tools are installed
# - Verifies API keys are configured
# - Tests connectivity to each service
# - Validates configuration
# - Suggests specific commands to fix issues
#
# Usage: ./doctor.sh [--fix] [--json] [--verbose] [--quick] [--suggest-config]
#                    [--suggest-preset --question "..."]
#
# Options:
#   --fix              Attempt to auto-fix common issues
#   --json             Output in JSON format
#   --verbose          Show detailed diagnostic information
#   --quick            Skip optional connectivity tests (accepted for compat)
#   --suggest-config   Print recommended ENABLE_* configuration based on detected CLIs
#   --suggest-preset   Recommend preset + strategy for a question (use --question)
#   --question "..."   Question text used by --suggest-preset (otherwise GENERAL)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# --- Parameters ---
FIX_MODE=false
JSON_OUTPUT=false
VERBOSE=false
QUICK_MODE=false
SUGGEST_CONFIG=false
SUGGEST_PRESET=false
LIVE_MODE=false
QUESTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --suggest-config)
            SUGGEST_CONFIG=true
            shift
            ;;
        --suggest-preset)
            SUGGEST_PRESET=true
            shift
            ;;
        --live)
            LIVE_MODE=true
            shift
            ;;
        --question)
            QUESTION="${2:-}"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--fix] [--json] [--verbose] [--quick] [--suggest-config]"
            echo "       $0 --suggest-preset [--question \"...\"]"
            echo ""
            echo "Comprehensive diagnostic for AI Consultants"
            echo ""
            echo "Options:"
            echo "  --fix              Attempt to auto-fix common issues"
            echo "  --json             Output in JSON format"
            echo "  --verbose          Show detailed diagnostic information"
            echo "  --quick            Skip optional connectivity tests (accepted for compat)"
            echo "  --suggest-config   Print recommended ENABLE_* configuration"
            echo "  --suggest-preset   Recommend preset + strategy for a question"
            echo "  --question \"...\"   Question text for --suggest-preset"
            echo "  --live             Send a real ping query to each enabled consultant"
            echo "                     (catches installed-but-unauthenticated CLIs that the"
            echo "                     static check reports as healthy). Costs a tiny query each."
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# --- State tracking ---
ISSUES=()
WARNINGS=()
FIXES_APPLIED=()
TOTAL_CHECKS=0
PASSED_CHECKS=0

# =============================================================================
# DIAGNOSTIC FUNCTIONS
# =============================================================================

add_issue() {
    local category="$1"
    local description="$2"
    local fix_command="$3"
    ISSUES+=("$category|$description|$fix_command")
}

add_warning() {
    local category="$1"
    local description="$2"
    WARNINGS+=("$category|$description")
}

check_pass() {
    (( ++TOTAL_CHECKS ))
    (( ++PASSED_CHECKS ))
}

check_fail() {
    (( ++TOTAL_CHECKS ))
}

# Print only in non-JSON mode
_print() {
    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo "$@"
    fi
}

print_header() {
    _print ""
    _print "╔══════════════════════════════════════════════════════════════╗"
    _print "║           AI Consultants v${AI_CONSULTANTS_VERSION:-2.2.0} - Doctor                    ║"
    _print "╚══════════════════════════════════════════════════════════════╝"
    _print ""
}

print_section() {
    local title="$1"
    _print ""
    _print "▶ $title"
    _print "────────────────────────────────────────────────────────────────"
}

# =============================================================================
# CHECK: Required Dependencies
# =============================================================================

check_dependencies() {
    print_section "Checking Required Dependencies"

    # jq is required
    if command -v jq &> /dev/null; then
        local jq_version
        jq_version=$(jq --version 2>/dev/null || echo "unknown")
        _print "  ✓ jq: $jq_version"
        check_pass
    else
        _print "  ✗ jq: NOT INSTALLED (required)"
        add_issue "dependency" "jq is not installed" "brew install jq  # or: apt install jq"
        check_fail
    fi

    # bash version check (3.2+ for macOS compatibility)
    local bash_version="${BASH_VERSION%%(*}"
    local bash_major="${bash_version%%.*}"
    if [[ $bash_major -ge 3 ]]; then
        _print "  ✓ bash: $BASH_VERSION"
        check_pass
    else
        _print "  ✗ bash: $BASH_VERSION (need 3.2+)"
        add_issue "dependency" "Bash version too old" "brew install bash"
        check_fail
    fi

    # timeout command (optional, has fallback)
    if command -v timeout &> /dev/null || command -v gtimeout &> /dev/null; then
        _print "  ✓ timeout: available"
        check_pass
    else
        _print "  ○ timeout: not found (using fallback)"
        add_warning "dependency" "timeout command not found, using POSIX fallback"
    fi

    # curl for API checks
    if command -v curl &> /dev/null; then
        _print "  ✓ curl: available"
        check_pass
    else
        _print "  ✗ curl: NOT INSTALLED"
        add_issue "dependency" "curl is not installed" "brew install curl"
        check_fail
    fi
}

# =============================================================================
# CHECK: CLI-based Consultants
# =============================================================================

check_cli_consultant() {
    local name="$1"
    local cmd="$2"
    local install_cmd="$3"
    local env_var="$4"

    # Check if enabled
    local enabled_var="ENABLE_${env_var}"
    local is_enabled="${!enabled_var:-false}"

    if [[ "$is_enabled" != "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: disabled"
        return 0
    fi

    # Skip the CLI install check when the consultant runs in API mode. For the
    # 6 switchable agents (Gemini, Codex, Claude, Mistral, Qwen3, MiniMax) a missing CLI
    # is irrelevant once API mode is on -- the API key is validated separately
    # by check_api_mode. This matters most for Gemini, which auto-resolves to
    # API mode whenever GEMINI_API_KEY is set (the npm-friendly path).
    local use_api_var="${env_var}_USE_API"
    if [[ "${!use_api_var:-false}" == "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: API mode (CLI not required)"
        return 0
    fi

    # Check if installed
    if ! command -v "$cmd" &> /dev/null; then
        _print "  ✗ $name: NOT INSTALLED (enabled but missing)"
        if [[ "$name" == "Gemini" ]]; then
            _print "      tip: set GEMINI_API_KEY to use API mode (no CLI install needed)"
        fi
        add_issue "consultant" "$name CLI not found" "$install_cmd"
        check_fail
        return 1
    fi

    # Get version (--version is standard and fast, no timeout needed)
    local version
    version=$("$cmd" --version 2>/dev/null | head -1 || echo "")

    if [[ -n "$version" ]]; then
        _print "  ✓ $name: $version"
        check_pass
    else
        # Fallback: CLI exists but --version failed, still consider it installed
        _print "  ✓ $name: installed (version unknown)"
        check_pass
    fi
}

check_cli_consultants() {
    print_section "Checking CLI-based Consultants"

    check_cli_consultant "Gemini" "$GEMINI_CMD" "curl -fsSL https://antigravity.google/cli/install.sh | bash" "GEMINI"
    check_cli_consultant "Codex" "$CODEX_CMD" "npm install -g @openai/codex" "CODEX"
    check_cli_consultant "Mistral Vibe" "$MISTRAL_CMD" "pip install mistral-vibe" "MISTRAL"
    check_cli_consultant "Cursor" "$CURSOR_CMD" "Visit https://cursor.com to install" "CURSOR"
    check_cli_consultant "Kimi" "$KIMI_CMD" "curl -L code.kimi.com/install.sh | bash" "KIMI"
    check_cli_consultant "Claude" "$CLAUDE_CMD" "See https://docs.anthropic.com/claude-code" "CLAUDE"
    check_cli_consultant "Qwen" "$QWEN3_CMD" "npm install -g @qwen-code/qwen-code@latest" "QWEN3"
    check_cli_consultant "MiniMax" "$MINIMAX_CMD" "npm install -g mmx-cli" "MINIMAX"
}

# =============================================================================
# CHECK: CLI/API Mode Switching (v2.6)
# =============================================================================

check_api_mode() {
    local name="$1"
    local use_api_var="$2"
    local api_key_var="$3"
    local enabled_var="$4"

    local is_enabled="${!enabled_var:-false}"
    local use_api="${!use_api_var:-false}"

    if [[ "$is_enabled" != "true" ]]; then
        return 0  # Skip disabled consultants
    fi

    if [[ "$use_api" == "true" ]]; then
        local api_key="${!api_key_var:-}"
        if [[ -z "$api_key" ]]; then
            _print "  ✗ $name: API mode enabled but $api_key_var not set"
            add_issue "api_mode" "$name API mode enabled but API key missing" "export ${api_key_var}='your-api-key'"
            check_fail
            return 1
        else
            local masked_key="${api_key:0:4}...${api_key: -4}"
            _print "  ✓ $name: API mode (key: $masked_key)"
            check_pass
        fi
    else
        _print "  ○ $name: CLI mode"
    fi
}

check_api_mode_switching() {
    print_section "Checking CLI/API Mode Switching (v2.7)"

    local has_api_mode=false

    # Check switchable consultants
    for agent in GEMINI CODEX CLAUDE MISTRAL QWEN3 MINIMAX; do
        local enabled_var="ENABLE_${agent}"
        local use_api_var="${agent}_USE_API"
        local is_enabled="${!enabled_var:-false}"
        local use_api="${!use_api_var:-false}"

        if [[ "$is_enabled" == "true" && "$use_api" == "true" ]]; then
            has_api_mode=true
            break
        fi
    done

    if [[ "$has_api_mode" == "true" ]] || [[ "$VERBOSE" == "true" ]]; then
        check_api_mode "Gemini" "GEMINI_USE_API" "GEMINI_API_KEY" "ENABLE_GEMINI"
        check_api_mode "Codex" "CODEX_USE_API" "OPENAI_API_KEY" "ENABLE_CODEX"
        check_api_mode "Claude" "CLAUDE_USE_API" "ANTHROPIC_API_KEY" "ENABLE_CLAUDE"
        check_api_mode "Mistral" "MISTRAL_USE_API" "MISTRAL_API_KEY" "ENABLE_MISTRAL"
        check_api_mode "Qwen3" "QWEN3_USE_API" "QWEN3_API_KEY" "ENABLE_QWEN3"
        check_api_mode "MiniMax" "MINIMAX_USE_API" "MINIMAX_API_KEY" "ENABLE_MINIMAX"
    else
        _print "  ○ All switchable consultants using CLI mode"
    fi
}

# =============================================================================
# CHECK: API-based Consultants
# =============================================================================

check_api_consultant() {
    local name="$1"
    local api_key_var="$2"
    local api_url_var="$3"
    local enabled_var="$4"

    local is_enabled="${!enabled_var:-false}"

    if [[ "$is_enabled" != "true" ]]; then
        [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: disabled"
        return 0
    fi

    local api_key="${!api_key_var:-}"
    local api_url="${!api_url_var:-}"

    # Check API key
    if [[ -z "$api_key" ]]; then
        _print "  ✗ $name: API key not set"
        add_issue "api" "$name API key not configured" "export ${api_key_var}='your-api-key'"
        check_fail
        return 1
    fi

    # Mask API key for display
    local masked_key="${api_key:0:4}...${api_key: -4}"

    # Test connectivity (simple HEAD request to avoid charges)
    if [[ -n "$api_url" ]] && command -v curl &> /dev/null; then
        if timeout 10 curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $api_key" "$api_url" 2>/dev/null | grep -qE "^(200|401|403)"; then
            _print "  ✓ $name: configured (key: $masked_key)"
            check_pass
        else
            _print "  △ $name: configured but API unreachable"
            add_warning "api" "$name API endpoint unreachable"
            check_pass
        fi
    else
        _print "  ✓ $name: configured (key: $masked_key)"
        check_pass
    fi
}

check_api_consultants() {
    print_section "Checking API-only Consultants"

    check_api_consultant "GLM" "GLM_API_KEY" "GLM_API_URL" "ENABLE_GLM"
    check_api_consultant "Grok" "GROK_API_KEY" "GROK_API_URL" "ENABLE_GROK"
    check_api_consultant "DeepSeek" "DEEPSEEK_API_KEY" "DEEPSEEK_API_URL" "ENABLE_DEEPSEEK"
}

# =============================================================================
# CHECK: Configuration
# =============================================================================

check_configuration() {
    print_section "Checking Configuration"

    # Count enabled consultants using a compact loop
    local enabled_count=0
    local consultant_flags="ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_CURSOR ENABLE_KIMI ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX"
    for flag in $consultant_flags; do
        [[ "${!flag:-false}" == "true" ]] && { ((enabled_count++)) || true; }
    done

    if [[ $enabled_count -ge 2 ]]; then
        _print "  ✓ Enabled consultants: $enabled_count (minimum 2 required)"
        check_pass
    elif [[ $enabled_count -eq 1 ]]; then
        _print "  ✗ Enabled consultants: $enabled_count (need at least 2)"
        add_issue "config" "Only 1 consultant enabled, need at least 2" "Run: ./scripts/setup_wizard.sh"
        check_fail
    else
        _print "  ✗ Enabled consultants: 0 (need at least 2)"
        add_issue "config" "No consultants enabled" "Run: ./scripts/setup_wizard.sh"
        check_fail
    fi

    # Check output directory permissions
    if [[ -d "$DEFAULT_OUTPUT_DIR_BASE" ]]; then
        if [[ -w "$DEFAULT_OUTPUT_DIR_BASE" ]]; then
            _print "  ✓ Output directory: writable"
            check_pass
        else
            _print "  ✗ Output directory: not writable"
            add_issue "config" "Output directory not writable" "chmod 755 $DEFAULT_OUTPUT_DIR_BASE"
            check_fail
        fi
    else
        _print "  ○ Output directory: will be created on first run"
        check_pass
    fi

    # Check session directory
    if [[ -d "$SESSION_DIR" ]]; then
        local session_count
        session_count=$(find "$SESSION_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
        _print "  ✓ Session directory: $session_count sessions"
        check_pass
    else
        _print "  ○ Session directory: will be created on first run"
        check_pass
    fi

    # Budget enforcement status
    local budget_enabled="${ENABLE_BUDGET_LIMIT:-false}"
    local budget_action="${BUDGET_ACTION:-warn}"
    if [[ "$budget_enabled" == "true" ]]; then
        _print "  ✓ Budget limit: \$${MAX_SESSION_COST} (enabled, action: $budget_action)"
        check_pass
    else
        _print "  ○ Budget limit: \$${MAX_SESSION_COST} (disabled)"
    fi
}

# =============================================================================
# CHECK: Synthesis Engine
# =============================================================================

check_user_config() {
    print_section "Checking User Config (v2.12)"

    # Resolve user config dir via the canonical helper (lib/user_config.sh).
    # Available transitively: doctor sources common.sh -> config.sh -> user_config.sh.
    local user_dir
    user_dir=$(get_user_config_dir)
    if [[ -z "$user_dir" ]]; then
        _print "  ○ User config dir: HOME and XDG_CONFIG_HOME both unset (running in container?)"
        return 0
    fi

    if [[ ! -d "$user_dir" ]]; then
        _print "  ○ User config dir: not present ($user_dir)"
        _print "       Create with: ai-consultants init"
        return 0
    fi
    _print "  ✓ User config dir: $user_dir"
    check_pass

    local files=()
    [[ -f "$user_dir/.env" ]] && files+=(".env")
    [[ -f "$user_dir/config.sh" ]] && files+=("config.sh")
    [[ -f "$user_dir/affinity.json" ]] && files+=("affinity.json")

    if [[ ${#files[@]} -eq 0 ]]; then
        _print "  ○ User config files: none (dir exists but is empty)"
    else
        _print "  ✓ User config files: ${files[*]}"
        check_pass
    fi

    # Warn if .env has lax permissions (likely contains API keys)
    if [[ -f "$user_dir/.env" ]]; then
        local perms
        perms=$(stat -f '%Lp' "$user_dir/.env" 2>/dev/null || stat -c '%a' "$user_dir/.env" 2>/dev/null || echo "")
        if [[ -n "$perms" ]] && [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]]; then
            _print "  △ .env permissions are $perms (recommended: 600)"
            add_warning "user_config" ".env has loose permissions ($perms); contains API keys, run: chmod 600 $user_dir/.env"
        fi
    fi
}

check_routing() {
    print_section "Checking Routing Affinity Matrix (v2.11)"

    local affinity_file="${AFFINITY_FILE:-$SCRIPT_DIR/../references/affinity.json}"

    if [[ ! -f "$affinity_file" ]]; then
        _print "  ✗ Affinity file: missing ($affinity_file)"
        add_issue "routing" "References file not found: $affinity_file" "Reinstall or restore from git"
        check_fail
        return 1
    fi

    if ! jq empty "$affinity_file" 2>/dev/null; then
        _print "  ✗ Affinity file: invalid JSON"
        add_issue "routing" "Invalid JSON in $affinity_file" "Validate with: jq . $affinity_file"
        check_fail
        return 1
    fi
    _print "  ✓ Affinity file: $affinity_file"
    check_pass

    # Schema sanity: required top-level keys
    local missing_keys
    missing_keys=$(jq -r '
        ["default_score","general_score","known_consultants","categories"]
        - (keys | map(select(. != "_comment" and . != "version")))
        | join(",")
    ' "$affinity_file" 2>/dev/null)
    if [[ -n "$missing_keys" ]]; then
        _print "  ✗ Affinity schema: missing keys ($missing_keys)"
        add_issue "routing" "Affinity JSON is missing required keys: $missing_keys" "See docs/SMART_ROUTING.md"
        check_fail
    else
        _print "  ✓ Affinity schema: valid (default_score, general_score, known_consultants, categories)"
        check_pass
    fi

    # Coverage: every known consultant should appear in every category
    local coverage_gaps
    coverage_gaps=$(jq -r '
        .known_consultants as $known
        | .categories
        | to_entries
        | map(
            . as $cat
            | $known - ($cat.value | keys)
            | select(length > 0)
            | "\($cat.key): \(. | join(","))"
          )
        | join("; ")
    ' "$affinity_file" 2>/dev/null)
    if [[ -n "$coverage_gaps" ]]; then
        _print "  △ Affinity coverage: gaps detected"
        _print "       $coverage_gaps"
        add_warning "routing" "Affinity matrix has consultants missing per category: $coverage_gaps"
    else
        local cat_count consultant_count
        cat_count=$(jq -r '.categories | length' "$affinity_file")
        consultant_count=$(jq -r '.known_consultants | length' "$affinity_file")
        _print "  ✓ Affinity coverage: $consultant_count consultants x $cat_count categories"
        check_pass
    fi
}

check_synthesis() {
    print_section "Checking Synthesis Engine"

    if [[ "$ENABLE_SYNTHESIS" != "true" ]]; then
        _print "  ○ Synthesis: disabled"
        return 0
    fi

    # Check for claude CLI (preferred)
    if command -v claude &> /dev/null; then
        local claude_version
        claude_version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
        _print "  ✓ Claude CLI: $claude_version"
        check_pass
    else
        _print "  △ Claude CLI: not found (will use fallback synthesis)"
        add_warning "synthesis" "Claude CLI not installed, using basic fallback synthesis"
    fi

    # Check synthesis template
    local template_file="$SCRIPT_DIR/../templates/synthesis_prompt.md"
    if [[ -f "$template_file" ]]; then
        _print "  ✓ Synthesis template: found"
        check_pass
    else
        _print "  ○ Synthesis template: using default"
    fi
}

# =============================================================================
# SUMMARY AND FIXES
# =============================================================================

print_summary() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Build issues array
        local issues_json="[]"
        if (( ${#ISSUES[@]} > 0 )); then
            for issue in "${ISSUES[@]}"; do
                IFS='|' read -r category description fix <<< "$issue"
                issues_json=$(echo "$issues_json" | jq \
                    --arg cat "$category" \
                    --arg desc "$description" \
                    --arg fix "$fix" \
                    '. + [{"category": $cat, "description": $desc, "fix": $fix}]')
            done
        fi

        # Build warnings array
        local warnings_json="[]"
        if (( ${#WARNINGS[@]} > 0 )); then
            for warning in "${WARNINGS[@]}"; do
                IFS='|' read -r category description <<< "$warning"
                warnings_json=$(echo "$warnings_json" | jq \
                    --arg cat "$category" \
                    --arg desc "$description" \
                    '. + [{"category": $cat, "description": $desc}]')
            done
        fi

        jq -n \
            --argjson total "$TOTAL_CHECKS" \
            --argjson passed "$PASSED_CHECKS" \
            --argjson issues "${#ISSUES[@]}" \
            --argjson warnings "${#WARNINGS[@]}" \
            --argjson issues_list "$issues_json" \
            --argjson warnings_list "$warnings_json" \
            --arg version "$AI_CONSULTANTS_VERSION" \
            --arg verified "$([[ "$LIVE_MODE" == "true" ]] && echo live || echo static)" \
            '{
                doctor: {
                    version: $version,
                    # "healthy" requires a live check. Static-only cannot see an
                    # expired key or exhausted quota, so it reports "static_ok",
                    # not "healthy". `verified` says which check backs the status.
                    status: (if $issues > 0 then "unhealthy"
                             elif $warnings > 0 then "degraded"
                             elif $verified == "live" then "healthy"
                             else "static_ok" end),
                    verified: $verified,
                    checks: {
                        total: $total,
                        passed: $passed,
                        failed: ($total - $passed)
                    },
                    issues: $issues_list,
                    warnings: $warnings_list
                }
            }'
    else
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                       Diagnosis Summary                       ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Checks: $PASSED_CHECKS/$TOTAL_CHECKS passed"
        echo "  Issues: ${#ISSUES[@]}"
        echo "  Warnings: ${#WARNINGS[@]}"
        echo ""

        if [[ ${#ISSUES[@]} -gt 0 ]]; then
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  ISSUES (must fix)                                          │"
            echo "└─────────────────────────────────────────────────────────────┘"
            for issue in "${ISSUES[@]}"; do
                IFS='|' read -r category description fix <<< "$issue"
                echo ""
                echo "  [$category] $description"
                echo "  Fix: $fix"
            done
            echo ""
        fi

        if [[ ${#WARNINGS[@]} -gt 0 ]]; then
            echo "┌─────────────────────────────────────────────────────────────┐"
            echo "│  WARNINGS (optional)                                        │"
            echo "└─────────────────────────────────────────────────────────────┘"
            for warning in "${WARNINGS[@]}"; do
                IFS='|' read -r category description <<< "$warning"
                echo "  [$category] $description"
            done
            echo ""
        fi

        if [[ ${#ISSUES[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
            # Do NOT claim "healthy" on static checks alone: they confirm a CLI is
            # installed and a key is present, NOT that a consultant can actually
            # answer. A consultant with an expired key or exhausted quota passes
            # every static check and fails on the first real query. Only --live,
            # which sends a real ping, earns the word "healthy".
            if [[ "$LIVE_MODE" == "true" ]]; then
                echo "  ✓ All checks passed — consultants verified responding (live)."
            else
                echo "  ✓ Static checks passed: CLIs installed, keys present."
                echo "    This does NOT confirm consultants can answer — an expired key or"
                echo "    used-up quota passes every static check. Verify with: doctor --live"
            fi
            echo ""
        elif [[ ${#ISSUES[@]} -eq 0 ]]; then
            echo "  △ System operational with warnings"
            [[ "$LIVE_MODE" != "true" ]] && echo "    (static only — run 'doctor --live' to confirm consultants answer)"
            echo ""
        else
            echo "  ✗ Issues found - run with --fix to attempt auto-repair"
            echo ""
        fi
    fi
}

attempt_fixes() {
    if [[ "$FIX_MODE" != "true" || ${#ISSUES[@]} -eq 0 ]]; then
        return 0
    fi

    print_section "Attempting Auto-Fixes"

    for issue in "${ISSUES[@]}"; do
        IFS='|' read -r category description fix <<< "$issue"

        # Only auto-fix safe operations with whitelisted commands
        case "$category" in
            dependency)
                # Extract package name safely (whitelist approach, no eval)
                local package=""
                if [[ "$fix" =~ ^brew\ install\ ([a-zA-Z0-9_-]+)$ ]]; then
                    package="${BASH_REMATCH[1]}"
                fi

                if [[ -n "$package" ]] && command -v brew &>/dev/null; then
                    echo "  Attempting: brew install $package"
                    if brew install "$package" 2>/dev/null; then
                        echo "  ✓ Fixed: $description"
                        FIXES_APPLIED+=("$description")
                    else
                        echo "  ✗ Failed to fix: $description"
                    fi
                else
                    echo "  ○ Manual fix required: $fix"
                fi
                ;;
            config)
                echo "  ○ Manual fix required: $fix"
                ;;
            *)
                echo "  ○ Manual fix required: $fix"
                ;;
        esac
    done

    if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
        echo ""
        echo "  Applied ${#FIXES_APPLIED[@]} fix(es). Re-run doctor to verify."
    fi
}

# =============================================================================
# SUGGEST CONFIGURATION
# =============================================================================
# Prints a recommended ENABLE_* configuration based on which CLI consultants
# are detected on the system. Supersedes preflight_check.sh --suggest-config.

suggest_configuration() {
    # Map of consultant flag -> CLI command (from config.sh defaults)
    local consultant_clis=(
        "ENABLE_GEMINI:${GEMINI_CMD:-agy}"
        "ENABLE_CODEX:${CODEX_CMD:-codex}"
        "ENABLE_MISTRAL:${MISTRAL_CMD:-vibe}"
        "ENABLE_CURSOR:${CURSOR_CMD:-agent}"
        "ENABLE_KIMI:${KIMI_CMD:-kimi}"
        "ENABLE_CLAUDE:${CLAUDE_CMD:-claude}"
        "ENABLE_QWEN3:${QWEN3_CMD:-qwen}"
        "ENABLE_MINIMAX:${MINIMAX_CMD:-mmx}"
    )

    local available_count=0
    local lines=()
    for entry in "${consultant_clis[@]}"; do
        local flag="${entry%%:*}"
        local cmd="${entry##*:}"
        if command -v "$cmd" >/dev/null 2>&1; then
            lines+=("${flag}=true")
            ((available_count++)) || true
        else
            lines+=("${flag}=false")
        fi
    done

    # API-only consultants: enable if API key is set
    local api_consultants=(
        "ENABLE_GLM:GLM_API_KEY"
        "ENABLE_GROK:GROK_API_KEY"
        "ENABLE_DEEPSEEK:DEEPSEEK_API_KEY"
    )
    for entry in "${api_consultants[@]}"; do
        local flag="${entry%%:*}"
        local key_var="${entry##*:}"
        if [[ -n "${!key_var:-}" ]]; then
            lines+=("${flag}=true")
            ((available_count++)) || true
        else
            lines+=("${flag}=false")
        fi
    done

    echo "# Recommended configuration based on detected CLIs and API keys"
    echo "# Generated by: ./scripts/doctor.sh --suggest-config"
    echo "# Available consultants: ${available_count}/${#consultant_clis[@]} CLI + API"
    echo ""
    printf '%s\n' "${lines[@]}"

    if (( available_count < 2 )); then
        echo ""
        echo "# WARNING: Less than 2 consultants available."
        echo "# AI Consultants requires at least 2 to deliberate."
        echo "# Install more CLIs or run ./scripts/setup_wizard.sh"
    fi
}

# =============================================================================
# SUGGEST PRESET (v2.13)
# =============================================================================
# Recommends a preset + strategy for a question, based on:
#   1. Question category (via classify_question.sh, defaults to GENERAL)
#   2. Number of available consultants (CLI presence + API key presence)
# Output is a one-liner ai-consultants command + reasoning.

# Count consultants that would actually participate in a consultation:
# - CLI is installed AND ENABLE_<NAME> == "true" (default from config.sh applies)
# - API key is set AND ENABLE_<NAME> == "true"
# - Subtract 1 if INVOKING_AGENT maps to one of the counted consultants
#   (self-exclusion at consult_all.sh runtime).
#
# IMPORTANT: get_self_consultant_name() returns UPPERCASE ("CLAUDE", "GEMINI"),
# so we compare against the UPPERCASE form of the entry name. v2.13.0 had a
# case-mismatch bug here that made self-exclusion a no-op.
_count_available_consultants() {
    local count=0
    local invoker_consultant=""
    if declare -f get_self_consultant_name >/dev/null 2>&1; then
        invoker_consultant=$(get_self_consultant_name 2>/dev/null || echo "")
    fi

    # name_upper | flag | command (uppercase pre-baked to match
    # get_self_consultant_name's output, so no per-iteration to_upper subshell).
    # ENABLE_<NAME> defaults are owned by config.sh — we deliberately do NOT
    # duplicate them here to avoid drift from config.sh defaults.
    local entries=(
        "GEMINI|ENABLE_GEMINI|${GEMINI_CMD:-agy}"
        "CODEX|ENABLE_CODEX|${CODEX_CMD:-codex}"
        "MISTRAL|ENABLE_MISTRAL|${MISTRAL_CMD:-vibe}"
        "CURSOR|ENABLE_CURSOR|${CURSOR_CMD:-agent}"
        "KIMI|ENABLE_KIMI|${KIMI_CMD:-kimi}"
        "CLAUDE|ENABLE_CLAUDE|${CLAUDE_CMD:-claude}"
        "QWEN3|ENABLE_QWEN3|${QWEN3_CMD:-qwen}"
        "MINIMAX|ENABLE_MINIMAX|${MINIMAX_CMD:-mmx}"
    )
    for entry in "${entries[@]}"; do
        IFS='|' read -r name flag cmd <<<"$entry"
        local enabled="${!flag:-false}"
        [[ "$enabled" != "true" ]] && continue
        if command -v "$cmd" >/dev/null 2>&1; then
            [[ "$name" == "$invoker_consultant" ]] && continue
            ((count++)) || true
        fi
    done

    # API-only consultants: enabled flag + API key both required
    local api_entries=(
        "GLM|ENABLE_GLM|GLM_API_KEY"
        "GROK|ENABLE_GROK|GROK_API_KEY"
        "DEEPSEEK|ENABLE_DEEPSEEK|DEEPSEEK_API_KEY"
    )
    for entry in "${api_entries[@]}"; do
        IFS='|' read -r name flag key <<<"$entry"
        local enabled="${!flag:-false}"
        [[ "$enabled" != "true" ]] && continue
        if [[ -n "${!key:-}" ]]; then
            [[ "$name" == "$invoker_consultant" ]] && continue
            ((count++)) || true
        fi
    done
    echo "$count"
}

# Returns "preset|strategy|reason" given category and consultant count.
_recommend_combo() {
    local category="$1"
    local count="$2"

    # Insufficient panel: regardless of category, point user at install help.
    # Without this short-circuit, e.g. "minimal" preset with count=0 would
    # produce an unrunnable suggestion.
    if (( count < 2 )); then
        echo "minimal|coverage|Only ${count} consultant(s) currently usable — install more CLIs (run: ai-consultants doctor --suggest-config) before deliberating"
        return 0
    fi

    case "$category" in
        SECURITY)
            if (( count >= 5 )); then
                echo "balanced|security_first|SECURITY detected; ${count} consultants available; debate is mandatory for SECURITY"
            else
                # Only mention Mistral as priority if it's actually available
                local mistral_note=""
                if command -v "${MISTRAL_CMD:-vibe}" >/dev/null 2>&1 && \
                   [[ "${ENABLE_MISTRAL:-true}" == "true" ]]; then
                    mistral_note=" — Mistral (Devil's Advocate) prioritized"
                fi
                echo "minimal|security_first|SECURITY detected; only ${count} consultants${mistral_note}"
            fi
            ;;
        ARCHITECTURE)
            if (( count >= 5 )); then
                echo "high-stakes|risk_averse|ARCHITECTURE detected; ${count} consultants — high-stakes adds debate, risk_averse weights conservative answers"
            else
                echo "balanced|risk_averse|ARCHITECTURE detected; ${count} consultants — debate is mandatory for ARCHITECTURE"
            fi
            ;;
        QUICK_SYNTAX)
            echo "fast|coverage|QUICK_SYNTAX detected — single-best-answer is enough; fast preset uses economy models"
            ;;
        ALGORITHM)
            echo "balanced|coverage|ALGORITHM detected; DeepSeek (Code Specialist) tends to lead in this category"
            ;;
        BUG_DEBUG|CODE_REVIEW|TESTING)
            if (( count >= 5 )); then
                echo "thorough|coverage|${category} detected; ${count} consultants — thorough preset for broader coverage"
            else
                echo "balanced|coverage|${category} detected; ${count} consultants — balanced for steady quality"
            fi
            ;;
        DATABASE|API_DESIGN)
            echo "balanced|coverage|${category} detected — balanced preset matches the routing affinity for this category"
            ;;
        *)
            if (( count >= 5 )); then
                echo "balanced|coverage|GENERAL category — balanced preset with coverage synthesis"
            elif (( count >= 2 )); then
                echo "minimal|coverage|GENERAL category; only ${count} consultants — minimal preset"
            else
                echo "minimal|coverage|Only ${count} consultant detected — install more CLIs (run: ai-consultants doctor --suggest-config) before deliberating"
            fi
            ;;
    esac
}

suggest_preset() {
    local category="GENERAL"
    local classification_failed=0
    local classifier_err=""

    if [[ -n "$QUESTION" ]]; then
        local errfile
        errfile=$(mktemp -t ai_consultants_classify.XXXXXX)
        local rc=0 raw=""
        # Capture stdout (one-line category) and stderr (logger output) separately;
        # surface the failure explicitly instead of silently degrading to GENERAL.
        raw=$("$SCRIPT_DIR/classify_question.sh" "$QUESTION" 2>"$errfile") || rc=$?
        if (( rc != 0 )) || [[ -z "$raw" ]]; then
            classification_failed=1
            [[ -s "$errfile" ]] && classifier_err=$(head -3 "$errfile")
            category="GENERAL"
        else
            # classify_question.sh prints exactly one line; trust the contract,
            # don't blindly tail. If the contract changes, the case below catches it.
            category="$raw"
            case "$category" in
                CODE_REVIEW|BUG_DEBUG|ARCHITECTURE|ALGORITHM|SECURITY|QUICK_SYNTAX|DATABASE|API_DESIGN|TESTING|GENERAL) ;;
                *)
                    classification_failed=1
                    classifier_err="classifier returned unexpected value: '$category'"
                    category="GENERAL"
                    ;;
            esac
        fi
        rm -f "$errfile"
    fi

    local count
    count=$(_count_available_consultants)

    local combo preset strategy reason
    combo=$(_recommend_combo "$category" "$count")
    preset="${combo%%|*}"
    combo="${combo#*|}"
    strategy="${combo%%|*}"
    reason="${combo#*|}"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Pre-flight jq because suggest_preset short-circuits before the main
        # check_dependencies pipeline. Without this, missing jq aborts via
        # set -e with a cryptic "command not found" instead of a clear error.
        if ! command -v jq >/dev/null 2>&1; then
            echo "ERROR: --json requires 'jq' to be installed" >&2
            return 1
        fi
        # Machine-parseable form. schema_version starts at 1; bump on breaking
        # field changes (renames/removals). Adding fields is non-breaking.
        # recommended_command is the full user-facing invocation, so tooling
        # doesn't have to reconstruct it from preset+strategy+question.
        local q_json recommended_command
        q_json=$(printf '%s' "${QUESTION:-}" | jq -Rs .)
        if [[ -n "$QUESTION" ]]; then
            recommended_command=$(printf 'ai-consultants --preset %s --strategy %s "%s"' \
                "$preset" "$strategy" "$QUESTION")
        else
            recommended_command=$(printf 'ai-consultants --preset %s --strategy %s "your question"' \
                "$preset" "$strategy")
        fi
        jq -n \
            --argjson schema_version 1 \
            --arg preset "$preset" \
            --arg strategy "$strategy" \
            --arg category "$category" \
            --argjson count "$count" \
            --arg reason "$reason" \
            --arg recommended_command "$recommended_command" \
            --argjson classification_failed "$classification_failed" \
            --arg classifier_err "$classifier_err" \
            --argjson question "$q_json" \
            '{
                schema_version: $schema_version,
                preset: $preset,
                strategy: $strategy,
                category: $category,
                consultants_available: $count,
                reason: $reason,
                recommended_command: $recommended_command,
                classification_failed: ($classification_failed == 1),
                classifier_error: (if $classifier_err == "" then null else $classifier_err end),
                question: (if $question == "" then null else $question end)
            }'
        return 0
    fi

    echo "Recommended:"
    if [[ -n "$QUESTION" ]]; then
        local q="$QUESTION"
        (( ${#q} > 60 )) && q="${q:0:57}..."
        printf '  ai-consultants --preset %s --strategy %s "%s"\n' "$preset" "$strategy" "$q"
    else
        printf '  ai-consultants --preset %s --strategy %s "your question"\n' "$preset" "$strategy"
    fi
    echo ""
    echo "Reason:"
    echo "  $reason"
    echo ""
    if (( classification_failed )); then
        echo "Warning: classification of your question failed; recommendation falls back to GENERAL."
        [[ -n "$classifier_err" ]] && echo "  classifier said: $classifier_err"
        echo ""
    elif [[ -z "$QUESTION" ]]; then
        echo "Tip: pass --question \"...\" for category-aware classification (currently defaulted to GENERAL)."
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# --- Live consultant ping (--live) ---------------------------------------------
# The static checks above only verify a CLI is installed (`--version`), so they
# report a consultant as healthy even when its CLI errors at query time (e.g.
# not authenticated). This sends a real, minimal query to each ENABLED consultant
# and reports pass/fail with the captured error reason. Opt-in (costs one tiny
# query per consultant).
check_live_consultants() {
    print_section "Live Consultant Check (real ping query)"

    local timeout_s="${DOCTOR_LIVE_TIMEOUT:-45}"
    local tmpdir
    tmpdir=$(mktemp -d)

    # name|enable-flag — mirrors consult_all's selection set.
    local entries=(
        "Gemini|ENABLE_GEMINI"   "Codex|ENABLE_CODEX"   "Mistral|ENABLE_MISTRAL"
        "Cursor|ENABLE_CURSOR"    "Kimi|ENABLE_KIMI"
        "Claude|ENABLE_CLAUDE"
        "Qwen3|ENABLE_QWEN3"     "GLM|ENABLE_GLM"       "Grok|ENABLE_GROK"
        "DeepSeek|ENABLE_DEEPSEEK" "MiniMax|ENABLE_MINIMAX"
    )

    local live_pass=0 live_fail=0 e name flagvar lower out err reason rc
    for e in "${entries[@]}"; do
        name="${e%%|*}"; flagvar="${e##*|}"
        if [[ "${!flagvar:-false}" != "true" ]]; then
            [[ "$VERBOSE" == "true" ]] && _print "  ○ $name: disabled"
            continue
        fi
        if should_skip_consultant "$name" 2>/dev/null; then
            _print "  ○ $name: excluded (invoking agent)"
            continue
        fi
        lower=$(to_lower "$name")
        out="$tmpdir/${lower}.json"; err="$tmpdir/${lower}.err"
        if ping_consultant "$lower" "$SCRIPT_DIR" "$timeout_s" "$out" "$err"; then rc=0; else rc=$?; fi
        if [[ $rc -eq 2 ]]; then
            _print "  ✗ $name: query script missing"
            add_issue "live" "$name query script missing" "reinstall the skill"
            check_fail; live_fail=$((live_fail + 1))
        elif [[ $rc -eq 0 ]]; then
            _print "  ✓ $name: responded"
            check_pass; live_pass=$((live_pass + 1))
        else
            reason=$(get_consultant_error_reason "$err")
            _print "  ✗ $name: no valid response${reason:+ — $reason}"
            add_issue "live" "$name failed live ping${reason:+: $reason}" "check that the $name CLI is installed and authenticated"
            check_fail; live_fail=$((live_fail + 1))
        fi
    done

    rm -rf "$tmpdir"
    _print ""
    _print "  Live result: ${live_pass} responding, ${live_fail} failing"
}

main() {
    print_header
    check_dependencies
    check_user_config
    check_cli_consultants
    check_api_mode_switching
    check_api_consultants
    check_configuration
    check_routing
    check_synthesis
    attempt_fixes
    print_summary

    # Exit code based on issues
    if [[ ${#ISSUES[@]} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

if [[ "$SUGGEST_CONFIG" == "true" ]]; then
    suggest_configuration
    exit 0
fi

if [[ "$SUGGEST_PRESET" == "true" ]]; then
    suggest_preset
    exit 0
fi

if [[ "$LIVE_MODE" == "true" ]]; then
    print_header
    check_live_consultants
    print_summary
    [[ ${#ISSUES[@]} -gt 0 ]] && exit 1 || exit 0
fi

main
