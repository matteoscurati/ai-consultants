# Cost Rates - AI Consultants v2.0

This page documents the per-token rates used by the cost tracking system.

## Rates per Model (USD per 1K tokens)

### Input Tokens

| Model | Cost/1K | Notes |
|-------|---------|-------|
| gemini-2.5-pro | $0.00125 | Default for Gemini |
| gemini-2.5-flash | $0.000075 | Budget option |
| gemini-2.0-flash | $0.0001 | Legacy |
| gpt-4 | $0.03 | Base GPT-4 |
| gpt-4-turbo | $0.01 | GPT-4 Turbo |
| gpt-4o | $0.005 | GPT-4o |
| gpt-4o-mini | $0.00015 | GPT-4o Mini |
| o1 | $0.015 | OpenAI o1 |
| o3 | $0.015 | OpenAI o3 |
| claude-3-opus | $0.015 | For synthesis |
| claude-3-sonnet | $0.003 | |
| claude-3-haiku | $0.00025 | |
| mistral-large | $0.004 | Default for Mistral |
| mistral-medium | $0.0027 | |
| mistral-small | $0.001 | |
| kilo | $0.002 | Default for Kilo |
| default | $0.005 | Fallback |

### Output Tokens

| Model | Cost/1K | Notes |
|-------|---------|-------|
| gemini-2.5-pro | $0.005 | 4x input |
| gemini-2.5-flash | $0.0003 | 4x input |
| gemini-2.0-flash | $0.0004 | 4x input |
| gpt-4 | $0.06 | 2x input |
| gpt-4-turbo | $0.03 | 3x input |
| gpt-4o | $0.015 | 3x input |
| gpt-4o-mini | $0.0006 | 4x input |
| o1 | $0.06 | 4x input |
| o3 | $0.06 | 4x input |
| claude-3-opus | $0.075 | 5x input |
| claude-3-sonnet | $0.015 | 5x input |
| claude-3-haiku | $0.00125 | 5x input |
| mistral-large | $0.012 | 3x input |
| mistral-medium | $0.0081 | 3x input |
| mistral-small | $0.003 | 3x input |
| kilo | $0.006 | 3x input |
| default | $0.015 | Fallback |

## Cost Estimation per Session

### Typical Consultation

**Parameters:**
- 4 active consultants
- ~5000 characters of context
- ~1000 input tokens per consultant (estimate: 4 char/token)
- ~750 output tokens per consultant

**Estimated cost:** $0.02 - $0.05

### With Multi-Agent Debate (2 rounds)

**Additional parameters:**
- +1 round with same context
- Previous responses as additional input

**Estimated cost:** $0.08 - $0.15

### With Self-Reflection

**Additional parameters:**
- Critique + refinement cycle per consultant
- ~500 additional tokens per cycle

**Estimated cost:** $0.10 - $0.20

## Budget Management

### Configuration Variables

```bash
# Maximum budget per session
MAX_SESSION_COST=1.00

# Warning threshold
WARN_AT_COST=0.50

# Cumulative tracking file
COST_TRACKING_FILE=/tmp/ai_consultants_costs.json
```

### Behavior

1. **Pre-consultation**: Estimated cost shown before execution
2. **Warning**: Alert if cost exceeds `WARN_AT_COST`
3. **Budget check**: Error if cost exceeds `MAX_SESSION_COST`
4. **Tracking**: Costs recorded in `COST_TRACKING_FILE`

### Cost Report

```bash
# Generate cost report
source scripts/lib/costs.sh
generate_cost_report
```

Output:
```
╔══════════════════════════════════════════════════════════════╗
║                    Cost Report                               ║
╚══════════════════════════════════════════════════════════════╝

  Total sessions: 15
  Total cost: $0.4523
  Average per session: $0.0301

  Recent sessions:
    2024-01-14T10:30:00: session_20240114_103000_1234 - $0.0325
    ...
```

## Technical Notes

### Token Estimation

The system estimates tokens using the heuristic:
- **4 characters = 1 token** (approximation)
- Assumed split: **60% input, 40% output**

This is a conservative estimate. Actual costs may vary.

### Data Source

Rates are defined in `scripts/lib/costs.sh` and are periodically updated to reflect official provider pricing.

### Dependencies

Cost tracking requires:
- `bc` - For floating point calculations
- `jq` - For JSON parsing
