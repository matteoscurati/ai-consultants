#!/bin/bash
# config.sh - Centralized configuration for AI Consultants
# Modify this file to customize skill behavior.
#
# Precedence (highest wins):
#   1. CLI flags (--preset, --strategy, etc.)
#   2. Existing env vars (`export FOO=bar` before invocation)
#   3. User config (~/.config/ai-consultants/{config.sh,.env}) — see v2.12
#   4. The ${VAR:-default} fallbacks in this file
#   5. Hardcoded defaults inside individual scripts

# =============================================================================
# USER CONFIG (v2.12+)
# =============================================================================
# Load persistent user-level config from ~/.config/ai-consultants/ before
# applying any defaults below. The user config sets variables only when they
# are not already in the environment, so CLI flags / shell exports still win.
# Also exports get_xdg_dir() — load-bearing for v2.13 XDG path defaults below.
_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_CONFIG_DIR/lib/user_config.sh" ]]; then
    # shellcheck source=lib/user_config.sh
    source "$_CONFIG_DIR/lib/user_config.sh"
    load_user_config
fi

# v2.13: get_xdg_dir() is required for the XDG path defaults below. If the
# helper is missing (corrupt install, bad refactor) we'd silently regress to
# /tmp paths — exactly the failure mode v2.13 set out to fix. Fail loudly.
if ! declare -f get_xdg_dir >/dev/null 2>&1; then
    echo "FATAL: lib/user_config.sh is missing or did not export get_xdg_dir()." >&2
    echo "       v2.13+ XDG path defaults require it. Reinstall the skill." >&2
    # shellcheck disable=SC2317  # exit 1 is the script-mode fallback when sourced
    return 1 2>/dev/null || exit 1
fi

# Resolve XDG roots ONCE at first config load and export them so child
# subshells (every query_*.sh launched in parallel by consult_all.sh) inherit
# the values and skip the 3 subshells per kind. Without this, a 14-consultant
# consultation paid ~200-400ms in repeated subshell forks.
: "${_AI_CONSULTANTS_XDG_CACHE:=$(get_xdg_dir cache)}"
: "${_AI_CONSULTANTS_XDG_STATE:=$(get_xdg_dir state)}"
: "${_AI_CONSULTANTS_XDG_DATA:=$(get_xdg_dir data)}"
export _AI_CONSULTANTS_XDG_CACHE _AI_CONSULTANTS_XDG_STATE _AI_CONSULTANTS_XDG_DATA

# =============================================================================
# GENERAL SETTINGS
# =============================================================================

# Maximum number of retry attempts on failure
MAX_RETRIES="${MAX_RETRIES:-2}"

# Pause in seconds between retry attempts
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"

# Base output directory for consultations.
# v2.13.0: defaults to $XDG_CACHE_HOME/ai-consultants/consultations (typically
# ~/.cache/ai-consultants/consultations). Pre-v2.13 default was /tmp/ai_consultations
# which lost data on reboot and was world-readable on multi-tenant boxes.
# To restore the old behavior: export DEFAULT_OUTPUT_DIR_BASE=/tmp/ai_consultations
DEFAULT_OUTPUT_DIR_BASE="${DEFAULT_OUTPUT_DIR_BASE:-${_AI_CONSULTANTS_XDG_CACHE}/consultations}"

# =============================================================================
# CLI/API MODE SWITCHING (v2.6+)
# =============================================================================
# For agents that support both CLI and API mode, set USE_API=true to use API mode.
# When API mode is enabled, CLI mode is automatically disabled (mutual exclusivity).
# 6 agents support switching: Gemini, Codex, Claude, Mistral, Qwen3, MiniMax

# Mode switching (true = API, false = CLI). DEFAULT IS CLI — when a consultant
# has a CLI, the tool uses it; the CLIs are the primary transport (OAuth /
# subscription, no API key needed). API mode is opt-in only: for CLI-less models
# (GLM/Grok/DeepSeek are API-only anyway) or an explicit per-run user
# choice. Set a switch to true (with its API key) to force API for that agent.
# GEMINI_USE_API is intentionally NOT defaulted here: it is auto-resolved in the
# Gemini configuration section below (needs GEMINI_API_KEY / GEMINI_CMD), so an
# explicit unset must remain distinguishable from an explicit "false".
CODEX_USE_API="${CODEX_USE_API:-false}"
CLAUDE_USE_API="${CLAUDE_USE_API:-false}"
MISTRAL_USE_API="${MISTRAL_USE_API:-false}"
QWEN3_USE_API="${QWEN3_USE_API:-false}"  # Default false to use qwen CLI
# MINIMAX_USE_API is intentionally NOT defaulted here: it is auto-resolved in the
# MiniMax configuration section below (needs MINIMAX_API_KEY), so an explicit
# unset stays distinguishable from an explicit "false" (back-compat for pre-v2.21
# API-only MiniMax users -- see the rationale at the resolve block).

