# AI Consultants - Claude Code Instructions

## Project Overview

AI Consultants is a multi-model AI deliberation system that queries up to 14 AI consultants (Gemini, Codex, Mistral, Kilo, Cursor, Aider, Amp, Kimi, Claude, Qwen3, GLM, Grok, DeepSeek, Ollama) to obtain diverse perspectives on coding problems.

**Self-Exclusion**: The invoking agent is automatically excluded from the panel to prevent self-consultation. Claude Code won't query Claude, Codex CLI won't query Codex, etc.

**Version**: 2.9.1

## Structure

```
ai-consultants/
├── scripts/
│   ├── consult_all.sh          # Main orchestrator - entry point
│   ├── config.sh               # Centralized configuration
│   ├── doctor.sh               # Diagnostic and auto-fix tool (v2.2)
│   ├── peer_review.sh          # Anonymous peer review (v2.2)
│   ├── install.sh              # One-liner installer (v2.2)
│   ├── query_*.sh              # Wrapper for each consultant
│   ├── query_claude.sh         # Claude consultant (v2.2)
│   ├── query_ollama.sh         # Local model support (v2.2)
│   ├── synthesize.sh           # Auto-synthesis of responses
│   ├── debate_round.sh         # Multi-Agent Debate
│   ├── classify_question.sh    # Question classifier
│   ├── followup.sh             # Follow-up queries
│   ├── preflight_check.sh      # Health check
│   └── lib/
│       ├── common.sh           # Shared utilities (logging, panic mode)
│       ├── personas.sh         # Consultant persona definitions
│       ├── schema.json         # JSON output schema
│       ├── voting.sh           # Voting/consensus + confidence intervals
│       ├── routing.sh          # Smart routing + cost-aware routing
│       ├── session.sh          # Session management
│       ├── costs.sh            # Cost tracking + response limits
│       ├── cache.sh            # Semantic caching (v2.3)
│       ├── api_query.sh        # API mode query execution (v2.6)
│       ├── progress.sh         # Progress bars
│       └── reflection.sh       # Self-reflection + judge step
└── templates/
    └── synthesis_prompt.md     # Synthesis prompt
```

## Claude Skills Compliance

