# Cost Rates - AI Consultants v5.2.0

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
| Gemini 4 Argon (High) | Maximum/Premium | $0.004 | Gemini (CLI smoke passed; API-equivalent list-rate estimate) |
| gemini-4-argon | API Maximum/Premium | $0.004 | Gemini API (list rate; offline-tested) |
| Gemini 3.8 Flash (High) | Standard | $0.00075 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Low) | Economy | $0.00075 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.1 Pro (High) | CLI opt-in | $0.002 | Gemini (agy CLI) |
| gemini-3.1-pro-preview | API Standard/Economy | $0.00125 | Gemini API |
| Gemini 3.6 Flash (High/Low) | Legacy CLI pins | $0.0015 | Gemini |
| gpt-6-astra | Maximum | $0.010 | Codex |
| gpt-6.1-sol | Default/Premium | $0.002 | Codex |
| gpt-5.6-sol | Explicit override | $0.004 | Codex |
| gpt-5.6-terra | Standard | $0.002 | Codex |
| gpt-5.6-luna | Economy | $0.0002 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.010 | Claude |
| claude-opus-5-5 | Standard | $0.004 | Claude |
| claude-opus-5 | Legacy override | $0.005 | Claude |
| claude-fable-5 | Legacy pins | $0.010 | Claude |
| claude-sonnet-5 | Legacy pins | $0.003 | Claude |
| claude-haiku-4-5 | Economy | $0.001 | Claude |
| mistral-large-4 / mistral-large-4-0 | API all tiers (preview, list rate) | $0.00136 | Mistral |
| mistral-large-3 | Legacy API pin | $0.002 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | CLI all tiers / API opt-in | $0.0015 | Mistral |
| mistral-large-2512 | API opt-in | $0.0005 | Mistral |
| mistral-small-2603 | API opt-in | $0.00015 | Mistral |
| devstral-small-2 | Legacy (retired) | $0.00 | Mistral |
| composer-2.5 | Legacy | $0.0005 | Removed Cursor consultant |
| composer-2 | Legacy | $0.0005 | Removed Cursor consultant |
| gemini-3-flash | Legacy | $0.0005 | Removed Cursor consultant |
| deepseek-v4-pro | Legacy explicit override | $0.000435 | DeepSeek |
| deepseek-flash | All tiers | $0.0003 | DeepSeek (peak, cache miss) |
| deepseek-v4-flash / deepseek-v4-flash-vision-exp | Retired aliases → V4.1 Flash | $0.0003 | DeepSeek (peak, cache miss) |
| glm-5.3-flash | Premium/Standard | Unpriced | GLM coding-plan endpoint |
| glm-5.3 | Maximum | Unpriced | GLM coding-plan endpoint |
| glm-4-flash | Economy | $0.001 | GLM |
| grok-4.7 | Maximum/Premium | $0.002 | Grok |
| grok-4.6 | Legacy override | $0.002 | Grok |
| grok-4.5 | Standard/Economy | $0.002 | Grok |
| qwen3.7-max | Legacy pins | $0.0012 | Qwen3 |
| qwen3.6-35b-a3b | Legacy pins | $0.000163 | Qwen3 |
| qwen3-32b | Legacy pins | $0.0004 | Qwen3 |
| qwen3.8-max | Maximum/Premium | Unpriced | Qwen3 Token Plan |
| qwen3.8-flash | Standard/Economy | Unpriced | Qwen3 Token Plan |
| MiniMax-M3.1-Flash | All tiers | $0.00015 | MiniMax |
| MiniMax-M3 | Legacy pins | $0.0003 | MiniMax (≤512k standard input) |
| MiniMax-M2.7 | Legacy pins | $0.0003 | MiniMax |
| MiniMax-M2.5 | Legacy pins | $0.0003 | MiniMax |
| kimi-code/k3 | Premium/Standard/Economy | $0.0005 | Kimi |
| kimi-code/k3-256k | Maximum | Unpriced | Kimi subscription |
| default | - | $0.005 | Fallback |