# API endpoints for CLI-switchable agents
GEMINI_API_URL="${GEMINI_API_URL:-https://generativelanguage.googleapis.com/v1beta/models}"
CODEX_API_URL="${CODEX_API_URL:-https://api.openai.com/v1/chat/completions}"
CLAUDE_API_URL="${CLAUDE_API_URL:-https://api.anthropic.com/v1/messages}"
MISTRAL_API_URL="${MISTRAL_API_URL:-https://api.mistral.ai/v1/chat/completions}"
# Note: QWEN3_API_URL is defined in the Qwen3 configuration section below

# API keys (use existing or set new)
# GEMINI_API_KEY - Google AI API key (for Gemini API mode)
# OPENAI_API_KEY - For Codex API mode (existing)
# ANTHROPIC_API_KEY - For Claude API mode
# MISTRAL_API_KEY - For Mistral API mode (existing)
# QWEN3_API_KEY - For Qwen3 API mode (existing)

# =============================================================================
# PARALLEL LAUNCH STAGGER (v2.10.1)
# =============================================================================
# Random delay (0 to N seconds) before launching each consultant in parallel.
# Prevents rate-limit bursts (e.g. Gemini 429 MODEL_CAPACITY_EXHAUSTED).
# Set to 0 to disable staggering.
LAUNCH_STAGGER_MAX_SECONDS="${LAUNCH_STAGGER_MAX_SECONDS:-2}"

# =============================================================================
# GEMINI CONFIGURATION - The Architect
# =============================================================================

# CLI mode uses the Antigravity CLI (`agy`), successor to the deprecated
# Gemini CLI (transitioned 2026-06-18). Models are passed by display name.
GEMINI_MODEL="${GEMINI_MODEL:-Gemini 3.1 Pro (High)}"
GEMINI_TIMEOUT_SECONDS="${GEMINI_TIMEOUT:-180}"
GEMINI_CMD="${GEMINI_CMD:-agy}"
# API mode (GEMINI_USE_API=true) talks to the Google AI generativelanguage
# endpoint, which expects an API model ID, not an `agy` display name.
GEMINI_API_MODEL="${GEMINI_API_MODEL:-gemini-3.1-pro-preview}"

# Auto-resolve the Gemini transport when the user hasn't pinned GEMINI_USE_API.
# Rationale (npm/npx distribution): the agy CLI cannot be installed via npm
# (curl|bash binary into ~/.local/bin) and is OAuth-only (no headless/API-key
# auth), so a fresh npx user almost never has a working CLI. A GEMINI_API_KEY,
# by contrast, works headlessly over plain HTTP. So when the mode is unset:
#   - GEMINI_API_KEY present -> API mode (the npm-friendly path)
#   - otherwise              -> CLI mode (agy; the orchestrator drops Gemini
#                               gracefully if absent, and doctor explains the fix)
# An explicit GEMINI_USE_API=true/false is always honored (back-compat). This
# block is idempotent across config.sh re-sourcing: once resolved+exported, the
# "${GEMINI_USE_API+x}" guard treats it as user-set on subsequent sources.
if [[ -z "${GEMINI_USE_API+x}" ]]; then
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        GEMINI_USE_API=true
    else
        GEMINI_USE_API=false
    fi
fi
export GEMINI_USE_API

# =============================================================================
# CODEX CONFIGURATION - The Pragmatist
# =============================================================================

# Model: "gpt-5.5" (default), "gpt-5.4", "gpt-5.4-nano", "gpt-5.3-codex", etc.
CODEX_MODEL="${CODEX_MODEL:-gpt-5.5}"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT:-180}"
CODEX_CMD="${CODEX_CMD:-codex}"

# =============================================================================
# MISTRAL VIBE CONFIGURATION - The Devil's Advocate
# =============================================================================

MISTRAL_MODEL="${MISTRAL_MODEL:-mistral-large-3}"
MISTRAL_TIMEOUT_SECONDS="${MISTRAL_TIMEOUT:-180}"
MISTRAL_CMD="${MISTRAL_CMD:-vibe}"

