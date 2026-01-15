---
description: Run the full interactive configuration wizard
allowed-tools: Bash Read
---

# AI Consultants - Configuration Wizard

Run the full interactive configuration wizard to set up all consultants, API keys, and personas.

## Instructions

**Run the interactive wizard:**

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/configure.sh
```

The wizard guides you through:
1. CLI Agent Detection and Selection
2. Custom CLI Agents (optional)
3. API Agent Configuration (Qwen3, GLM, Grok)
4. Custom API Agents (OpenRouter, Groq, Together)
5. Persona Assignment
6. Validation (ensures at least 2 agents enabled)
7. Save Configuration (.env file)

## Options

| Mode | Command |
|------|---------|
| Interactive (default) | `./scripts/configure.sh` |
| Non-interactive | `./scripts/configure.sh --non-interactive` |
| Custom output path | `./scripts/configure.sh --output /path/to/custom.env` |

## Related Commands

- `/config-status` - View current configuration
- `/config-check` - Verify CLI installations
- `/config-personas` - Change persona assignments
- `/config-api` - Configure API consultants only
