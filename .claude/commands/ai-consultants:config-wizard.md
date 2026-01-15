---
description: Run the full interactive configuration wizard
allowed-tools: Bash Read AskUserQuestion
---

# AI Consultants - Configuration Wizard

Run the configuration wizard to set up all consultants, API keys, and personas.

## Instructions

**IMPORTANT**: The wizard script is interactive and cannot run directly in Claude Code. Use one of these approaches:

### Option 1: Non-Interactive Mode (Recommended for Claude Code)

Auto-detect and enable all available CLI agents:

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/configure.sh --non-interactive
```

This will:
- Detect all installed CLI agents (Gemini, Codex, Vibe, Kilo, Cursor)
- Auto-enable any that are found
- Skip API configuration (use `/ai-consultants:config-api` for that)
- Save configuration to `.env`

### Option 2: Manual Terminal (Full Interactive)

Tell the user to run in their terminal:

```
Run this command in your terminal for the full interactive wizard:
~/.claude/skills/ai-consultants/scripts/configure.sh
```

## What the Wizard Configures

1. CLI Agent Detection and Selection
2. Custom CLI Agents (optional)
3. API Agent Configuration (Qwen3, GLM, Grok)
4. Custom API Agents (OpenRouter, Groq, Together)
5. Persona Assignment
6. Validation (ensures at least 2 agents enabled)
7. Save Configuration (.env file)

## Related Commands

- `/ai-consultants:config-status` - View current configuration
- `/ai-consultants:config-check` - Verify CLI installations
- `/ai-consultants:config-personas` - Change persona assignments
- `/ai-consultants:config-api` - Configure API consultants only