# =============================================================================
# CURSOR CONFIGURATION - The Integrator
# =============================================================================

CURSOR_MODEL="${CURSOR_MODEL:-composer-2.5}"
CURSOR_TIMEOUT_SECONDS="${CURSOR_TIMEOUT:-180}"
CURSOR_CMD="${CURSOR_CMD:-agent}"

# =============================================================================
# QWEN3 CONFIGURATION - The Analyst (CLI/API switchable v2.7)
# =============================================================================

QWEN3_MODEL="${QWEN3_MODEL:-qwen3.7-max}"
QWEN3_TIMEOUT_SECONDS="${QWEN3_TIMEOUT:-180}"
QWEN3_CMD="${QWEN3_CMD:-qwen}"
QWEN3_API_URL="${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}"
QWEN3_FORMAT="${QWEN3_FORMAT:-qwen}"
# CLI mode: npm install -g @qwen-code/qwen-code@latest
# API key: Set QWEN3_API_KEY environment variable

# =============================================================================
# GLM CONFIGURATION - The Code Specialist (API-based)
# =============================================================================

GLM_MODEL="${GLM_MODEL:-glm-5.2}"
GLM_TIMEOUT_SECONDS="${GLM_TIMEOUT:-180}"
GLM_API_URL="${GLM_API_URL:-https://api.z.ai/api/coding/paas/v4/chat/completions}"
GLM_FORMAT="${GLM_FORMAT:-openai}"
# API key: Set GLM_API_KEY environment variable

# =============================================================================
# GROK CONFIGURATION - The Provocateur (API-based)
# =============================================================================

GROK_MODEL="${GROK_MODEL:-grok-4.5}"
GROK_TIMEOUT_SECONDS="${GROK_TIMEOUT:-180}"
GROK_API_URL="${GROK_API_URL:-https://api.x.ai/v1/chat/completions}"
GROK_FORMAT="${GROK_FORMAT:-openai}"
# API key: Set GROK_API_KEY environment variable

# =============================================================================
# DEEPSEEK CONFIGURATION - The Methodologist (API-based)
# =============================================================================

DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-v4-pro}"
DEEPSEEK_TIMEOUT_SECONDS="${DEEPSEEK_TIMEOUT:-180}"
DEEPSEEK_API_URL="${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}"
DEEPSEEK_FORMAT="${DEEPSEEK_FORMAT:-openai}"
# API key: Set DEEPSEEK_API_KEY environment variable

# =============================================================================
# MINIMAX CONFIGURATION - The Pragmatic Optimizer (CLI/API, v2.10; CLI via mmx v2.21)
# =============================================================================

MINIMAX_CMD="${MINIMAX_CMD:-mmx}"
MINIMAX_MODEL="${MINIMAX_MODEL:-MiniMax-M2.7}"
MINIMAX_TIMEOUT_SECONDS="${MINIMAX_TIMEOUT:-180}"
MINIMAX_API_URL="${MINIMAX_API_URL:-https://api.minimax.io/v1/chat/completions}"
MINIMAX_FORMAT="${MINIMAX_FORMAT:-openai}"
# CLI mode (default) uses the mmx CLI (npm i -g mmx-cli; auth: mmx auth login).
# API mode (MINIMAX_USE_API=true) uses MINIMAX_API_KEY against MINIMAX_API_URL.
#
# Auto-resolve the MiniMax transport when the user hasn't pinned MINIMAX_USE_API.
# Unlike Gemini, the mmx CLI IS npm-installable, so CLI is the genuine default
# (per the CLI-first principle). This block exists purely for BACK-COMPAT: before
# v2.21 MiniMax was API-only, so a working pre-v2.21 config necessarily had
# MINIMAX_API_KEY and no mmx. Defaulting such a user to CLI would break MiniMax on
# upgrade (mmx not found). So when the mode is unset:
#   - MINIMAX_API_KEY present -> API mode (preserves the pre-v2.21 API-only user;
#                                a set key is itself the "explicit user choice")
#   - otherwise               -> CLI mode (mmx; the new default)
# An explicit MINIMAX_USE_API=true/false is always honored. Idempotent across
# re-sourcing via the "${MINIMAX_USE_API+x}" set-vs-unset guard.
if [[ -z "${MINIMAX_USE_API+x}" ]]; then
    if [[ -n "${MINIMAX_API_KEY:-}" ]]; then
        MINIMAX_USE_API=true
    else
        MINIMAX_USE_API=false
    fi
