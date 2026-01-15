# AI Consultants - Claude Code Instructions

## Project Overview

AI Consultants is a multi-model AI deliberation system that simultaneously queries 4 AI consultants (Gemini, Codex, Mistral Vibe, Kilo) to obtain diverse perspectives on coding problems.

## Structure

```
ai-consultants/
├── scripts/
│   ├── consult_all.sh          # Main orchestrator - entry point
│   ├── config.sh               # Centralized configuration
│   ├── query_*.sh              # Wrapper for each consultant
│   ├── synthesize.sh           # Auto-synthesis of responses
│   ├── debate_round.sh         # Multi-Agent Debate
│   ├── classify_question.sh    # Question classifier
│   ├── followup.sh             # Follow-up queries
│   ├── preflight_check.sh      # Health check
│   └── lib/
│       ├── common.sh           # Shared utilities (logging, etc.)
│       ├── personas.sh         # Consultant persona definitions
│       ├── schema.json         # JSON output schema
│       ├── voting.sh           # Voting/consensus algorithms
│       ├── routing.sh          # Smart routing
│       ├── session.sh          # Session management
│       ├── costs.sh            # Cost tracking
│       ├── progress.sh         # Progress bars
│       └── reflection.sh       # Self-reflection
└── templates/
    └── synthesis_prompt.md     # Synthesis prompt
```

## Claude Skills Compliance

**IMPORTANT**: This project is a Claude Skill and follows the open agentskills.io standard. When modifying this codebase, you MUST stay updated with and follow the official documentation.

### Official Documentation

**Anthropic Platform:**
- **Overview**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- **Best Practices**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- **Quickstart**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/quickstart
- **API Guide**: https://platform.claude.com/docs/en/build-with-claude/skills-guide

**Open Standard (agentskills.io):**
- **What Are Skills**: https://agentskills.io/what-are-skills
- **Specification**: https://agentskills.io/specification
- **Integration Guide**: https://agentskills.io/integrate-skills

### Cross-Platform Compatibility

Agent Skills is an open format supported by multiple tools:
- Claude Code, Claude.ai, Claude API
- Gemini CLI
- OpenAI Codex
- Cursor
- VS Code
- GitHub
- And others (Amp, Letta, Goose, OpenCode, Factory)

### Key Requirements (from official docs)

1. **SKILL.md Frontmatter**:
   - `name`: max 64 chars, lowercase letters/numbers/hyphens only, no XML tags, no reserved words ("anthropic", "claude")
   - `description`: max 1024 chars, non-empty, no XML tags, must include WHAT the skill does AND WHEN to use it
   - Write descriptions in third person (not "I can help you..." or "You can use this...")

2. **Progressive Disclosure** (3 levels):
   - Level 1 (Metadata): Only name/description loaded at startup (~100 tokens)
   - Level 2 (Instructions): SKILL.md body loaded when triggered (<5k tokens)
   - Level 3 (Resources): Additional files loaded as needed (unlimited)

3. **Conciseness**:
   - Keep SKILL.md body under 500 lines
   - Only add context Claude doesn't already have
   - Use progressive disclosure: reference separate files for detailed content

4. **File Organization**:
   - Keep references one level deep from SKILL.md
   - Use forward slashes in paths (Unix-style), never backslashes
   - Name files descriptively (`form_validation_rules.md`, not `doc2.md`)

5. **Scripts**:
   - Handle errors explicitly, don't punt to Claude
   - Document configuration parameters (no "voodoo constants")
   - Scripts are executed via bash, not loaded into context

6. **Testing**:
   - Test with all models (Haiku, Sonnet, Opus)
   - Create evaluations before writing extensive documentation

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
    "approach": "Approach name"
  },
  "confidence": {
    "score": 1-10,
    "reasoning": "Justification"
  }
}
```

## Main Flow

1. `consult_all.sh` receives query and optional files
2. Classifies the question (`classify_question.sh`)
3. Selects consultants (smart routing or all)
4. Launches parallel queries (`query_*.sh`)
5. Calculates voting/consensus (`lib/voting.sh`)
6. Generates synthesis (`synthesize.sh`)
7. Produces final report

## Testing

```bash
# Verify CLIs are installed
./scripts/preflight_check.sh

# Basic test
./scripts/consult_all.sh "How to optimize a SQL query?"

# Test with debate
ENABLE_DEBATE=true ./scripts/consult_all.sh "Microservices or monolith?"
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

## External Dependencies

- `gemini` CLI - Google Gemini
- `codex` CLI - OpenAI Codex
- `vibe` CLI - Mistral Vibe
- `kilocode` CLI - Kilo Code
- `jq` - JSON parsing
- `claude` CLI (optional) - For advanced synthesis

## Self-Reflection (Experimental)

The self-reflection feature implements the "generate-critique-refine" pattern:

```bash
# Enable reflection
ENABLE_REFLECTION=true
REFLECTION_CYCLES=2  # Number of critique-refine cycles
```

**Note**: This feature is implemented in `lib/reflection.sh` but not yet integrated into the main flow of `consult_all.sh`. To use it, manually import the functions.

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
```

## Extended Documentation

For detailed information, see:
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

## Changelog v2.0.0

- Personas for each consultant (The Architect, The Pragmatist, etc.)
- Confidence scoring 1-10 on every response
- Auto-synthesis with weighted recommendation
- Multi-Agent Debate with cross-critique
- Smart routing based on category
- Session management for follow-up
- Cost tracking and budget limits
- Interactive progress bars
