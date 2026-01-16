---
description: Show help and usage for AI Consultants skill
allowed-tools:
---

# AI Consultants - Help

AI Consultants is a multi-model AI deliberation system that queries multiple AI consultants simultaneously to get diverse perspectives on coding questions.

## Quick Start

```
/ai-consultants:config-wizard    # Initial setup
/ai-consultants:consult          # Ask a question
```

## How It Works

1. You ask a coding question
2. Multiple AI consultants respond in parallel with their unique perspectives
3. Responses are synthesized into a weighted recommendation with consensus summary

## Available Commands

AI Consultants provides 12 slash commands:

### Consultation Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Ask AI consultants a coding question |
| `/ai-consultants:ask-experts` | Quick query (alias for consult) |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show this help |

### Configuration Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:config-wizard` | Full setup wizard (CLI detection, API keys, personas) |
| `/ai-consultants:config-check` | Verify CLI agents are installed |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset (minimal, balanced, high-stakes, local) |
| `/ai-consultants:config-strategy` | Set default synthesis strategy (majority, risk_averse, etc.) |
| `/ai-consultants:config-features` | Toggle features (Debate, Synthesis, Peer Review, etc.) |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API-based consultants (Qwen3, GLM, Grok, DeepSeek) |

## Configuration Workflow

Set up your preferences using slash commands:

```
/ai-consultants:config-preset       # Choose: minimal, balanced, high-stakes, local
/ai-consultants:config-strategy     # Choose: majority, risk_averse, security_first
/ai-consultants:config-features     # Toggle: debate, synthesis, peer review
/ai-consultants:config-status       # View your current settings
```

All settings are saved to `~/.claude/skills/ai-consultants/.env`.

## CLI Consultants

| Consultant | CLI | Default Persona | Focus |
|------------|-----|-----------------|-------|
| Gemini | `gemini` | The Architect | Design patterns, scalability |
| Codex | `codex` | The Pragmatist | Simplicity, proven solutions |
| Mistral | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| Kilo | `kilocode` | The Innovator | Creative approaches |
| Cursor | `agent` | The Integrator | Full-stack perspective |
| Aider | `aider` | The Pair Programmer | Collaborative coding |
| Ollama | `ollama` | The Local Expert | Privacy-first, zero cost |

## API Consultants

| Consultant | Model | Default Persona | Focus |
|------------|-------|-----------------|-------|
| Qwen3 | qwen-max | The Analyst | Data-driven analysis |
| GLM | glm-4 | The Methodologist | Structured approaches |
| Grok | grok-beta | The Provocateur | Challenge conventions |
| DeepSeek | deepseek-coder | The Code Specialist | Code generation, algorithms |

## Presets (v2.2)

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick, cheap |
| `balanced` | 4 (+Mistral +Kilo) | Standard |
| `thorough` | 5 (+Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |

## Strategies (v2.2)

| Strategy | Description |
|----------|-------------|
| `majority` | Most common answer wins (default) |
| `risk_averse` | Weight conservative responses |
| `security_first` | Prioritize security |
| `compare_only` | No recommendation |

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

## Examples

```
/ai-consultants:consult "How to optimize this SQL query?"
/ai-consultants:consult "Review this code" src/utils.ts
/ai-consultants:debate "Microservices vs monolith?"
```

## Requirements

- At least 2 CLI agents installed (Gemini, Codex, Mistral, Kilo, Cursor, Aider, or Ollama)
- `jq` for JSON processing
- Optional: `claude` CLI for synthesis
- Optional: API keys for API-based consultants (Qwen3, GLM, Grok, DeepSeek)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Unknown skill" | Run install script or restart Claude Code |
| "Exit code 1" | Run `/ai-consultants:config-check` to diagnose |
| No consultants | Run `/ai-consultants:config-wizard` |
| API errors | Check `/ai-consultants:config-status` |
| Configuration not saving | Check file permissions on `~/.claude/skills/` |

## More Info

See [README.md](https://github.com/matteoscurati/ai-consultants) for full documentation.