fi
export MINIMAX_USE_API

# CLI installation: curl -fsSL https://ampcode.com/install.sh | bash
# =============================================================================
# KIMI CONFIGURATION - The Eastern Sage (v2.9)
# =============================================================================

KIMI_MODEL="${KIMI_MODEL:-kimi-code/k3}"
KIMI_TIMEOUT_SECONDS="${KIMI_TIMEOUT:-180}"
KIMI_CMD="${KIMI_CMD:-kimi}"
# CLI installation: curl -L code.kimi.com/install.sh | bash

# =============================================================================
# CLAUDE CONFIGURATION - The Synthesizer (v2.2)
# =============================================================================

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-8}"
CLAUDE_TIMEOUT_SECONDS="${CLAUDE_TIMEOUT:-240}"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

# =============================================================================
# CANONICAL CONSULTANT LIST
# =============================================================================
# This is the single source of truth for all available consultants.
# Use this array when iterating over consultants programmatically.

# All available consultants (ordered by typical usage)
ALL_CONSULTANTS=("Gemini" "Codex" "Mistral" "Cursor" "Kimi" "Claude" "Qwen3" "GLM" "Grok" "DeepSeek" "MiniMax")

# CLI-based consultants (use CLI tools, some support CLI/API switching)
CLI_CONSULTANTS=("Gemini" "Codex" "Mistral" "Cursor" "Kimi" "Claude" "Qwen3" "MiniMax")

# API-only consultants (use HTTP API directly, no CLI available)
API_CONSULTANTS=("GLM" "Grok" "DeepSeek")

# =============================================================================
# ENABLED CONSULTANTS
# =============================================================================

# Set to "false" to disable a specific consultant
# CLI-based consultants (enabled by default)
ENABLE_GEMINI="${ENABLE_GEMINI:-true}"
ENABLE_CODEX="${ENABLE_CODEX:-true}"
ENABLE_MISTRAL="${ENABLE_MISTRAL:-true}"
ENABLE_CURSOR="${ENABLE_CURSOR:-true}"
ENABLE_KIMI="${ENABLE_KIMI:-true}"       # Kimi Code (v2.9)
ENABLE_CLAUDE="${ENABLE_CLAUDE:-true}"   # Auto-disabled when invoked by Claude Code
ENABLE_QWEN3="${ENABLE_QWEN3:-true}"     # qwen-code CLI (v2.7); API opt-in
ENABLE_MINIMAX="${ENABLE_MINIMAX:-true}" # mmx CLI (v2.21); API opt-in

# API-only consultants (disabled by default - require API keys)
ENABLE_GLM="${ENABLE_GLM:-false}"
ENABLE_GROK="${ENABLE_GROK:-false}"
ENABLE_DEEPSEEK="${ENABLE_DEEPSEEK:-false}"

# =============================================================================
# INVOKING AGENT DETECTION (v2.2)
# =============================================================================

# Agent that invoked this skill - used for self-exclusion to prevent
# an agent from consulting itself.
# Values: claude, codex, gemini, cursor, mistral, kimi, qwen3, or "unknown"
# Example: INVOKING_AGENT=claude ./scripts/consult_all.sh "question"
INVOKING_AGENT="${INVOKING_AGENT:-unknown}"

# =============================================================================
# PERSONAS (v2.0)
# =============================================================================

# Enable/disable persona system
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"

# Persona assignments (by ID) - override with {AGENT}_PERSONA_ID or {AGENT}_PERSONA
# Available: 1=Architect, 2=Pragmatist, 3=Devil's Advocate, 4=Innovator,
#   5=Integrator, 6=Analyst, 7=Methodologist, 8=Provocateur, 9=Mentor,
#   10=Optimizer, 11=Security Expert, 12=Minimalist, 13=DX Advocate,
#   14=Debugger, 15=Reviewer
# Defaults are set in lib/personas.sh (GEMINI=1, CODEX=2, MISTRAL=3, etc.)

# =============================================================================
# AUTO-SYNTHESIS (v2.0)
# =============================================================================

# Enable automatic response synthesis
ENABLE_SYNTHESIS="${ENABLE_SYNTHESIS:-true}"

# CLI for synthesis (default: claude)
SYNTHESIS_CMD="${SYNTHESIS_CMD:-claude}"

# =============================================================================
# DEFAULT PRESET AND STRATEGY (v2.2)
# =============================================================================

