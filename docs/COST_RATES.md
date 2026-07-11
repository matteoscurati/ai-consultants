# Cost Rates - AI Consultants v2.19.2

This page documents the per-token rates used by the cost tracking system.

> **Units:** all rates below are **USD per 1,000 tokens (per-1K)** and mirror `docs/cost_rates.json`, which is the runtime source of truth. `lib/costs.sh` computes cost as `(token_count / 1000) * rate`, so a per-1K rate equals the provider's `$/1M` price divided by 1000.

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
| Gemini 3.1 Pro (High) | Premium | $0.002 | Gemini (agy CLI) |
| Gemini 3.5 Flash (High) | Standard | $0.0015 | Gemini (agy CLI) |
| Gemini 3.5 Flash (Low) | Economy | $0.0015 | Gemini (agy CLI) |
| gpt-5.5 | Premium | $0.005 | Codex |
| gpt-5.4 | Standard | $0.0025 | Codex/Aider |
| gpt-5.4-nano | Economy | $0.0002 | Codex/Aider |
| qwen3-coder:free | Premium | $0.00 | Aider |
| claude-opus-4-8 | Premium | $0.005 | Claude |
| claude-sonnet-4-6 | Standard | $0.003 | Claude |
| claude-haiku-4-5 | Economy | $0.001 | Claude |
| mistral-large-3 | Premium | $0.002 | Mistral |
| mistral-medium-latest | Standard | $0.001 | Mistral |
| devstral-small-2 | Economy | $0.00 | Mistral |
| composer-2.5 | Premium | $0.0005 | Cursor |
| composer-2 | Standard | $0.0005 | Cursor |
| gemini-3-flash | Economy | $0.0005 | Cursor |
| deepseek-v4-pro | Premium | $0.000435 | DeepSeek |
| deepseek-v4-flash | Standard/Economy | $0.00014 | DeepSeek |
| glm-5.2 | Premium/Standard | $0.00098 | GLM |
| glm-4-flash | Economy | $0.001 | GLM |
| grok-4.3 | Premium | $0.00125 | Grok |
| grok-4.1-fast | Standard/Economy | $0.0002 | Grok |
| qwen3.7-max | Premium | $0.0012 | Qwen3 |
| qwen3.6-35b-a3b | Standard | $0.000163 | Qwen3 |
| qwen3-32b | Economy | $0.0004 | Qwen3 |
| MiniMax-M2.7 | Premium/Standard | $0.00025 | MiniMax |
| MiniMax-M2.5 | Economy | $0.000255 | MiniMax |
| kimi-code/kimi-for-coding | Premium/Standard | $0.0005 | Kimi |
| hf.co/prithivMLmods/VibeThinker-3B-GGUF | All | $0.00 | Ollama (local) |
| auto | All | $0.002 | Kilo (internal routing) |
| default | - | $0.005 | Fallback |

### Output Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| Gemini 3.1 Pro (High) | Premium | $0.012 | Gemini (agy CLI) |
| Gemini 3.5 Flash (High) | Standard | $0.009 | Gemini (agy CLI) |
| Gemini 3.5 Flash (Low) | Economy | $0.009 | Gemini (agy CLI) |
| gpt-5.5 | Premium | $0.030 | Codex |
| gpt-5.4 | Standard | $0.015 | Codex/Aider |
| gpt-5.4-nano | Economy | $0.00125 | Codex/Aider |
| qwen3-coder:free | Premium | $0.00 | Aider |
| claude-opus-4-8 | Premium | $0.025 | Claude |
| claude-sonnet-4-6 | Standard | $0.015 | Claude |
| claude-haiku-4-5 | Economy | $0.005 | Claude |
| mistral-large-3 | Premium | $0.006 | Mistral |
| mistral-medium-latest | Standard | $0.003 | Mistral |
| devstral-small-2 | Economy | $0.00 | Mistral |
| composer-2.5 | Premium | $0.0025 | Cursor |
| composer-2 | Standard | $0.0025 | Cursor |
| gemini-3-flash | Economy | $0.003 | Cursor |
| deepseek-v4-pro | Premium | $0.00087 | DeepSeek |
| deepseek-v4-flash | Standard/Economy | $0.00028 | DeepSeek |
| glm-5.2 | Premium/Standard | $0.00308 | GLM |
| glm-4-flash | Economy | $0.003 | GLM |
| grok-4.3 | Premium | $0.0025 | Grok |
| grok-4.1-fast | Standard/Economy | $0.0005 | Grok |
| qwen3.7-max | Premium | $0.006 | Qwen3 |
| qwen3.6-35b-a3b | Standard | $0.0009 | Qwen3 |
| qwen3-32b | Economy | $0.0016 | Qwen3 |
| MiniMax-M2.7 | Premium/Standard | $0.001 | MiniMax |
| MiniMax-M2.5 | Economy | $0.001 | MiniMax |
| kimi-code/kimi-for-coding | Premium/Standard | $0.002 | Kimi |
| hf.co/prithivMLmods/VibeThinker-3B-GGUF | All | $0.00 | Ollama (local) |
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
