---
name: ai-consultants
description: Consult Gemini CLI, Codex CLI, Mistral Vibe, and Kilo CLI as external experts for coding questions. Use when you have doubts about implementations, want a second opinion, need to choose between different approaches, or when explicitly requested with phrases like "ask the consultants", "what do the other models think", "compare solutions", "ask Gemini/Codex/Mistral/Kilo".
---

# AI Consultants v2.0 - AI Expert Panel

Simultaneously consult four AIs as "consultants" for coding questions. Each consultant has a **unique persona** that influences their response style.

## What's New in v2.0

- **Personas**: Each consultant has a specific role (Architect, Pragmatist, Devil's Advocate, Innovator)
- **Confidence Scoring**: Each response includes a confidence score from 1-10
- **Auto-Synthesis**: Automatic synthesis of responses with weighted recommendation
- **Multi-Agent Debate (MAD)**: Deliberation rounds where consultants critique each other
- **Smart Routing**: Automatic selection of best consultants for question type
- **Session Management**: Follow-up and continuity between consultations
- **Cost Tracking**: Cost estimation and tracking

## Consultants and Personas

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `gemini` | The Architect | Design patterns, scalability, enterprise |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, quick wins, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Problems, edge cases, vulnerabilities |
| **Kilo Code** | `kilocode` | The Innovator | Creativity, unconventional approaches |

## Requirements

### Minimum Setup

- **At least 2 consultant CLIs** must be installed and authenticated
- **jq** is required for JSON processing

### CLI Installation

```bash
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
npm install -g @kilocode/cli           # Kilo
brew install jq                        # Required
```

### Authentication

Each CLI requires its own API key or authentication:

| CLI | Auth Method | Get API Key |
|-----|-------------|-------------|
| Gemini | `gemini auth login` or `GOOGLE_API_KEY` | [Google AI Studio](https://makersuite.google.com/app/apikey) |
| Codex | `OPENAI_API_KEY` env var | [OpenAI Platform](https://platform.openai.com/api-keys) |
| Mistral | `MISTRAL_API_KEY` env var | [Mistral Console](https://console.mistral.ai/api-keys/) |
| Kilo | `kilocode auth login` | CLI auth flow |

### Setup Wizard

Run the interactive setup wizard to auto-detect and configure:

```bash
./scripts/setup_wizard.sh
```

For detailed setup instructions, see [docs/SETUP.md](docs/SETUP.md).

### Partial Setup

If you don't have all CLIs, disable unavailable consultants:

```bash
# Example: Only OpenAI + Google configured
ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=false ENABLE_KILO=false \
./scripts/consult_all.sh "Your question"
```

## Quick Start

```bash
# Basic usage: question + optional files
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# Multiple context files
./scripts/consult_all.sh "Better to use Redis or Memcached for this case?" src/cache.py src/config.py

# With multi-round debate (consultants critique each other)
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "Best architecture?"

# With smart routing (selects best consultants for the question)
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh "Bug in my auth code"
```

## Workflow v2.0

```
Query → [Classify] → [Parallel Round 1] → [Debate Round 2] → [Synthesis] → Report
              ↓              ↓                    ↓                ↓
         ARCHITECTURE    Gemini (8)           Cross-critique    Recommendation
         BUG_DEBUG       Codex (7)            Position updates  Comparison table
         SECURITY        Mistral (6)          Critiques         Risk assessment
         ...             Kilo (9)             Final stance      Action items
```

## Usage Triggers

### Automatic Triggers
- Doubts about which implementation approach is better
- Validating a complex solution before applying it
- Exploring architectural or design alternatives
- Debugging complex problems

### Explicit Triggers
- "Ask the consultants..."
- "What do the other models think?"
- "Compare solutions"
- "Ask Gemini/Codex/Mistral/Kilo"
- "I want a second opinion"

## Advanced Configuration

Modify `scripts/config.sh` or use environment variables:

```bash
# === Personas and Synthesis ===
ENABLE_PERSONA=true           # Enable personas (default: true)
ENABLE_SYNTHESIS=true         # Enable auto-synthesis (default: true)

# === Multi-Agent Debate ===
ENABLE_DEBATE=false           # Enable debate (default: false)
DEBATE_ROUNDS=2               # Number of rounds (1-3)

# === Smart Routing ===
ENABLE_CLASSIFICATION=true    # Classify questions (default: true)
ENABLE_SMART_ROUTING=false    # Intelligent routing (default: false)
MIN_AFFINITY=7                # Minimum consultant affinity (1-10)

# === Cost Management ===
ENABLE_COST_TRACKING=true     # Track costs (default: true)
MAX_SESSION_COST=1.00         # Max budget per session ($)
WARN_AT_COST=0.50             # Warning threshold ($)

# === Session Management ===
SESSION_DIR=/tmp/ai_consultants_sessions

# === Consultants ===
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KILO=true

# === Timeout and Retry ===
GEMINI_TIMEOUT=180
MAX_RETRIES=2
```

## Output v2.0

Each consultation generates:

```
/tmp/ai_consultations/TIMESTAMP/
├── context.md         # Automatically generated context
├── gemini.json        # Gemini response (with confidence)
├── codex.json         # Codex response (with confidence)
├── mistral.json       # Mistral response (with confidence)
├── kilo.json          # Kilo response (with confidence)
├── voting.json        # Voting and consensus results
├── synthesis.json     # Automatic synthesis (NEW)
├── report.md          # Combined report with recommendation
└── round_2/           # (if ENABLE_DEBATE) Debate responses
```

### JSON Response Schema

```json
{
  "consultant": "Gemini",
  "model": "gemini-2.5-pro",
  "persona": "The Architect",
  "response": {
    "summary": "TL;DR in 2-3 sentences",
    "detailed": "Complete response",
    "approach": "Event-Driven Architecture",
    "pros": ["scalability", "decoupling"],
    "cons": ["complexity", "eventual consistency"],
    "caveats": ["requires message broker"]
  },
  "confidence": {
    "score": 8,
    "reasoning": "High experience with this pattern",
    "uncertainty_factors": ["depends on traffic volume"]
  },
  "metadata": {
    "tokens_used": 1234,
    "latency_ms": 5600,
    "timestamp": "2026-01-14T10:30:00Z"
  }
}
```

## Follow-up

After a consultation, you can do follow-ups:

```bash
# Follow-up to all consultants
./scripts/followup.sh "Elaborate on the architecture point"

# Follow-up to a specific consultant
./scripts/followup.sh -c Gemini "Can you provide a code example?"

# Request clarification on disagreements
./scripts/followup.sh --clarify "Why do Codex and Mistral disagree?"
```

## Pre-flight Check

Verify that all consultants are ready:

```bash
# Full check
./scripts/preflight_check.sh

# Quick check (CLI only, no API)
./scripts/preflight_check.sh --quick

# JSON output
./scripts/preflight_check.sh --json
```

## Question Categories

The system automatically classifies questions:

| Category | Best Consultants | Timeout |
|-----------|------------------|---------|
| CODE_REVIEW | Codex, Kilo, Mistral | 180s |
| BUG_DEBUG | Codex, Mistral | 180s |
| ARCHITECTURE | Gemini, Kilo | 240s |
| SECURITY | All (critical) | 240s |
| QUICK_SYNTAX | Gemini (only) | 60s |
| ALGORITHM | Gemini, Codex | 180s |
| DATABASE | Codex, Gemini | 120s |
| TESTING | Codex, Mistral | 120s |

## Consensus and Voting

The system automatically calculates:

- **Consensus Score**: 0-100% (how many consultants agree)
- **Confidence-Weighted Vote**: Recommendation weighted by confidence
- **Approach Groups**: Grouping by similar approach

```
100%    Unanimous - All agree
75-99%  High - 3+ agree
50-74%  Medium - 2 vs 2 or partial agreement
25-49%  Low - Strong disagreement
0-24%   None - No convergence
```

## Practical Examples

### 1. Code Review with Devil's Advocate

```bash
./scripts/consult_all.sh \
  "Review this code. Find all problems." \
  src/auth.py
```

Mistral (The Devil's Advocate) will actively look for vulnerabilities and edge cases.

### 2. Architectural Choice with Debate

```bash
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh \
  "Microservices or monolith for this project?" \
  src/services/ architecture.md
```

The consultants will critique each other and refine their positions.

### 3. Debug with Smart Routing

```bash
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh \
  "Intermittent memory leak, heap grows 50MB/hour" \
  src/cache.py
```

The system will select Codex (The Pragmatist) as the primary consultant for debugging.

## Best Practices v2.0

### Security
- **NEVER** include credentials, API keys, or sensitive data
- Review context before sending it
- Files in `/tmp` are cleaned automatically

### Effective Queries
- Be specific about the question
- Include constraints (performance, compatibility, etc.)
- Provide only relevant files
- Use debate for controversial decisions

### Interpreting Results
- **High confidence + High consensus**: Proceed with confidence
- **Low confidence OR Low consensus**: Consider more options
- **Mistral disagrees**: Investigate identified risks
- **Kilo proposes alternative**: Evaluate innovation vs risk

## Troubleshooting

### CLI not found

```bash
# Verify installation
./scripts/preflight_check.sh

# Install if missing
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral Vibe
npm install -g @kilocode/cli           # Kilo
brew install jq                        # Required for JSON
```

### Synthesis not working

Auto-synthesis requires `claude` CLI. If not available, a local fallback is used.

```bash
# Verify claude
which claude

# Disable synthesis if problematic
ENABLE_SYNTHESIS=false ./scripts/consult_all.sh "Query"
```

### High costs

```bash
# Limit consultants
ENABLE_SMART_ROUTING=true MIN_AFFINITY=9 ./scripts/consult_all.sh "Query"

# Quick questions only
ENABLE_GEMINI=true ENABLE_CODEX=false ENABLE_MISTRAL=false ENABLE_KILO=false \
  ./scripts/consult_all.sh "Quick syntax question"
```

## Skill Structure

```
~/.claude/skills/ai-consultants/
├── SKILL.md                    # This documentation
├── scripts/
│   ├── config.sh               # Centralized configuration
│   ├── lib/
│   │   ├── common.sh           # Shared functions
│   │   ├── personas.sh         # Persona definitions (NEW)
│   │   ├── schema.json         # JSON output schema (NEW)
│   │   ├── voting.sh           # Confidence-weighted voting (NEW)
│   │   ├── routing.sh          # Smart routing (NEW)
│   │   ├── progress.sh         # Progress bars (NEW)
│   │   ├── session.sh          # Session management (NEW)
│   │   ├── costs.sh            # Cost tracking (NEW)
│   │   └── reflection.sh       # Self-reflection (NEW)
│   ├── consult_all.sh          # Main script (UPDATED)
│   ├── preflight_check.sh      # Health check (NEW)
│   ├── classify_question.sh    # Question classifier (NEW)
│   ├── synthesize.sh           # Auto-synthesis (NEW)
│   ├── debate_round.sh         # MAD implementation (NEW)
│   ├── followup.sh             # Follow-up queries (NEW)
│   ├── build_context.sh        # Context builder
│   ├── query_gemini.sh         # Gemini wrapper (UPDATED)
│   ├── query_codex.sh          # Codex wrapper (UPDATED)
│   ├── query_mistral.sh        # Mistral wrapper (UPDATED)
│   └── query_kilo.sh           # Kilo wrapper (UPDATED)
└── templates/
    ├── consultation_report.md  # Report template
    └── synthesis_prompt.md     # Synthesis prompt (NEW)
```

## Changelog v2.0

### New Features
- Personas for each consultant
- Confidence scoring (1-10) on each response
- Auto-synthesis with weighted recommendation
- Multi-Agent Debate (MAD) with cross-critique
- Smart routing based on question category
- Session management for follow-ups
- Cost tracking and budget limits
- Pre-flight health checks
- Interactive progress bars

### Improvements
- Structured and consistent JSON output
- Report with pre-compiled automatic synthesis
- Automatic consensus score
- Confidence-weighted voting

### Breaking Changes
- Output files now in JSON format (no longer TXT for some consultants)
- Report includes Synthesis section instead of empty template

## Known Limitations

- **Minimum 2 consultants required**: At least 2 CLIs must be installed and authenticated for comparison
- **Self-Reflection not integrated**: `lib/reflection.sh` is implemented but not yet used by the main flow
- **Smart Routing off by default**: Requires explicit `ENABLE_SMART_ROUTING=true`
- **Synthesis requires Claude CLI**: Local fallback available but less accurate
- **Estimated costs**: Token counting is heuristic (4 chars = 1 token)

## Extended Documentation

For in-depth technical details:

- [docs/SETUP.md](docs/SETUP.md) - CLI installation and authentication guide
- [docs/COST_RATES.md](docs/COST_RATES.md) - Model rates and budget management
- [docs/SMART_ROUTING.md](docs/SMART_ROUTING.md) - Complete affinity matrix
- [docs/JSON_SCHEMA.md](docs/JSON_SCHEMA.md) - Output schema and validation
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guide