### Output Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| Gemini 4 Argon (High) | Maximum/Premium | $0.020 | Gemini (CLI smoke passed; API-equivalent list-rate estimate) |
| gemini-4-argon | API Maximum/Premium | $0.020 | Gemini API (list rate; offline-tested) |
| Gemini 3.8 Flash (High) | Standard | $0.00375 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Low) | Economy | $0.00375 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.1 Pro (High) | CLI opt-in | $0.012 | Gemini (agy CLI) |
| gemini-3.1-pro-preview | API Standard/Economy | $0.005 | Gemini API |
| Gemini 3.6 Flash (High/Low) | Legacy CLI pins | $0.0075 | Gemini |
| gpt-6-astra | Maximum | $0.050 | Codex |
| gpt-6.1-sol | Default/Premium | $0.010 | Codex |
| gpt-5.6-sol | Explicit override | $0.020 | Codex |
| gpt-5.6-terra | Standard | $0.012 | Codex |
| gpt-5.6-luna | Economy | $0.0012 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.050 | Claude |
| claude-opus-5-5 | Standard | $0.020 | Claude |
| claude-opus-5 | Legacy override | $0.025 | Claude |
| claude-fable-5 | Legacy pins | $0.050 | Claude |
| claude-sonnet-5 | Legacy pins | $0.015 | Claude |
| claude-haiku-4-5 | Economy | $0.005 | Claude |
| mistral-large-4 / mistral-large-4-0 | API all tiers (preview, list rate) | $0.00418 | Mistral |
| mistral-large-3 | Legacy API pin | $0.006 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | CLI all tiers / API opt-in | $0.0075 | Mistral |
| mistral-large-2512 | API opt-in | $0.0015 | Mistral |
| mistral-small-2603 | API opt-in | $0.0006 | Mistral |
| devstral-small-2 | Legacy (retired) | $0.00 | Mistral |
| composer-2.5 | Legacy | $0.0025 | Removed Cursor consultant |
| composer-2 | Legacy | $0.0025 | Removed Cursor consultant |
| gemini-3-flash | Legacy | $0.003 | Removed Cursor consultant |
| deepseek-v4-pro | Legacy explicit override | $0.00087 | DeepSeek |
| deepseek-flash | All tiers | $0.0012 | DeepSeek (peak) |
| deepseek-v4-flash / deepseek-v4-flash-vision-exp | Retired aliases → V4.1 Flash | $0.0012 | DeepSeek (peak) |
| glm-5.3-flash | Premium/Standard | Unpriced | GLM coding-plan endpoint |
| glm-5.3 | Maximum | Unpriced | GLM coding-plan endpoint |
| glm-4-flash | Economy | $0.003 | GLM |
| grok-4.7 | Maximum/Premium | $0.006 | Grok |
| grok-4.6 | Legacy override | $0.006 | Grok |
| grok-4.5 | Standard/Economy | $0.006 | Grok |
| qwen3.7-max | Legacy pins | $0.006 | Qwen3 |
| qwen3.6-35b-a3b | Legacy pins | $0.0009 | Qwen3 |
| qwen3-32b | Legacy pins | $0.0016 | Qwen3 |
| qwen3.8-max | Maximum/Premium | Unpriced | Qwen3 Token Plan |
| qwen3.8-flash | Standard/Economy | Unpriced | Qwen3 Token Plan |
| MiniMax-M3.1-Flash | All tiers | $0.0006 | MiniMax |
| MiniMax-M3 | Legacy pins | $0.0012 | MiniMax (≤512k standard input) |
| MiniMax-M2.7 | Legacy pins | $0.0012 | MiniMax |
| MiniMax-M2.5 | Legacy pins | $0.0012 | MiniMax |
| kimi-code/k3 | Premium/Standard/Economy | $0.002 | Kimi |
| kimi-code/k3-256k | Maximum | Unpriced | Kimi subscription |
| default | - | $0.015 | Fallback |

## Cost Estimation per Session

### Typical Consultation

Session cost reports from two live runs on 2026-10-19 with the default models,
a short question and about 130 lines of automatic context (estimates, not
invoices):

| Panel | Consultants | Synthesis (Claude Fable 5.1) | Reported session cost |
|-------|-------------|------------------------------|-----------------------|
| `balanced` | Gemini 4 Argon (High), GPT-6.1 Sol, Mistral Large 4 | ≈ $0.14 | ≈ $0.22 |
| Every consultant enabled | 9 answering consultants | ≈ $0.30 | ≈ $0.59 |

Reasoning models add thinking tokens, synthesis on Fable 5.1 is often the
largest single item, and Token Plan, coding-plan and subscription models are
excluded rather than counted as free. The pre-run estimate is a rough lower
bound.

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

