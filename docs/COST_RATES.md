# Cost Rates - AI Consultants model-policy update

This page documents the per-token rates used by the cost tracking system.

> **Units:** all rates below are **USD per 1,000 tokens (per-1K)** and mirror `docs/cost_rates.json`, which is the runtime source of truth. `lib/costs.sh` computes cost as `(token_count / 1000) * rate`, so a per-1K rate equals the provider's `$/1M` price divided by 1000.

## Model Quality Tiers (v2.5+)

Automatic selection has three normal tiers plus the `maximum` tier used by
`max_quality`. Use `apply_model_tier()` or `get_model_for_tier()` to select
models programmatically.

| Tier | Description | Cost Level |
|------|-------------|------------|
| **Premium** | Latest flagship models (default) | Highest |
| **Maximum** | Smoke-tested separate-plan or highest-cost targets | Varies / may be unpriced |
| **Standard** | Good quality at reasonable cost | Medium |
| **Economy** | Optimized for speed and low cost | Lowest |

## Rates per Model (USD per 1K tokens)

### Input Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| Gemini 3.7 Flash (High) | Maximum/Premium/Standard | $0.00075 | Gemini (verified agy CLI; promotional through 2026-12-31) |
| Gemini 3.7 Flash (Low) | Economy | $0.00075 | Gemini (verified agy CLI; promotional through 2026-12-31) |
| Gemini 3.1 Pro (High) | CLI opt-in | $0.002 | Gemini (agy CLI) |
| gemini-3.1-pro-preview | API default | $0.00125 | Gemini API |
| Gemini 3.6 Flash (High/Low) | Legacy CLI pins | $0.0015 | Gemini |
| gpt-5.6-sol | Maximum/Premium | $0.004 | Codex |
| gpt-5.6-terra | Standard | $0.002 | Codex |
| gpt-5.6-luna | Economy | $0.0002 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.010 | Claude |
| claude-opus-5 | Standard | $0.005 | Claude |
| claude-fable-5 | Legacy pins | $0.010 | Claude |
| claude-sonnet-5 | Legacy pins | $0.003 | Claude |
| claude-haiku-4-5 | Economy | $0.001 | Claude |
| mistral-large-3 | Premium | $0.002 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | Premium CLI / API opt-in | $0.0015 | Mistral |
| mistral-large-2512 | API opt-in | $0.0005 | Mistral |
| mistral-small-2603 | API opt-in | $0.00015 | Mistral |
| devstral-small-2 | Economy | $0.00 | Mistral |
| composer-2.5 | Legacy | $0.0005 | Removed Cursor consultant |
| composer-2 | Legacy | $0.0005 | Removed Cursor consultant |
| gemini-3-flash | Legacy | $0.0005 | Removed Cursor consultant |
| deepseek-v4-pro | Premium | $0.000435 | DeepSeek |
| deepseek-v4-flash | Standard/Economy | $0.00014 | DeepSeek |
| glm-5.3-flash | Maximum/Premium/Standard | Unpriced | GLM coding-plan endpoint |
| glm-5.3 | Legacy pins | Unpriced | GLM coding-plan endpoint |
| glm-4-flash | Economy | $0.001 | GLM |
| grok-4.6 | Maximum/Premium | $0.002 | Grok |
| grok-4.5 | Standard/Economy | $0.002 | Grok |
| qwen3.7-max | Premium | $0.0012 | Qwen3 |
| qwen3.6-35b-a3b | Standard | $0.000163 | Qwen3 |
| qwen3-32b | Economy | $0.0004 | Qwen3 |
| qwen3.8-max | Maximum | Unpriced | Qwen3 Token Plan |
| MiniMax-M3 | Maximum | $0.0003 | MiniMax (≤512k standard input) |
| MiniMax-M2.7 | Premium/Standard | $0.0003 | MiniMax |
| MiniMax-M2.5 | Economy | $0.0003 | MiniMax |
| kimi-code/k3 | Premium/Standard/Economy | $0.0005 | Kimi |
| kimi-code/k3-256k | Maximum | Unpriced | Kimi subscription |
| default | - | $0.005 | Fallback |

