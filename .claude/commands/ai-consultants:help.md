---
description: Show help and usage for AI Consultants skill
allowed-tools:
---

# AI Consultants - Help

AI Consultants is a multi-model AI deliberation system that queries multiple AI consultants simultaneously to get diverse perspectives on coding questions.

## Quick Start

```
/ai-consultants:consult "Your question here"
```

## How It Works

1. You ask a coding question
2. Multiple AI consultants respond in parallel with their unique perspectives
3. Responses are synthesized into a weighted recommendation with consensus summary

## Slash Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show this help |

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

## CLI Consultants

| Consultant | CLI | Default Persona | Focus |
|------------|-----|-----------------|-------|
| Gemini | `gemini` | The Architect | Design patterns, scalability |
| Codex | `codex` | The Pragmatist | Simplicity, proven solutions |
| Mistral | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| Kilo | `kilocode` | The Innovator | Creative approaches |
| Cursor | `agent` | The Integrator | Full-stack perspective |
| Aider | `aider` | The Pair Programmer | Collaborative coding |
| Amp | `amp` | The Systems Thinker | System design, interactions |
| Kimi | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| Claude | `claude` | The Synthesizer | Big picture, synthesis |
| Qwen | `qwen` | The Analyst | Data-driven analysis |
| Ollama | `ollama` | The Local Expert | Privacy-first, zero cost |

## API Consultants

| Consultant | Model | Default Persona | Focus |
|------------|-------|-----------------|-------|
| GLM | glm-5 | The Methodologist | Structured approaches |
| Grok | grok-4-1-fast-reasoning | The Provocateur | Challenge conventions |
| DeepSeek | deepseek-reasoner | The Code Specialist | Code generation, algorithms |
| MiniMax | MiniMax-M2.5 | The Pragmatic Optimizer | Performance, efficiency |

## Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick, cheap |
| `balanced` | 4 (+Mistral +Kilo) | Standard |
| `thorough` | 5 (+Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |

## Strategies

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
- Optional: API keys for API-based consultants (GLM, Grok, DeepSeek, MiniMax)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Unknown skill" | Run install script or restart Claude Code |
| "Exit code 1" | Run `./scripts/doctor.sh` to diagnose |
| No consultants | Install at least 2 CLI agents |
| API errors | Check API keys in `.env` |
| Configuration not saving | Check file permissions on `~/.claude/skills/` |

## More Info

See [README.md](https://github.com/matteoscurati/ai-consultants) for full documentation.
