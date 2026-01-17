# AI Consultants - Claude Code Instructions

## Project Overview

AI Consultants is a multi-model AI deliberation system that queries up to 12 AI consultants (Gemini, Codex, Mistral, Kilo, Cursor, Aider, Claude, Qwen3, GLM, Grok, DeepSeek, Ollama) to obtain diverse perspectives on coding problems.

**Self-Exclusion**: The invoking agent is automatically excluded from the panel to prevent self-consultation. Claude Code won't query Claude, Codex CLI won't query Codex, etc.

**Version**: 2.3.0

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
- `OLLAMA_MODEL` - Model to use (default: llama3.2)
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
| `OLLAMA_MODEL` | llama3.2 | Ollama model (v2.2) |
| `SYNTHESIS_STRATEGY` | majority | Synthesis strategy (v2.2) |
| `ENABLE_SEMANTIC_CACHE` | true | Semantic response caching (v2.3) |
| `CACHE_TTL_HOURS` | 24 | Cache expiration in hours (v2.3) |
| `ENABLE_RESPONSE_LIMITS` | false | Response token limits (v2.3, opt-in) |
| `ENABLE_COST_AWARE_ROUTING` | false | Cost-based model routing (v2.3) |
| `ENABLE_DEBATE_OPTIMIZATION` | false | Skip debate if all agree (v2.3, opt-in) |
| `ENABLE_COMPACT_REPORT` | true | Compact report format (v2.3) |

## External Dependencies

- `gemini` CLI - Google Gemini
- `codex` CLI - OpenAI Codex
- `vibe` CLI - Mistral Vibe
- `kilocode` CLI - Kilo Code
- `agent` CLI - Cursor
- `aider` CLI - Aider
- `claude` CLI - Claude (v2.2, also used for synthesis)
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
