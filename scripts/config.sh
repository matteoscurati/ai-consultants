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
# shellcheck source=public_registry.sh
source "$_CONFIG_DIR/public_registry.sh"
if [[ -f "$_CONFIG_DIR/lib/user_config.sh" ]]; then
    # shellcheck source=lib/user_config.sh
    source "$_CONFIG_DIR/lib/user_config.sh"
    load_user_config
fi

# Preserve an explicit false from the environment or persistent user config
# before the defaults below make every ENABLE_* value appear set. Presets and
# their fallback selector honor this marker, especially for billed APIs.
if [[ "${_AI_CONSULTANTS_PRESET_APPLIED:-false}" != "true" ]]; then
    for _preset_optout_flag in ENABLE_GEMINI ENABLE_CODEX ENABLE_MISTRAL ENABLE_KIMI \
        ENABLE_CLAUDE ENABLE_QWEN3 ENABLE_GLM ENABLE_GROK ENABLE_DEEPSEEK ENABLE_MINIMAX; do
        if [[ -n "${!_preset_optout_flag+x}" && "${!_preset_optout_flag}" == "false" ]]; then
            export "_AI_CONSULTANTS_PRESET_OPTOUT_${_preset_optout_flag}=true"
        fi
    done
fi
unset _preset_optout_flag

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
# 7 agents support switching: Gemini, Codex, Claude, Mistral, Qwen3, Grok, MiniMax

# Mode switching (true = API, false = CLI). DEFAULT IS CLI — when a consultant
# has a CLI, the tool uses it; the CLIs are the primary transport (OAuth /
# subscription, no API key needed). API mode is opt-in only: for CLI-less models
# (GLM/DeepSeek are API-only) or an explicit per-run user
# choice. Set a switch to true (with its API key) to force API for that agent.
# GEMINI_USE_API is intentionally NOT defaulted here: it is auto-resolved in the
# Gemini configuration section below (needs GEMINI_API_KEY / GEMINI_CMD), so an
# explicit unset must remain distinguishable from an explicit "false".
CODEX_USE_API="${CODEX_USE_API:-false}"
CLAUDE_USE_API="${CLAUDE_USE_API:-false}"
MISTRAL_USE_API="${MISTRAL_USE_API:-false}"
QWEN3_USE_API="${QWEN3_USE_API:-false}"  # Default false to use qwen CLI
# GROK_USE_API is intentionally resolved in the Grok section: it is CLI-first,
# but must preserve an API-only installation when Grok Build is unavailable.
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
GEMINI_MODEL="${GEMINI_MODEL:-Gemini 3.7 Flash (High)}"
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

# Model: "gpt-5.6-sol" (default), "gpt-5.6-terra", "gpt-5.6-luna", etc.
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-sol}"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT:-180}"
CODEX_API_MAX_TOKENS="${CODEX_API_MAX_TOKENS:-4096}"
CODEX_CMD="${CODEX_CMD:-codex}"

# =============================================================================
# MISTRAL VIBE CONFIGURATION - The Devil's Advocate
# =============================================================================

# The Vibe CLI and Mistral API use different model namespaces. Keep
# MISTRAL_MODEL as the long-standing API setting, and select the CLI alias
# independently through VIBE_ACTIVE_MODEL at dispatch time.
MISTRAL_MODEL="${MISTRAL_MODEL:-mistral-large-3}"
MISTRAL_CLI_MODEL="${MISTRAL_CLI_MODEL:-mistral-medium-3.5}"
MISTRAL_API_MAX_TOKENS="${MISTRAL_API_MAX_TOKENS:-4096}"
MISTRAL_TIMEOUT_SECONDS="${MISTRAL_TIMEOUT:-180}"
MISTRAL_CMD="${MISTRAL_CMD:-vibe}"
MISTRAL_MAX_TURNS="${MISTRAL_MAX_TURNS:-4}"

# =============================================================================
# QWEN3 CONFIGURATION - The Analyst (CLI/API switchable v2.7)
# =============================================================================

