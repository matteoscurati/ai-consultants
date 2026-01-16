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
# AIDER CONFIGURATION - The Pair Programmer
# =============================================================================

AIDER_MODEL="${AIDER_MODEL:-}"
AIDER_TIMEOUT_SECONDS="${AIDER_TIMEOUT:-180}"
AIDER_CMD="${AIDER_CMD:-aider}"

# =============================================================================
# QWEN3 CONFIGURATION - The Analyst (API-based)
# =============================================================================

QWEN3_MODEL="${QWEN3_MODEL:-qwen-max}"
QWEN3_TIMEOUT_SECONDS="${QWEN3_TIMEOUT:-180}"
QWEN3_API_URL="${QWEN3_API_URL:-https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation}"
QWEN3_FORMAT="${QWEN3_FORMAT:-qwen}"
# API key: Set QWEN3_API_KEY environment variable

# =============================================================================
# GLM CONFIGURATION - The Code Specialist (API-based)
# =============================================================================

GLM_MODEL="${GLM_MODEL:-glm-4}"
GLM_TIMEOUT_SECONDS="${GLM_TIMEOUT:-180}"
GLM_API_URL="${GLM_API_URL:-https://open.bigmodel.cn/api/paas/v4/chat/completions}"
GLM_FORMAT="${GLM_FORMAT:-openai}"
# API key: Set GLM_API_KEY environment variable

# =============================================================================
# GROK CONFIGURATION - The Provocateur (API-based)
# =============================================================================

GROK_MODEL="${GROK_MODEL:-grok-beta}"
GROK_TIMEOUT_SECONDS="${GROK_TIMEOUT:-180}"
GROK_API_URL="${GROK_API_URL:-https://api.x.ai/v1/chat/completions}"
GROK_FORMAT="${GROK_FORMAT:-openai}"
# API key: Set GROK_API_KEY environment variable

# =============================================================================
# DEEPSEEK CONFIGURATION - The Methodologist (API-based)
# =============================================================================

DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-coder}"
DEEPSEEK_TIMEOUT_SECONDS="${DEEPSEEK_TIMEOUT:-180}"
DEEPSEEK_API_URL="${DEEPSEEK_API_URL:-https://api.deepseek.com/v1/chat/completions}"
DEEPSEEK_FORMAT="${DEEPSEEK_FORMAT:-openai}"
# API key: Set DEEPSEEK_API_KEY environment variable

# =============================================================================
# OLLAMA CONFIGURATION - The Local Expert (v2.2)
# =============================================================================

# Default model for local inference
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2}"
# Alternative models: codellama, mistral, deepseek-coder, qwen2.5-coder

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

# API-based consultants (disabled by default - require API keys)
ENABLE_QWEN3="${ENABLE_QWEN3:-false}"
ENABLE_GLM="${ENABLE_GLM:-false}"
ENABLE_GROK="${ENABLE_GROK:-false}"
ENABLE_DEEPSEEK="${ENABLE_DEEPSEEK:-false}"

# Local model support via Ollama (disabled by default)
ENABLE_OLLAMA="${ENABLE_OLLAMA:-false}"

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
# CONFIGURATION PRESETS (v2.2)
# =============================================================================

# Presets allow quick configuration for different use cases:
#   minimal      - 2 models (fast, cheap): Gemini + Codex
#   balanced     - 4 models (good coverage): + Mistral + Kilo
#   thorough     - 5 models (comprehensive): + Cursor
#   high-stakes  - All models + debate (maximum rigor)
#
# Usage: ./consult_all.sh --preset balanced "Your question"

# Helper: Disable all consultants
_disable_all_consultants() {
    export ENABLE_GEMINI=false ENABLE_CODEX=false ENABLE_MISTRAL=false
    export ENABLE_KILO=false ENABLE_CURSOR=false ENABLE_AIDER=false
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
        *)
            echo "Unknown preset: $preset" >&2
            echo "Available presets: minimal, balanced, thorough, high-stakes, local, security, cost-capped" >&2
            return 1
            ;;
    esac

    return 0
}

# List available presets with descriptions
list_presets() {
    cat << 'EOF'
Available presets:

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

AI_CONSULTANTS_VERSION="2.2.0"
