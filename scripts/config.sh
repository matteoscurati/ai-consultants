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
# CLI/API MODE SWITCHING (v2.6+)
# =============================================================================
# For agents that support both CLI and API mode, set USE_API=true to use API mode.
# When API mode is enabled, CLI mode is automatically disabled (mutual exclusivity).
# 5 agents support switching: Gemini, Codex, Claude, Mistral, Qwen3

# Mode switching (true = use API, false = use CLI)
GEMINI_USE_API="${GEMINI_USE_API:-false}"
CODEX_USE_API="${CODEX_USE_API:-false}"
CLAUDE_USE_API="${CLAUDE_USE_API:-false}"
MISTRAL_USE_API="${MISTRAL_USE_API:-false}"
QWEN3_USE_API="${QWEN3_USE_API:-true}"  # Default true to preserve v2.6 API behavior

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
# GEMINI CONFIGURATION - The Architect
# =============================================================================

GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.0-pro}"
GEMINI_TIMEOUT_SECONDS="${GEMINI_TIMEOUT:-180}"
GEMINI_CMD="${GEMINI_CMD:-gemini}"

# =============================================================================
# CODEX CONFIGURATION - The Pragmatist
# =============================================================================

# Model: "gpt-5.2-codex" (default), "gpt-5.2", "gpt-4o-mini", etc.
CODEX_MODEL="${CODEX_MODEL:-gpt-5.2-codex}"
CODEX_TIMEOUT_SECONDS="${CODEX_TIMEOUT:-180}"
CODEX_CMD="${CODEX_CMD:-codex}"

# =============================================================================
# MISTRAL VIBE CONFIGURATION - The Devil's Advocate
# =============================================================================

MISTRAL_MODEL="${MISTRAL_MODEL:-mistral-large-3}"
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
# AIDER CONFIGURATION - The Pair Programmer
# =============================================================================

AIDER_MODEL="${AIDER_MODEL:-gpt-5.2-codex}"
AIDER_TIMEOUT_SECONDS="${AIDER_TIMEOUT:-180}"
AIDER_CMD="${AIDER_CMD:-aider}"

# =============================================================================
# QWEN3 CONFIGURATION - The Analyst (CLI/API switchable v2.7)
# =============================================================================

QWEN3_MODEL="${QWEN3_MODEL:-qwen3-max}"
QWEN3_TIMEOUT_SECONDS="${QWEN3_TIMEOUT:-180}"
QWEN3_CMD="${QWEN3_CMD:-qwen}"
QWEN3_API_URL="${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}"
QWEN3_FORMAT="${QWEN3_FORMAT:-qwen}"
# CLI mode: npm install -g @qwen-code/qwen-code@latest
# API key: Set QWEN3_API_KEY environment variable

# =============================================================================
# GLM CONFIGURATION - The Code Specialist (API-based)
# =============================================================================

GLM_MODEL="${GLM_MODEL:-glm-4.7}"
GLM_TIMEOUT_SECONDS="${GLM_TIMEOUT:-180}"
GLM_API_URL="${GLM_API_URL:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"
GLM_FORMAT="${GLM_FORMAT:-openai}"
# API key: Set GLM_API_KEY environment variable

# =============================================================================
# GROK CONFIGURATION - The Provocateur (API-based)
# =============================================================================

GROK_MODEL="${GROK_MODEL:-grok-4-1-fast-reasoning}"
GROK_TIMEOUT_SECONDS="${GROK_TIMEOUT:-180}"
GROK_API_URL="${GROK_API_URL:-https://api.x.ai/v1/chat/completions}"
GROK_FORMAT="${GROK_FORMAT:-openai}"
# API key: Set GROK_API_KEY environment variable

# =============================================================================
# DEEPSEEK CONFIGURATION - The Methodologist (API-based)
# =============================================================================

DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-v3.2-speciale}"
DEEPSEEK_TIMEOUT_SECONDS="${DEEPSEEK_TIMEOUT:-180}"
DEEPSEEK_API_URL="${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}"
DEEPSEEK_FORMAT="${DEEPSEEK_FORMAT:-openai}"
# API key: Set DEEPSEEK_API_KEY environment variable

# =============================================================================
# CLAUDE CONFIGURATION - The Synthesizer (v2.2)
# =============================================================================

CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-5-20251124}"
CLAUDE_TIMEOUT_SECONDS="${CLAUDE_TIMEOUT:-240}"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

# =============================================================================
# OLLAMA CONFIGURATION - The Local Expert (v2.2)
# =============================================================================

# Default model for local inference (premium: qwen2.5-coder:32b)
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:32b}"
# Alternative models: llama3.3, llama3.2, codellama, mistral, deepseek-coder

# Ollama server URL (default: local)
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Timeout for local inference (longer than API due to local hardware)
OLLAMA_TIMEOUT="${OLLAMA_TIMEOUT:-300}"

# Temperature for generation
OLLAMA_TEMPERATURE="${OLLAMA_TEMPERATURE:-0.7}"

# Comma-separated list of models to query (for multi-model local consultations)
# Example: OLLAMA_MODELS="llama3.2,codellama,mistral"
OLLAMA_MODELS="${OLLAMA_MODELS:-}"

# =============================================================================
# CANONICAL CONSULTANT LIST
# =============================================================================
# This is the single source of truth for all available consultants.
# Use this array when iterating over consultants programmatically.

# All available consultants (ordered by typical usage)
ALL_CONSULTANTS=("Gemini" "Codex" "Mistral" "Kilo" "Cursor" "Aider" "Claude" "Qwen3" "GLM" "Grok" "DeepSeek" "Ollama")

# CLI-based consultants (use CLI tools, some support CLI/API switching)
CLI_CONSULTANTS=("Gemini" "Codex" "Mistral" "Kilo" "Cursor" "Aider" "Claude" "Qwen3" "Ollama")

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
ENABLE_KILO="${ENABLE_KILO:-true}"
ENABLE_CURSOR="${ENABLE_CURSOR:-true}"
ENABLE_AIDER="${ENABLE_AIDER:-false}"
ENABLE_CLAUDE="${ENABLE_CLAUDE:-false}"  # Auto-disabled when invoked by Claude Code

# API-based consultants (disabled by default - require API keys)
ENABLE_QWEN3="${ENABLE_QWEN3:-false}"
ENABLE_GLM="${ENABLE_GLM:-false}"
ENABLE_GROK="${ENABLE_GROK:-false}"
ENABLE_DEEPSEEK="${ENABLE_DEEPSEEK:-false}"

# Local model support via Ollama (disabled by default)
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"

# =============================================================================
# INVOKING AGENT DETECTION (v2.2)
# =============================================================================

# Agent that invoked this skill - used for self-exclusion to prevent
# an agent from consulting itself.
# Values: claude, codex, gemini, cursor, mistral, kilo, aider, or "unknown"
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
# Options: minimal, balanced, thorough, high-stakes, local, security, cost-capped
# Leave empty to use individual ENABLE_* settings
DEFAULT_PRESET="${DEFAULT_PRESET:-}"

# Default synthesis strategy
# Options: majority, risk_averse, security_first, cost_capped, compare_only
DEFAULT_STRATEGY="${DEFAULT_STRATEGY:-majority}"

# =============================================================================
# PEER REVIEW (v2.2)
# =============================================================================

# Enable anonymous peer review step
ENABLE_PEER_REVIEW="${ENABLE_PEER_REVIEW:-false}"

# Minimum responses required for peer review (default: 3)
PEER_REVIEW_MIN_RESPONSES="${PEER_REVIEW_MIN_RESPONSES:-3}"

# =============================================================================
# MULTI-AGENT DEBATE - MAD (v2.0)
# =============================================================================

# Enable multi-round debate
ENABLE_DEBATE="${ENABLE_DEBATE:-false}"

# Number of debate rounds (1 = initial responses only, 2-3 = with cross-critique)
DEBATE_ROUNDS="${DEBATE_ROUNDS:-1}"

# =============================================================================
# PANIC BUTTON MODE (v2.2)
# =============================================================================

# Panic mode triggers additional rigor when uncertainty is detected
# Values: "auto" (detect), "always" (always enable), "never" (disable)
ENABLE_PANIC_MODE="${ENABLE_PANIC_MODE:-auto}"

# Threshold for average confidence below which panic mode triggers
PANIC_CONFIDENCE_THRESHOLD="${PANIC_CONFIDENCE_THRESHOLD:-5}"

