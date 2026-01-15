---
description: Toggle feature flags (Debate, Smart Routing, Synthesis, etc.)
allowed-tools: Bash Read Edit AskUserQuestion
---

# AI Consultants - Feature Configuration

Toggle feature flags for AI Consultants.

## Instructions

1. **Read current .env configuration:**

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}/.env"
grep -E '^ENABLE_(PERSONA|SYNTHESIS|DEBATE|SMART_ROUTING|COST_TRACKING|REFLECTION)=' "$ENV_FILE" 2>/dev/null || echo "No .env found"
```

2. **Show current status** and ask user which features to toggle using AskUserQuestion.

3. **Available features:**

| Feature | Variable | Description |
|---------|----------|-------------|
| Personas | `ENABLE_PERSONA` | Consultant personality/role |
| Synthesis | `ENABLE_SYNTHESIS` | Auto-synthesis of responses |
| Debate | `ENABLE_DEBATE` | Multi-Agent Debate rounds |
| Smart Routing | `ENABLE_SMART_ROUTING` | Auto-select best consultants |
| Cost Tracking | `ENABLE_COST_TRACKING` | Track API costs |
| Reflection | `ENABLE_REFLECTION` | Self-critique and refine |

4. **Toggle using sed:**

```bash
# Enable a feature
sed -i '' 's/^ENABLE_DEBATE=false/ENABLE_DEBATE=true/' "$ENV_FILE"

# Disable a feature
sed -i '' 's/^ENABLE_DEBATE=true/ENABLE_DEBATE=false/' "$ENV_FILE"
```

5. **For Debate, also configure rounds:**

```bash
# Set debate rounds (1-3 recommended)
sed -i '' 's/^DEBATE_ROUNDS=.*/DEBATE_ROUNDS=2/' "$ENV_FILE"
```

6. **Show updated configuration** after changes.

## Related Commands

- `/ai-consultants:config-status` - View full configuration
- `/ai-consultants:config-wizard` - Full setup wizard
