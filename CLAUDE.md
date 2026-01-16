# AI Consultants - Claude Code Instructions

## Project Overview

AI Consultants is a multi-model AI deliberation system that queries up to 11 AI consultants (Gemini, Codex, Mistral, Kilo, Cursor, Aider, Qwen3, GLM, Grok, DeepSeek, Ollama) to obtain diverse perspectives on coding problems.

**Version**: 2.2.0

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
│       ├── routing.sh          # Smart routing
│       ├── session.sh          # Session management
│       ├── costs.sh            # Cost tracking
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

## External Dependencies

- `gemini` CLI - Google Gemini
- `codex` CLI - OpenAI Codex
- `vibe` CLI - Mistral Vibe
- `kilocode` CLI - Kilo Code
- `agent` CLI - Cursor
- `aider` CLI - Aider
- `ollama` CLI - Local models (v2.2)
- `jq` - JSON parsing
- `claude` CLI (optional) - For advanced synthesis

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

### v2.2.0
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