**IMPORTANT**: This project is a Claude Skill following the [agentskills.io](https://agentskills.io) open standard.

**Key Requirements:**
- SKILL.md `name`: max 64 chars, lowercase letters/numbers/hyphens only
- SKILL.md `description`: max 1024 chars, must include WHAT and WHEN to use
- Keep SKILL.md body under 500 lines
- Use progressive disclosure: reference separate files for detailed content
- Scripts are executed via bash, not loaded into context
- Test with all models (Haiku, Sonnet, Opus)

## Language Policy

**IMPORTANT**: The entire codebase MUST remain in English. This includes:
- All code comments
- All user-facing messages (log_info, log_error, echo, etc.)
- All documentation (README, CLAUDE.md, docs/, etc.)
- All prompt templates
- Variable names and function names

Do NOT introduce Italian or other languages in any part of the codebase.

## Code Conventions

### Bash Scripts
- Always use `set -euo pipefail` at the beginning
- Source `lib/common.sh` for logging (`log_info`, `log_error`, `log_success`, `log_warn`)
- Source `config.sh` for configuration
- JSON output must follow `lib/schema.json`
- Use environment variables for configuration override

### Logging
```bash
log_info "Informational message"
log_success "Operation completed"
log_warn "Warning"
log_error "Critical error"
log_debug "Debug message"  # Only shown when LOG_LEVEL=DEBUG
```

### Shared Response Processing
Query scripts should use `process_consultant_response()` from `lib/common.sh` for DRY response handling:
```bash
source "$SCRIPT_DIR/lib/common.sh"
process_consultant_response "$raw_output" "$consultant_name" "$model" "$persona" "$output_file"
```

### JSON Output
Each consultant must produce JSON with this minimum structure:
```json
{
  "consultant": "ConsultantName",
  "model": "model-used",
  "persona": "The Architect|Pragmatist|Devil's Advocate|Innovator",
  "response": {
    "summary": "TL;DR",
    "detailed": "Full response",
    "approach": "Approach name",
    "pros": ["advantage 1", "advantage 2"],
    "cons": ["disadvantage 1"],
    "caveats": ["important note"]
  },
  "confidence": {
    "score": 1-10,
    "reasoning": "Justification",
    "uncertainty_factors": ["what could affect this"]
  },
  "metadata": {
    "tokens_used": 1234,
    "latency_ms": 5600,
    "timestamp": "ISO-8601"
  }
}
```

## Main Flow

1. `consult_all.sh` receives query, optional files, and flags (`--preset`, `--strategy`)
2. Applies preset if specified (`apply_preset()` in config.sh)
3. Classifies the question (`classify_question.sh`)
4. Selects consultants (smart routing or all)
5. Launches parallel queries (`query_*.sh`)
6. Calculates voting/consensus with confidence intervals (`lib/voting.sh`)
7. Checks for panic mode triggers (`lib/common.sh`)
8. Generates synthesis with selected strategy (`synthesize.sh`)
9. Optionally runs peer review (`peer_review.sh`)
10. Produces final report

## v2.2 Features

### Self-Exclusion
The invoking agent is automatically excluded from the panel:

```bash
# From Claude Code slash commands (automatic)
# Claude is excluded, all others participate

# Manual bash usage
INVOKING_AGENT=claude ./scripts/consult_all.sh "question"   # Claude excluded
INVOKING_AGENT=codex ./scripts/consult_all.sh "question"    # Codex excluded
./scripts/consult_all.sh "question"                          # No exclusion
```

Functions in `lib/common.sh`:
- `get_self_consultant_name()` - Maps invoking agent to consultant name
- `should_skip_consultant()` - Returns true if consultant should be excluded
- `log_self_exclusion_status()` - Debug logging for exclusion

### Configuration Presets
```bash
# Quality Tier Presets (v2.5)
./scripts/consult_all.sh --preset max_quality "question"  # All + premium models + debate
./scripts/consult_all.sh --preset medium "question"       # 4 consultants + standard models
./scripts/consult_all.sh --preset fast "question"         # 2 consultants + economy models

# Use Case Presets
./scripts/consult_all.sh --preset minimal "question"    # Gemini + Codex
./scripts/consult_all.sh --preset balanced "question"   # + Mistral + Kilo
./scripts/consult_all.sh --preset high-stakes "question" # All + debate
./scripts/consult_all.sh --preset local "question"      # Ollama only
```

Presets are defined in `config.sh` via `apply_preset()` function.

### Synthesis Strategies
```bash
./scripts/consult_all.sh --strategy majority "question"      # Default
./scripts/consult_all.sh --strategy risk_averse "question"   # Conservative
./scripts/consult_all.sh --strategy security_first "question" # Security focus
./scripts/consult_all.sh --strategy compare_only "question"  # No recommendation
```

Strategies are implemented in `synthesize.sh` via `get_strategy_instructions()`.

### Doctor Command
```bash
./scripts/doctor.sh              # Full diagnostic
./scripts/doctor.sh --fix        # Auto-fix issues
./scripts/doctor.sh --json       # JSON output
./scripts/doctor.sh --verbose    # Detailed output
```

### Ollama Local Models
```bash
ENABLE_OLLAMA=true ./scripts/consult_all.sh "question"
OLLAMA_MODEL=codellama ./scripts/consult_all.sh "question"
```

Configuration in `config.sh`:
- `OLLAMA_MODEL` - Model to use (default: qwen2.5-coder:32b)
- `OLLAMA_HOST` - Server URL (default: http://localhost:11434)
- `OLLAMA_TIMEOUT` - Timeout in seconds (default: 300)

### Panic Button Mode
Automatically adds rigor when uncertainty detected:
- Average confidence below `PANIC_CONFIDENCE_THRESHOLD` (default: 5)
- Uncertainty keywords detected in responses

Configuration in `config.sh`:
- `ENABLE_PANIC_MODE` - "auto", "always", or "never"
- `PANIC_CONFIDENCE_THRESHOLD` - Trigger threshold
- `PANIC_EXTRA_DEBATE_ROUNDS` - Additional debate rounds

### Confidence Intervals
Functions in `lib/voting.sh`:
- `calculate_confidence_stddev()` - Returns stddev scaled by 10
- `calculate_confidence_interval()` - Returns JSON with mean, stddev, interval
- `has_high_confidence_variance()` - Returns 0 if variance > 2.0
- `format_confidence_range()` - Returns "7 ± 1.5" format

### Anonymous Peer Review
```bash
./scripts/peer_review.sh <responses_dir> <output_dir>
```

Process:
1. Anonymize all responses (remove consultant names)
2. Each consultant ranks and critiques responses
3. Aggregate peer scores to identify strongest arguments
4. De-anonymize in final report

### Judge Step (Overconfidence Detection)
Functions in `lib/reflection.sh`:
- `judge_response()` - Evaluates single response for overconfidence
- `heuristic_overconfidence_check()` - Fast fallback without LLM
- `judge_all_responses()` - Batch evaluation

## v2.8 Features

### Amp CLI Support
Amp Code is now supported as a CLI-based consultant with "The Systems Thinker" persona.

```bash
# Enable Amp consultant
export ENABLE_AMP=true
./scripts/consult_all.sh "question"
```

**CLI Installation:**
```bash
curl -fsSL https://ampcode.com/install.sh | bash
```

**Environment Variables:**
- `ENABLE_AMP` - Enable Amp consultant (default: false)
- `AMP_CMD` - CLI command (default: amp)
- `AMP_TIMEOUT` - Timeout in seconds (default: 180)
- `AMP_API_KEY` - API key for authentication

**Persona:** The Systems Thinker - Focuses on holistic system design, component interactions, and emergent behaviors.

## v2.9 Features

### Kimi CLI Support
Kimi (MoonshotAI) is now supported as a CLI-based consultant with "The Eastern Sage" persona.

```bash
# Enable Kimi consultant
export ENABLE_KIMI=true
./scripts/consult_all.sh "question"
```

**CLI Installation:**
```bash
pip install kimi-cli
kimi login  # OAuth-based authentication
```

**Environment Variables:**
- `ENABLE_KIMI` - Enable Kimi consultant (default: false)
- `KIMI_CMD` - CLI command (default: kimi)
- `KIMI_TIMEOUT` - Timeout in seconds (default: 180)
- `KIMI_MODEL` - Model identifier (default: kimi-code/kimi-for-coding)

**Persona:** The Eastern Sage - Focuses on holistic understanding, balance of perspectives, and wisdom from diverse viewpoints.

## v2.7 Features

### Qwen CLI Support (qwen-code)
Qwen3 now supports CLI/API mode switching using the qwen-code CLI.

```bash
# CLI mode (new in v2.7)
export QWEN3_USE_API=false
./scripts/consult_all.sh "question"

# API mode (default, preserves v2.6 behavior)
export QWEN3_USE_API=true
export QWEN3_API_KEY="your-dashscope-key"
./scripts/consult_all.sh "question"
```

**CLI Installation:**
```bash
npm install -g @qwen-code/qwen-code@latest
```

**Note:** `QWEN3_USE_API` defaults to `true` to preserve backward compatibility with v2.6 API behavior.

## v2.6 Features

### CLI/API Mode Switching
Five consultants can now switch between CLI and API mode: **Gemini, Codex, Claude, Mistral, Qwen3**.

When API mode is enabled for an agent, CLI mode is disabled (mutual exclusivity).

```bash
# Enable API mode for individual consultants
export GEMINI_USE_API=true
export GEMINI_API_KEY="your-google-ai-key"
./scripts/consult_all.sh "question"

export CODEX_USE_API=true
export OPENAI_API_KEY="sk-..."
./scripts/consult_all.sh "question"

export CLAUDE_USE_API=true
export ANTHROPIC_API_KEY="sk-ant-..."
./scripts/consult_all.sh "question"

export MISTRAL_USE_API=true
export MISTRAL_API_KEY="your-mistral-key"
./scripts/consult_all.sh "question"

export QWEN3_USE_API=true  # Default for backward compat
export QWEN3_API_KEY="your-dashscope-key"
./scripts/consult_all.sh "question"
```

### API Mode Configuration
New environment variables in `config.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_USE_API` | false | Use Google AI API instead of gemini CLI |
| `CODEX_USE_API` | false | Use OpenAI API instead of codex CLI |
| `CLAUDE_USE_API` | false | Use Anthropic API instead of claude CLI |
| `MISTRAL_USE_API` | false | Use Mistral API instead of vibe CLI |
| `QWEN3_USE_API` | true | Use DashScope API instead of qwen CLI (v2.7) |
| `GEMINI_API_URL` | https://generativelanguage.googleapis.com/v1beta/models | Google AI endpoint |
| `CODEX_API_URL` | https://api.openai.com/v1/chat/completions | OpenAI endpoint |
| `CLAUDE_API_URL` | https://api.anthropic.com/v1/messages | Anthropic endpoint |
| `MISTRAL_API_URL` | https://api.mistral.ai/v1/chat/completions | Mistral endpoint |

### API Keys for API Mode

| Agent | API Key Variable | Notes |
|-------|------------------|-------|
| Gemini | `GEMINI_API_KEY` | Google AI API key |
| Codex | `OPENAI_API_KEY` | Same as existing OpenAI key |
| Claude | `ANTHROPIC_API_KEY` | Anthropic API key |
| Mistral | `MISTRAL_API_KEY` | Same as existing Mistral key |
| Qwen3 | `QWEN3_API_KEY` | DashScope API key |

### Mode Checking Functions
New functions in `lib/common.sh`:
- `is_api_mode()` - Check if agent is in API mode
- `validate_api_mode()` - Validate API key is set
- `get_api_key_var()` - Get API key variable name
- `get_api_url()` - Get API endpoint URL
- `get_api_format()` - Get response format (openai, anthropic, google_ai)

### Doctor Diagnostics
The `doctor.sh` script now shows CLI/API mode status:
```bash
./scripts/doctor.sh --verbose
# Shows:
#   ✓ Gemini: API mode (key: AIza...1234)
#   ○ Codex: CLI mode
#   ○ Claude: CLI mode
#   ○ Mistral: CLI mode
#   ✓ Qwen3: API mode (key: sk-...1234)
```

## v2.5 Features

### Model Quality Tiers
Three tiers of models are available for each consultant, configurable via `apply_model_tier()`:

| Tier | Description | Example Models |
|------|-------------|----------------|
| **premium** | Latest flagship models | claude-opus-4-5, gemini-3-pro-preview, gpt-5.2-codex |
| **standard** | Good quality at reasonable cost | claude-sonnet-4-5, gemini-3-flash-preview, gpt-5.2 |
| **economy** | Optimized for speed and low cost | claude-3-5-haiku, gemini-2.0-flash, gpt-4o-mini |

**Default models are now premium tier** for maximum quality.

```bash
# Programmatic usage
source scripts/config.sh
apply_model_tier "premium"   # Set all consultants to premium models
apply_model_tier "standard"  # Set all consultants to standard models
apply_model_tier "economy"   # Set all consultants to economy models

# Get model for a specific consultant and tier (v2.8.1)
get_model_for_tier "gemini" "premium"   # → gemini-3-pro-preview
get_model_for_tier "claude" "economy"   # → haiku
```

### Quality Tier Presets
Three new presets leverage the model tiers:

```bash
# Maximum quality - all premium models + debate + reflection
./scripts/consult_all.sh --preset max_quality "critical architecture decision"

# Balanced quality - standard models, 4 consultants, light debate
./scripts/consult_all.sh --preset medium "general coding question"

# Super fast - economy models, 2 consultants, no debate
./scripts/consult_all.sh --preset fast "quick syntax question"
```

### Premium Model Defaults (January 2026)
All consultants now use premium models by default:

| Consultant | Default Model |
|------------|---------------|
| Claude | claude-opus-4-5-20251124 |
| Gemini | gemini-3-pro-preview |
| Codex | gpt-5.2-codex |
| Mistral | mistral-large-3 |
| DeepSeek | deepseek-v3.2-speciale |
| GLM | glm-4.7 |
| Grok | grok-4-1-fast-reasoning |
| Qwen3 | qwen3-max |
| Kimi | kimi-code/kimi-for-coding |
| Aider | gpt-5.2-codex |
| Ollama | qwen2.5-coder:32b |

Override with environment variables: `CLAUDE_MODEL`, `GEMINI_MODEL`, `CODEX_MODEL`, `KIMI_MODEL`, etc.

## v2.4 Features

### Budget Enforcement (Opt-in)
Optional budget limits to prevent consultations from exceeding configurable cost limits.

```bash
# Enable budget enforcement
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=1.00
BUDGET_ACTION=warn  # or "stop"
```

**BUDGET_ACTION options:**
- `warn` - Log warning but continue consultation
- `stop` - Halt consultation and return partial results

**Enforcement Points:**
1. Before Round 1 - Check estimated cost vs budget
2. After Round 1 - Check actual cost vs warning threshold
3. Before Debate - Check cumulative + debate estimate
4. Before Synthesis - Check cumulative + synthesis estimate

Functions in `lib/costs.sh`:
- `is_budget_enabled()` - Check if budget enforcement is enabled
- `enforce_budget()` - Check budget and take action based on BUDGET_ACTION
- `get_remaining_budget()` - Get remaining budget
- `format_budget_status()` - Format budget status for display
- `estimate_phase_cost()` - Estimate cost for a specific phase

Configuration via `/ai-consultants:config-budget` slash command.

## v2.3 Features

### Semantic Caching
Reduces redundant API calls by caching responses based on query + context fingerprints.

```bash
# Configuration in config.sh
ENABLE_SEMANTIC_CACHE=true      # Enable caching (default: true)
CACHE_TTL_HOURS=24              # Cache expiration
CACHE_DIR=/tmp/ai_consultants_cache
```

Functions in `lib/cache.sh`:
- `generate_fingerprint()` - Creates hash from query + category + context
- `check_cache()` - Returns cached response if valid
- `store_cache()` - Stores response with metadata
- `cleanup_cache()` - Removes expired entries
- `get_cache_stats()` - Returns cache statistics as JSON

### Response Length Limits (Opt-in)
Limits output tokens by question category to reduce costs.

```bash
ENABLE_RESPONSE_LIMITS=false    # Default: false (opt-in per quality review)
MAX_RESPONSE_TOKENS_BY_CATEGORY="QUICK_SYNTAX:200,CODE_REVIEW:800,ARCHITECTURE:1000,SECURITY:1000,GENERAL:500"
```

Functions in `lib/costs.sh`:
- `get_max_response_tokens()` - Returns limit for category
- `is_response_limits_enabled()` - Check if enabled

### Cost-Aware Routing
Routes simple queries to cheaper models, complex queries to premium models.

```bash
ENABLE_COST_AWARE_ROUTING=false # Enable cost-based routing
USE_ECONOMIC_MODELS_FOR_SIMPLE=true
COMPLEXITY_THRESHOLD_SIMPLE=3   # Score 1-3 = simple
COMPLEXITY_THRESHOLD_MEDIUM=6   # Score 4-6 = medium, 7-10 = complex
```

Functions in `lib/routing.sh`:
- `select_consultants_cost_aware()` - Selects consultants based on complexity
- `get_cost_aware_model()` - Returns economic model for simple queries
- `calculate_query_complexity()` - Scores query 1-10

Functions in `lib/costs.sh`:
- `get_economic_model()` - Maps consultant to cheaper model
- `get_model_tier()` - Returns economy/standard/premium

### Fallback Escalation
Automatically re-queries with premium models if confidence is too low.

```bash
FALLBACK_CONFIDENCE_THRESHOLD=7  # Escalate if confidence < 7
```

Functions in `lib/routing.sh`:
- `needs_escalation()` - Returns true if response needs premium model
- `get_premium_model()` - Returns premium model for consultant
- `get_escalation_summary()` - Returns escalation info as JSON

### Debate Optimization (Opt-in)
Skips debate if confidence spread is low (all consultants agree).

```bash
ENABLE_DEBATE_OPTIMIZATION=false  # Default: false (opt-in per quality review)
DEBATE_CONFIDENCE_SPREAD_THRESHOLD=2  # Min spread to trigger debate
DEBATE_USE_SUMMARIES=true         # Use summaries in debate rounds
```

**Category Exceptions**: SECURITY and ARCHITECTURE always trigger debate regardless of confidence spread.

Functions in `lib/debate_round.sh`:
- `is_mandatory_debate_category()` - Returns true for SECURITY/ARCHITECTURE
- `should_skip_debate()` - Returns true if debate can be skipped
- `extract_compact_summary()` - Token-optimized summary for debates

### Quality Monitoring
Logs optimization metrics and saves to output directory.

```bash
# In LOG_LEVEL=DEBUG mode, shows optimization status
# Always saves optimization_metrics.json to output directory
```

Output file `optimization_metrics.json`:
```json
{
  "optimization_settings": {
    "cache_enabled": true,
    "cache_hits": 2,
    "response_limits_enabled": false,
    "cost_aware_routing": false,
    "debate_optimization": false,
    "compact_report": true
  },
  "quality_metrics": {
    "consensus_score": 75,
    "consensus_level": "medium",
    "successful_responses": 4,
    "total_consultants": 4,
    "category": "ARCHITECTURE"
  },
  "timestamp": "2026-01-17T10:30:00Z"
}
```

### Compact Reports
Generates shorter reports by default (summaries only, no full JSON).

```bash
ENABLE_COMPACT_REPORT=true       # Default: true
REPORT_MAX_JSON_LINES=50         # Max JSON lines in full report
```

## Testing

```bash
# Full diagnostic
./scripts/doctor.sh

# Basic test
./scripts/consult_all.sh "How to optimize a SQL query?"

# Test with preset
./scripts/consult_all.sh --preset minimal "Quick question"

# Test with debate
ENABLE_DEBATE=true ./scripts/consult_all.sh "Microservices or monolith?"

# Test with strategy
./scripts/consult_all.sh --strategy risk_averse "Security question"

# Syntax validation (all scripts)
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f" && echo "OK: $f"; done
```

## Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INVOKING_AGENT` | unknown | Agent invoking the skill (for self-exclusion) |
| `ENABLE_CLAUDE` | false | Enable Claude consultant |
| `ENABLE_DEBATE` | false | Enable Multi-Agent Debate |
| `DEBATE_ROUNDS` | 1 | Number of debate rounds |
| `ENABLE_SYNTHESIS` | true | Auto-synthesis of responses |
| `ENABLE_SMART_ROUTING` | false | Intelligent routing |
| `ENABLE_COST_TRACKING` | true | Track costs |
| `MAX_SESSION_COST` | 1.00 | Max budget ($) |
| `ENABLE_PANIC_MODE` | auto | Panic mode trigger (v2.2) |
| `PANIC_CONFIDENCE_THRESHOLD` | 5 | Panic threshold (v2.2) |
| `ENABLE_OLLAMA` | false | Local model support (v2.2) |
| `OLLAMA_MODEL` | qwen2.5-coder:32b | Ollama model (v2.5 - premium default) |
| `CLAUDE_MODEL` | claude-opus-4-5-20251124 | Claude model (v2.5) |
| `GEMINI_MODEL` | gemini-3-pro-preview | Gemini model (v2.5) |
| `CODEX_MODEL` | gpt-5.2-codex | Codex model (v2.5) |
| `MISTRAL_MODEL` | mistral-large-3 | Mistral model (v2.5) |
| `SYNTHESIS_STRATEGY` | majority | Synthesis strategy (v2.2) |
| `ENABLE_SEMANTIC_CACHE` | true | Semantic response caching (v2.3) |
| `CACHE_TTL_HOURS` | 24 | Cache expiration in hours (v2.3) |
| `ENABLE_RESPONSE_LIMITS` | false | Response token limits (v2.3, opt-in) |
| `ENABLE_COST_AWARE_ROUTING` | false | Cost-based model routing (v2.3) |
| `ENABLE_DEBATE_OPTIMIZATION` | false | Skip debate if all agree (v2.3, opt-in) |
| `ENABLE_COMPACT_REPORT` | true | Compact report format (v2.3) |
| `ENABLE_BUDGET_LIMIT` | false | Budget enforcement (v2.4, opt-in) |
| `BUDGET_ACTION` | warn | Action on budget exceeded: warn/stop (v2.4) |
| `QWEN3_USE_API` | true | Use DashScope API instead of qwen CLI (v2.7) |
| `QWEN3_CMD` | qwen | Qwen CLI command (v2.7) |
| `ENABLE_KIMI` | false | Enable Kimi consultant (v2.9) |
| `KIMI_CMD` | kimi | Kimi CLI command (v2.9) |
| `KIMI_MODEL` | kimi-code/kimi-for-coding | Kimi model (v2.9) |

## External Dependencies

- `gemini` CLI - Google Gemini
- `codex` CLI - OpenAI Codex
- `vibe` CLI - Mistral Vibe
- `kilocode` CLI - Kilo Code
- `agent` CLI - Cursor
- `aider` CLI - Aider
- `amp` CLI - Amp Code (v2.8)
- `kimi` CLI - Kimi Code (v2.9)
- `claude` CLI - Claude (v2.2, also used for synthesis)
- `qwen` CLI - Qwen via qwen-code (v2.7, optional)
- `ollama` CLI - Local models (v2.2)
- `jq` - JSON parsing

## Error Handling and Retry

The system handles errors with:

- **Automatic retry**: `MAX_RETRIES` attempts (default: 2)
- **Delay between retries**: `RETRY_DELAY_SECONDS` (default: 5s)
- **Cross-platform timeout**: Supports Linux (`timeout`), macOS (`gtimeout`), and POSIX fallback
- **Exit codes**: 0 = success, 1 = error, 124 = timeout

```bash
# Retry configuration
MAX_RETRIES=3
RETRY_DELAY_SECONDS=10

# Per-consultant timeout
GEMINI_TIMEOUT=240
CODEX_TIMEOUT=180
OLLAMA_TIMEOUT=300  # Longer for local inference
```

## Extended Documentation

For detailed information, see:
- [docs/SETUP.md](docs/SETUP.md) - Installation, authentication, Ollama setup
- [docs/COST_RATES.md](docs/COST_RATES.md) - Rates and budget management
- [docs/SMART_ROUTING.md](docs/SMART_ROUTING.md) - Affinity matrix and routing
- [docs/JSON_SCHEMA.md](docs/JSON_SCHEMA.md) - Complete output schema

## Development Notes

- Scripts in `lib/` are libraries, not standalone executables
- Output goes to `/tmp/ai_consultations/TIMESTAMP/`
- Session state in `/tmp/ai_consultants_sessions/`
- All timeouts are configurable in `config.sh`
- Consultants can be disabled individually (`ENABLE_GEMINI=false`, etc.)
- Use `.env.example` as template for environment configuration
- Run `./scripts/doctor.sh` to verify configuration

## Changelog

### v2.9.1
- Fixed Gemini model names to use real API names
- Premium: `gemini-3-pro-preview`, Standard: `gemini-3-flash-preview`, Economy: `gemini-2.0-flash`

### v2.9.0
- Kimi CLI support via kimi-cli (`pip install kimi-cli`, `kimi login`)
- New consultant: Kimi with "The Eastern Sage" persona (ID: 20)
- New environment variables: `ENABLE_KIMI`, `KIMI_CMD`, `KIMI_TIMEOUT`, `KIMI_MODEL`
- Updated doctor.sh diagnostics for Kimi CLI
- Now supports 14 consultants total

### v2.8.1
- CRITICAL: Fixed `((count++))` abort under `set -e` in consult_all.sh and routing.sh
- Fixed missing integer validation for jq confidence values in escalation
- Fixed Amp missing from `_consultant_map` in consult_all.sh
- Fixed hardcoded `"claude"` in synthesize.sh (now uses `$CLAUDE_CMD`)
- Security: Variable name validation before `export` in escalation and cost-aware routing
- DRY: Rewrote `query_kilo.sh` and `query_cursor.sh` using `process_consultant_response()`
- DRY: Added `get_model_for_tier()` as single source of truth for model tier mappings
- Removed hardcoded version numbers from script headers

### v2.8.0
- Amp CLI support via ampcode (`curl -fsSL https://ampcode.com/install.sh | bash`)
- New consultant: Amp with "The Systems Thinker" persona (ID: 19)
- New environment variables: `ENABLE_AMP`, `AMP_CMD`, `AMP_TIMEOUT`
- Updated doctor.sh diagnostics for Amp CLI

### v2.7.0
- Qwen CLI support via qwen-code (`npm install -g @qwen-code/qwen-code@latest`)
- CLI/API mode switching for Qwen3 (now 5 agents support switching)
- New environment variables: `QWEN3_USE_API`, `QWEN3_CMD`
- `QWEN3_USE_API` defaults to `true` to preserve v2.6 API behavior
- Updated `validate_api_mode()` to support Qwen3
- Moved Qwen3 from API-only to CLI/API switchable consultant
- Updated doctor.sh diagnostics for Qwen3 CLI/API mode

### v2.6.0
- CLI/API mode switching for Gemini, Codex, Claude, and Mistral
- New environment variables: `*_USE_API`, `*_API_URL`
- API request builders for Anthropic and Google AI formats
- Response parsers for all API formats (OpenAI, Anthropic, Google AI)
- New `lib/api_query.sh` module for unified API query execution
- Mode checking functions in `lib/common.sh`
- Doctor diagnostics for CLI/API mode status
- Updated query scripts with CLI/API branching

### v2.5.0
- Model quality tiers: premium, standard, economy
- New `apply_model_tier()` function for programmatic tier selection
- Quality tier presets: `max_quality`, `medium`, `fast`
- Premium model defaults for all consultants (January 2026 models)
- Updated docs/cost_rates.json with tier-based model rates

### v2.4.0
- Budget enforcement (opt-in) with configurable limits
- ENABLE_BUDGET_LIMIT and BUDGET_ACTION configuration
- Budget checks at 4 enforcement points (before/after consultation, debate, synthesis)
- `/ai-consultants:config-budget` slash command
- Updated doctor.sh to display budget status

### v2.3.0
- Semantic caching with fingerprint-based cache keys
- Response length limits (opt-in, per category)
- Cost-aware routing (economic models for simple queries)
- Fallback escalation (premium model if confidence < 7)
- Debate optimization (opt-in, skip if all agree)
- Mandatory debate for SECURITY/ARCHITECTURE categories
- Quality monitoring with `optimization_metrics.json`
- Compact reports (summaries only by default)
- Code simplification (extracted helper functions)

### v2.2.0
- Claude consultant with "The Synthesizer" persona
- Self-exclusion logic (invoking agent excluded from panel)
- Configuration presets (`--preset minimal/balanced/high-stakes/local`)
- Doctor command with auto-fix
- Synthesis strategies (`--strategy majority/risk_averse/security_first`)
- Confidence intervals with statistical ranges
- Anonymous peer review
- Ollama local model support
- Panic button mode for uncertainty detection
- Judge step for overconfidence detection
- One-liner installation

### v2.1.0
- New consultants: Aider, DeepSeek
- 17 configurable personas
- Token optimization with AST extraction

### v2.0.0
- Personas for each consultant (The Architect, The Pragmatist, etc.)
- Confidence scoring 1-10 on every response
- Auto-synthesis with weighted recommendation
- Multi-Agent Debate with cross-critique
- Smart routing based on category
- Session management for follow-up
- Cost tracking and budget limits
- Interactive progress bars