# Default preset to use when no --preset flag is provided
# Options: minimal, balanced, thorough, high-stakes, security, cost-capped
# Leave empty to use individual ENABLE_* settings
DEFAULT_PRESET="${DEFAULT_PRESET:-}"

# Default synthesis strategy
# Options: majority, risk_averse, security_first, cost_capped, compare_only
DEFAULT_STRATEGY="${DEFAULT_STRATEGY:-majority}"

# =============================================================================
# SMART ROUTING (v2.0)
# =============================================================================

# Enable automatic question classification
ENABLE_CLASSIFICATION="${ENABLE_CLASSIFICATION:-true}"

# Classification mode: "pattern" (fast) or "llm" (more accurate)
CLASSIFICATION_MODE="${CLASSIFICATION_MODE:-pattern}"

# Enable intelligent routing (selects consultants based on category)
ENABLE_SMART_ROUTING="${ENABLE_SMART_ROUTING:-false}"

# Minimum affinity to include a consultant (1-10)
MIN_AFFINITY="${MIN_AFFINITY:-7}"

# =============================================================================
# COST MANAGEMENT (v2.0)
# =============================================================================

# Enable cost tracking
ENABLE_COST_TRACKING="${ENABLE_COST_TRACKING:-true}"

# Maximum budget per session in USD
MAX_SESSION_COST="${MAX_SESSION_COST:-1.00}"

# Warning threshold in USD
WARN_AT_COST="${WARN_AT_COST:-0.50}"

# File for cumulative tracking. v2.13: defaults to $XDG_DATA_HOME/ai-consultants/
# (persistent across reboots; this is user data, not cache).
COST_TRACKING_FILE="${COST_TRACKING_FILE:-${_AI_CONSULTANTS_XDG_DATA}/costs.json}"

# --- Reliability Tracking (foundation for a future self-tuning roster) ---
# Enable per-consultant success/failure recording (opt-in default: ON)
ENABLE_RELIABILITY_TRACKING="${ENABLE_RELIABILITY_TRACKING:-true}"

# File for cumulative per-consultant reliability tracking (same XDG data dir as costs)
RELIABILITY_FILE="${RELIABILITY_FILE:-${_AI_CONSULTANTS_XDG_DATA}/reliability.json}"

# --- Budget Enforcement (v2.4) ---
# Enable budget limit enforcement (opt-in, default OFF)
ENABLE_BUDGET_LIMIT="${ENABLE_BUDGET_LIMIT:-false}"

# Action to take when budget is exceeded
# Options: warn (log warning but continue), stop (halt consultation with partial results)
BUDGET_ACTION="${BUDGET_ACTION:-warn}"

# =============================================================================
# SESSION MANAGEMENT (v2.0)
# =============================================================================

# Directory for session files. v2.13: defaults to $XDG_STATE_HOME/ai-consultants/
# (persistent across reboots; sessions enable follow-up queries).
SESSION_DIR="${SESSION_DIR:-${_AI_CONSULTANTS_XDG_STATE}/sessions}"

# Days after which to clean old sessions
SESSION_CLEANUP_DAYS="${SESSION_CLEANUP_DAYS:-7}"

# =============================================================================
# INTERACTIVE MODE (v2.0)
# =============================================================================

# Enable interactive progress bars
ENABLE_PROGRESS_BARS="${ENABLE_PROGRESS_BARS:-true}"

# Enable early termination (Ctrl+C to stop with partial responses)
ENABLE_EARLY_TERMINATION="${ENABLE_EARLY_TERMINATION:-true}"

# =============================================================================
# PRE-FLIGHT CHECKS (v2.0)
# =============================================================================

# Run pre-flight check before each consultation
ENABLE_PREFLIGHT="${ENABLE_PREFLIGHT:-false}"

# Quick mode for preflight (CLI check only, no API test)
PREFLIGHT_QUICK="${PREFLIGHT_QUICK:-true}"

# =============================================================================
# TOKEN OPTIMIZATION (v2.1)
# =============================================================================

# Optimization mode: "none", "basic", "ast", "full"
#   none  - No optimization, pass files as-is
#   basic - Simple byte-based truncation (legacy)
#   ast   - AST-based extraction (recommended, ~60% savings)
#   full  - AST + symbol compression + chunking (~70% savings)
TOKEN_OPTIMIZATION_MODE="${TOKEN_OPTIMIZATION_MODE:-ast}"

