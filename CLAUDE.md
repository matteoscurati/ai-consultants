# AI Consultants - Claude Code Instructions

## Project Overview

AI Consultants is a multi-model AI deliberation system that queries up to 15 AI consultants (Gemini, Codex, Mistral, Kilo, Cursor, Aider, Amp, Kimi, Claude, Qwen3, GLM, Grok, DeepSeek, MiniMax, Ollama) to obtain diverse perspectives on coding problems.

**Self-Exclusion**: The invoking agent is automatically excluded from the panel to prevent self-consultation. Claude Code won't query Claude, Codex CLI won't query Codex, etc.

**Version**: 2.20.0

## Distribution

Two distribution methods are supported:

1. **npx** (recommended): `npx ai-consultants "question"` - uses npm as distribution mechanism only (zero dependencies)
2. **curl | bash**: `curl -fsSL .../install.sh | bash` - git clone into `~/.claude/skills/`

### npm Architecture

`bin/ai-consultants` is a bash wrapper that npm registers as the CLI entry point. npm creates a symlink in `node_modules/.bin/` pointing to this file. The wrapper:

1. Resolves its own path through symlinks (portable `readlink` loop for macOS/Linux)
2. Computes `PROJECT_ROOT` and `SCRIPTS_DIR` from the resolved path
3. Fixes `chmod +x` on first run (npm can strip execute permissions)
4. Routes subcommands (`doctor`, `install`, `version`, `help`) or delegates to `consult_all.sh` via `exec`

**Key insight**: Because the wrapper resolves symlinks before calling scripts, `BASH_SOURCE[0]` in every script points to the real file. This means **zero modifications** to the 28 existing scripts.

## Structure

```
ai-consultants/
├── bin/
│   └── ai-consultants          # npm/npx entry point (bash wrapper)
├── package.json                # npm distribution metadata (zero dependencies)
├── .npmignore                  # Excludes dev artifacts from npm package
├── scripts/
│   ├── consult_all.sh          # Main orchestrator - entry point
│   ├── config.sh               # Centralized configuration
│   ├── doctor.sh               # Diagnostic and auto-fix tool (v2.2)
│   ├── update_clis.sh          # Check/update installed consultant CLIs (v2.21)
│   ├── peer_review.sh          # Anonymous peer review (v2.2)
│   ├── roster_audit.sh         # Roster uncorrelated-value audit (v2.20)
│   ├── roster_calibrate.sh     # Measured capability calibration, Tier A (v2.20)
│   ├── run_calibration.sh      # Calibration data-collection harness (v2.20)
│   ├── taste_elo.sh            # Pairwise-judge taste Elo, Tier B (v2.20)
│   ├── install.sh              # One-liner installer (v2.2)
│   ├── query_*.sh              # Wrapper for each consultant
│   ├── query_claude.sh         # Claude consultant (v2.2)
│   ├── query_ollama.sh         # Local model support (v2.2)
│   ├── synthesize.sh           # Auto-synthesis of responses
│   ├── debate_round.sh         # Multi-Agent Debate
│   ├── classify_question.sh    # Question classifier
│   ├── followup.sh             # Follow-up queries
│   ├── preflight_check.sh      # DEPRECATED v2.10.9 (thin wrapper -> doctor.sh)
│   └── lib/
│       ├── common.sh           # Shared utilities (logging, panic mode)
│       ├── personas.sh         # Consultant persona definitions
│       ├── schema.json         # JSON output schema
│       ├── voting.sh           # Voting/consensus + confidence intervals
│       ├── routing.sh          # Smart routing + cost-aware routing
│       ├── orchestration.sh    # Dynamic orchestration planner + shapes (v2.16)
│       ├── stance.sh           # Stance-based semantic consensus (v2.21, opt-in)
│       ├── session.sh          # Session management
│       ├── costs.sh            # Cost tracking + response limits
│       ├── cache.sh            # Semantic caching (v2.3)
│       ├── api_query.sh        # API mode query execution (v2.6)
│       ├── progress.sh         # Progress bars
│       └── reflection.sh       # Self-reflection + judge step
├── references/
│   ├── configuration.md      # Full configuration reference
│   └── details.md            # Presets, strategies, best practices
├── docs/
│   ├── releases/             # Release notes (one per version)
│   ├── SETUP.md              # Installation guide
│   ├── COST_RATES.md         # Model pricing
│   ├── SMART_ROUTING.md      # Affinity matrix
│   └── JSON_SCHEMA.md        # Output schema
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
4. Plans orchestration: complexity + intent → shape (`select_orchestration_shape()` in `lib/orchestration.sh`); `ORCHESTRATION_MODE=fixed` bypasses to the legacy path
5. Selects consultants (smart routing or all)
6. Launches parallel queries (`query_*.sh`)
7. Deliberates per the chosen shape: convergence loop / adversarial gate / tournament / exhaustive sweep (`run_orchestration()`), or fixed debate rounds in `fixed` mode
8. Calculates voting/consensus with confidence intervals (`lib/voting.sh`)
9. Checks for panic mode triggers (`lib/common.sh`)
10. Generates synthesis with selected strategy (`synthesize.sh`)
11. Optionally runs peer review (`peer_review.sh`)
12. Produces final report

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
- `OLLAMA_MODEL` - Model to use (default: hf.co/prithivMLmods/VibeThinker-3B-GGUF)
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
- `ENABLE_AMP` - Enable Amp consultant (default: true)
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
curl -L code.kimi.com/install.sh | bash
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

# API mode (opt-in)
export QWEN3_USE_API=true
export QWEN3_API_KEY="your-dashscope-key"
./scripts/consult_all.sh "question"
```

**CLI Installation:**
```bash
npm install -g @qwen-code/qwen-code@latest
```

**Note:** `QWEN3_USE_API` defaults to `false` to use the qwen CLI by default.

## v2.6 Features

### CLI/API Mode Switching
Six consultants can now switch between CLI and API mode: **Gemini, Codex, Claude, Mistral, Qwen3, MiniMax**.

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

export QWEN3_USE_API=true  # Enable API mode (CLI is default)
export QWEN3_API_KEY="your-dashscope-key"
./scripts/consult_all.sh "question"
```

### API Mode Configuration
New environment variables in `config.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `GEMINI_USE_API` | false | Use Google AI API instead of the agy CLI |
| `CODEX_USE_API` | false | Use OpenAI API instead of codex CLI |
| `CLAUDE_USE_API` | false | Use Anthropic API instead of claude CLI |
| `MISTRAL_USE_API` | false | Use Mistral API instead of vibe CLI |
| `QWEN3_USE_API` | false | Use DashScope API instead of qwen CLI (v2.7) |
| `MINIMAX_USE_API` | false | Use MiniMax API instead of the mmx CLI (v2.21) |
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
| **premium** | Latest flagship models | claude-opus-4-8, Gemini 3.1 Pro (High), gpt-5.5 |
| **standard** | Good quality at reasonable cost | claude-sonnet-4-6, Gemini 3.5 Flash (High), gpt-5.4 |
| **economy** | Optimized for speed and low cost | claude-haiku-4-5, Gemini 3.5 Flash (Low), gpt-5.4-nano |

**Default models are now premium tier** for maximum quality.

```bash
# Programmatic usage
source scripts/config.sh
apply_model_tier "premium"   # Set all consultants to premium models
apply_model_tier "standard"  # Set all consultants to standard models
apply_model_tier "economy"   # Set all consultants to economy models

# Get model for a specific consultant and tier (v2.8.1)
get_model_for_tier "gemini" "premium"   # → Gemini 3.1 Pro (High)
get_model_for_tier "claude" "economy"   # → claude-haiku-4-5
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

### Premium Model Defaults (June 2026)
All consultants now use premium models by default:

| Consultant | Default Model |
|------------|---------------|
| Claude | claude-opus-4-8 |
| Gemini | Gemini 3.1 Pro (High) (via agy CLI) |
| Codex | gpt-5.5 |
| Mistral | mistral-large-3 |
| Cursor | composer-2.5 |
| DeepSeek | deepseek-v4-pro |
| GLM | glm-5.2 |
| Grok | grok-4.3 |
| Qwen3 | qwen3.7-max |
| Kimi | kimi-code/kimi-for-coding |
| Aider | qwen3-coder:free |
| MiniMax | MiniMax-M2.7 |
| Kilo | auto |
| Ollama | hf.co/prithivMLmods/VibeThinker-3B-GGUF |

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

Configuration via environment variables or natural language.

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
DEBATE_CONFIDENCE_SPREAD_THRESHOLD=3  # Min spread to trigger debate
DEBATE_USE_SUMMARIES=true         # Use summaries in debate rounds
```

**Category Exceptions**: SECURITY and ARCHITECTURE always trigger debate regardless of confidence spread.

