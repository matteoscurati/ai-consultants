---
name: ai-consultants
description: Consult Gemini CLI, Codex CLI, Mistral Vibe, Kilo CLI, Cursor, and Ollama as external experts for coding questions. Use when you have doubts about implementations, want a second opinion, need to choose between different approaches, or when explicitly requested with phrases like "ask the consultants", "what do the other models think", "compare solutions", "ask Gemini/Codex/Mistral/Kilo", "chiedi ai consulenti", "cosa ne pensano gli altri modelli".
---

# AI Consultants v2.2 - AI Expert Panel

Simultaneously consult multiple AIs as "consultants" for coding questions. Each consultant has a **configurable persona** that influences their response style.

## What's New in v2.2

- **Configuration Presets**: `--preset minimal/balanced/high-stakes/local`
- **Doctor Command**: `./scripts/doctor.sh --fix` to diagnose and auto-fix
- **Synthesis Strategies**: `--strategy majority/risk_averse/security_first/compare_only`
- **Anonymous Peer Review**: Consultants evaluate each other without bias
- **Ollama Support**: Local models for privacy (zero API cost)
- **Panic Mode**: Auto-triggers rigor when uncertainty detected
- **Confidence Intervals**: Statistical ranges like "8 ± 1.2"

## Consultants and Personas

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `gemini` | The Architect | Design patterns, scalability |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| **Kilo Code** | `kilocode` | The Innovator | Creativity, unconventional |
| **Cursor** | `agent` | The Integrator | Full-stack perspective |
| **Ollama** | `ollama` | The Local Expert | Privacy-first, zero cost |

## Requirements

- **At least 2 consultant CLIs** installed and authenticated
- **jq** for JSON processing

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
```

### CLI Installation

```bash
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
npm install -g @kilocode/cli           # Kilo
brew install jq                        # Required

# For local inference (optional)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2
```

## Quick Start (Claude Code)

```
# Verify installation
/ai-consultants:config-check

# Basic consultation
/ai-consultants:consult "How to optimize this function?"

# With debate mode
/ai-consultants:debate "Microservices or monolith?"
```

## Quick Start (Bash)

```bash
cd ~/.claude/skills/ai-consultants

# With preset (recommended)
./scripts/consult_all.sh --preset balanced "Best approach for caching?"

# With strategy
./scripts/consult_all.sh --strategy risk_averse "Security question"

# With local model
./scripts/consult_all.sh --preset local "Private question"
```

## Configuration Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions |
| `balanced` | 4 (+ Mistral + Kilo) | Standard use |
| `thorough` | 5 (+ Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |

```bash
./scripts/consult_all.sh --preset high-stakes "Critical choice"
```

## Synthesis Strategies

| Strategy | Description |
|----------|-------------|
| `majority` | Most common answer wins (default) |
| `risk_averse` | Weight conservative responses |
| `security_first` | Prioritize security |
| `compare_only` | No recommendation |

```bash
./scripts/consult_all.sh --strategy security_first "Auth implementation"
```

## Claude Code Slash Commands

### Usage Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation |
| `/ai-consultants:ask-experts` | Quick query |
| `/ai-consultants:debate` | With multi-round debate |

### Configuration Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:config-check` | Verify CLIs installed |
| `/ai-consultants:config-status` | View configuration |
| `/ai-consultants:config-wizard` | Interactive setup |
| `/ai-consultants:config-preset` | Set default preset |
| `/ai-consultants:config-strategy` | Set synthesis strategy |
| `/ai-consultants:config-features` | Toggle features |
| `/ai-consultants:config-personas` | Change personas |
| `/ai-consultants:config-api` | Add API consultants |

## Workflow

```
Query → Classify → Parallel Queries → Voting → Synthesis → Report
                        ↓                ↓           ↓
                   Gemini (8)      Consensus    Recommendation
                   Codex (7)       Analysis     Comparison
                   Mistral (6)                  Risk Assessment
```

With debate:
```
Round 1 → Cross-Critique → Round 2 → Final Synthesis
```

## Usage Triggers

### Automatic
- Doubts about implementation approach
- Validating complex solutions
- Exploring architectural alternatives

### Explicit
- "Ask the consultants..."
- "What do the other models think?"
- "Compare solutions"
- "I want a second opinion"

## Configuration

```bash
# Defaults (v2.2)
DEFAULT_PRESET=balanced      # Preset when --preset not given
DEFAULT_STRATEGY=majority    # Strategy when --strategy not given

# Core features
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_PEER_REVIEW=false     # Anonymous peer review
ENABLE_PANIC_MODE=auto       # Auto-rigor for uncertainty

# Ollama (local models)
ENABLE_OLLAMA=true
OLLAMA_MODEL=llama3.2
OLLAMA_HOST=http://localhost:11434

# Cost management
MAX_SESSION_COST=1.00
```

## Output

```
/tmp/ai_consultations/TIMESTAMP/
├── gemini.json        # Individual responses
├── codex.json
├── voting.json        # Consensus
├── synthesis.json     # Recommendation
└── report.md          # Human-readable
```

## Doctor Command

Diagnose and fix issues:

```bash
./scripts/doctor.sh              # Full check
./scripts/doctor.sh --fix        # Auto-fix
./scripts/doctor.sh --json       # JSON output
```

## Peer Review

Run anonymous peer review after consultation:

```bash
./scripts/peer_review.sh /tmp/ai_consultations/latest /tmp/peer_review
```

## Consensus and Voting

```
100%    Unanimous - All agree
75-99%  High - 3+ agree
50-74%  Medium - Partial agreement
25-49%  Low - Strong disagreement
0-24%   None - No convergence
```

## Interpreting Results

| Scenario | Recommendation |
|----------|----------------|
| High confidence + High consensus | Proceed confidently |
| Low confidence OR Low consensus | Consider more options |
| Mistral disagrees | Investigate risks |
| Panic mode triggered | Add debate rounds |

## Best Practices

### Security
- **Never** include credentials in queries
- Use `--preset local` for sensitive code

### Effective Queries
- Be specific about the question
- Include constraints (performance, etc.)
- Use debate for controversial decisions

## Troubleshooting

### CLI not found
```bash
./scripts/doctor.sh --fix
```

### Synthesis not working
Claude CLI required. Fallback available but less accurate.

### High costs
```bash
./scripts/consult_all.sh --preset minimal "Quick question"
```

## Extended Documentation

- [Setup Guide](docs/SETUP.md) - Installation and auth
- [Cost Rates](docs/COST_RATES.md) - Model pricing
- [Smart Routing](docs/SMART_ROUTING.md) - Category routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format

## Known Limitations

- Minimum 2 consultants required
- Smart Routing off by default
- Synthesis requires Claude CLI (fallback available)
- Estimated costs (heuristic token counting)