QWEN3_MODEL="${QWEN3_MODEL:-qwen3.7-max}"
if [[ -n "${QWEN3_TIMEOUT+x}" ]]; then
    QWEN3_TIMEOUT_SECONDS="$QWEN3_TIMEOUT"
elif [[ -z "${QWEN3_TIMEOUT_SECONDS+x}" ]]; then
    QWEN3_TIMEOUT_SECONDS=180
fi
QWEN3_MAX_QUALITY_TIMEOUT="${QWEN3_MAX_QUALITY_TIMEOUT:-600}"
QWEN3_API_MAX_TOKENS="${QWEN3_API_MAX_TOKENS:-16384}"
QWEN3_CMD="${QWEN3_CMD:-qwen}"
QWEN3_API_URL="${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}"
QWEN3_FORMAT="${QWEN3_FORMAT:-qwen}"
# CLI mode: npm install -g @qwen-code/qwen-code@latest
# API key: Set QWEN3_API_KEY environment variable

# =============================================================================
# GLM CONFIGURATION - The Code Specialist (API-based)
# =============================================================================

GLM_MODEL="${GLM_MODEL:-glm-5.3-flash}"
GLM_TIMEOUT_SECONDS="${GLM_TIMEOUT:-180}"
GLM_API_MAX_TOKENS="${GLM_API_MAX_TOKENS:-16384}"
GLM_API_URL="${GLM_API_URL:-https://api.z.ai/api/coding/paas/v4/chat/completions}"
GLM_FORMAT="${GLM_FORMAT:-openai}"
# API key: Set GLM_API_KEY environment variable

# =============================================================================
# GROK CONFIGURATION - The Provocateur (Grok Build CLI + API fallback)
# =============================================================================

GROK_CMD="${GROK_CMD:-grok}"
GROK_MODEL="${GROK_MODEL:-grok-4.6}"
GROK_TIMEOUT_SECONDS="${GROK_TIMEOUT:-180}"
GROK_API_MAX_TOKENS="${GROK_API_MAX_TOKENS:-4096}"
GROK_MAX_TURNS="${GROK_MAX_TURNS:-4}"
GROK_OAUTH_MODE="${GROK_OAUTH_MODE:-shared}"
GROK_API_URL="${GROK_API_URL:-https://api.x.ai/v1/chat/completions}"
GROK_FORMAT="${GROK_FORMAT:-openai}"
# Grok Build's official credential name is XAI_API_KEY. Keep the historical
# GROK_API_KEY public contract and accept XAI_API_KEY as its fallback alias.
GROK_API_KEY="${GROK_API_KEY:-${XAI_API_KEY:-}}"
export GROK_API_KEY

# CLI-first auto-resolution. Existing users can still pin GROK_USE_API=true,
# while an unpinned setup uses the CLI whenever it is installed and falls back
# to the API when only a key is available.
if [[ -z "${GROK_USE_API+x}" ]]; then
    if command -v "$GROK_CMD" >/dev/null 2>&1; then
        GROK_USE_API=false
    elif [[ -n "$GROK_API_KEY" ]]; then
        GROK_USE_API=true
    else
        GROK_USE_API=false
    fi
fi
export GROK_USE_API GROK_OAUTH_MODE

# =============================================================================
# DEEPSEEK CONFIGURATION - The Methodologist (API-based)
# =============================================================================

DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-v4-pro}"
if [[ -n "${DEEPSEEK_TIMEOUT+x}" ]]; then
    DEEPSEEK_TIMEOUT_SECONDS="$DEEPSEEK_TIMEOUT"
elif [[ -z "${DEEPSEEK_TIMEOUT_SECONDS+x}" ]]; then
    DEEPSEEK_TIMEOUT_SECONDS=180
fi
DEEPSEEK_MAX_QUALITY_TIMEOUT="${DEEPSEEK_MAX_QUALITY_TIMEOUT:-600}"
DEEPSEEK_API_MAX_TOKENS="${DEEPSEEK_API_MAX_TOKENS:-16384}"
DEEPSEEK_API_URL="${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}"
DEEPSEEK_FORMAT="${DEEPSEEK_FORMAT:-openai}"
# API key: Set DEEPSEEK_API_KEY environment variable