Functions in `debate_round.sh`:
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
| `ENABLE_CLAUDE` | true | Enable Claude consultant (auto-excluded under Claude Code) |
| `ENABLE_DEBATE` | false | Enable Multi-Agent Debate |
| `DEBATE_ROUNDS` | 1 | Number of debate rounds |
| `ENABLE_SYNTHESIS` | true | Auto-synthesis of responses |
| `ENABLE_SMART_ROUTING` | false | Intelligent routing |
| `ENABLE_COST_TRACKING` | true | Track costs |
| `MAX_SESSION_COST` | 1.00 | Max budget ($) |
| `ENABLE_PANIC_MODE` | auto | Panic mode trigger (v2.2) |
| `PANIC_CONFIDENCE_THRESHOLD` | 5 | Panic threshold (v2.2) |
| `ENABLE_OLLAMA` | false | Local model support (v2.2) |
| `OLLAMA_MODEL` | hf.co/prithivMLmods/VibeThinker-3B-GGUF | Ollama model (v2.17 default) |
| `CLAUDE_MODEL` | claude-opus-4-8 | Claude model (v2.5) |
| `GEMINI_MODEL` | Gemini 3.1 Pro (High) | Gemini agy CLI model (v2.15) |
| `GEMINI_API_MODEL` | gemini-3.1-pro-preview | Gemini API-mode model ID (v2.15) |
| `CODEX_MODEL` | gpt-5.5 | Codex model (v2.5) |
| `MISTRAL_MODEL` | mistral-large-3 | Mistral model (v2.5) |
| `SYNTHESIS_STRATEGY` | majority | Synthesis strategy (v2.2) |
| `ENABLE_SEMANTIC_CACHE` | true | Semantic response caching (v2.3) |
| `CACHE_TTL_HOURS` | 24 | Cache expiration in hours (v2.3) |
| `ENABLE_RESPONSE_LIMITS` | false | Response token limits (v2.3, opt-in) |
| `ENABLE_COST_AWARE_ROUTING` | false | Cost-based model routing (v2.3) |
| `ENABLE_DEBATE_OPTIMIZATION` | false | Skip debate if all agree (v2.3, opt-in) |
| `ENABLE_COMPACT_REPORT` | true | Compact report format (v2.3) |
| `ENABLE_CAPABILITY_WEIGHTING` | false | Capability-weighted voting (v2.20, opt-in) |
| `ENABLE_CAPABILITY_ROUTING` | false | Capability-aware panel composition (v2.20, opt-in) |
| `CAPABILITY_WEIGHT_STRENGTH` | 10 | Vote-weight modulation: conf*(S+cap)/S (v2.20) |
| `CAPABILITY_DEFAULT` | 5 | Fallback capability for a missing consultant/axis (v2.20) |
| `ENABLE_STANCE_CONSENSUS` | false | Enumerated-stance exact-match consensus (v2.21, opt-in; +1 LLM call/run) |
| `STANCE_MAX_OPTIONS` | 5 | Max stance options generated per question (v2.21) |
| `ENABLE_BUDGET_LIMIT` | false | Budget enforcement (v2.4, opt-in) |
| `BUDGET_ACTION` | warn | Action on budget exceeded: warn/stop (v2.4) |
| `QWEN3_USE_API` | false | Use DashScope API instead of qwen CLI (v2.7) |
| `QWEN3_CMD` | qwen | Qwen CLI command (v2.7) |
| `ENABLE_KIMI` | true | Enable Kimi consultant (v2.9) |
| `KIMI_CMD` | kimi | Kimi CLI command (v2.9) |
| `KIMI_MODEL` | kimi-code/kimi-for-coding | Kimi model (v2.9) |
| `ENABLE_MINIMAX` | true | Enable MiniMax consultant (v2.10; CLI via mmx v2.21) |
| `MINIMAX_USE_API` | false | Use MiniMax API instead of the mmx CLI (v2.21) |
| `MINIMAX_CMD` | mmx | MiniMax CLI command (v2.21) |
| `MINIMAX_API_KEY` | - | MiniMax API key (API mode only) (v2.10) |
| `MINIMAX_MODEL` | MiniMax-M2.7 | MiniMax model (v2.10) |

## External Dependencies

- `agy` CLI - Antigravity CLI (Gemini consultant; successor to the deprecated Gemini CLI, v2.15)
- `codex` CLI - OpenAI Codex
- `vibe` CLI - Mistral Vibe
- `kilocode` CLI - Kilo Code
- `agent` CLI - Cursor
- `aider` CLI - Aider
- `amp` CLI - Amp Code (v2.8)
- `kimi` CLI - Kimi Code (v2.9)
- `claude` CLI - Claude (v2.2, also used for synthesis)
- `qwen` CLI - Qwen via qwen-code (v2.7, optional)
- `mmx` CLI - MiniMax via mmx-cli (v2.21, optional; `npm i -g mmx-cli`, auth `mmx auth login`)
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

## Git Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `perf:`, `ci:`. Scope is optional (e.g., `feat(routing): add fallback escalation`).

### Pre-commit hook (v2.14.1+)

A git pre-commit hook runs `shellcheck` on staged `.sh` files using the exact CI invocation. Install it once per checkout:

```bash
npm run install-hooks    # copies scripts/hooks/pre-commit into .git/hooks/
```

Manual lint of the full repo: `npm run lint`. Bypass the hook: `git commit --no-verify` (use sparingly — CI will catch the same warnings).

## Release Process

Every version bump **must** include a release note in `docs/releases/v<VERSION>.md`. Use the template below.

### Steps

1. **Update version** in all files: `package.json`, `scripts/config.sh` (`AI_CONSULTANTS_VERSION`), `SKILL.md` (frontmatter + title), `README.md` (title + badge), `CLAUDE.md` (`**Version**`), `docs/cost_rates.json`, `docs/COST_RATES.md` (title)
2. **Add `## Changelog` entry** in CLAUDE.md (developer-facing, long-form, rationale + line-level commentary)
3. **Add `CHANGELOG.md` entry** at the top of `CHANGELOG.md` (Keep a Changelog format: `## [VERSION] - YYYY-MM-DD` with `### Added/Changed/Fixed/Removed/Deprecated/Security` subsections — user-facing, one-line bullets)
4. **Create `docs/releases/v<VERSION>.md`** using the template below (highlights + upgrade guide — for GitHub releases / users)
5. **Update workspace sync surfaces** if applicable: `aiconsultants.sh/index.html` (`softwareVersion` schema + badge), `../CLAUDE.md` workspace guide ("Latest at time of last sync" + Recent release line)
6. **Run tests**: `npm test` must pass before committing
7. **Commit, push**, and optionally create a GitHub release pointing to the release note

**Why three changelog surfaces?** They serve different audiences:
- `CLAUDE.md ## Changelog` — what the *next maintainer* needs (file/line references, rationale, latent bugs uncovered)
- `CHANGELOG.md` — what *users on a specific version* need (concise, categorized, scannable)
- `docs/releases/v<VERSION>.md` — what *people deciding to upgrade* need (highlights, breaking changes, upgrade guide)

Drift between these is the most common release-process bug. Keep them in sync per release.

### Release Note Template

```markdown
# Release v<VERSION>

**Date:** <YYYY-MM-DD>
**Type:** <Major | Minor | Patch> — <one-line summary>
**Previous:** v<PREVIOUS_VERSION>

## Highlights

- <3-5 bullet points with the most impactful changes>

## What's New

### <Feature/Area 1>

<Description of what changed and why. Include tables for multi-item changes.>

### <Feature/Area 2>

<Description.>

## Breaking Changes

<List breaking changes, or "None" if backwards-compatible.>

## Upgrade Guide

\`\`\`bash
# If installed via git clone
cd ~/.claude/skills/ai-consultants && git pull

# If installed via curl | bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
\`\`\`

<Note any configuration changes required, or "No configuration changes required.">

## Commits

- \`<hash>\` <commit message>

## Contributors

- <list>
```

### Guidelines

- **Audience**: Developers who use the skill. Write for someone who hasn't seen the commits.
- **Highlights first**: Lead with impact, not implementation. "Debate rounds no longer crash on Linux" > "Added `|| true` to `((count++))` in debate_round.sh".
- **Breaking changes prominent**: If any exist, they go in a dedicated section — never buried in a bullet list.
- **Quantify when possible**: Token savings percentages, issue counts, file counts.
- **Upgrade guide always present**: Even if the answer is "just pull", make it explicit.
- **No internal jargon**: Avoid referencing issue tracker IDs or internal codenames without context.

## Changelog

### v2.20.0
- **Capability axes (borrowed from the delegation-kit cost/intelligence/taste table).** `references/affinity.json` → v1.1: new `capabilities` (per-consultant {intelligence, taste, cost}, 1-10), `category_axis` (category → the quality axis it stresses: taste for API_DESIGN/ARCHITECTURE/CODE_REVIEW/GENERAL, intelligence otherwise), `capability_default`. New `lib/routing.sh::get_capability` / `get_category_axis` (cached like `get_affinity`).
- **Capability-weighted voting** (`ENABLE_CAPABILITY_WEIGHTING`, opt-in): `lib/voting.sh::_effective_vote_weight` modulates a vote by the consultant's capability on the run's axis — `confidence × (S + cap) / S` (`S = CAPABILITY_WEIGHT_STRENGTH`, default 10). Applied in `calculate_weighted_recommendation` and `calculate_final_score` (normalizer uses the same weight → 1-10 scale preserved). Axis from `QUESTION_CATEGORY`. `cost` never weights a vote (tie-break intelligence > taste > cost).
- **Capability-aware composition** (`ENABLE_CAPABILITY_ROUTING`, opt-in): `select_consultants` keeps the raw-affinity eligibility filter but ranks eligible consultants by `affinity + (cap − capability_default)`, so under a size limit the quality axis reorders who makes the cut.
- **Roster audit** — `scripts/roster_audit.sh` scores each consultant's "distinct approach" rate (max pairwise Jaccard of approaches < threshold) across consultations; verdicts unique-value / some-value / redundant? / insufficient-data. Wired as `doctor.sh --roster-audit` (short-circuit mode) and the `/ai-consultants:roster-audit` slash command (3 hosts). Reuses `voting.sh` keyword/Jaccard helpers.
- **Measured calibration** — `scripts/roster_calibrate.sh` (Tier A): intelligence/taste = mean blind peer-review score sliced by `category_axis`, cost = mean observed `tokens_used`×rate (60/40 split, rank-normalized cheapest=10); emits a `capabilities` block (`--json`/`--write`). `scripts/taste_elo.sh` (Tier B): taste via pairwise-judge Elo (pluggable judge — `JUDGE_CLI` / `TASTE_JUDGE_CMD`). `scripts/run_calibration.sh` drives `references/calibration_benchmark.json` (50 questions, 20 taste / 30 intelligence) through the panel with peer review, then calibrates.
- **Config** (`config.sh`): `ENABLE_CAPABILITY_WEIGHTING`, `ENABLE_CAPABILITY_ROUTING` (both false), `CAPABILITY_WEIGHT_STRENGTH` (10), `CAPABILITY_DEFAULT` (5). **Observability**: `consult_all.sh` records `capability{weighting_enabled, routing_enabled, axis}` in `optimization_metrics.json`.
- **Tests**: `test_capability_weighting` (17), `test_roster_audit` (6), `test_roster_calibrate` (10), `test_taste_elo` (6) — 12 suites total. All opt-in; with flags off, existing voting/routing/parity tests pass unchanged. shellcheck clean.
- **Docs**: `SMART_ROUTING.md` (capability + roster-audit + measured-calibration sections), `.env.example`, `references/configuration.md`, env-var table + structure list here. Website feature card added (sync on push).
- **Seeds are subjective** (Claude/Codex grounded on the model-routing table; the rest heuristic) — the calibration workflow measures them empirically. Fully back-compat.

