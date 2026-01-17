---
description: Toggle feature flags (Debate, Smart Routing, Synthesis, etc.)
allowed-tools: Bash Read Edit
---

# AI Consultants - Feature Configuration

Toggle feature flags for AI Consultants.

## Available Features

| Feature | Variable | Description |
|---------|----------|-------------|
| Personas | `ENABLE_PERSONA` | Consultant personality/role |
| Synthesis | `ENABLE_SYNTHESIS` | Auto-synthesis of responses |
| Debate | `ENABLE_DEBATE` | Multi-Agent Debate rounds |
| Smart Routing | `ENABLE_SMART_ROUTING` | Auto-select best consultants |
| Cost Tracking | `ENABLE_COST_TRACKING` | Track API costs |
| Reflection | `ENABLE_REFLECTION` | Self-critique and refine |
| Peer Review | `ENABLE_PEER_REVIEW` | Anonymous consultant peer review |
| Panic Mode | `ENABLE_PANIC_MODE` | Auto-rigor when uncertainty detected |

## Instructions

### Step 1: Show Current Status

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}/.env"
echo "=== Feature Flags ==="
grep -E '^ENABLE_(PERSONA|SYNTHESIS|DEBATE|SMART_ROUTING|COST_TRACKING|REFLECTION|PEER_REVIEW|PANIC_MODE)=' "$ENV_FILE" 2>/dev/null || echo "No .env found"
grep -E '^(DEBATE_ROUNDS|PEER_REVIEW_MIN_RESPONSES|PANIC_CONFIDENCE_THRESHOLD)=' "$ENV_FILE" 2>/dev/null
```

### Step 2: Toggle a Feature

Use the Edit tool to update the .env file. Change `true` to `false` or vice versa:

```
ENABLE_DEBATE=true
ENABLE_SMART_ROUTING=false
```

### Step 3: Configure Debate Rounds (Optional)

When enabling Debate, also set the number of rounds (1-3 recommended):

```
DEBATE_ROUNDS=2
```

### Step 4: Verify the Change

Re-run the status check from Step 1 to confirm.

## Related Commands

- `/ai-consultants:config-status` - View full configuration
- `/ai-consultants:config-wizard` - Full setup wizard