# =============================================================================
# MINIMAX CONFIGURATION - The Pragmatic Optimizer (CLI/API, v2.10; CLI via mmx v2.21)
# =============================================================================

MINIMAX_CMD="${MINIMAX_CMD:-mmx}"
MINIMAX_MODEL="${MINIMAX_MODEL:-MiniMax-M2.7}"
MINIMAX_TIMEOUT_SECONDS="${MINIMAX_TIMEOUT:-180}"
MINIMAX_API_MAX_TOKENS="${MINIMAX_API_MAX_TOKENS:-4096}"
MINIMAX_MAX_TOKENS="${MINIMAX_MAX_TOKENS:-4096}"
MINIMAX_MAX_QUALITY_TOKENS="${MINIMAX_MAX_QUALITY_TOKENS:-16384}"
MAX_QUALITY_API_MAX_TOKENS="${MAX_QUALITY_API_MAX_TOKENS:-16384}"
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

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-5}"
CLAUDE_API_MAX_TOKENS="${CLAUDE_API_MAX_TOKENS:-16384}"
CLAUDE_TIMEOUT_SECONDS="${CLAUDE_TIMEOUT:-240}"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

# =============================================================================
# CANONICAL CONSULTANT LIST
# =============================================================================
# This is the single source of truth for all available consultants.
# Use this array when iterating over consultants programmatically.

# All available consultants (ordered by typical usage)
ALL_CONSULTANTS=("Gemini" "Codex" "Mistral" "Kimi" "Claude" "Qwen3" "GLM" "Grok" "DeepSeek" "MiniMax")

# =============================================================================
# ENABLED CONSULTANTS
# =============================================================================

# Set to "false" to disable a specific consultant
# CLI-based consultants (enabled by default)
ENABLE_GEMINI="${ENABLE_GEMINI:-true}"
ENABLE_CODEX="${ENABLE_CODEX:-true}"
ENABLE_MISTRAL="${ENABLE_MISTRAL:-true}"
ENABLE_KIMI="${ENABLE_KIMI:-true}"       # Kimi Code (v2.9)
ENABLE_CLAUDE="${ENABLE_CLAUDE:-true}"   # Auto-disabled when invoked by Claude Code
ENABLE_QWEN3="${ENABLE_QWEN3:-true}"     # qwen-code CLI (v2.7); API opt-in
ENABLE_GROK="${ENABLE_GROK:-true}"       # Grok Build CLI; API fallback
ENABLE_MINIMAX="${ENABLE_MINIMAX:-true}" # mmx CLI (v2.21); API opt-in

# API-only consultants (disabled by default - require API keys)
ENABLE_GLM="${ENABLE_GLM:-false}"
ENABLE_DEEPSEEK="${ENABLE_DEEPSEEK:-false}"

# =============================================================================
# INVOKING AGENT DETECTION (v2.2)
# =============================================================================

# Agent that invoked this skill - used for self-exclusion to prevent
# an agent from consulting itself.
# Values: claude, codex, gemini, mistral, kimi, qwen3, or "unknown".
# Cursor may still be the host, but maps to no panel consultant.
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
# Accepted names (and aliases) are owned by public_registry.sh.
# Leave empty to use individual ENABLE_* settings
DEFAULT_PRESET="${DEFAULT_PRESET:-}"

# Default synthesis strategy
# The registry owns the accepted names and its single default.
DEFAULT_STRATEGY="${DEFAULT_STRATEGY:-$(registry_default_strategy)}"

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

# Deprecated no-op; retained through v4.x for configuration compatibility.
SESSION_CLEANUP_DAYS="${SESSION_CLEANUP_DAYS:-7}"

# Deprecated no-ops; retained through v4.x for configuration compatibility.
ENABLE_PROGRESS_BARS="${ENABLE_PROGRESS_BARS:-true}"
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

# Deprecated no-op; retained through v4.x for configuration compatibility.
USE_COMPACT_PROMPTS="${USE_COMPACT_PROMPTS:-true}"