### v2.19.2
- **Cost tracking silently lost on a fresh install — fixed.** `lib/costs.sh::track_session_cost` wrote to `$COST_TRACKING_FILE` (`$XDG_DATA_HOME/ai-consultants/costs.json`, i.e. `~/.local/share/...`) without ever creating the parent directory. That dir doesn't exist until something makes it, and `costs.json` is the only artifact stored there — so on a fresh install every session's cost write failed with "No such file or directory" (swallowed under `set -e` in the caller) and cumulative cost tracking never accumulated. Fix: `mkdir -p "$(dirname "$COST_TRACKING_FILE")"` up front; on failure, `log_warn` + `return 0`.
- **Function split for lock discipline**: `track_session_cost` (outer) now owns dir creation + locking and delegates the read-modify-write to a new inner `_track_session_cost_update`, which runs with the lock held and never propagates failure. Rationale documented inline: the caller in `consult_all.sh` runs under `set -e` *after* every consultant has already been queried and billed, so a bookkeeping failure must degrade to a warning, never abort the run.
- **Concurrency**: the RMW of `costs.json` was unguarded, so parallel consultations could interleave and lose records or fail the `mv`. Added a portable `mkdir`-based lock (flock is unavailable on macOS) with a bounded wait (50 × 0.1s = 5s); if the lock stays busy it proceeds unlocked with a warning rather than blocking or aborting. Writes now go through `mktemp "${COST_TRACKING_FILE}.XXXXXX"` instead of a fixed `.tmp` sibling, so an unlocked concurrent writer can't clobber another run's temp file (lost record / failed `mv`).
- **Corrupt-file self-heal**: a corrupt `costs.json` (truncated write, interleaved update) previously failed every future `jq` update forever and never recovered. Now `jq empty` gates the file; on failure it's moved aside to `${COST_TRACKING_FILE}.corrupt` and reset, so tracking recovers on the next session.
- **Tests**: `scripts/test_suite.sh::test_cost_tracking_resilience` (5 assertions, wired into `main()`) — costs.json created under a missing nested parent dir (fresh-install path), second session accumulates on the existing file (0.25 → 0.75, both exact in binary float), a corrupt costs.json is reset with the new session recorded, and the corrupt original is preserved as `.corrupt`. Calls guarded with `|| true` so a regression surfaces as a FAIL assertion, not a `set -e` suite abort. 8 suites pass; the new assertions are green; shellcheck clean.
- **No behavioral change for existing installs** whose data dir already exists; the fix only affects the first-run/absent-dir, concurrent, and corrupt-file paths. Cost bookkeeping remains best-effort by design.

