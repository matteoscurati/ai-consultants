# AI Consultants - Full Configuration Reference

All configuration is done via environment variables. Set them in your shell, `.env` file, or inline before the command.

## Defaults

```bash
DEFAULT_PRESET=balanced      # Preset when --preset not given
DEFAULT_STRATEGY=majority    # Strategy when --strategy not given
```

## Core Features

```bash
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_PEER_REVIEW=false     # Anonymous peer review
ENABLE_PANIC_MODE=auto       # Auto-rigor for uncertainty
ENABLE_SMART_ROUTING=false   # Category-based consultant selection
ENABLE_COST_TRACKING=true    # Track API usage costs
```

## CLI/API Mode Switching (v2.6+)

Five consultants support switching between CLI and API mode. When API mode is enabled, the CLI is not used.

```bash
GEMINI_USE_API=false         # Use Google AI API instead of gemini CLI
CODEX_USE_API=false          # Use OpenAI API instead of codex CLI
CLAUDE_USE_API=false         # Use Anthropic API instead of claude CLI
MISTRAL_USE_API=false        # Use Mistral API instead of vibe CLI
QWEN3_USE_API=false          # Use qwen CLI (default) or DashScope API
```

### API Keys

| Agent | API Key Variable | Notes |
|-------|------------------|-------|
| Gemini | `GEMINI_API_KEY` | Google AI API key |
| Codex | `OPENAI_API_KEY` | OpenAI API key |
| Claude | `ANTHROPIC_API_KEY` | Anthropic API key |
| Mistral | `MISTRAL_API_KEY` | Mistral API key |
| Qwen3 | `QWEN3_API_KEY` | DashScope API key |

## Consultant Toggles and Models

```bash
# Consultants enabled by default
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KILO=true
ENABLE_CURSOR=true
ENABLE_AIDER=true

# Opt-in consultants
ENABLE_AMP=false             # Amp CLI - The Systems Thinker
ENABLE_KIMI=false            # Kimi CLI - The Eastern Sage
ENABLE_QWEN3=false           # Qwen CLI/API - The Analyst
ENABLE_CLAUDE=false          # Claude CLI - The Synthesizer
ENABLE_OLLAMA=false          # Ollama - The Local Expert
ENABLE_MINIMAX=false         # MiniMax API - The Pragmatic Optimizer

# API-only consultants
ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
```

### Model Overrides

```bash
GEMINI_MODEL=gemini-3.1-pro-preview
CODEX_MODEL=gpt-5.3-codex
CLAUDE_MODEL=opus-4.6
MISTRAL_MODEL=mistral-large-3
KILO_MODEL=auto
CURSOR_MODEL=composer-1.5
AIDER_MODEL=gpt-5.3-codex
AMP_MODEL=amp
KIMI_MODEL=kimi-code/kimi-for-coding
QWEN3_MODEL=qwen3.6-plus
GLM_MODEL=glm-5.1
GROK_MODEL=grok-4.20-0309-reasoning
DEEPSEEK_MODEL=deepseek-reasoner
MINIMAX_MODEL=MiniMax-M2.7
OLLAMA_MODEL=qwen2.5-coder:32b
```

## Model Quality Tiers (v2.5)

```bash
# Set all consultants to a tier programmatically
source scripts/config.sh
apply_model_tier "premium"   # Latest flagship models
apply_model_tier "standard"  # Good quality at reasonable cost
apply_model_tier "economy"   # Optimized for speed and low cost
```

## Ollama (Local Models)

```bash
ENABLE_OLLAMA=true
OLLAMA_MODEL=qwen2.5-coder:32b
OLLAMA_HOST=http://localhost:11434
OLLAMA_TIMEOUT=300
```

## Budget Management (v2.4)

```bash
ENABLE_BUDGET_LIMIT=false
MAX_SESSION_COST=1.00        # Maximum cost in USD
BUDGET_ACTION=warn           # warn or stop
```

## Caching and Optimization (v2.3)

```bash
ENABLE_SEMANTIC_CACHE=true   # Cache responses by query fingerprint
CACHE_TTL_HOURS=24           # Cache expiration
ENABLE_RESPONSE_LIMITS=false # Limit output tokens by category
ENABLE_COST_AWARE_ROUTING=false  # Route simple queries to cheaper models
ENABLE_DEBATE_OPTIMIZATION=false # Skip debate if all agree
ENABLE_COMPACT_REPORT=true   # Summaries only in reports
```

## Timeouts and Retries

```bash
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
GEMINI_TIMEOUT=240
CODEX_TIMEOUT=180
MISTRAL_TIMEOUT=180
KILO_TIMEOUT=180
CURSOR_TIMEOUT=180
AMP_TIMEOUT=180
KIMI_TIMEOUT=180
OLLAMA_TIMEOUT=300           # Longer for local inference
```
