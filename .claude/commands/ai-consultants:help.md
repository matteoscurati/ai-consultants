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

### Main Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Ask AI consultants a coding question (alias: `ask-experts`) |
| `/ai-consultants:debate` | Run consultation with multi-round debate |

### Configuration Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:config-wizard` | Full setup wizard (CLI detection, API keys, personas) |
| `/ai-consultants:config-check` | Verify CLI agents are installed |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset (minimal, balanced, high-stakes) |
| `/ai-consultants:config-strategy` | Set default synthesis strategy |
| `/ai-consultants:config-features` | Toggle features (Debate, Synthesis, Peer Review, etc.) |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API-based consultants (Qwen3, GLM, Grok, DeepSeek) |
| `/ai-consultants:help` | Show this help |

## CLI Consultants

| Consultant | CLI | Default Persona | Focus |
|------------|-----|-----------------|-------|
| Gemini | `gemini` | The Architect | Design patterns, scalability |
| Codex | `codex` | The Pragmatist | Simplicity, proven solutions |
| Mistral | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| Kilo | `kilocode` | The Innovator | Creative approaches |
| Cursor | `agent` | The Integrator | Full-stack perspective |
| Aider | `aider` | The Pair Programmer | Collaborative coding |

## API Consultants

| Consultant | Model | Default Persona | Focus |
|------------|-------|-----------------|-------|
| Qwen3 | qwen-max | The Analyst | Data-driven analysis |
| GLM | glm-4 | The Methodologist | Structured approaches |
| Grok | grok-beta | The Provocateur | Challenge conventions |
| DeepSeek | deepseek-coder | The Code Specialist | Code generation, algorithms |

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

- At least 2 CLI agents installed (Gemini, Codex, Mistral, Kilo, Cursor, or Aider)
- `jq` for JSON processing
- Optional: `claude` CLI for synthesis
- Optional: API keys for API-based consultants (Qwen3, GLM, Grok, DeepSeek)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Unknown skill" | Run install script or check `~/.claude/commands/` |
| "Exit code 1" | Run `/ai-consultants:config-check` to diagnose |
| No consultants | Run `/ai-consultants:config-wizard` |
| API errors | Check `/ai-consultants:config-status` |

## More Info

See [README.md](https://github.com/matteoscurati/ai-consultants) for full documentation.