### v2.19.1
- Cleanup from `/code-review max` on v2.19.0 (the workflow ran degraded under rate limits but surfaced these once it completed; all confirmed inline):
  - **Report-table mangling fixed**: a failure reason containing a `|` (e.g. a CLI error mentioning a piped command) broke the "Diagnosed Failures" markdown row. The new `lib/common.sh::render_diagnosed_failure <entry> [console|table]` escapes `|`→`\|` in table mode. (Not a security injection — the text is the user's own CLI stderr — but a real rendering bug.)
  - **DRY**: that helper is now the single source of the `name|reason` decode; the console log (quorum FAILED branch) and the report table both call it, so a future delimiter/encoding change touches one place instead of two.
  - **Health gate is cache-aware**: it no longer pings a consultant whose response is already cached (Round 1 would serve it free via `check_cache`) — it keeps the cached consultant without a billed probe. Avoids the opt-in gate defeating the semantic cache.
  - **`ping_consultant` takes the already-lowercased id** (callers compute it for the out/err paths anyway), dropping a redundant `to_lower` fork per consultant on both call sites (`doctor --live`, health gate).
  - **Documented** the health gate's inherent pre-Round-1 startup latency (serial with the run by definition; up to `HEALTH_GATE_TIMEOUT`) in `config.sh` — it's the cost of pruning up front; opt-in + tunable.
- Tests: `test_render_diagnosed_failure` (4 assertions incl. pipe-escaping); `test_ping_consultant` updated for the lowercased-id signature. 8 suites pass; shellcheck clean. Smoke-verified: report table renders correctly, health gate still prunes + the min-2 guard fires on the pruned count.

### v2.19.0
- **Quorum grading + "Diagnosed Failures" report** (the #1 pick from the `/workflows` CLI-reliability investigation — chosen for zero transport/billing risk over the CLI→API fallback, which the workflow's adversarial critique showed would emit persona-less confidence-5 stubs that poison voting). After the round-1 collect loop, `grade_quorum <success> <attempted> <min>` (new pure helper in `lib/common.sh`) classifies the run **MET / DEGRADED / FAILED** vs `QUORUM_MIN` (default 2). The report gains an `**Outcome**:` banner and a **## Diagnosed Failures** table that surfaces each dropped consultant's reason (the v2.18.0 `.err` capture) — so a panel that silently shrank to 2/7 is visibly DEGRADED instead of presenting as authoritative. `QUORUM_ACTION=stop` aborts below quorum; default `warn` continues with the banner. Failures are collected in `_surface_consultant_error` (DRY — same call that already logs the reason).
- **Health gate (`ENABLE_HEALTH_GATE`, opt-in)** — before the run, ping every selected consultant **in parallel** (new `lib/common.sh::ping_consultant`, `HEALTH_GATE_TIMEOUT` default 30s) and drop the non-responsive ones, so installed-but-unauthenticated CLIs (Cursor/Kimi/stale installs) are pruned up front and the quorum/budget checks see the genuinely-working panel. Script-less custom API agents (no `query_*.sh`) return code 2 and are kept (not probeable). Opt-in because it costs one extra tiny query per consultant; it prunes, it does not switch transport.
- **DRY**: `doctor --live` refactored to use the shared `ping_consultant`; both surfaces now share one probe implementation.
- **Explicitly NOT done** (per the workflow synthesis): CLI→API automatic fallback (persona-loss vote poisoning; Gemini already auto-resolves), cold-start retry-timeout escalation (stretches the whole round's worst case), warm-up calls, and the transport-abstraction circuit breaker (racy on-disk state, highest blast radius).
- **Tests**: `test_functions.sh` — `test_grade_quorum` (5 assertions: MET/DEGRADED/FAILED + boundaries) and `test_ping_consultant` (3: valid→0, no-output→fail, missing-script→2, via stub query scripts). 8 suites pass; shellcheck clean. End-to-end smoke verified: a forced CLI failure yields FAILED outcome + Diagnosed Failures table with the real reason, and the health gate prunes the dead consultant pre-run.

### v2.18.0
- **Failures are now diagnosable, not silent (Fix A).** `consult_all.sh` launched every consultant with `> /dev/null 2>&1` — discarding stderr — so a failed consultant produced only a bare `Failed`/`Empty response`, with no way to tell *not installed* vs *not authenticated* vs *transient* (this is exactly what led a real session to mis-attribute failures to a timeout). Now each consultant's stderr is captured to `$OUTPUT_DIR/<consultant>.err`, and on FAILED/EMPTY the run surfaces a one-line reason via the new `lib/common.sh::get_consultant_error_reason` helper (ANSI-stripped, prefers an explicit error line, drops orchestration status noise, falls back to "no error captured — CLI likely missing or not authenticated").
- **`run_query` now embeds the CLI's real error in its failure log.** The per-attempt CLI stderr (`${output_file}.err`, an unpredictable mktemp path the orchestrator can't locate) was only `log_debug`'d. Its first line is now appended to the `Error (code: N)` and `All N attempts failed` warnings, so the actual reason (e.g. `401 Unauthorized`, `command not found`) reaches the captured stderr and the surfaced message.
- **`doctor.sh --live` (Fix B): real ping per consultant.** The static checks only verify a CLI is installed (`--version`), so `doctor` reports a consultant healthy even when it errors at query time (unauthenticated) — a real source of "All systems healthy" while 3 consultants silently fail. `--live` sends a minimal real query to each *enabled* (and not self-excluded) consultant with a short timeout (`DOCTOR_LIVE_TIMEOUT`, default 45s), and reports ✓/✗ with the captured reason; failures become `doctor` issues (exit 1). Opt-in (costs one tiny query each). Standalone short-circuit mode like `--suggest-preset`.
- **Tests**: `test_functions.sh::test_get_consultant_error_reason` (5 assertions: explicit-error line, embedded-auth reason, orchestration-noise-not-mistaken, empty/missing file). 8 suites pass; shellcheck clean (CI invocation).
- **Not fixable in code (documented for users)**: the underlying CLI auth/install state, and cold-start/warm-up retry effects, are environment issues — `--live` *surfaces* them but can't authenticate a CLI for you.

### v2.17.2
- **SECURITY: revert v2.17.1's `allow_absolute=true` for context files — it opened a secret-exfiltration surface (caught in `/code-review max`).** v2.17.1 fixed the macOS `/private/tmp` drop by letting `build_context.sh` accept *any* absolute context path behind `validate_file_path`'s prefix-only blocklist (`/etc /root /var/log /proc /sys /dev`). That blocklist covers no home secrets, so a context arg of `~/.ssh/id_rsa`, `~/.aws/credentials`, `~/.netrc`, or `~/.config/gh/hosts.yml` was read verbatim and **sent to the external AI providers**. It also matched literal non-canonical prefixes, so `/private/etc/master.passwd` (the real `/etc` on macOS, via the same symlink aliasing) bypassed the `/etc` rule.
- **Fix (correct altitude — allowlist, not blocklist)**: context files are now accepted only when (a) relative and in-tree (`validate_file_path ... false` — rejects absolute and `..`), or (b) under a recognized temp root via the new `_is_temp_path` helper (`/tmp`, `/private/tmp`, `$TMPDIR`, and the `/private`-prefixed macOS alias of `$TMPDIR`; `..` rejected so a temp prefix can't traverse out). Still fixes the original macOS scratch-file regression (Claude Code writes `/private/tmp/...`) **without** widening to the whole filesystem. Verified: `/tmp`, `/private/tmp`, `$TMPDIR/...`, relative in-tree → accepted; `~/.ssh/id_rsa`, `/etc/passwd`, `/private/etc/master.passwd`, `/tmp/../etc/passwd` → rejected.
- **`build_context.sh` OUTPUT_FILE**: removed the `/tmp/*` short-circuit that jumped past `validate_file_path` (so `/tmp/../etc/x` bypassed the `..` check). Output paths now always run through `validate_file_path "$OUTPUT_FILE" "true"` — absolute allowed (output lives under the XDG cache or `/tmp`), traversal + sensitive-path guards enforced. The two validation sites are intentionally different now (OUTPUT is tool-chosen; context files are untrusted input) and the comments say so.
- **Test**: rewrote `test_context_optimization.sh` Test 15 as a *boundary* test — temp-root accepted, `~/.ssh/id_rsa` rejected (exfiltration blocked), `/etc/passwd` rejected. Uses the auto-cleaned `$_TMPDIR` (no `$HOME` litter) and `QUESTION_CATEGORY=SECURITY` to skip the project-tree `find` the assertions don't need. Fixed the stale suite-header comment that contradicted the new behavior. 8 suites pass; shellcheck clean.
- **Note**: v2.17.1 was tagged and GitHub-released but **never published to npm** (npm stayed at 2.17.0), so no npm user received the vulnerable version. Publish **2.17.2**, not 2.17.1.

### v2.17.1
- **Fix: context files at absolute paths outside `/tmp` were silently dropped.** `build_context.sh`'s context-file gate accepted only relative paths or a literal `/tmp/*` prefix (`if [[ "$_PARSED_PATH" == /tmp/* ]] || validate_file_path "$_PARSED_PATH" "false"`). On macOS `/tmp` is a symlink to `/private/tmp`, so Claude Code scratch files arrive as `/private/tmp/...` and matched neither branch → `log_warn "Skipping invalid file path"` and the file was excluded, with `build_context.sh` falling back to a generic repo auto-context. Net effect: a consultation looked like it ran with the user's context but the consultants never received it. (Reported from a real session where the passed context was dropped and an auto-context substituted.)
- **Fix**: the gate now uses `validate_file_path "$_PARSED_PATH" "true"` (allow absolute), mirroring the OUTPUT_FILE handling a few lines above. Context files are explicitly user/agent-provided, so absolute paths are legitimate; the sensitive-path blocklist (`/etc /root /var/log /proc /sys /dev`), path-traversal (`..`), and null-byte guards in `validate_file_path` still apply. Verified: `/private/tmp/...`, `/tmp/...`, relative, and `$HOME/...` paths accepted; `/etc/passwd`, `/var/log/...`, `../../etc/...` still rejected.
- **Test**: `test_context_optimization.sh` Test 15 — an absolute context path outside `/tmp` (a `$HOME` file) is now included in the built context, and `/etc/passwd` is still skipped. 8 suites pass; shellcheck clean.
- **Note (not a code change)**: the same session also showed Gemini/Codex failing immediately — because the *installed* skill at `~/.claude/skills/ai-consultants` was **v2.10.0** (pre-agy migration), so Gemini called the deprecated `gemini` binary. Updating the installed skill to ≥v2.15 (now v2.17.1) resolves that; it's an install-staleness issue, not a current-code bug.

### v2.17.0
- **Model catalog refresh (June 2026)** across all three tiers + cost rates, for every agent. Source of truth stays `config.sh::get_model_for_tier` (+ default `*_MODEL` vars) mirrored by `docs/cost_rates.json` (`model_tiers` + `consultant_fallbacks` + per-1K `models` rates). CLI-addressed models verified by querying the installed binaries (`agy models`, `agent --list-models`, kimi config); API/provider models + pricing researched against official sources. Superseded IDs kept in `cost_rates.json` for historical/pinned lookups.
- **Changed models** (premium / standard / economy):
  - **codex**: gpt-5.5 / **gpt-5.4** (was gpt-5.3) / **gpt-5.4-nano** (was gpt-4o-mini).
  - **cursor**: **composer-2.5** / **composer-2** / **gemini-3-flash** (was composer-2 / composer-1.5 / gemini-2.0-flash).
  - **deepseek**: deepseek-v4-pro / **deepseek-v4-flash** ×2 (was deepseek-v3.2 / deepseek-chat; chat+reasoner deprecate 2026-07-24).
  - **glm**: **glm-5.2** premium+standard (was glm-5.1) / glm-4-flash.
  - **grok**: grok-4.3 / **grok-4.1-fast** ×2 (was grok-3 / grok-3-mini).
  - **qwen3**: **qwen3.7-max** (was qwen3.6-plus) / qwen3.6-35b-a3b / qwen3-32b.
  - **aider**: **qwen3-coder:free** (was nvidia/nemotron…:free) / **gpt-5.4** / **gpt-5.4-nano**.
  - **ollama**: **hf.co/prithivMLmods/VibeThinker-3B-GGUF** default (was qwen2.5-coder:32b); standard/economy keep llama3.3/llama3.2.
- **Unchanged (verified current)**: claude, gemini (agy display names — no newer Gemini), mistral, minimax, kimi/amp/kilo.
- **Cost-rate corrections (per-1K)**: `gpt-5.5` → 0.005/0.030 (was understated 0.003/0.012), `deepseek-v4-pro` → 0.000435/0.00087, `minimax-m2.7` → 0.00025/0.001, `composer-2` → 0.0005/0.0025, Gemini Flash → 0.0015/0.009, Gemini 3.1 Pro → 0.002/0.012, mistral-medium → 0.001/0.003, devstral-small-2 → 0 (free). New IDs added with researched per-1K rates. `COST_RATES.md` regenerated to match the JSON.
- **Estimates flagged**: `glm-5.2` (mirrors glm-5.1) and `qwen3.7-max` (mirrors qwen3-max) pending official pricing.
- **Docs synced**: README, configuration.md, .env.example (+ fixed pre-existing GROK/DEEPSEEK default drift), SETUP.md, CLAUDE.md tables. Tests: tier assertions updated +10 new; 8 suites pass; shellcheck clean.
- **Found in `/code-review max` (workflow-backed, 61 agents): case-insensitive cost lookup.** `lib/costs.sh::get_rate_from_file` did an exact-case jq key match, but callers lowercase the model name first — so every **mixed-case** rate key silently missed and fell to `default_rate` ($0.005/$0.015 per 1K). This diff newly tripped it with the Ollama default `hf.co/prithivMLmods/VibeThinker-3B-GGUF` (a free local model billed at $0.02/query → wrong session cost reports, pre-run estimates, and budget halts under `ENABLE_BUDGET_LIMIT`), and it had silently rendered the **Gemini** agy display-name rates inert since v2.15 (every Gemini consultation cost-reported at default, not its real rate). Fixed by matching keys case-insensitively (`ascii_downcase` both sides via `first(.models|to_entries[]|select(...))`) — lowercase keys (minimax/gpt-5.5) still match; mixed-case (Gemini, VibeThinker) now resolve. Verified: VibeThinker → $0, Gemini 3.1 Pro → $0.014 for 1k+1k. Regression tests added (VibeThinker=0, Gemini resolves, local model free).
- **Also from review**: `estimate_query_cost`/`format_cost` now restore the leading zero bc drops on sub-1 values (".014000"/".03¢" → "0.014000"/"0.03¢") — surfaced by the diff's many sub-cent rates. README roster + `references/configuration.md` Grok/DeepSeek default cells synced to grok-4.3 / deepseek-v4-pro (the partial sync had left them stale). `config.sh` codex + ollama inline comments corrected to the new defaults. `cost_rates.json` premium-block date comment → Jun 2026. (Skipped as deliberate: re-ordering legacy entries under `_comment_legacy`, and the `gemini-3-flash-preview` vs `gemini-3-flash` coexistence — the former is the historical Gemini-API id, the latter Cursor's economy model, kept separately on purpose.)

### v2.16.0
- **Dynamic orchestration engine** — the fixed `classify → query → debate(N fixed rounds) → synth` pipeline becomes adaptive, inspired by Claude Code's dynamic workflows but implemented entirely in standalone bash (no Workflow tool / Claude-Code dependency). A planner picks an orchestration **shape** per question; debate becomes a **convergence loop**.
- **New module `lib/orchestration.sh`** (sourced by `consult_all.sh` after voting/costs). Public surface:
  - `detect_intent <query>` → `advise|compare|exhaustive` (heuristic regex over the query; zero-dep).
  - `select_orchestration_shape <category> <complexity> <intent>` → `quick|converge|adversarial|tournament|exhaustive|fixed`. Auto resolution priority: explicit `ORCHESTRATION_MODE` override → intent (`exhaustive`/`compare`) → category (`SECURITY`→adversarial) → complexity (≤`COMPLEXITY_THRESHOLD_SIMPLE`→quick, else converge).
  - `run_orchestration <shape> <dir> <category>` dispatcher; skips multi-round shapes when `SUCCESS_COUNT ≤ 1`.
  - Pure decision helpers, unit-tested without live CLIs: `_convergence_should_stop <score> <prev> <target> <epsilon>` (→`converged|stalled|continue`) and `_approach_signature <dir>` (sorted-unique approach set, the loop-until-dry stop signal).
- **Convergence loop (`run_convergence_loop`)** replaces the fixed `for round=2..DEBATE_ROUNDS`. Stops on: consensus ≥ `CONVERGENCE_TARGET_CONSENSUS` (converged), per-round gain < `CONVERGENCE_STALL_EPSILON` (stalled), `CONVERGENCE_MAX_ROUNDS` reached, or budget. `min_rounds` param forces ≥N critique rounds even on early consensus (adversarial uses 2). Reuses `calculate_consensus_score` (voting.sh) for the stop signal and the extracted `_apply_debate_round` helper (the legacy loop body, now shared) for execution+merge. Trajectory + stop reason written to `orchestration.json`.
- **Shapes**: `quick` (no debate), `converge` (loop to consensus), `adversarial` (forced critique round + peer review as refutation gate — `SECURITY`), `tournament` (converge, then synthesis declares one winner via `ORCHESTRATION_SELECT_WINNER` directive in `synthesize.sh`), `exhaustive` (`run_exhaustive_loop`: iterate until a round adds no new `.response.approach`).
- **`consult_all.sh` integration**: after classification, computes `QUERY_COMPLEXITY` (`calculate_query_complexity`, costs.sh) + `QUERY_INTENT` + `ORCH_SHAPE`; the debate block dispatches on `ORCHESTRATION_MODE` (`fixed` → byte-equivalent legacy loop via `_apply_debate_round`; else → `run_orchestration`). Adversarial shape force-enables `ENABLE_PEER_REVIEW`. Shape/complexity/intent recorded in `optimization_metrics.json`.
- **Config (all back-compat)**: `ORCHESTRATION_MODE` (default `auto`), `CONVERGENCE_MAX_ROUNDS` (4), `CONVERGENCE_TARGET_CONSENSUS` (75), `CONVERGENCE_STALL_EPSILON` (5), `ENABLE_ADVERSARIAL_VERIFY` (true). `ORCHESTRATION_MODE=fixed` restores the exact pre-2.16 pipeline.
- **Behavioral change (default)**: with `auto` the panel may run more or fewer rounds than the old fixed default, driven by consensus — complex/contested questions iterate further, simple ones short-circuit to `quick`. Every round still passes `enforce_budget`, so `MAX_SESSION_COST` continues to cap spend. Set `ORCHESTRATION_MODE=fixed` to opt out.
- **Minor robustness**: `_apply_debate_round` swallows a failed `debate_round.sh` (`|| true`) instead of aborting the whole consultation under `set -e` (the legacy inline `$()` capture would abort). Applies to both `fixed` and dynamic paths.
- **Convergence actually converges (fixed in `/code-review max`).** The round file carries the consultant's *updated* top-level `.response.approach` (`build_structured_response` uses `$inner.response`), but the legacy merge grafts only `.debate` (which `build_structured_response` doesn't even preserve → null). Since `calculate_consensus_score` reads `.response.approach`, the consensus signal was invariant under debate → the loop stalled after exactly one round every time. Fix: `_apply_debate_round` gained a `promote` flag; the dynamic loops (`promote=true`) adopt the round file's post-debate `.response`/`.confidence` so consensus reflects evolved positions. The legacy `fixed` path (`promote=false`) keeps the original `.debate`-only graft. Verified: a stubbed converging panel now moves 0 → 100 (`converged`), where before it logged `stalled` at round 1. Regression tests assert promote adopts the updated approach and legacy preserves the original.
- **ARCHITECTURE keeps its mandatory debate (fixed in `/code-review max`).** The legacy pipeline always debated `SECURITY` *and* `ARCHITECTURE`; the first planner cut only special-cased `SECURITY`→adversarial, letting `ARCHITECTURE` fall through to `converge` (min_rounds=1), which early-exits with zero debate rounds when the fan-out already agrees. Now `ARCHITECTURE` pins to `converge` (never `quick`) and `run_orchestration` forces `min_rounds=2` for both mandatory categories, so they always run ≥1 critique round — restoring pre-2.16 behavior.
- **Tests**: new `scripts/test_orchestration.sh` (32 assertions, 13 tests) — intent detection, shape selection (intent/category/complexity priority + overrides + fixed bypass + threshold boundary + ARCHITECTURE mandatory-debate), convergence stop decision (converged/stalled incl. negative-gain/continue), `_apply_debate_round` promote-vs-legacy merge, `_approach_signature` over fixtures, `ORCHESTRATION_MODE=auto` default. Auto-discovered by `test_all.sh` → now **8 suites**. Convergence loop smoke-tested end-to-end with a stubbed `debate_round.sh` (0 → 100 converged).

### v2.15.1
- **Markdown-fence parsing fix — Gemini's default model produced degraded (fallback) responses under v2.15.0.** The v2.15.0 migration note claimed "agy prints the model JSON directly (top-level `.response`)"; verified against agy 1.0.10, that is only true for some models (e.g. `Gemini 3.5 Flash (Low)` returns bare JSON). The **default** `Gemini 3.1 Pro (High)` wraps the envelope in a ```` ```json … ``` ```` markdown fence, so `process_consultant_response` failed the `.response.summary` jq probe and fell through to `build_fallback_response` — emitting `summary: "Unstructured response - see detailed"`, `confidence: 5`, and empty pros/cons for every Gemini reply, with the real structured envelope buried as a fenced string inside `.detailed`. Fix: new shared helper `lib/common.sh::strip_json_fence` — returns the text unchanged when it already parses as JSON (a real fence makes the text invalid JSON, so the gate reliably detects it), otherwise drops pure fence-marker lines (`/^[[:space:]]*```[[:alnum:]]*[[:space:]]*$/d`). Consultant-agnostic; the bare-JSON path (Flash, every other consultant) is untouched. Verified end-to-end against live agy: `Gemini 3.1 Pro (High)` now yields a populated `build_structured_response` (summary/approach/pros/cons/confidence=10). Regression test in `test_functions.sh::test_process_consultant_response_fence`.
- **Fence fix applied to ALL agy output paths (caught in `/code-review max`).** The fence isn't only seen by `process_consultant_response` — two other paths consume agy output directly and were still corrupting it:
  - **`lib/reflection.sh::run_reflection_cycle`**: `_exec_consultant` returns raw (fenced) agy output. The critique's `jq -r '.needs_refinement'` returned `""` on fenced text (so the early-stop never fired and every cycle ran), and the refined response was written back as fenced non-JSON, making downstream voting/synthesis/report `jq` reads silently fall back — discarding the refined Gemini answer. Now de-fences `critique` and `refined` via `strip_json_fence` at the consumption points.
  - (`peer_review.sh` already had its own `extract_json_from_response` fence handler applied before aggregation — verified safe, left as-is.)
- **Synthesis via agy was broken (caught in `/code-review max`).** `lib/common.sh::build_synthesis_args` gemini branch produced a bare `agy` invocation (`SYNTHESIS_ARGS=("${GEMINI_CMD:-agy}")`), invoked as `echo "$prompt" | agy`. Unlike codex (`--full-auto`) and claude (`--print`), agy with no `--print`/`-p` launches its **interactive** session and never reads the piped prompt, so synthesis hung/produced nothing whenever agy was the chosen synthesizer (reachable e.g. when Claude Code is the invoking agent and agy is on PATH). Fixed to `("${GEMINI_CMD:-agy}" "-p" "-")` + `--model`, mirroring `query_gemini.sh`.
- **Comment rot (caught in `/code-review max`)**: `query_gemini.sh` comments claimed agy emits raw JSON "no envelope to unwrap"; corrected to note the default model fences its JSON and that the fence is stripped centrally.
- **Gemini transport auto-resolution — makes the Gemini consultant work out-of-the-box for npm/npx users.** v2.15.0 left Gemini enabled by default (`ENABLE_GEMINI=true`) in CLI mode (`GEMINI_USE_API=false`), but the agy (Antigravity) CLI cannot be installed via npm (it's a `curl|bash` binary into `~/.local/bin/agy`) and is OAuth-only (no headless/API-key auth). Net effect: every fresh `npx ai-consultants` run silently dropped Gemini from the panel (`consult_all.sh` marks it FAILED and continues) — *even when the user had `GEMINI_API_KEY` exported*, because API mode was opt-in with no auto-detection. The API path (pure `curl` + key, no binary, no browser) is the npm-friendly one but was off by default.
- **`config.sh`**: removed the hardcoded `GEMINI_USE_API="${GEMINI_USE_API:-false}"` at the mode-switching block (`scripts/config.sh:69-72`). The mode is now auto-resolved in the Gemini config section (`scripts/config.sh:113-131`), *after* `GEMINI_CMD`/`GEMINI_API_KEY` are known: when `GEMINI_USE_API` is unset, pick `true` if `GEMINI_API_KEY` is present, else `false` (agy CLI). An explicit `GEMINI_USE_API=true/false` is always honored (back-compat, via the `${GEMINI_USE_API+x}` set-vs-unset guard). Idempotent across the 15-30 `config.sh` re-sources per consultation: once resolved and `export`ed, subsequent sources see it as user-set. Only Gemini auto-resolves; the other four switchable agents (Codex, Claude, Mistral, Qwen3) keep their hardcoded `:-false` defaults since their CLIs are npm/pip-installable.
- **`doctor.sh`**: `check_cli_consultant` now skips the CLI install check when the consultant is in API mode (`${env_var}_USE_API == true`) — previously it would flag a missing CLI as a hard `✗ NOT INSTALLED` failure regardless of mode, which after auto-resolution would false-fail for every key-only Gemini user. This also fixes the same pre-existing latent false-positive for Codex/Claude/Mistral/Qwen3 when those run in API mode. Additionally, when Gemini *is* in CLI mode and `agy` is missing, the failure now prints a `tip: set GEMINI_API_KEY to use API mode (no CLI install needed)` remediation pointing at the npm-friendly path.
- **Tests**: `test_user_config.sh` +4 assertions (Tests 19-22): auto-API with key, auto-CLI without key, explicit `false` wins over a present key, explicit `true` honored without a key. Suite now 42 checks; all 7 suites pass.
- **No breaking change**: agy/OAuth users without a key keep CLI mode; anyone who pinned `GEMINI_USE_API` keeps their value. The only behavioral change is that a key-only environment now reaches Gemini over the API instead of silently dropping it.

### v2.15.0
- **Gemini consultant migrated from the Gemini CLI to the Antigravity CLI (`agy`)**. Google deprecated the Gemini CLI on 2026-06-18 (transitioning all individual/Pro/Ultra users to Antigravity CLI); the `gemini` binary stops serving requests for non-enterprise accounts. The consultant stays "Gemini" / "The Architect" (ID 1) — only the transport binary, model addressing, and auth change. Verified against `agy` 1.0.10.
- **`config.sh`**: `GEMINI_CMD` default `gemini` → `agy` (`scripts/config.sh:106`); `GEMINI_MODEL` default `gemini-3.1-pro-preview` → `Gemini 3.1 Pro (High)` (agy addresses models by display name, not API ID); new `GEMINI_API_MODEL` (default `gemini-3.1-pro-preview`) decouples the API-mode model ID from the CLI display name. `get_model_for_tier "gemini"` now returns agy display names: premium `Gemini 3.1 Pro (High)`, standard `Gemini 3.5 Flash (High)`, economy `Gemini 3.5 Flash (Low)`.
- **`query_gemini.sh`** — three verified flag/parse changes:
  - `-m` → `--model` (agy has no `-m` short alias).
  - **Dropped `--output-format json`** — agy has no such flag and prints the model's response as plain text. Because the persona instruction already forces the model to emit our JSON schema, that plain text *is* the JSON envelope we need.
  - **Dropped the `native_json_field="response"` argument** to `process_consultant_response`. The old Gemini CLI wrapped output as `{"response":"<text>","stats":{…}}` and we extracted `.response`; agy's output is the model JSON directly (top-level `.response`), so extracting `.response` would strip a level and force every structured reply into the fallback path. Confirmed end-to-end: a real `agy` call now yields a correct `build_structured_response` (consultant=Gemini, model="Gemini 3.1 Pro (High)", persona=The Architect, populated pros/cons/confidence).
  - API-mode branch now passes `$GEMINI_API_MODEL` (not `$GEMINI_MODEL`) to `run_api_mode_query`, since the Google AI endpoint builds `…/${model}:generateContent` and needs an API ID, not a display name.
- **CLI invocation parity**: same `-m`→`--model` change applied to the two other call sites — `peer_review.sh:150` and `lib/reflection.sh:71`.
- **Install/auth surfaces** repointed to agy: `doctor.sh` (install hint + `${GEMINI_CMD:-gemini}`→`:-agy` in the two config-dump fallbacks), `setup_wizard.sh`, `configure.sh` (`CLI_AGENT_CMDS`/`CLI_AGENT_HINTS`), `lib/common.sh` synthesis fallbacks (`:-agy`), `.env.example`, `docs/SETUP.md`, `references/configuration.md`. Install is now `curl -fsSL https://antigravity.google/cli/install.sh | bash` (binary lands in `~/.local/bin/agy`). Auth is **OAuth-only** (`agy` with no args → browser sign-in; creds cached); `agy` does **not** honor an API-key env var for headless use — that path remains exclusive to API mode.
- **Cost catalog**: added `Gemini 3.1 Pro (High)` / `Gemini 3.5 Flash (High)` / `Gemini 3.5 Flash (Low)` keys to `cost_rates.json` (per-1K, mirroring the matching Gemini API tier; agy itself bills via OAuth/subscription) and repointed `consultant_fallbacks.gemini` + all three `model_tiers.*.gemini` to the display names. The old `gemini-3.1-pro-preview`/`gemini-3-flash-preview`/`gemini-2.0-flash` entries are kept for API mode and historical lookups. `COST_RATES.md` synced.
- **Tests**: `test_suite.sh` tier assertions updated (`get_model_for_tier "gemini" premium/economy` and `get_economic_model "gemini"` now expect the agy display names) — same pattern as the v2.14.2 claude-opus-4-8 bump. All 7 suites pass.
- **Known follow-up (out of scope, flagged in the release note)**: the *host-side* integration — running ai-consultants **from** Gemini CLI as a slash-command host (`~/.gemini/skills/`, `INVOKING_AGENT=gemini`) — is affected by the same deprecation (Antigravity rebrands Extensions as "plugins", `agy plugin …`). That migration is **not** done here; this release covers only the Gemini *consultant* (the model we query). The relevant README/SETUP host sections were left intact rather than rewritten on unverified plugin mechanics.

### v2.14.2
- **Claude premium tier upgraded `claude-opus-4-7` → `claude-opus-4-8`** (Opus 4.8 released 2026-05-29). Single source of truth is the `premium` case in `config.sh::get_model_for_tier` (`scripts/config.sh:583`) and the `CLAUDE_MODEL` default (`scripts/config.sh:223`); both now resolve to `claude-opus-4-8`. Standard (`claude-sonnet-4-6`) and economy (`claude-haiku-4-5`) tiers are unchanged — Sonnet 4.6 and Haiku 4.5 remain the latest in their classes.
- **`docs/cost_rates.json`**: added a `claude-opus-4-8` entry; repointed `consultant_fallbacks.claude` and `model_tiers.premium.claude` to it; moved `claude-opus-4-7` into the `_comment_legacy` block so cost lookups for cached/historical responses and pinned overrides still resolve. Value entered in per-1K (see units fix below).
- **CRITICAL — cost-catalog unit normalization (fixes ~1000× cost overstatement)**: `lib/costs.sh` computes cost as `(token_count / 1000) * rate`, i.e. every value in `cost_rates.json` MUST be USD **per-1K** tokens (the hardcoded fallback table in `costs.sh`, e.g. `claude-3-haiku → 0.00025`, confirms this contract). But the premium/standard blocks had been populated with **per-MTok** dollar figures (`claude-opus-4-7: 5.00`, `claude-sonnet-4-6: 3.00`, `gpt-5.5: 3.00`, …) — so `estimate_query_cost` reported ~1000× the true cost for almost every premium/standard model (e.g. a ~1k-in/1k-out Opus query was reported as **$30** instead of **$0.03**). The economy block (incl. `claude-haiku-4-5: 0.001`) was already correct per-1K. Normalized the **entire** catalog (premium, standard, economy, legacy, `default_rate`) to per-1K by dividing the per-MTok entries by 1000; left the already-correct per-1K entries untouched. Added a `_comment_units` field documenting the contract to prevent regression. Verified: Opus 1k+1k = $0.03, 1M+1M = $30; Haiku 1k+1k = $0.006; gpt-5.5 1M+1M = $15; gemini-pro 1M+1M = $6.25 — all match provider pricing.
- **`docs/COST_RATES.md`**: Claude rows synced to the corrected per-1K values (`claude-opus-4-8` $0.005/$0.025, `claude-sonnet-4-6` $0.003/$0.015, `claude-haiku-4-5` $0.001/$0.005). Note: non-Claude rows in this human-facing doc may still lag the JSON and should be re-synced in a follow-up — `cost_rates.json` is the runtime source of truth, not this file.
- **Stale-alias cleanup (pre-existing, fixed in passing)**: five spots still carried pre-v2.10.6 short aliases and now use canonical IDs — `scripts/query_claude.sh` (header comment + `MODEL_USED` fallback), `.env.example` (`CLAUDE_MODEL=opus-4.6`), `references/configuration.md`, and the README "Models by Tier" table all → `claude-opus-4-8`; plus `lib/api.sh::build_anthropic_request` default `sonnet-4.6` → `claude-sonnet-4-6`. All were latent (callers always pass an explicit model / `config.sh` always exports `CLAUDE_MODEL`), but would have surfaced if those scripts were invoked standalone or the example `.env` copied verbatim.
- **Test**: `scripts/test_suite.sh::test_model_for_tier` premium assertion updated to expect `claude-opus-4-8`. No other test references the Claude premium ID.
- **Correction of an earlier mis-diagnosis (for the record)**: during development this was first flagged as "Haiku is 1000× *understated*". That was wrong — under the per-1K contract `claude-haiku-4-5: 0.001` is correct ($1/$5 per MTok). The real bug was the *opposite*: premium/standard entries were 1000× *overstated*. The unit normalization above is the actual fix.
- **Behavioral change**: cost *reporting* now drops ~1000× for premium/standard models (it was massively overstating). Orchestration, routing, and synthesis are unaffected. Note: `ENABLE_COST_AWARE_ROUTING` / budget thresholds compare against these figures, so anyone who tuned `MAX_SESSION_COST` against the old inflated numbers should revisit their threshold. Remaining out-of-scope item: a few legacy per-model rates (e.g. Mistral/DeepSeek/GLM tier orderings) reflect pre-existing catalog figures I couldn't verify against authoritative pricing — only the unit bug was fixed, not per-model price accuracy.

### v2.14.1
- **Pre-commit hook**: `scripts/hooks/pre-commit` runs `shellcheck` on staged `.sh` files under `scripts/` using the exact CI invocation (`-S warning -x -e SC1091,SC1090,SC2034,SC2155`). Mirrors `.github/workflows/ci.yml:32` so the same warnings that fail CI also fail the local commit. Filtered with the regex `^scripts/(lib/)?[^/]+\.sh$` to match the CI glob exactly (test fixtures under `scripts/test_fixtures/` are correctly excluded). Bypass: `git commit --no-verify`.
- **`scripts/install-hooks.sh`**: idempotent installer wired to `npm run install-hooks`. Backs up any existing different hook to `.git/hooks/pre-commit.backup.<timestamp>` to avoid clobbering contributor customizations (`FORCE=1` skips backup). Silent no-op outside a git checkout, so it's safe to wire to npm `prepare` or similar lifecycle hooks if ever needed.
- **`npm run lint`**: convenience wrapper for the full-repo shellcheck invocation. Useful pre-push when you want to validate without staging.
- **Motivation**: v2.14.0 push to `main` failed CI due to SC2164 in `scripts/test_context_optimization.sh:18` (`cd "$PROJECT_ROOT"` lacked `|| exit`). The new script passed `bash -n` locally but `bash -n` is purely a parser check — it doesn't run any linter. The pre-commit hook closes that gap. Documented in `CONTRIBUTING.md` Development Environment Setup section and briefly in `## Git Conventions` here.
- **No runtime behavior change**: this is contributor-only tooling. Tests still pass (7 suites, ~510 assertions).

### v2.14.0
- **Context handoff: AST optimization pipeline now engages on the primary slash-command path**. Pre-fix, `/ai-consultants:consult` instructed the invoking agent (Claude/Codex/Gemini) to inline file contents into the query string, which meant `build_context.sh` ran with zero `FILES` and the entire `lib/code_optimizer.sh` + `lib/chunking.sh` + `lib/symbol_map.sh` stack was dead code. The three `.{claude,codex,gemini}/commands/ai-consultants:{consult,debate}.md` slash commands now instruct agents to pass file paths as positional arguments to `consult_all.sh`; `build_context.sh` does the file reading and runs the optimizer.
- **`build_context.sh` reads exported `QUESTION_CATEGORY`** to decide whether to include the project tree section. SECURITY, QUICK_SYNTAX, ALGORITHM, BUG_DEBUG, DATABASE, TESTING categories skip it (noise for pointed questions); ARCHITECTURE, CODE_REVIEW, API_DESIGN, GENERAL include it; unknown categories default to "include" (conservative). New env var `FORCE_PROJECT_TREE=true` bypasses the heuristic. Categories source: `classify_question.sh` already exports `QUESTION_CATEGORY` in `consult_all.sh:241-242` — zero new code path, just consumes existing signal.
- **File relevance tags**: `path/to/file@PRIMARY` (focus of the question) vs `path/to/file@CONTEXT` (ambient reference). Default `PRIMARY` when omitted. Unknown tags fall back to PRIMARY with a `log_warn`. New parallel `FILE_TAGS` array in `build_context.sh`. Rendered as `### File: \`path\` (TAG)` in the `## Relevant Files` section, with a header explaining the two values to consultants. Downstream synthesis/debate/peer_review unaffected (they don't read `context.md`).
- **`--query-file <path>` flag in `consult_all.sh`** as escape hatch for queries exceeding shell ARG_MAX (~256KB on macOS) or containing mixed-quote payloads. Conflicts with positional question arg (parser-level error). Validates file existence at parse time.
- **Slash-command file detection**: replaced the hardcoded extension regex + `/`-in-token heuristic with "use your judgment, verify via Glob/Bash when uncertain". Pre-fix missed `Makefile`, `Dockerfile`, dotfiles; false-positive on URLs and regex patterns in question text. The invoking agent has full conversation context so it's better placed than a regex.
- **Claude-only note in `.claude/commands/ai-consultants:consult.md`**: explicit instruction not to use `Read` tool output (which carries `N\t` line-number prefix) since `build_context.sh` reads files itself. Codex and Gemini variants don't carry this note (their tools don't add the prefix).
- **First test coverage for `lib/code_optimizer.sh` and `lib/chunking.sh`**: new `scripts/test_context_optimization.sh` (17 assertions, 14 tests). Covers: @TAG default/explicit/unknown, QUESTION_CATEGORY routing (SECURITY drops, ARCHITECTURE keeps, unknown includes), FORCE_PROJECT_TREE override, Python AST extraction over MAX_CONTEXT_FILE_BYTES threshold, `optimize_code_file` smoke, `chunk_file_semantically` JSON shape, --query-file parsing (valid/missing/conflict), legacy no-FILES path preservation. Picked up automatically by `test_all.sh`'s `find`-based discovery — no manual wire-up needed. Total: 7 suites, ~510 assertions.
- **Test fixtures**: new `scripts/test_fixtures/context/` with `sample.py` (Python class + methods + main), `sample.sh` (Bash with functions), `sample.json` (config), `sample.txt` (plain text). Deterministic, no timestamps or randomness.
- **Help text updates**: `consult_all.sh --help` documents `--query-file` and `@TAG` syntax; `build_context.sh` usage error documents `QUESTION_CATEGORY` and `FORCE_PROJECT_TREE`.
- **Known gap surfaced**: `_supports_ast_extraction` declares 13 languages (Python, JS, TS, Go, Rust, Java, C++, C, C#, Ruby, PHP, Swift) but `lib/code_optimizer.sh` has dedicated extractors for only 4 (Python, JS/TS, Bash, Go); the other 9 fall back to `_extract_generic` (grep-based). Documented in release note; tracked for future tree-sitter-backed extraction.
- **Backwards compat**: agents that still inline file contents into the query (pinned old slash commands) keep working — `build_context.sh` degrades to no-FILES branch, just without the optimization benefit. Direct bash users of `./scripts/consult_all.sh "q" file1 file2` get the same behavior plus the new optimization.

### v2.13.1
- **Perf**: XDG roots resolved once at first `config.sh` source and **exported** as `_AI_CONSULTANTS_XDG_{CACHE,STATE,DATA}` — child query subshells inherit the values and skip ~6 subshells/child × 14 children = ~84 forks per consultation (~200-400ms saving on macOS).
- **Perf**: `apply_launch_stagger()` switched from `awk "BEGIN{printf}"` to pure-bash `printf '%d.%03d'` — 14 forks eliminated per consultation (~50-70ms aggregate).
- **Perf/DRY**: `_count_available_consultants` entries pre-uppercased (`"GEMINI|ENABLE_GEMINI|gemini"`) — 15 `to_upper` subshells eliminated per `--suggest-preset` invocation. Also fixes the latent self-exclusion case-mismatch the round-2 review caught.
- **Latent bug fix**: 5 `lib/*.sh` files (`cache.sh`, `session.sh`, `api.sh`, `chunking.sh`, `costs.sh`) had hardcoded `/tmp/...` defaults that drifted from the v2.13 XDG migration. Their fallbacks now reference `${_AI_CONSULTANTS_XDG_*}` so they stay aligned even if sourced standalone (e.g. from a future test). `lib/session.sh::cleanup_old_sessions` no longer hardcodes `/tmp/ai_consultations` either — uses `$DEFAULT_OUTPUT_DIR_BASE`.
- **DRY**: extracted `scripts/lib/test_helpers.sh` (~80 LOC) — `assert_eq`, `assert_match`, `run_test`, `test_summary`, `_reset_state` hook. Eliminates the ~90 LOC of triplication across `test_user_config.sh`, `test_doctor.sh`, `test_bin.sh`. Future test suites just `source lib/test_helpers.sh`.
- **CI**: `scripts/test_all.sh` (master runner introduced post-v2.13.0) now also includes `test_suite.sh` — adds 258 library assertions to `npm test`, closing the "tests on disk but not gating CI" gap. Total: 6 suites, ~493 assertions.
- **Style**: 37 → 0 shellcheck warnings under the project exclusions (`-e SC2034,SC2086,SC1091,SC2155,SC2154`). Touches: `configure.sh` (26 SC2004 + 1 SC2129), `lib/routing.sh` (4 SC2004/2321), `lib/code_optimizer.sh` (2 SC2001 sed → param expansion), `lib/chunking.sh` (2 SC2001), `lib/voting.sh` (1 SC2126), `lib/common.sh` (1 SC2005, 1 SC2317 annotated), `lib/api_query.sh` (1 SC2317 annotated), `lib/symbol_map.sh` (2 SC1090 annotated), `config.sh` (1 SC2317 annotated), `test_set_e_safety.sh` (1 SC2001 annotated).
- **Code quality**: `consult_all.sh` `_MODEL` var resolution switched from inline `tr` to `to_upper()` helper for consistency. Stale `name_upper` variable in `_count_available_consultants` renamed to `name`. `find_user_config_file` redundant `|| echo ""` simplified to `|| true`.
- All 6 test suites pass (493 assertions). Zero behavioral change for end users; XDG cache export is the only new env-var contract.

### v2.13.0
- New `doctor --suggest-preset --question "..."` recommends a preset + strategy combo for a question, based on category classification (`classify_question.sh`) and the count of available consultants (gated by `ENABLE_*` flags and self-exclusion). Outputs a one-line `ai-consultants` command + reasoning, or structured JSON via `--json` for tooling/automation.
- Classifier failures now surface explicitly as `Warning: classification of your question failed` (with the underlying error). Pre-fix the failure was masked by `2>/dev/null` and silently degraded to `GENERAL`.
- `--suggest-preset` short-circuits to "install more CLIs" hint when fewer than 2 consultants are usable — previously could recommend e.g. `minimal` preset with 0 consultants.
- `_count_available_consultants()` now respects `ENABLE_*` flags and subtracts the invoking agent (self-exclusion). Pre-fix the count included disabled consultants, leading `_recommend_combo` boundaries to fire on a phantom panel size.
- `ENABLE_DEBATE_OPTIMIZATION` promoted from opt-in to default `true` based on operator experience over 4 stable releases — debate is auto-skipped when confidence spread < `DEBATE_CONFIDENCE_SPREAD_THRESHOLD` (default 2). SECURITY and ARCHITECTURE remain mandatory-debate. No empirical benchmark in-tree yet; tracked for v2.14.
- XDG Base Directory compliance for transient and persistent paths (per freedesktop.org spec):
  - `DEFAULT_OUTPUT_DIR_BASE`: `/tmp/ai_consultations` → `$XDG_CACHE_HOME/ai-consultants/consultations` (typically `~/.cache/...`)
  - `CACHE_DIR`: `/tmp/ai_consultants_cache` → `$XDG_CACHE_HOME/ai-consultants/cache`
  - `RATE_LIMIT_DIR`, `CHUNK_TEMP_DIR`: `/tmp/ai_consultants_*` → `$XDG_CACHE_HOME/ai-consultants/{ratelimit,chunks}`
  - `SESSION_DIR`: `/tmp/ai_consultants_sessions` → `$XDG_STATE_HOME/ai-consultants/sessions` (`~/.local/state/...`)
  - `COST_TRACKING_FILE`: `/tmp/ai_consultants_costs.json` → `$XDG_DATA_HOME/ai-consultants/costs.json` (`~/.local/share/...`)
  - All env vars still respected; restore old behavior with `export DEFAULT_OUTPUT_DIR_BASE=/tmp/ai_consultations` etc.
- New `lib/user_config.sh::get_xdg_dir()` helper — single source of truth for XDG resolution; falls back to `$HOME/.{cache,local/state,local/share}` then `/tmp/ai-consultants-{kind}` for distroless containers.
- README slimmed: env-var section now points to `references/configuration.md` for the full ~150-var list and recommends `ai-consultants init` as the primary onboarding path.
- `RATE_LIMIT_DIR` and `CHUNK_TEMP_DIR` lifted to `config.sh` for consistency (were lib-only defaults).
- `config.sh` now hard-fails with `FATAL: ... get_xdg_dir()` if `lib/user_config.sh` is missing — pre-fix the v2.13 XDG defaults silently regressed to `/tmp/ai_consultants/...` when the helper was absent (corrupt install, refactor regression).
- New `scripts/test_doctor.sh` — 25 assertions in 12 tests: `--suggest-preset` across categories (SECURITY, QUICK_SYNTAX, ARCHITECTURE, ALGORITHM, GENERAL), no-question default, long-question truncation, short-circuit behavior, **+ review fixes**: `--json` output schema, count<2 install hint, classifier failure warning, `config.sh` FATAL on missing helper, count respects ENABLE_* flags.
- `scripts/test_user_config.sh` extended to 38 assertions in 18 tests — added: `get_xdg_dir` cache/state/data resolution, fallback to `~/.{cache,local/state,local/share}`, distroless `/tmp/ai-consultants-*` fallback, invalid kind handling, `config.sh` XDG path defaults, explicit env var override precedence, `ENABLE_DEBATE_OPTIMIZATION=true` default assertion.
- Round-2 review fix: `_count_available_consultants` self-exclusion was dead code due to UPPERCASE vs MixedCase mismatch — counter compared `Claude` to `get_self_consultant_name`'s `CLAUDE`. Now uppercases the entry name via `to_upper`; `INVOKING_AGENT` correctly drops 1 from the count. Regression test added.
- Round-2 fix: `--suggest-preset --json` pre-flights `jq` with a clear error message instead of aborting under `set -e` with `command not found` (the main `check_dependencies` jq probe doesn't run when `--suggest-preset` short-circuits).
- Round-2 fix: `--json` schema gains `schema_version: 1` and `recommended_command` fields — tooling no longer has to reconstruct the invocation client-side and has a signal for future schema evolution.
- Round-2 fix: `_count_available_consultants` no longer hardcodes a "default-true" list that drifted from `config.sh` (claimed Aider default-true; actually false). Removed; relies solely on `config.sh` defaults via `${!flag:-false}`.
- New `scripts/test_all.sh` master runner aggregates all 5 standalone test suites; `npm test` wired in `package.json`. Closes the "tests on disk but not gating CI" gap from v2.11/v2.12 review carryovers.
- `scripts/test_doctor.sh` extended to 31 assertions: + self-exclusion regression, + jq preflight, + schema_version/recommended_command shape.

### v2.12.0
- New persistent user-config dir at `~/.config/ai-consultants/` (XDG-compliant; honors `AI_CONSULTANTS_CONFIG_DIR` and `XDG_CONFIG_HOME`)
- New `lib/user_config.sh` with `load_user_config()` — sourced from `config.sh` at the very top, before any defaults are applied
- `load_user_config` is **idempotent** via a process-wide guard `_AI_CONSULTANTS_USER_CONFIG_LOADED` — `config.sh` is sourced 15-30 times per consultation transitively, and without the guard non-idempotent user config (PATH appends, counters, log appends) would compound silently
- `.env` (KEY=value) and `config.sh` (full bash) both supported; existing env vars always win over user config (precedence: CLI > env > user config > defaults > hardcoded)
- `.env` parser **strips trailing CR** so Windows CR-LF line endings don't silently corrupt values (`ENABLE_DEBATE=true\r` would otherwise break every `[[ "$X" == "true" ]]` comparison downstream)
- New `ai-consultants init [--force]` subcommand scaffolds the user config dir with `.env` (copied from `.env.example`, chmod 600) and `config.sh` (minimal sourceable template); refuses to scaffold into a symlinked dir (root + hostile symlink protection); pre-flights write permission with a friendly error pointing to `AI_CONSULTANTS_CONFIG_DIR`
- `bin/ai-consultants` no longer hardcodes the version (was stuck at 2.10.0 since v2.10.0 release); reads `AI_CONSULTANTS_VERSION` from `scripts/config.sh` and **validates it as semver** — falls back to `vunknown` instead of `vAI_CONSULTANTS_VERSION=2.12.0` when the parse fails
- `get_user_config_dir` returns empty + exit 1 when both `HOME` and `XDG_CONFIG_HOME` are unset (e.g. distroless container) instead of computing the broken path `/.config/ai-consultants`; callers (`doctor.sh`, `bin/init`) handle this with a clear error
- Single source of truth for user-dir resolution: `lib/user_config.sh::get_user_config_dir()`; `routing.sh`, `doctor.sh`, and `bin/ai-consultants` now all source it instead of duplicating the precedence ladder (was DRY-violated 4x)
- `lib/routing.sh::_load_affinity_data` extended with search path: `AFFINITY_FILE` env > `~/.config/ai-consultants/affinity.json` > bundled default — drops a custom matrix in the user dir without setting any env var
- `doctor.sh` adds `check_user_config()` reporting dir presence, files loaded, and warns on `.env` lax permissions — total checks now 22
- New regression test `scripts/test_user_config.sh` — 20 assertions in 11 tests: .env loading + quote stripping, env precedence, edge cases (comments/blanks/`export`/quoted/indented), invalid keys, config.sh ordering, XDG fallback, missing-files silence (now also asserts no stderr output), AI_CONSULTANTS_CONFIG_DIR priority, **CR-LF stripping**, **idempotency guard**, **HOME-unset fallback**
- New `scripts/test_bin.sh` — 10 assertions in 8 tests covering `bin/ai-consultants version` (matches config.sh, semver-shaped, fallback to "unknown" on malformed config) and `init` (chmod 600 enforcement, both files created, idempotent without --force, --force overwrites, refuses symlinked dir)
- `scripts/test_routing_parity.sh` extended to 146 assertions (added user-dir branch of `_resolve_affinity_path`)

### v2.11.0
- Externalized routing affinity matrix from nested `case` statements in `lib/routing.sh` to `references/affinity.json` (~190 lines of bash → 60 lines of JSON)
- Custom matrix at runtime via `AFFINITY_FILE=/path/to/custom.json` (e.g. tweak scores per project, disable consultants by category)
- `get_affinity()` now performs JSON lookup with two-level cache: file content cached on first read, per-(category, consultant) result cached after first lookup
- Cache uses leading-space delimiter to prevent substring collisions (e.g. `DEBUG|X=` would have falsely matched a cached `BUG_DEBUG|X=10` — caught in review pass before release)
- `doctor.sh` adds 3 new checks for affinity: file presence, JSON schema validity, coverage (every consultant in every category) — total checks now 21
- Golden parity test in `scripts/test_routing_parity.sh`: 144 assertions covering all 9 categories × 14 consultants + edge cases (unknown consultant, unknown category, AFFINITY_FILE override, cache auto-invalidation, cache substring-collision regression)
- `docs/SMART_ROUTING.md` rewritten: removed stale per-consultant table (was out of sync with code since v2.8/v2.9/v2.10 added Amp, Kimi, MiniMax), now points to JSON as source of truth and documents schema + override
- `references/affinity.json` `_comment` documents the asymmetric 3-tier fallback (unknown consultant → 5, unknown category → 8, missing cell → 5) and the rationale
- Bug class regression test in `scripts/test_set_e_safety.sh`: static lint covers `((var++))` AND `((var--))` AND `let var++` family, plus dynamic check on bash 4+ for the abort pattern fixed in v2.8.1, v2.10.1, v2.10.9
- `consult_all.sh` ENABLE_PREFLIGHT path no longer swallows doctor output — the diagnostic is now captured to a tmpfile and dumped on failure (previously `>/dev/null 2>&1` repeated the original preflight silent-failure bug)
- Cleaned `((attempt++)) || true || true` artifacts in `lib/api.sh` (introduced by the v2.10.9 mechanical sweep on lines that were already protected)

### v2.10.9
- Fixed silent failure of `preflight_check.sh` under `set -euo pipefail`: helper functions like `check_cli_installed` returned non-zero on missing CLIs, and call sites lacked `|| true` — the script aborted after "Checking CLI installations..." with no diagnostic output
- Deprecated `preflight_check.sh` in favor of `doctor.sh` (stale v2.0 script covering only 6/15 consultants and missing CLI/API mode checks); `preflight_check.sh` is now a thin wrapper that prints a deprecation warning and execs `doctor.sh "$@"`
- Ported `--suggest-config` from preflight to `doctor.sh`, expanded coverage from 6 to 15 consultants (now also detects API-only consultants via API key presence)
- Added `--quick` flag to `doctor.sh` (accepted as no-op for backward compat with preflight)
- Updated `consult_all.sh` ENABLE_PREFLIGHT path to invoke `doctor.sh` directly
- Defensive sweep: protected 15 latent `((var++))` increments across `peer_review.sh`, `setup_wizard.sh`, `test_functions.sh`, `lib/api.sh`, `lib/common.sh`, `lib/reflection.sh`, and `doctor.sh` with `|| true` (matches v2.8.1/v2.10.1 codebase convention; latent because bash 3.2 doesn't abort but bash 4+ does)
- Fixed real shellcheck warnings: SC2059 unsafe printf format string in `lib/progress.sh`, SC2012 `ls | wc -l` race in `install.sh` (replaced with `find`), SC2329 false positive in `query_ollama.sh` cleanup trap (annotated), SC2016 intentional sed pattern in `peer_review.sh` (annotated)

### v2.10.8
- Fixed `docs/cost_rates.json` drift introduced by v2.10.6: `consultant_fallbacks` (used at runtime by `lib/costs.sh`) and `model_tiers` were still pointing at the old IDs (`opus-4.6`, `gpt-5.3-codex`, `composer-1.5`, `deepseek-reasoner`, `sonnet-4.6`, `haiku-4.5`)
- Added price entries for the v2.10.6 model IDs: `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5`, `gpt-5.5`, `composer-2`, `deepseek-v4-pro`, `nvidia/nemotron-3-super-120b-a12b:free`
- Moved superseded IDs to the legacy section so cost calculation still works for historical responses or pinned overrides
- Synced `COST_RATES.md` tables to match
- Pricing for `nvidia/nemotron-3-super-120b-a12b:free` set to $0/$0 (OpenRouter free tier)

### v2.10.7
- Grok premium upgraded from `grok-4.20-0309-reasoning` to `grok-4.3` (released 2026-04-30)
- ~75% cheaper input ($1.25/M vs $5.00/M) and ~83% cheaper output ($2.50/M vs $15.00/M)
- 1M-token context window
- Moved `grok-4.20-0309-reasoning` to legacy section in cost catalog
- Standard (`grok-3`) and economy (`grok-3-mini`) tiers unchanged

### v2.10.6
- Codex premium upgraded from `gpt-5.3-codex` to `gpt-5.5`
- Cursor premium upgraded from `composer-1.5` to `composer-2`
- Aider switched provider: `gpt-5.3-codex` → `nvidia/nemotron-3-super-120b-a12b:free` (free tier)
- DeepSeek premium upgraded from `deepseek-reasoner` to `deepseek-v4-pro`
- Claude IDs migrated from short aliases to canonical model IDs across all tiers: `opus-4.6` → `claude-opus-4-7`, `sonnet-4.6` → `claude-sonnet-4-6`, `haiku-4.5` → `claude-haiku-4-5`
- Fixed Kilo SIGPIPE abort under `set -euo pipefail` (replaced `head -c` with parameter expansion)

### v2.10.5
- Qwen3 premium model upgraded from `qwen3.5-plus` to `qwen3.6-plus` ($0.325/$1.95 per M tokens)
- Qwen3 standard tier now uses open-weight `qwen3.6-35b-a3b` (MoE, 35B total / 3B active)
- Refactored `get_economic_model()` to delegate to `get_model_for_tier()`, eliminating stale hardcoded mappings
- Moved `qwen3.5-plus` to legacy section in cost catalog
- Fixed `AI_CONSULTANTS_VERSION` in `config.sh` (was stuck at `2.10.0`)

### v2.10.4
- GLM premium/standard model upgraded from `glm-5` to `glm-5.1`
- Fixed Kilo CLI hanging indefinitely in non-TTY mode (query via stdin instead of CLI argument)
- Fixed Kilo CLI picking wrong provider when other consultants' API keys were in the environment
- Collapsed 5-stage ANSI stripping pipeline into single sed invocation in `query_kilo.sh`
- Fixed overly aggressive markdown fence filter in `query_kilo.sh` (only strips standalone ``` lines now)
- Updated `.env.example` GLM signup URL to `open.z.ai`

### v2.10.3
- Grok premium model upgraded to `grok-4.20-0309-reasoning` (replaces `grok-4-1-fast-reasoning`)
- GLM API endpoint migrated from `open.bigmodel.cn` to `api.z.ai/api/coding/paas/v4`
- Removed non-functional MiniMax highspeed models (`MiniMax-M2.7-highspeed`, `MiniMax-M2.5-highspeed`)
- Removed legacy `grok-beta` from cost catalog
- Fixed GLM URL fallback in `common.sh` and `configure.sh` (were still using old endpoint)
- Fixed duplicate `minimax-m2.5` entry with conflicting rates in `cost_rates.json`

### v2.10.2
- MiniMax M2.7 upgrade: premium/standard now use MiniMax-M2.7, economy uses MiniMax-M2.5
- Model tiers: premium (MiniMax-M2.7), standard (MiniMax-M2.7), economy (MiniMax-M2.5)

### v2.10.1
- Slash command quality improvements: file context handling, result presentation templates, error recovery guidance
- debate_round.sh hardening: Amp/Kimi/MiniMax case entries, `((count++)) || true` fixes, `*` default case, stderr to `.err` files, ROUND_NUMBER validation
- Token efficiency: SKILL.md trimmed (-17%), help.md slimmed (-77%), content moved to `references/details.md`
- Self-exclusion consistency in slash command descriptions

### v2.10.0
- MiniMax M2.5 API support via OpenAI-compatible endpoint
- New consultant: MiniMax with "The Pragmatic Optimizer" persona (ID: 21)
- New environment variables: `ENABLE_MINIMAX`, `MINIMAX_API_KEY`, `MINIMAX_MODEL`, `MINIMAX_API_URL`
- Model tiers: premium (MiniMax-M2.5), standard (MiniMax-M2.1), economy (MiniMax-M2.5)
- npx distribution: `npx ai-consultants "question"` (zero dependencies)
- New `bin/ai-consultants` wrapper with symlink resolution and subcommand routing
- Now supports 15 consultants total

### v2.9.1
- Fixed Gemini model names to use real API names
- Premium: `gemini-3.1-pro-preview`, Standard: `gemini-3-flash-preview`, Economy: `gemini-2.0-flash`

### v2.9.0
- Kimi CLI support via kimi-cli (`curl -L code.kimi.com/install.sh | bash`)
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
- `QWEN3_USE_API` defaults to `false` to use the qwen CLI by default
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
