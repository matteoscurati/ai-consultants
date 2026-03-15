---
description: Show help and usage for AI Consultants skill
allowed-tools:
---

# AI Consultants - Help

All skill details (consultants, personas, presets, strategies, features, configuration) are shown in the skill overview loaded alongside this command. Here's a quick reference:

## Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation — ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show this help |

## Quick Examples

```
/ai-consultants:consult "How to optimize this SQL query?"
/ai-consultants:consult "Review this code" src/utils.ts
/ai-consultants:debate "Microservices or monolith?"
```

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

Troubleshooting: run `./scripts/doctor.sh` or `./scripts/doctor.sh --fix`.

Full docs: https://github.com/matteoscurati/ai-consultants