# Number of additional debate rounds to add in panic mode
PANIC_EXTRA_DEBATE_ROUNDS="${PANIC_EXTRA_DEBATE_ROUNDS:-1}"

# Keywords that trigger panic mode when found in responses
PANIC_KEYWORDS="${PANIC_KEYWORDS:-uncertain|maybe|not sure|possibly|unclear|depends|hard to say|difficult to determine}"

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

# --- Budget Enforcement (v2.4) ---
# Enable budget limit enforcement (opt-in, default OFF)
ENABLE_BUDGET_LIMIT="${ENABLE_BUDGET_LIMIT:-false}"

# Action to take when budget is exceeded
# Options: warn (log warning but continue), stop (halt consultation with partial results)
BUDGET_ACTION="${BUDGET_ACTION:-warn}"

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
# Cache responses based on query + context hash
ENABLE_SEMANTIC_CACHE="${ENABLE_SEMANTIC_CACHE:-true}"
CACHE_TTL_HOURS="${CACHE_TTL_HOURS:-24}"
CACHE_DIR="${CACHE_DIR:-/tmp/ai_consultants_cache}"

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

# --- Debate Optimization ---
# Optimize debate rounds for token efficiency
# NOTE: Default is FALSE (opt-in) per quality review - can miss critical disagreements
ENABLE_DEBATE_OPTIMIZATION="${ENABLE_DEBATE_OPTIMIZATION:-false}"
# Only activate debate if confidence spread exceeds threshold
# Lowered to 2 per quality review (original: 3)
DEBATE_CONFIDENCE_SPREAD_THRESHOLD="${DEBATE_CONFIDENCE_SPREAD_THRESHOLD:-2}"
# Use summaries in debate rounds instead of full responses
DEBATE_USE_SUMMARIES="${DEBATE_USE_SUMMARIES:-true}"

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

# Apply model tier to all consultants
# Usage: apply_model_tier <tier: premium|standard|economy>
# Premium = latest flagship models, highest quality
# Standard = good balance of quality and cost
# Economy = optimized for speed and low cost
apply_model_tier() {
    local tier="$1"

    case "$tier" in
        premium|max|best)
            # Verified January 2026 - Latest flagship models
            export CLAUDE_MODEL="claude-opus-4-5-20251124"
            export GEMINI_MODEL="gemini-3.0-pro"
            export CODEX_MODEL="gpt-5.2-codex"
            export MISTRAL_MODEL="mistral-large-3"
            export DEEPSEEK_MODEL="deepseek-v3.2-speciale"
            export GLM_MODEL="glm-4.7"
            export GROK_MODEL="grok-4-1-fast-reasoning"
            export QWEN3_MODEL="qwen3-max"
            export AIDER_MODEL="gpt-5.2-codex"
            export OLLAMA_MODEL="qwen2.5-coder:32b"
            ;;
        standard|medium|balanced)
            # Good quality at reasonable cost
            export CLAUDE_MODEL="claude-sonnet-4-5-20251124"
            export GEMINI_MODEL="gemini-3.0-flash"
            export CODEX_MODEL="gpt-5.2"
            export MISTRAL_MODEL="mistral-medium-latest"
            export DEEPSEEK_MODEL="deepseek-v3.2"
            # GLM-4.7 is used for both premium and standard (no mid-tier GLM available)
            export GLM_MODEL="glm-4.7"
            export GROK_MODEL="grok-3"
            export QWEN3_MODEL="qwen3-235b-a22b"
            export AIDER_MODEL="gpt-5.2"
            export OLLAMA_MODEL="llama3.3"
            ;;
        economy|fast|quick)
            # Optimized for speed and low cost
            export CLAUDE_MODEL="claude-3-5-haiku-20241022"
            export GEMINI_MODEL="gemini-2.0-flash-lite"
            export CODEX_MODEL="gpt-4o-mini"
            export MISTRAL_MODEL="devstral-small-2"
            export DEEPSEEK_MODEL="deepseek-chat"
            export GLM_MODEL="glm-4-flash"
            export GROK_MODEL="grok-3-mini"
            export QWEN3_MODEL="qwen3-32b"
            export AIDER_MODEL="gpt-4o-mini"
            export OLLAMA_MODEL="llama3.2"
            ;;
        *)
            echo "Unknown model tier: $tier" >&2
            echo "Available tiers: premium, standard, economy" >&2
            return 1
            ;;
    esac

    return 0
}

