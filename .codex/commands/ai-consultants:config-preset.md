---
description: Set default consultation preset (minimal, balanced, thorough, high-stakes)
allowed-tools: Bash Read Edit
---

# AI Consultants - Preset Configuration

Configure the default preset used when no `--preset` flag is provided.

## Available Presets

| Preset | Models | Features |
|--------|--------|----------|
| minimal | 2 (Gemini + Claude) | Fast, cheap |
| balanced | 4 (+Mistral +Kilo) | Good coverage |
| thorough | 5 (+Cursor) | Comprehensive |
| high-stakes | All + debate | Maximum rigor |
| local | Ollama only | Full privacy |
| security | Security-focused | +Debate |
| cost-capped | Budget-friendly | Low cost |

## Instructions

### Step 1: Show Current Preset

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}/.env"
echo "=== Default Preset ==="
grep "^DEFAULT_PRESET=" "$ENV_FILE" 2>/dev/null || echo "No default preset set (using individual ENABLE_* settings)"
```

### Step 2: Set Default Preset

Use the Edit tool to update the .env file:

```
DEFAULT_PRESET=balanced
```

Or leave empty to use individual `ENABLE_*` settings:

```
DEFAULT_PRESET=
```

### Step 3: Use Directly in Consultation

You can also override the default with the `--preset` flag:

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ./scripts/consult_all.sh --preset high-stakes "Your question"
```

### Step 4: List All Presets

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && ./scripts/consult_all.sh --list-presets
```

## Related Commands

- `/ai-consultants:config-strategy` - Set default synthesis strategy
- `/ai-consultants:config-features` - Toggle feature flags
- `/ai-consultants:config-status` - View full configuration
