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

**Note:** When invoked from Gemini CLI, the Gemini consultant is automatically excluded from the panel (self-exclusion).

## Available Commands

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
| `/ai-consultants:config-wizard` | Full setup wizard |
| `/ai-consultants:config-check` | Verify CLI agents are installed |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset |
| `/ai-consultants:config-strategy` | Set default synthesis strategy |
| `/ai-consultants:config-features` | Toggle features |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API-based consultants |

## CLI Consultants

| Consultant | CLI | Default Persona | Focus |
|------------|-----|-----------------|-------|
| Claude | `claude` | The Synthesizer | Big picture, synthesis |
| Codex | `codex` | The Pragmatist | Simplicity, proven solutions |
| Mistral | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| Kilo | `kilocode` | The Innovator | Creative approaches |
| Cursor | `agent` | The Integrator | Full-stack perspective |
| Aider | `aider` | The Pair Programmer | Collaborative coding |
| Ollama | `ollama` | The Local Expert | Privacy-first, zero cost |

## More Info

See [README.md](https://github.com/matteoscurati/ai-consultants) for full documentation.