# Maximum bytes per context file before truncation (~2000 tokens)
# Only used when TOKEN_OPTIMIZATION_MODE=basic
MAX_CONTEXT_FILE_BYTES="${MAX_CONTEXT_FILE_BYTES:-8000}"

# Enable AST-based code extraction
ENABLE_AST_EXTRACTION="${ENABLE_AST_EXTRACTION:-true}"

# Enable symbol compression (minification)
ENABLE_SYMBOL_COMPRESSION="${ENABLE_SYMBOL_COMPRESSION:-false}"

# Enable semantic chunking for large files
ENABLE_SEMANTIC_CHUNKING="${ENABLE_SEMANTIC_CHUNKING:-true}"

# Maximum tokens per chunk (for chunking mode)
CHUNK_MAX_TOKENS="${CHUNK_MAX_TOKENS:-500}"

# Use compact prompts (shorter personas and output format)
USE_COMPACT_PROMPTS="${USE_COMPACT_PROMPTS:-true}"

# Extract only essential fields for synthesis (instead of full JSON)
SYNTHESIS_EXTRACT_FIELDS="${SYNTHESIS_EXTRACT_FIELDS:-true}"

# =============================================================================
# TOKEN COST OPTIMIZATION (v2.3)
# =============================================================================

# --- Semantic Caching ---
# Cache responses based on query + context hash.
# v2.13: defaults to $XDG_CACHE_HOME/ai-consultants/cache (regenerable data).
ENABLE_SEMANTIC_CACHE="${ENABLE_SEMANTIC_CACHE:-true}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"
CACHE_DIR="${CACHE_DIR:-${_AI_CONSULTANTS_XDG_CACHE}/cache}"

# --- Transient Workspaces (v2.13) ---
# Both regenerable, default to XDG_CACHE_HOME alongside semantic cache.
RATE_LIMIT_DIR="${RATE_LIMIT_DIR:-${_AI_CONSULTANTS_XDG_CACHE}/ratelimit}"
CHUNK_TEMP_DIR="${CHUNK_TEMP_DIR:-${_AI_CONSULTANTS_XDG_CACHE}/chunks}"

# --- Response Length Limits ---
# Limit output tokens by question category
# NOTE: Default is FALSE (opt-in) per quality review - can truncate critical info
ENABLE_RESPONSE_LIMITS="${ENABLE_RESPONSE_LIMITS:-false}"
# Format: "CATEGORY:MAX_TOKENS,..."
MAX_RESPONSE_TOKENS_BY_CATEGORY="${MAX_RESPONSE_TOKENS_BY_CATEGORY:-QUICK_SYNTAX:200,CODE_REVIEW:800,BUG_DEBUG:800,ARCHITECTURE:1000,SECURITY:1000,DATABASE:600,GENERAL:500}"

# --- Cost-Aware Model Routing ---
# Route simple queries to cheaper models
ENABLE_COST_AWARE_ROUTING="${ENABLE_COST_AWARE_ROUTING:-false}"
USE_ECONOMIC_MODELS_FOR_SIMPLE="${USE_ECONOMIC_MODELS_FOR_SIMPLE:-true}"
# Complexity thresholds (1-10 scale)
COMPLEXITY_THRESHOLD_SIMPLE="${COMPLEXITY_THRESHOLD_SIMPLE:-3}"
COMPLEXITY_THRESHOLD_MEDIUM="${COMPLEXITY_THRESHOLD_MEDIUM:-6}"

# --- Selective Context ---
# Send only relevant files to each consultant
ENABLE_SELECTIVE_CONTEXT="${ENABLE_SELECTIVE_CONTEXT:-false}"
MAX_FILES_PER_CONSULTANT="${MAX_FILES_PER_CONSULTANT:-5}"

# =============================================================================
# QUORUM GRADING (v2.19.0)
# =============================================================================
# Grade the consultation outcome by the number of consultants that actually
# responded, so a run that silently shrank to a few panelists is reported as
# DEGRADED/FAILED instead of presenting as authoritative. Failures are listed
# with their diagnosed reason (from the v2.18.0 .err capture) in the report.
# Minimum successful responses below which the outcome is FAILED.
QUORUM_MIN="${QUORUM_MIN:-2}"
# warn (default: banner + continue) | stop (abort if below quorum)
QUORUM_ACTION="${QUORUM_ACTION:-warn}"