### Output Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| Gemini 3.7 Flash (High) | Maximum/Premium/Standard | $0.00375 | Gemini (verified agy CLI; promotional through 2026-12-31) |
| Gemini 3.7 Flash (Low) | Economy | $0.00375 | Gemini (verified agy CLI; promotional through 2026-12-31) |
| Gemini 3.1 Pro (High) | CLI opt-in | $0.012 | Gemini (agy CLI) |
| gemini-3.1-pro-preview | API default | $0.005 | Gemini API |
| Gemini 3.6 Flash (High/Low) | Legacy CLI pins | $0.0075 | Gemini |
| gpt-5.6-sol | Maximum/Premium | $0.020 | Codex |
| gpt-5.6-terra | Standard | $0.012 | Codex |
| gpt-5.6-luna | Economy | $0.0012 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.050 | Claude |
| claude-opus-5 | Standard | $0.025 | Claude |
| claude-fable-5 | Legacy pins | $0.050 | Claude |
| claude-sonnet-5 | Legacy pins | $0.015 | Claude |
| claude-haiku-4-5 | Economy | $0.005 | Claude |
| mistral-large-3 | Premium | $0.006 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | Premium CLI / API opt-in | $0.0075 | Mistral |
| mistral-large-2512 | API opt-in | $0.0015 | Mistral |
| mistral-small-2603 | API opt-in | $0.0006 | Mistral |
| devstral-small-2 | Economy | $0.00 | Mistral |
| composer-2.5 | Legacy | $0.0025 | Removed Cursor consultant |
| composer-2 | Legacy | $0.0025 | Removed Cursor consultant |
| gemini-3-flash | Legacy | $0.003 | Removed Cursor consultant |
| deepseek-v4-pro | Premium | $0.00087 | DeepSeek |
| deepseek-v4-flash | Standard/Economy | $0.00028 | DeepSeek |
| glm-5.3-flash | Maximum/Premium/Standard | Unpriced | GLM coding-plan endpoint |
| glm-5.3 | Legacy pins | Unpriced | GLM coding-plan endpoint |
| glm-4-flash | Economy | $0.003 | GLM |
| grok-4.6 | Maximum/Premium | $0.006 | Grok |
| grok-4.5 | Standard/Economy | $0.006 | Grok |
| qwen3.7-max | Premium | $0.006 | Qwen3 |
| qwen3.6-35b-a3b | Standard | $0.0009 | Qwen3 |
| qwen3-32b | Economy | $0.0016 | Qwen3 |
| qwen3.8-max | Maximum | Unpriced | Qwen3 Token Plan |
| MiniMax-M3 | Maximum | $0.0012 | MiniMax (≤512k standard input) |
| MiniMax-M2.7 | Premium/Standard | $0.0012 | MiniMax |
| MiniMax-M2.5 | Economy | $0.0012 | MiniMax |
| kimi-code/k3 | Premium/Standard/Economy | $0.002 | Kimi |
| kimi-code/k3-256k | Maximum | Unpriced | Kimi subscription |
| default | - | $0.015 | Fallback |

## Cost Estimation per Session

### Typical Consultation

**Parameters:**
- 4 active consultants
- ~5000 characters of context
- ~1000 input tokens per consultant (estimate: 4 char/token)
- ~750 output tokens per consultant

**Estimated cost:** $0.02 - $0.05

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

Rates are defined in `docs/cost_rates.json` and are periodically updated from
the providers' official pricing pages: [Anthropic](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model),
[Google](https://ai.google.dev/gemini-api/docs/pricing),
[Mistral](https://docs.mistral.ai/getting-started/models/models_overview/),
[xAI](https://docs.x.ai/developers/models), and
[MiniMax](https://platform.minimax.io/docs/guides/pricing-paygo). Gemini 3.7's
listed rate is the promotion effective through December 31, 2026.

`glm-5.3-flash`, legacy-pinned `glm-5.3`, `qwen3.8-max`, and
`kimi-code/k3-256k` are explicitly unpriced on
the transports used here. Their zero catalog entries prevent the estimator from
inventing a dollar figure; session reports disclose their exclusion rather than
presenting them as free.

### Dependencies

Cost tracking requires:
- `bc` - For floating point calculations
- `jq` - For JSON parsing