# Extract only essential fields for synthesis (instead of full JSON)
SYNTHESIS_EXTRACT_FIELDS="${SYNTHESIS_EXTRACT_FIELDS:-true}"
SYNTH_DETAIL_MAX_CHARS="${SYNTH_DETAIL_MAX_CHARS:-4000}"
SYNTHESIS_TIMEOUT="${SYNTHESIS_TIMEOUT:-240}"
SYNTHESIS_TOTAL_TIMEOUT="${SYNTHESIS_TOTAL_TIMEOUT:-480}"

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

# Deprecated no-ops; retained through v4.x for configuration compatibility.
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

# Get the provider-specific model name for a consultant, tier, and transport.
# Usage: get_model_for_tier <consultant> <tier> [cli|api]
# Returns: model name, or empty string for an unknown consultant/tier.
get_model_for_tier() {
    local consultant="$1"
    local tier="${2:-premium}"
    local transport="${3:-}"
    consultant=$(echo "$consultant" | tr '[:upper:]' '[:lower:]')

    if [[ -z "$transport" ]]; then
        case "$consultant" in
            gemini|mistral)
                local mode_var mode_value
                mode_var="$(echo "$consultant" | tr '[:lower:]' '[:upper:]')_USE_API"
                mode_value="${!mode_var:-false}"
                [[ "$mode_value" == "true" ]] && transport="api" || transport="cli"
                ;;
            *) transport="native" ;;
        esac
    fi

    case "$tier" in
        maximum|max_quality|max-quality)
            case "$consultant" in
                claude)   echo "claude-opus-5" ;;
                gemini)   [[ "$transport" == "api" ]] && echo "gemini-3.1-pro-preview" || echo "Gemini 3.7 Flash (High)" ;;
                codex)    echo "gpt-5.6-sol" ;;
                mistral)  [[ "$transport" == "api" ]] && echo "mistral-large-3" || echo "mistral-medium-3.5" ;;
                deepseek) echo "deepseek-v4-pro" ;;
                glm)      echo "glm-5.3-flash" ;;
                grok)     echo "grok-4.6" ;;
                qwen3)    echo "qwen3.8-max" ;;
                kimi)     echo "kimi-code/k3-256k" ;;
                minimax)  echo "MiniMax-M3" ;;
                *)        echo "" ;;
            esac
            ;;
        premium|max|best)
            case "$consultant" in
                claude)   echo "claude-opus-5" ;;
                gemini)   [[ "$transport" == "api" ]] && echo "gemini-3.1-pro-preview" || echo "Gemini 3.7 Flash (High)" ;;
                codex)    echo "gpt-5.6-sol" ;;
                mistral)  [[ "$transport" == "api" ]] && echo "mistral-large-3" || echo "mistral-medium-3.5" ;;
                deepseek) echo "deepseek-v4-pro" ;;
                glm)      echo "glm-5.3-flash" ;;
                grok)     echo "grok-4.6" ;;
                qwen3)    echo "qwen3.7-max" ;;
                kimi)     echo "kimi-code/k3" ;;
                minimax)  echo "MiniMax-M2.7" ;;
                *)        echo "" ;;
            esac
            ;;
        standard|medium|balanced)
            case "$consultant" in
                claude)   echo "claude-sonnet-5" ;;
                gemini)   [[ "$transport" == "api" ]] && echo "gemini-3.1-pro-preview" || echo "Gemini 3.7 Flash (High)" ;;
                codex)    echo "gpt-5.6-terra" ;;
                mistral)  [[ "$transport" == "api" ]] && echo "mistral-large-3" || echo "mistral-medium-3.5" ;;
                deepseek) echo "deepseek-v4-flash" ;;
                glm)      echo "glm-5.3-flash" ;;  # Same as premium (no mid-tier GLM)
                grok)     echo "grok-4.5" ;;
                qwen3)    echo "qwen3.6-35b-a3b" ;;  # Open-weight MoE (35B total, 3B active)
                kimi)     echo "kimi-code/k3" ;;
                minimax)  echo "MiniMax-M2.7" ;;
                *)        echo "" ;;
            esac
            ;;
        economy|fast|quick)
            case "$consultant" in
                claude)   echo "claude-haiku-4-5" ;;
                gemini)   [[ "$transport" == "api" ]] && echo "gemini-3.1-pro-preview" || echo "Gemini 3.7 Flash (Low)" ;;
                codex)    echo "gpt-5.6-luna" ;;
                mistral)  [[ "$transport" == "api" ]] && echo "mistral-large-3" || echo "devstral-small-2" ;;
                deepseek) echo "deepseek-v4-flash" ;;
                glm)      echo "glm-4-flash" ;;
                grok)     echo "grok-4.5" ;;
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
# Usage: apply_model_tier <tier: maximum|premium|standard|economy>
# Premium = latest flagship models, highest quality
# Standard = good balance of quality and cost
# Economy = optimized for speed and low cost
apply_model_tier() {
    local tier="$1"
    local effort_provider effort_var managed_var prior_set_var prior_value_var
    local effort_spec effort_target
    local api_provider api_tokens_var api_managed_var api_prior_var

    # Validate tier name
    case "$tier" in
        maximum|max_quality|max-quality|premium|max|best|standard|medium|balanced|economy|fast|quick) ;;
        *)
            echo "Unknown model tier: $tier" >&2
            echo "Available tiers: maximum, premium, standard, economy" >&2
            return 1
            ;;
    esac

    local consultants="claude codex deepseek glm grok minimax kimi"
    for c in $consultants; do
        local model
        model=$(get_model_for_tier "$c" "$tier")
        if [[ -n "$model" ]]; then
            local var_name
            var_name="$(echo "$c" | tr '[:lower:]' '[:upper:]')_MODEL"
            export "$var_name=$model"
        fi
    done

    # Gemini and Mistral intentionally carry both transport-specific IDs so a
    # later transport choice cannot send a CLI display name to an HTTP API (or
    # an API slug to a CLI). Gemini 3.7 uses one API ID plus a thinking level.
    export GEMINI_MODEL="$(get_model_for_tier gemini "$tier" cli)"
    export GEMINI_API_MODEL="$(get_model_for_tier gemini "$tier" api)"
    export MISTRAL_CLI_MODEL="$(get_model_for_tier mistral "$tier" cli)"
    export MISTRAL_MODEL="$(get_model_for_tier mistral "$tier" api)"

    # Clear only an effort value that a previous tier application injected.
    # An ambient/user-pinned QWEN3_REASONING_EFFORT is never overwritten.
    if [[ "${_AI_CONSULTANTS_TIER_QWEN_EFFORT_MANAGED:-false}" == "true" ]]; then
        unset QWEN3_REASONING_EFFORT _AI_CONSULTANTS_TIER_QWEN_EFFORT_MANAGED
    fi

    # Qwen3.8-Max at xhigh can legitimately take longer than the normal tier.
    # Preserve the caller's timeout and restore it when leaving maximum.
    case "$tier" in
        maximum|max_quality|max-quality) ;;
        *)
            if [[ "${_AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED:-false}" == "true" ]]; then
                export QWEN3_TIMEOUT_SECONDS="$_AI_CONSULTANTS_TIER_QWEN_TIMEOUT_PRIOR"
                if [[ "${_AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET:-false}" == "true" ]]; then
                    export QWEN3_TIMEOUT="$_AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR"
                else
                    unset QWEN3_TIMEOUT
                fi
                unset _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_PRIOR \
                    _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR
            fi
            ;;
    esac

    # Maximum temporarily overrides these provider efforts so the preset can
    # honor its name even when the ambient config pins a lower value. Preserve
    # that prior state and restore it when a later tier is applied; otherwise a
    # documented sequence such as maximum -> economy leaks maximum reasoning.
    case "$tier" in
        maximum|max_quality|max-quality) ;;
        *)
            for effort_provider in GROK GLM DEEPSEEK; do
                effort_var="${effort_provider}_REASONING_EFFORT"
                managed_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_MANAGED"
                prior_set_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_PRIOR_SET"
                prior_value_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_PRIOR_VALUE"
                if [[ "${!managed_var:-false}" == "true" ]]; then
                    if [[ "${!prior_set_var:-false}" == "true" ]]; then
                        export "$effort_var=${!prior_value_var:-}"
                    else
                        unset "$effort_var"
                    fi
                    unset "$managed_var" "$prior_set_var" "$prior_value_var"
                fi
            done
            if [[ "${_AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_MANAGED:-false}" == "true" ]]; then
                export DEEPSEEK_TIMEOUT_SECONDS="$_AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_PRIOR"
                if [[ "${_AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR_SET:-false}" == "true" ]]; then
                    export DEEPSEEK_TIMEOUT="$_AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR"
                else
                    unset DEEPSEEK_TIMEOUT
                fi
                unset _AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_MANAGED _AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_PRIOR \
                    _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR_SET _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR
            fi
            if [[ "${_AI_CONSULTANTS_TIER_MINIMAX_TOKENS_MANAGED:-false}" == "true" ]]; then
                export MINIMAX_MAX_TOKENS="$_AI_CONSULTANTS_TIER_MINIMAX_TOKENS_PRIOR"
                unset _AI_CONSULTANTS_TIER_MINIMAX_TOKENS_MANAGED _AI_CONSULTANTS_TIER_MINIMAX_TOKENS_PRIOR
            fi
            for api_provider in CODEX MISTRAL GROK MINIMAX; do
                api_tokens_var="${api_provider}_API_MAX_TOKENS"
                api_managed_var="_AI_CONSULTANTS_TIER_${api_provider}_API_TOKENS_MANAGED"
                api_prior_var="_AI_CONSULTANTS_TIER_${api_provider}_API_TOKENS_PRIOR"
                if [[ "${!api_managed_var:-false}" == "true" ]]; then
                    export "$api_tokens_var=${!api_prior_var}"
                    unset "$api_managed_var" "$api_prior_var"
                fi
            done
            ;;
    esac

    case "$tier" in
        maximum|max_quality|max-quality)
            # Qwen3.8-Max exists only on the OpenAI-compatible Token Plan
            # transport. Do not redirect a DashScope key or a CLI user to that
            # separate paid endpoint just because they selected max_quality.
            if [[ "${QWEN3_USE_API:-false}" == "true" \
                && "${QWEN3_FORMAT:-qwen}" == "openai" \
                && "${QWEN3_API_URL:-}" == *token-plan* \
                && "${QWEN3_API_URL:-}" == */chat/completions \
                && -n "${QWEN3_API_KEY:-}" ]]; then
                export QWEN3_MODEL="qwen3.8-max"
                if [[ -z "${QWEN3_REASONING_EFFORT:-}" ]]; then
                    export QWEN3_REASONING_EFFORT=xhigh
                    export _AI_CONSULTANTS_TIER_QWEN_EFFORT_MANAGED=true
                fi
                if [[ "${_AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED:-false}" != "true" ]]; then
                    export _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_PRIOR="$QWEN3_TIMEOUT_SECONDS"
                    if declare -p QWEN3_TIMEOUT >/dev/null 2>&1; then
                        export _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET=true
                        export _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR="$QWEN3_TIMEOUT"
                    else
                        export _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET=false
                        unset _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR
                    fi
                    export _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED=true
                fi
                export QWEN3_TIMEOUT="$QWEN3_MAX_QUALITY_TIMEOUT"
                export QWEN3_TIMEOUT_SECONDS="$QWEN3_MAX_QUALITY_TIMEOUT"
            else
                export QWEN3_MODEL="qwen3.7-max"
                if [[ "${_AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED:-false}" == "true" ]]; then
                    export QWEN3_TIMEOUT_SECONDS="$_AI_CONSULTANTS_TIER_QWEN_TIMEOUT_PRIOR"
                    if [[ "${_AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET:-false}" == "true" ]]; then
                        export QWEN3_TIMEOUT="$_AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR"
                    else
                        unset QWEN3_TIMEOUT
                    fi
                    unset _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_MANAGED _AI_CONSULTANTS_TIER_QWEN_TIMEOUT_PRIOR \
                        _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR_SET _AI_CONSULTANTS_TIER_QWEN_PUBLIC_TIMEOUT_PRIOR
                fi
            fi
            ;;
        *)
            export QWEN3_MODEL="$(get_model_for_tier qwen3 "$tier")"
            ;;
    esac

    # Gemini 3.7 is promoted only on the exact agy transport that completed a
    # live adapter smoke. API tiers remain on the separately proven 3.1 Pro ID;
    # neither transport silently substitutes the other's model namespace.

    case "$tier" in
        maximum|max_quality|max-quality)
            for effort_spec in GROK:xhigh GLM:max DEEPSEEK:max; do
                effort_provider="${effort_spec%%:*}"
                effort_target="${effort_spec#*:}"
                effort_var="${effort_provider}_REASONING_EFFORT"
                managed_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_MANAGED"
                prior_set_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_PRIOR_SET"
                prior_value_var="_AI_CONSULTANTS_TIER_${effort_provider}_EFFORT_PRIOR_VALUE"
                if [[ "${!managed_var:-false}" != "true" ]]; then
                    if declare -p "$effort_var" >/dev/null 2>&1; then
                        export "$prior_set_var=true"
                        export "$prior_value_var=${!effort_var}"
                    else
                        export "$prior_set_var=false"
                        unset "$prior_value_var"
                    fi
                    export "$managed_var=true"
                fi
                export "$effort_var=$effort_target"
            done
            if [[ "${_AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_MANAGED:-false}" != "true" ]]; then
                export _AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_PRIOR="$DEEPSEEK_TIMEOUT_SECONDS"
                if declare -p DEEPSEEK_TIMEOUT >/dev/null 2>&1; then
                    export _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR_SET=true
                    export _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR="$DEEPSEEK_TIMEOUT"
                else
                    export _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR_SET=false
                    unset _AI_CONSULTANTS_TIER_DEEPSEEK_PUBLIC_TIMEOUT_PRIOR
                fi
                export _AI_CONSULTANTS_TIER_DEEPSEEK_TIMEOUT_MANAGED=true
            fi
            export DEEPSEEK_TIMEOUT="$DEEPSEEK_MAX_QUALITY_TIMEOUT"
            export DEEPSEEK_TIMEOUT_SECONDS="$DEEPSEEK_MAX_QUALITY_TIMEOUT"
            if [[ "${_AI_CONSULTANTS_TIER_MINIMAX_TOKENS_MANAGED:-false}" != "true" ]]; then
                export _AI_CONSULTANTS_TIER_MINIMAX_TOKENS_PRIOR="$MINIMAX_MAX_TOKENS"
                export _AI_CONSULTANTS_TIER_MINIMAX_TOKENS_MANAGED=true
            fi
            export MINIMAX_MAX_TOKENS="$MINIMAX_MAX_QUALITY_TOKENS"
            for api_provider in CODEX MISTRAL GROK MINIMAX; do
                api_tokens_var="${api_provider}_API_MAX_TOKENS"
                api_managed_var="_AI_CONSULTANTS_TIER_${api_provider}_API_TOKENS_MANAGED"
                api_prior_var="_AI_CONSULTANTS_TIER_${api_provider}_API_TOKENS_PRIOR"
                if [[ "${!api_managed_var:-false}" != "true" ]]; then
                    export "$api_prior_var=${!api_tokens_var}"
                    export "$api_managed_var=true"
                fi
                export "$api_tokens_var=$MAX_QUALITY_API_MAX_TOKENS"
            done
            ;;
    esac

    return 0
}