# =============================================================================
# HEALTH GATE (v2.19.0, opt-in)
# =============================================================================
# Before the consultation, send a cheap real "ping" query to each selected
# consultant in parallel and drop the non-responsive ones (installed-but-
# unauthenticated CLIs, stale installs), so the panel only spends the full run
# on consultants that actually work. Opt-in: it costs one tiny extra query per
# consultant. Prunes; it does not switch transport. Consultants whose response
# is already cached are kept WITHOUT a ping (cache-aware).
#
# TRADE-OFF: the gate runs BEFORE Round 1 and is serial with it (a pre-flight
# probe can't overlap the real run by definition), so it adds up to
# HEALTH_GATE_TIMEOUT of blocking startup latency when a consultant is slow/dead.
# That's the cost of pruning up front; keep it opt-in and tune the timeout.
ENABLE_HEALTH_GATE="${ENABLE_HEALTH_GATE:-false}"
HEALTH_GATE_TIMEOUT="${HEALTH_GATE_TIMEOUT:-30}"

# --- Report Optimization ---
# Generate compact reports by default (summaries only)
ENABLE_COMPACT_REPORT="${ENABLE_COMPACT_REPORT:-true}"
# Max lines of JSON to include per consultant in full report
REPORT_MAX_JSON_LINES="${REPORT_MAX_JSON_LINES:-50}"

# =============================================================================
# LOGGING
# =============================================================================

# Log level: "DEBUG", "INFO", "WARN", "ERROR"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Log colors (set to empty to disable)
if [[ -t 2 ]]; then
    # Only if stderr is a terminal
    C_DEBUG="\033[0;90m"
    C_INFO="\033[0;34m"
    C_SUCCESS="\033[0;32m"
    C_WARN="\033[0;33m"
    C_ERROR="\033[0;31m"
    C_RESET="\033[0m"
else
    C_DEBUG=""
    C_INFO=""
    C_SUCCESS=""
    C_WARN=""
    C_ERROR=""
    C_RESET=""
fi

# =============================================================================
# MODEL QUALITY TIERS (v2.5)
# =============================================================================

# Get model name for a specific consultant and tier (single source of truth)
# Usage: get_model_for_tier <consultant> <tier>
# Returns: model name, or empty string for an unknown consultant/tier.
get_model_for_tier() {
    local consultant="$1"
    local tier="${2:-premium}"
    consultant=$(echo "$consultant" | tr '[:upper:]' '[:lower:]')

    case "$tier" in
        premium|max|best)
            case "$consultant" in
                claude)   echo "claude-opus-4-8" ;;
                gemini)   echo "Gemini 3.1 Pro (High)" ;;
                codex)    echo "gpt-5.5" ;;
                mistral)  echo "mistral-large-3" ;;
                cursor)   echo "composer-2.5" ;;
                deepseek) echo "deepseek-v4-pro" ;;
                glm)      echo "glm-5.2" ;;
                grok)     echo "grok-4.5" ;;
                qwen3)    echo "qwen3.7-max" ;;
                kimi)     echo "kimi-code/k3" ;;
                minimax)  echo "MiniMax-M2.7" ;;
                *)        echo "" ;;
            esac
            ;;
        standard|medium|balanced)
            case "$consultant" in
                claude)   echo "claude-sonnet-4-6" ;;
                gemini)   echo "Gemini 3.5 Flash (High)" ;;
                codex)    echo "gpt-5.4" ;;
                mistral)  echo "mistral-medium-latest" ;;
                cursor)   echo "composer-2" ;;
                deepseek) echo "deepseek-v4-flash" ;;
                glm)      echo "glm-5.2" ;;  # Same as premium (no mid-tier GLM)
                grok)     echo "grok-4.1-fast" ;;
                qwen3)    echo "qwen3.6-35b-a3b" ;;  # Open-weight MoE (35B total, 3B active)
                kimi)     echo "kimi-code/k3" ;;
                minimax)  echo "MiniMax-M2.7" ;;
                *)        echo "" ;;
            esac
            ;;
        economy|fast|quick)
            case "$consultant" in
                claude)   echo "claude-haiku-4-5" ;;
                gemini)   echo "Gemini 3.5 Flash (Low)" ;;
                codex)    echo "gpt-5.4-nano" ;;
                mistral)  echo "devstral-small-2" ;;
                cursor)   echo "gemini-3-flash" ;;
                deepseek) echo "deepseek-v4-flash" ;;
                glm)      echo "glm-4-flash" ;;
                grok)     echo "grok-4.1-fast" ;;
                qwen3)    echo "qwen3-32b" ;;
                kimi)     echo "kimi-code/k3" ;;
                minimax)  echo "MiniMax-M2.5" ;;
                *)        echo "" ;;
            esac
            ;;
        *)
            echo "" ;;
    esac
}

