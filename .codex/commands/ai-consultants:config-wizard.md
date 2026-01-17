---
description: Run the full interactive configuration wizard
allowed-tools: Bash Read
---

# AI Consultants - Configuration Wizard

Configure consultants, API keys, and personas.

## Non-Interactive Mode

Auto-detect and enable all available CLI agents:

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && ./scripts/configure.sh --non-interactive
```

This detects installed CLI agents (Gemini, Claude, Vibe, Kilo, Cursor), enables them, and saves to `.env`.

For API configuration, use `/ai-consultants:config-api` separately.

## Interactive Mode (Terminal)

For full interactive setup, tell the user to run:

```
~/.codex/skills/ai-consultants/scripts/configure.sh
```

The wizard configures: CLI agents, API agents (Qwen3, GLM, Grok, custom), persona assignments, and validates at least 2 agents are enabled.

## Related Commands

- `/ai-consultants:config-status` - View current configuration
- `/ai-consultants:config-check` - Verify CLI installations
- `/ai-consultants:config-personas` - Change persona assignments
- `/ai-consultants:config-api` - Configure API consultants
- `/ai-consultants:config-features` - Toggle feature flags