# =============================================================================
# CONFIGURATION PRESETS (v2.2)
# =============================================================================

# Presets allow quick configuration for different use cases:
#   minimal      - 2 models (fast, cheap): Gemini + Codex
#   balanced     - 3 models (good coverage): Gemini + Codex + Mistral
#   thorough     - 3 models (comprehensive)
#   high-stakes  - Broad premium panel for critical decisions
#
# Quality Tiers (v2.5):
#   max_quality  - all 10 consultants + maximum models/effort
#   medium       - 3 consultants + standard models
#   fast         - 2 consultants + economy models
#
# Usage: ./consult_all.sh --preset balanced "Your question"

# Helper: Disable all consultants
_disable_all_consultants() {
    export ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false
    export ENABLE_KIMI=false ENABLE_CLAUDE=false
    export ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false
    export ENABLE_DEEPSEEK=false ENABLE_MINIMAX=false
}

# A deliberate per-consultant false remains an opt-out when a preset is used.
# This prevents a fallback from silently enrolling a billed API transport that
# the user disabled.
_enable_preset_consultant() {
    local consultant="$1" flag="ENABLE_$1" optout="_AI_CONSULTANTS_PRESET_OPTOUT_ENABLE_$1"
    [[ "${!optout:-false}" == "true" ]] && return 0
    export "$flag=true"
}