# Cumulative tracking file (default: the XDG data directory)
# COST_TRACKING_FILE=${XDG_DATA_HOME:-~/.local/share}/ai-consultants/costs.json
```

### Behavior

1. **Pre-consultation**: Estimated cost shown before execution
2. **Warning**: Alert if cost exceeds `WARN_AT_COST`
3. **Budget check** (only with `ENABLE_BUDGET_LIMIT=true`): before Round 1,
   before each escalation and before synthesis, `BUDGET_ACTION` warns or stops
   when the session would exceed `MAX_SESSION_COST`. The synthesis estimate is
   part of the session total.
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

Provider-reported usage (API mode, Claude CLI, Codex CLI telemetry) is used
when available and recorded as `tokens_source=measured`. Otherwise the system
estimates tokens using the heuristic:
- **4 characters = 1 token** (approximation)
- Assumed split: **60% input, 40% output** (only when no split is known)

Session reports say how many responses were estimated. Actual costs may vary.

### Data Source

Rates are defined in `docs/cost_rates.json` and are periodically updated from
the providers' official pricing pages: [Anthropic](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model),
[Google](https://ai.google.dev/gemini-api/docs/pricing),
[Mistral](https://docs.mistral.ai/getting-started/models/models_overview/),
[xAI](https://docs.x.ai/developers/models), and
[MiniMax](https://platform.minimax.io/docs/guides/pricing-paygo). The Gemini
3.8 Flash rate is the promotion effective through December 31, 2026; Gemini 4
Argon and Mistral Large 4 use their list rates, not the introductory or preview
prices.

`glm-5.3-flash`, `glm-5.3`, `qwen3.8-max`, `qwen3.8-flash`, and
`kimi-code/k3-256k` are explicitly unpriced on
the transports used here. Their zero catalog entries prevent the estimator from
inventing a dollar figure; session reports disclose their exclusion rather than
presenting them as free.

### Dependencies

Cost tracking requires:
- `bc` - For floating point calculations
- `jq` - For JSON parsing

## DeepSeek V4.1 Flash pricing

As of 2026-09-10, the official API name `deepseek-flash` selects V4.1 Flash.
The estimator uses peak cache-miss rates: $0.30/M input and $1.20/M output.
Off-peak rates are $0.15/M input and $0.60/M output; cached input is $0.006/M
peak or $0.003/M off-peak. Peak hours are weekdays 01:00–04:00 and 06:00–10:00
UTC. The estimate deliberately excludes these discounts; it is not an invoice.
Legacy Flash and Flash Vision Exp aliases are now served and billed as V4.1 Flash.
Other legacy catalog entries remain historical estimates, not newly verified quotes.
Source: [DeepSeek models and pricing](https://api-docs.deepseek.com/quick_start/pricing/).

## Grok 4.7 and Opus 5.5

Grok 4.7 uses $2/M input and $6/M output at standard API rates; above 200K
input tokens the estimator applies $4/M and $12/M to the whole request. It
excludes cached-input discounts and regional, priority and Grok Build Fast
adjustments. CLI subscription usage is not an API invoice. Opus 5.5 uses
$4/M input and $20/M output; measured Claude provider cost takes precedence
when present. Otherwise cache/service adjustments are excluded from estimates.

Sources checked 2026-09-26: [xAI release notes](https://docs.x.ai/developers/release-notes)
and [Opus 5.5](https://platform.claude.com/docs/en/models/opus-5-5/overview).

## Gemini 4 Argon

`Gemini 4 Argon (High)` on `agy` and `gemini-4-argon` on the API serve the
default (premium) and maximum tiers. Google lists Argon at $4/M input and $20/M
output, with an introductory $2/M and $10/M through 2026-11-30. The estimator
uses the list rate so budgets fail safe; thinking tokens bill as output, and
implicit-cache discounts are excluded. The `agy` Medium/Low variants share the
same API-equivalent rate. A CLI estimate is not a subscription invoice; Google
excludes Argon from the Free tier and the AI Pro plan. Sources:
[What's new in Gemini 4 Argon](https://ai.google.dev/gemini-api/docs/latest-model)
and the [Google Cloud announcement](https://cloud.google.com/blog/products/ai-machine-learning/gemini-4-argon-available-on-google-cloud),
checked 2026-10-16.

## Gemini 3.8 Flash

CLI High/Medium/Low and API ID `gemini-3.8-flash` are priced at the promotional
API-equivalent rate: $0.75/M input, $3.75/M output through 2026-12-31. Standard
rates from 2027-01-01 are $1.50/M input and $7.50/M output; the static catalog
must be refreshed at expiry. Cache, service-tier and subscription adjustments
are excluded: a CLI estimate is not a subscription invoice. Legacy model rates
remain in the catalog. In API mode, Pro 3.1 serves standard/economy and
`gemini-4-argon` the default and maximum tiers.
Source: [Google latest-model guide](https://ai.google.dev/gemini-api/docs/latest-model),
checked 2026-09-27.

## Mistral Large 4 (API)

`mistral-large-4` (alias of `mistral-large-4-0`) is the Mistral API target for
every tier. It is a public preview since 2026-10-06. The model page lists
$1.36/M input, $0.14/M cached input and $4.18/M output, and currently shows a
50% preview price of $0.68/M, $0.07/M and $2.09/M. The estimator uses the list
rate, so budgets fail safe during the preview. Cached-input discounts are
excluded. Vibe CLI usage (`MISTRAL_CLI_MODEL`) is unaffected. A minimal API
call on 2026-10-15 reported `service_tier: standard`. Sources: [Mistral Large 4](https://docs.mistral.ai/models/mistral-large-4)
and the [announcement](https://mistral.ai/news/mistral-large-4/), checked 2026-10-07.
