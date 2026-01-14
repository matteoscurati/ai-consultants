#!/bin/bash
# config.sh - Centralized configuration for AI Consultants v2.0
# Modify this file to customize skill behavior

# =============================================================================
# GENERAL SETTINGS
# =============================================================================

# Maximum number of retry attempts on failure
MAX_RETRIES="${MAX_RETRIES:-2}"

# Pause in seconds between retry attempts
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"

# Base output directory for consultations
DEFAULT_OUTPUT_DIR_BASE="${DEFAULT_OUTPUT_DIR_BASE:-/tmp/ai_consultations}"

# =============================================================================
# GEMINI CONFIGURATION - The Architect
# =============================================================================

GEMINI_MODEL="${GEMINI_MODEL:-gemini-2.5-pro}"
GEMINI_TIMEOUT_SECONDS="${GEMINI_TIMEOUT:-180}"
GEMINI_CMD="${GEMINI_CMD:-gemini}"

# =============================================================================
# CODEX CONFIGURATION - The Pragmatist
# =============================================================================

# Model: empty = default, or "o3", "gpt-4", "gpt-4o", etc.
CODEX_MODEL="${CODEX_MODEL:-}"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT:-180}"
CODEX_CMD="${CODEX_CMD:-codex}"

# =============================================================================
# MISTRAL VIBE CONFIGURATION - The Devil's Advocate
# =============================================================================

MISTRAL_TIMEOUT_SECONDS="${MISTRAL_TIMEOUT:-180}"
MISTRAL_CMD="${MISTRAL_CMD:-vibe}"

# =============================================================================
# KILO CONFIGURATION - The Innovator
# =============================================================================

KILO_TIMEOUT_SECONDS="${KILO_TIMEOUT:-180}"
KILO_WORKSPACE="${KILO_WORKSPACE:-$(pwd)}"
KILO_CMD="${KILO_CMD:-kilocode}"

# =============================================================================
# CURSOR CONFIGURATION - The Integrator
# =============================================================================

CURSOR_TIMEOUT_SECONDS="${CURSOR_TIMEOUT:-180}"
CURSOR_CMD="${CURSOR_CMD:-agent}"

# =============================================================================
# QWEN3 CONFIGURATION - The Analyst (API-based)
# =============================================================================

QWEN3_MODEL="${QWEN3_MODEL:-qwen-max}"
QWEN3_TIMEOUT_SECONDS="${QWEN3_TIMEOUT:-180}"
QWEN3_API_URL="${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}"
# API key: Set QWEN3_API_KEY environment variable

# =============================================================================
# GLM CONFIGURATION - The Methodologist (API-based)
# =============================================================================

GLM_MODEL="${GLM_MODEL:-glm-4}"
GLM_TIMEOUT_SECONDS="${GLM_TIMEOUT:-180}"
GLM_API_URL="${GLM_API_URL:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"
# API key: Set GLM_API_KEY environment variable

# =============================================================================
# GROK CONFIGURATION - The Provocateur (API-based)
# =============================================================================

GROK_MODEL="${GROK_MODEL:-grok-beta}"
GROK_TIMEOUT_SECONDS="${GROK_TIMEOUT:-180}"
GROK_API_URL="${GROK_API_URL:-https://api.x.ai/v1/chat/completions}"
# API key: Set GROK_API_KEY environment variable

# =============================================================================
# ENABLED CONSULTANTS
# =============================================================================

# Set to "false" to disable a specific consultant
# CLI-based consultants (enabled by default)
ENABLE_GEMINI="${ENABLE_GEMINI:-true}"
ENABLE_CODEX="${ENABLE_CODEX:-true}"
ENABLE_MISTRAL="${ENABLE_MISTRAL:-true}"
ENABLE_KILO="${ENABLE_KILO:-true}"
ENABLE_CURSOR="${ENABLE_CURSOR:-true}"

# API-based consultants (disabled by default - require API keys)
ENABLE_QWEN3="${ENABLE_QWEN3:-false}"
ENABLE_GLM="${ENABLE_GLM:-false}"
ENABLE_GROK="${ENABLE_GROK:-false}"

# =============================================================================
# PERSONAS (v2.0)
# =============================================================================

# Enable/disable persona system
ENABLE_PERSONA="${ENABLE_PERSONA:-true}"

# =============================================================================
# AUTO-SYNTHESIS (v2.0)
# =============================================================================

# Enable automatic response synthesis
ENABLE_SYNTHESIS="${ENABLE_SYNTHESIS:-true}"

# CLI for synthesis (default: claude)
SYNTHESIS_CMD="${SYNTHESIS_CMD:-claude}"

# =============================================================================
# MULTI-AGENT DEBATE - MAD (v2.0)
# =============================================================================

# Enable multi-round debate
ENABLE_DEBATE="${ENABLE_DEBATE:-false}"

# Number of debate rounds (1 = initial responses only, 2-3 = with cross-critique)
DEBATE_ROUNDS="${DEBATE_ROUNDS:-1}"

# =============================================================================
# SELF-REFLECTION (v2.0)
# =============================================================================

# Enable auto-reflection (generate-critique-refine)
ENABLE_REFLECTION="${ENABLE_REFLECTION:-false}"

# Number of reflection cycles per response
REFLECTION_CYCLES="${REFLECTION_CYCLES:-1}"

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

# File for cumulative tracking
COST_TRACKING_FILE="${COST_TRACKING_FILE:-/tmp/ai_consultants_costs.json}"

# =============================================================================
# SESSION MANAGEMENT (v2.0)
# =============================================================================

# Directory for session files
SESSION_DIR="${SESSION_DIR:-/tmp/ai_consultants_sessions}"

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
# VERSION
# =============================================================================

AI_CONSULTANTS_VERSION="2.0.0"