_enable_preset_consultants() {
    local consultant
    for consultant in "$@"; do
        _enable_preset_consultant "$consultant"
    done
}

# Return the promised number of canonical consultants for a preset.
#
# This deliberately describes the preset contract, rather than the transports
# that happen to be usable on this machine.  consult_all.sh uses it after
# self-exclusion to fill from ALL_CONSULTANTS without changing a preset's
# models, tier, or primary ordering.
# Usage: get_preset_panel_size <preset_name>
get_preset_panel_size() {
    registry_preset_target "$1"
}

# Return the host-aware target for a preset. The raw max_quality contract is
# ten consultants, but a canonical invoking host is fail-closed excluded and
# cannot be replaced from a ten-member canonical roster. Its attainable panel
# is therefore nine; every other preset retains its raw target and is filled
# from the canonical roster by the orchestrator.
# Usage: get_effective_preset_panel_size <preset_name>
get_effective_preset_panel_size() {
    local preset="$1" raw self_name
    raw=$(get_preset_panel_size "$preset") || return 1
    self_name=$(get_self_consultant_name)
    preset=$(registry_canonical_preset "$preset") || return 1
    case "$preset" in
        max_quality)
            [[ -n "$self_name" ]] && echo $((raw - 1)) || echo "$raw"
            ;;
        *) echo "$raw" ;;
    esac
}

