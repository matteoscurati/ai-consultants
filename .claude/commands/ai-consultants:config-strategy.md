---
description: Set default synthesis strategy (majority, risk_averse, security_first, etc.)
allowed-tools: Bash Read Edit
---

# AI Consultants - Strategy Configuration

Configure the default synthesis strategy for combining consultant responses.

## Available Strategies

| Strategy | Description |
|----------|-------------|
| majority | Simple voting, most common answer wins (default) |
| risk_averse | Weight conservative responses higher, prefer safety |
| security_first | Prioritize security-focused consultants and insights |
| cost_capped | Prefer opinions from cheaper consultants within budget |
| compare_only | No recommendation, just structured comparison table |

## Instructions

### Step 1: Show Current Strategy

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}/.env"
echo "=== Default Strategy ==="
grep "^DEFAULT_STRATEGY=" "$ENV_FILE" 2>/dev/null || echo "DEFAULT_STRATEGY=majority (default)"
```

### Step 2: Set Default Strategy

Use the Edit tool to update the .env file:

```
DEFAULT_STRATEGY=risk_averse
```

### Step 3: Use Directly in Consultation

You can also override the default with the `--strategy` flag:

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/consult_all.sh --strategy security_first "Your question"
```

### Step 4: List All Strategies

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/consult_all.sh --list-strategies
```

## Strategy Recommendations

| Use Case | Recommended Strategy |
|----------|---------------------|
| General questions | `majority` |
| Production deployments | `risk_averse` |
| Security audits | `security_first` |
| Budget constraints | `cost_capped` |
| Learning/exploration | `compare_only` |

## Related Commands

- `/ai-consultants:config-preset` - Set default preset
- `/ai-consultants:config-features` - Toggle feature flags
- `/ai-consultants:config-status` - View full configuration