# =============================================================================
# CONFIGURATION PRESETS (v2.2)
# =============================================================================

# Presets allow quick configuration for different use cases:
#   minimal      - 2 models (fast, cheap): Gemini + Codex
#   balanced     - 4 models (good coverage): + Mistral + Kilo
#   thorough     - 5 models (comprehensive): + Cursor
#   high-stakes  - All models + debate (maximum rigor)
#
# Quality Tiers (v2.5):
#   max_quality  - All consultants + premium models + debate + reflection
#   medium       - 4 consultants + standard models + light debate
#   fast         - 2 consultants + economy models, no debate
#
# Usage: ./consult_all.sh --preset balanced "Your question"

# Helper: Disable all consultants
_disable_all_consultants() {
    export ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false
    export ENABLE_KILO=false ENABLE_CURSOR=false ENABLE_AIDER=false
    export ENABLE_CLAUDE=false
    export ENABLE_QWEN3=false ENABLE_GLM=false ENABLE_GROK=false
    export ENABLE_DEEPSEEK=false ENABLE_OLLAMA=false
    export ENABLE_DEBATE=false ENABLE_REFLECTION=false
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
            export ENABLE_MISTRAL=true ENABLE_KILO=true
            ;;
        thorough)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_KILO=true ENABLE_CURSOR=true
            ;;
        high-stakes)
            export ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true
            export ENABLE_KILO=true ENABLE_CURSOR=true ENABLE_AIDER=true
            export ENABLE_DEBATE=true DEBATE_ROUNDS=2
            export ENABLE_REFLECTION=true REFLECTION_CYCLES=1
            ;;
        local)
            # Local inference with Ollama - use economy tier for speed
            apply_model_tier "economy"
            export ENABLE_OLLAMA=true
            export OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.2,codellama}"
            ;;
        security)
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_CURSOR=true
            export ENABLE_DEBATE=true DEBATE_ROUNDS=2
            ;;
        cost-capped)
            export ENABLE_GEMINI=true ENABLE_MISTRAL=true ENABLE_OLLAMA=true
            export MAX_SESSION_COST=0.10
            ;;
        # --- Quality Tier Presets (v2.5) ---
        max_quality|max-quality)
            # Maximum quality - all premium models + all features
            apply_model_tier "premium"
            export ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=true
            export ENABLE_KILO=true ENABLE_CURSOR=true ENABLE_AIDER=true
            export ENABLE_CLAUDE=true
            export ENABLE_DEBATE=true DEBATE_ROUNDS=3
            export ENABLE_REFLECTION=true REFLECTION_CYCLES=2
            export ENABLE_PEER_REVIEW=true
            ;;
        medium)
            # Balanced quality - standard models, good coverage
            apply_model_tier "standard"
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_MISTRAL=true ENABLE_KILO=true
            export ENABLE_DEBATE=true DEBATE_ROUNDS=1
            ;;
        fast)
            # Super fast - economy models, minimal consultants
            apply_model_tier "economy"
            export ENABLE_GEMINI=true ENABLE_CODEX=true
            export ENABLE_DEBATE=false ENABLE_REFLECTION=false
            export ENABLE_COMPACT_REPORT=true
            ;;
        *)
            echo "Unknown preset: $preset" >&2
            echo "Available presets: minimal, balanced, thorough, high-stakes, local, security, cost-capped, max_quality, medium, fast" >&2
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
  max_quality  All consultants + premium models + debate + reflection
  medium       4 consultants + standard models + light debate
  fast         2 consultants + economy models, no debate

Use Cases:
  minimal      2 models (Gemini + Codex) - Fast, cheap
  balanced     4 models (+ Mistral + Kilo) - Good coverage [DEFAULT]
  thorough     5 models (+ Cursor) - Comprehensive analysis
  high-stakes  All models + debate - Maximum rigor for critical decisions
  local        Ollama only - Full privacy, no API calls
  security     Security-focused models + debate - For security reviews
  cost-capped  Budget-conscious options - Minimal API costs

Usage: ./consult_all.sh --preset <name> "Your question"
EOF
}

# =============================================================================
# VERSION
# =============================================================================

AI_CONSULTANTS_VERSION="2.7.0"
