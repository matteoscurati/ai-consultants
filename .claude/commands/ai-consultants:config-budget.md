---
description: Configure budget limits for AI Consultants
allowed-tools: Bash Read Edit
---

# AI Consultants - Budget Configuration

Configure optional budget enforcement to prevent consultations from exceeding cost limits.

## Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_BUDGET_LIMIT` | `false` | Enable budget enforcement (opt-in) |
| `MAX_SESSION_COST` | `1.00` | Maximum cost per consultation ($) |
| `WARN_AT_COST` | `0.50` | Warning threshold ($) |
| `BUDGET_ACTION` | `warn` | Action when exceeded: `warn` or `stop` |

## Budget Actions

- **warn**: Log a warning but continue the consultation
- **stop**: Halt the consultation and return partial results

## Instructions

### Step 1: Show Current Status

```bash
ENV_FILE="${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}/.env"
echo "=== Budget Configuration ==="
grep -E '^(ENABLE_BUDGET_LIMIT|MAX_SESSION_COST|WARN_AT_COST|BUDGET_ACTION)=' "$ENV_FILE" 2>/dev/null || echo "No .env found (using defaults)"
echo ""
echo "Defaults: ENABLE_BUDGET_LIMIT=false, MAX_SESSION_COST=1.00, BUDGET_ACTION=warn"
```

### Step 2: Enable Budget Enforcement

Use the Edit tool to add or modify these lines in the .env file:

```
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=1.00
WARN_AT_COST=0.50
BUDGET_ACTION=warn
```

### Step 3: Choose Budget Action

- For **warn** (continue despite exceeding budget):
  ```
  BUDGET_ACTION=warn
  ```

- For **stop** (halt consultation when budget exceeded):
  ```
  BUDGET_ACTION=stop
  ```

### Step 4: Verify Configuration

```bash
./scripts/doctor.sh | grep -A1 "Budget"
```

## Example Configurations

### Conservative (stop on budget)
```
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=0.50
BUDGET_ACTION=stop
```

### Monitoring Only (warn but continue)
```
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=1.00
BUDGET_ACTION=warn
```

### Disabled (default)
```
ENABLE_BUDGET_LIMIT=false
```

## Enforcement Points

Budget is checked at 4 points:
1. **Before Round 1**: Estimated cost vs budget (stop if over)
2. **After Round 1**: Actual cost vs warning threshold (log warning)
3. **Before Debate**: Cumulative + debate estimate (skip if over)
4. **Before Synthesis**: Cumulative + synthesis estimate (skip if over)

## Related Commands

- `/ai-consultants:config-status` - View full configuration
- `/ai-consultants:config-features` - Toggle other features
