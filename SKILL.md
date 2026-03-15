---
name: ai-consultants
description: Consult Gemini CLI, Codex CLI, Mistral Vibe, Kilo CLI, Cursor, Claude, Amp, Kimi, Qwen, MiniMax, and Ollama as external experts for coding questions. Automatically excludes the invoking agent from the panel to avoid self-consultation. Use when you have doubts about implementations, want a second opinion, need to choose between different approaches, or when explicitly requested with phrases like "ask the consultants", "what do the other models think", "compare solutions", "get expert opinions", "I'm not sure about this approach", "what would other models say". Make sure to consult this skill whenever the user is weighing trade-offs, comparing architectures, validating complex solutions, or wants multiple perspectives on any non-trivial coding decision. Do NOT use for simple questions that only need one model's answer or when you already have high confidence in a solution.
license: MIT
compatibility: Requires bash, jq, and at least 2 AI CLI tools (gemini, codex, vibe, etc.). macOS and Linux.
metadata:
  author: matteoscurati
  version: 2.10.0
---

# AI Consultants v2.10.0 - AI Expert Panel

Simultaneously consult multiple AIs as "consultants" for coding questions. Each consultant has a **configurable persona** that influences their response style.

## Quick Start

```
/ai-consultants:consult "Your question here"
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show all commands and usage |

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

## Consultants and Personas

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `gemini` | The Architect | Design patterns, scalability |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| **Kilo Code** | `kilocode` | The Innovator | Creativity, unconventional |
| **Cursor** | `agent` | The Integrator | Full-stack perspective |
| **Aider** | `aider` | The Pair Programmer | Collaborative coding |
| **Amp** | `amp` | The Systems Thinker | System design, interactions |
| **Kimi** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis |
| **Qwen** | `qwen` | The Analyst | Data-driven, metrics |
| **Ollama** | `ollama` | The Local Expert | Privacy-first, zero cost |

**API-only consultants**: GLM (The Methodologist), Grok (The Provocateur), DeepSeek (The Code Specialist), MiniMax (The Pragmatic Optimizer)

**CLI/API Mode**: Gemini, Codex, Claude, Mistral, and Qwen can switch between CLI and API mode via `*_USE_API` environment variables.

**Self-Exclusion**: The invoking agent is automatically excluded from the panel. When invoked from Claude Code, Claude is excluded; when invoked from Codex CLI, Codex is excluded, etc.

## Requirements

- **At least 2 consultant CLIs** installed and authenticated
- **jq** for JSON processing

### Quick Install

```bash
# Option A: npx (recommended, no install needed)
npx ai-consultants doctor --fix
npx ai-consultants install  # Install slash commands for Claude Code

# Option B: curl | bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
```

For detailed CLI installation instructions, see [Setup Guide](docs/SETUP.md).

## Usage Examples

```
/ai-consultants:consult "How to optimize this SQL query?"
/ai-consultants:consult "Review this authentication flow" src/auth.ts
/ai-consultants:debate "Microservices or monolith for our new service?"
```

Presets: `minimal`, `balanced`, `thorough`, `high-stakes`, `local`, `security`, `cost-capped`. Strategies: `majority`, `risk_averse`, `security_first`, `cost_capped`, `compare_only`. See [Reference Details](references/details.md) for full tables, bash usage, and best practices.

## Workflow

Query is classified, then sent to consultants in parallel. Responses are scored, voted on, and synthesized into a recommendation. With debate enabled, consultants cross-critique before final synthesis.

## Features

| Feature | Description | Toggle |
|---------|-------------|--------|
| **Personas** | Each consultant has a role that shapes responses | `ENABLE_PERSONA` |
| **Synthesis** | Auto-combine responses into recommendation | `ENABLE_SYNTHESIS` |
| **Debate** | Consultants critique each other's answers | `ENABLE_DEBATE` |
| **Peer Review** | Consultants anonymously rank each other | `ENABLE_PEER_REVIEW` |
| **Smart Routing** | Auto-select best consultants per question type | `ENABLE_SMART_ROUTING` |
| **Cost Tracking** | Track API usage costs | `ENABLE_COST_TRACKING` |
| **Panic Mode** | Auto-add rigor when uncertainty detected | `ENABLE_PANIC_MODE` |

## Configuration

All settings use environment variables. Key toggles:

```bash
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_PANIC_MODE=auto       # Auto-rigor for uncertainty
ENABLE_BUDGET_LIMIT=false    # Budget enforcement (v2.4)
```

Enable opt-in consultants: `ENABLE_AMP`, `ENABLE_KIMI`, `ENABLE_QWEN3`, `ENABLE_CLAUDE`, `ENABLE_OLLAMA`, `ENABLE_MINIMAX`.

CLI/API switching: `GEMINI_USE_API`, `CODEX_USE_API`, `CLAUDE_USE_API`, `MISTRAL_USE_API`, `QWEN3_USE_API`.

See [Full Configuration Reference](references/configuration.md) for all variables, model overrides, tiers, timeouts, and optimization settings.

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

## Interpreting Results

| Scenario | Recommendation |
|----------|----------------|
| High confidence + High consensus | Proceed confidently |
| Low confidence OR Low consensus | Consider more options |
| Mistral disagrees | Investigate risks |
| Panic mode triggered | Add debate rounds |

## Troubleshooting

Run `./scripts/doctor.sh` to diagnose issues, or `./scripts/doctor.sh --fix` to auto-fix.

## Extended Documentation

- [Reference Details](references/details.md) - Presets, strategies, best practices, limitations
- [Full Configuration](references/configuration.md) - All environment variables, models, tiers, timeouts
- [Setup Guide](docs/SETUP.md) - Installation, authentication
- [Cost Rates](docs/COST_RATES.md) - Model pricing
- [Smart Routing](docs/SMART_ROUTING.md) - Category routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format