# Apply model tier to all consultants
# Usage: apply_model_tier <tier: premium|standard|economy>
# Premium = latest flagship models, highest quality
# Standard = good balance of quality and cost
# Economy = optimized for speed and low cost
apply_model_tier() {
    local tier="$1"

    # Validate tier name
    case "$tier" in
        premium|max|best|standard|medium|balanced|economy|fast|quick) ;;
        *)
            echo "Unknown model tier: $tier" >&2
            echo "Available tiers: premium, standard, economy" >&2
            return 1
            ;;
    esac

    local consultants="claude gemini codex mistral cursor deepseek glm grok qwen3 minimax kimi"
    for c in $consultants; do
        local model
        model=$(get_model_for_tier "$c" "$tier")
        if [[ -n "$model" ]]; then
            local var_name
            var_name="$(echo "$c" | tr '[:lower:]' '[:upper:]')_MODEL"
            export "$var_name=$model"
        fi
    done

    return 0
}

# =============================================================================
# CONFIGURATION PRESETS (v2.2)
# =============================================================================

# Presets allow quick configuration for different use cases:
#   minimal      - 2 models (fast, cheap): Gemini + Codex
#   balanced     - 4 models (good coverage): + Mistral + Cursor
#   thorough     - 4 models (comprehensive)
#   high-stakes  - Broad premium panel + debate (maximum rigor)
#
# Quality Tiers (v2.5):
#   max_quality  - 8 of 11 consultants + premium models + peer review
#   medium       - 4 consultants + standard models + light debate
#   fast         - 2 consultants + economy models, no debate
#
# Usage: ./consult_all.sh --preset balanced "Your question"

# Helper: Disable all consultants
_disable_all_consultants() {
    export ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false
    export ENABLE_CURSOR=false ENABLE_KIMI=false ENABLE_CLAUDE=false
    export ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false
    export ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false
}

# Apply a preset configuration
# Usage: apply_preset <preset_name>
apply_preset() {
    local preset="$1"

    # Start with all disabled, then enable what's needed
    _disable_all_consultants

    case "$preset" in
        minimal)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            ;;
        balanced)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_CURSOR=true
            ;;
        thorough)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_CURSOR=true
            ;;
        high-stakes)
            export ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true
            export ENABLE_CURSOR=true ENABLE_CLAUDE=true
            ;;
        security)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_CURSOR=true
            ;;
        cost-capped)
            apply_model_tier "economy"
            export ENABLE_GEMINI=true ENABLE_MISTRAL=true ENABLE_QWEN3=true
            export MAX_SESSION_COST=0.10
            ;;
        # --- Quality Tier Presets (v2.5) ---
        max_quality|max-quality)
            # Maximum quality - all premium models + all features
            apply_model_tier "premium"
            export ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true
            export ENABLE_CURSOR=true ENABLE_KIMI=true
            export ENABLE_CLAUDE=true ENABLE_QWEN3=true ENABLE_MINIMAX=true
            ;;
        medium)
            # Balanced quality - standard models, good coverage
            apply_model_tier "standard"
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_CURSOR=true
            ;;
        fast)
            # Super fast - economy models, minimal consultants
            apply_model_tier "economy"
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_COMPACT_REPORT=true
            ;;
        *)
            echo "Unknown preset: $preset" >&2
            echo "Available presets: minimal, balanced, thorough, high-stakes, security, cost-capped, max_quality, medium, fast" >&2
            return 1
            ;;
    esac

    return 0
}

# List available presets with descriptions
list_presets() {
    cat << 'EOF'
Available presets:

Quality Tiers (v2.5):
  max_quality  8 of 11 consultants + premium models + peer review
  medium       4 consultants + standard models + light debate
  fast         2 consultants + economy models, no debate

Use Cases:
  minimal      2 models (Gemini + Codex) - Fast, cheap
  balanced     4 models (+ Mistral + Cursor) - Good coverage [DEFAULT]
  thorough     4 models - Comprehensive analysis
  high-stakes  Broad premium panel + debate - Maximum rigor for critical decisions
  security     Security-focused models + debate - For security reviews
  cost-capped  Budget-conscious options - Minimal API costs

Usage: ./consult_all.sh --preset <name> "Your question"
EOF
}

# =============================================================================
# VERSION
# =============================================================================

AI_CONSULTANTS_VERSION="2.25.2"
