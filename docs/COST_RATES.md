# Cost Rates - AI Consultants v2.10.0

This page documents the per-token rates used by the cost tracking system.

## Model Quality Tiers (v2.5+)

Since v2.5, models are organized into three tiers. Use `apply_model_tier()` or `get_model_for_tier()` to select models programmatically.

| Tier | Description | Cost Level |
|------|-------------|------------|
| **Premium** | Latest flagship models (default) | Highest |
| **Standard** | Good quality at reasonable cost | Medium |
| **Economy** | Optimized for speed and low cost | Lowest |

## Rates per Model (USD per 1K tokens)

### Input Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| gemini-3-pro-preview | Premium | $0.00125 | Gemini |
| gemini-3-flash-preview | Standard | $0.000075 | Gemini |
| gemini-2.0-flash | Economy | $0.0001 | Gemini |
| gpt-5.3-codex | Premium | $0.01 | Codex |
| gpt-5.3 | Standard | $0.005 | Codex |
| gpt-4o-mini | Economy | $0.00015 | Codex |
| opus-4.6 | Premium | $0.015 | Claude |
| sonnet-4.6 | Standard | $0.003 | Claude |
| haiku-4.5 | Economy | $0.00025 | Claude |
| mistral-large-3 | Premium | $0.004 | Mistral |
| mistral-medium-latest | Standard | $0.0027 | Mistral |
| devstral-small-2 | Economy | $0.001 | Mistral |
| composer-1.5 | Premium/Standard | $0.005 | Cursor |
| deepseek-v3.2-speciale | Premium | $0.002 | DeepSeek |
| deepseek-v3.2 | Standard | $0.0014 | DeepSeek |
| deepseek-chat | Economy | $0.001 | DeepSeek |
| glm-5 | Premium/Standard | $0.002 | GLM |
| glm-4-flash | Economy | $0.0005 | GLM |
| grok-4-1-fast-reasoning | Premium | $0.005 | Grok |
| grok-3 | Standard | $0.003 | Grok |
| grok-3-mini | Economy | $0.001 | Grok |
| qwen3.5-plus | Premium/Standard | $0.002 | Qwen3 |
| qwen3-32b | Economy | $0.0005 | Qwen3 |
| MiniMax-M2.5 | Premium | $0.002 | MiniMax |
| MiniMax-M2.1 | Standard | $0.0015 | MiniMax |
| MiniMax-M2.5-highspeed | Economy | $0.001 | MiniMax |
| auto | All | $0.002 | Kilo (internal routing) |
| default | - | $0.005 | Fallback |

### Output Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| gemini-3-pro-preview | Premium | $0.005 | Gemini |
| gemini-3-flash-preview | Standard | $0.0003 | Gemini |
| gemini-2.0-flash | Economy | $0.0004 | Gemini |
| gpt-5.3-codex | Premium | $0.03 | Codex |
| gpt-5.3 | Standard | $0.015 | Codex |
| gpt-4o-mini | Economy | $0.0006 | Codex |
| opus-4.6 | Premium | $0.075 | Claude |
| sonnet-4.6 | Standard | $0.015 | Claude |
| haiku-4.5 | Economy | $0.00125 | Claude |
| mistral-large-3 | Premium | $0.012 | Mistral |
| mistral-medium-latest | Standard | $0.0081 | Mistral |
| devstral-small-2 | Economy | $0.003 | Mistral |
| composer-1.5 | Premium/Standard | $0.015 | Cursor |
| deepseek-v3.2-speciale | Premium | $0.006 | DeepSeek |
| deepseek-v3.2 | Standard | $0.004 | DeepSeek |
| deepseek-chat | Economy | $0.003 | DeepSeek |
| glm-5 | Premium/Standard | $0.006 | GLM |
| glm-4-flash | Economy | $0.0015 | GLM |
| grok-4-1-fast-reasoning | Premium | $0.015 | Grok |
| grok-3 | Standard | $0.009 | Grok |
| grok-3-mini | Economy | $0.003 | Grok |
| qwen3.5-plus | Premium/Standard | $0.006 | Qwen3 |
| qwen3-32b | Economy | $0.0015 | Qwen3 |
| MiniMax-M2.5 | Premium | $0.006 | MiniMax |
| MiniMax-M2.1 | Standard | $0.004 | MiniMax |
| MiniMax-M2.5-highspeed | Economy | $0.003 | MiniMax |
| auto | All | $0.006 | Kilo |
| default | - | $0.015 | Fallback |

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

# Budget enforcement (v2.4, opt-in)
ENABLE_BUDGET_LIMIT=false
BUDGET_ACTION=warn  # warn or stop

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
Total sessions: 15
Total cost: $0.4523
Average per session: $0.0301
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