# Apply a preset configuration
# Usage: apply_preset <preset_name>
apply_preset() {
    local preset
    preset=$(registry_canonical_preset "$1") || {
        echo "Unknown preset: $1" >&2
        echo "Available presets: $(registry_preset_rows | cut -d'|' -f1 | tr '\n' ' ' | sed 's/ $//')" >&2
        return 1
    }
    export _AI_CONSULTANTS_PRESET_APPLIED=true

    # Start with all disabled, then enable what's needed
    _disable_all_consultants

    case "$preset" in
        minimal)
            _enable_preset_consultants GEMINI CODEX
            ;;
        balanced)
            _enable_preset_consultants GEMINI CODEX MISTRAL
            ;;
        thorough)
            _enable_preset_consultants GEMINI CODEX MISTRAL
            ;;
        high-stakes)
            _enable_preset_consultants GEMINI CODEX MISTRAL CLAUDE
            ;;
        security)
            _enable_preset_consultants GEMINI CODEX MISTRAL
            ;;
        cost-capped)
            apply_model_tier "economy"
            _enable_preset_consultants GEMINI MISTRAL QWEN3
            export MAX_SESSION_COST=0.10
            ;;
        # --- Quality Tier Presets (v2.5) ---
        max_quality)
            # Maximum quality - costly/separate-plan models stay confined here.
            apply_model_tier "maximum"
            _enable_preset_consultants GEMINI CODEX MISTRAL KIMI CLAUDE QWEN3 GLM GROK DEEPSEEK MINIMAX
            ;;
        medium)
            # Balanced quality - standard models, good coverage
            apply_model_tier "standard"
            _enable_preset_consultants GEMINI CODEX MISTRAL
            ;;
        fast)
            # Super fast - economy models, minimal consultants
            apply_model_tier "economy"
            _enable_preset_consultants GEMINI CODEX
            export ENABLE_COMPACT_REPORT=true
            ;;
    esac

    return 0
}

# List available presets with descriptions
list_presets() {
    registry_list_presets
}

# =============================================================================
# VERSION
# =============================================================================

AI_CONSULTANTS_VERSION="4.0.4"
