# Cost Rates - AI Consultants v5.5.0

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
| Gemini 4 Argon (Medium/Low) | CLI opt-in | $0.004 | Gemini (agy CLI; API-equivalent list-rate estimate) |
| gemini-4-argon | API Maximum/Premium | $0.004 | Gemini API (list rate; offline-tested) |
| Gemini 3.8 Flash (High) | Standard | $0.00075 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Low) | Economy | $0.00075 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Medium) | CLI opt-in | $0.00075 | Gemini (agy CLI; promotional through 2026-12-31) |
| gemini-3.8-flash | API Standard/Economy | $0.00075 | Gemini API (promotional through 2026-12-31; offline-tested) |
| gpt-6-astra | Maximum | $0.010 | Codex |
| gpt-6.1-sol | Default/Premium/Standard | $0.002 | Codex |
| gpt-6-luna | Economy | $0.0001 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.010 | Claude |
| claude-opus-5-5 | Standard | $0.004 | Claude |
| claude-haiku-5-5 | Economy | $0.0001 | Claude (prompts over 100K: 5x for the whole request) |
| mistral-large-4 / mistral-large-4-0 | API all tiers (preview, list rate) | $0.00136 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | CLI all tiers / API opt-in | $0.0015 | Mistral |
| mistral-small-2603 | API opt-in | $0.00015 | Mistral |
| deepseek-flash | All tiers | $0.0003 | DeepSeek (peak, cache miss) |
| deepseek-v4-pro | Opt-in | $0.00132 | DeepSeek (peak, cache miss) |
| grok-4.7 | All tiers | $0.002 | Grok |
| MiniMax-M3.1-Flash | All tiers | $0.00015 | MiniMax |
| muse-wonder-1.0 | Default/Maximum/Premium | $0.004 | Meta (preview, Standard mode) |
| muse-spark-1.3 | Standard/Economy | $0.00125 | Meta (Standard mode) |
| muse-spark-1.3-contributor | Opt-in | $0.0001 | Meta (Contributor mode: Meta may train on the content) |
| glm-5.3 | Maximum | Unpriced | GLM coding-plan endpoint |
| glm-5.3-flash | Premium/Standard/Economy | Unpriced | GLM coding-plan endpoint |
| qwen3.8-max | Maximum/Premium | Unpriced | Qwen3 Token Plan |
| qwen3.8-flash | Standard/Economy | Unpriced | Qwen3 Token Plan |
| kimi-code/k3.1-pro | All tiers | Unpriced | Kimi subscription |
| any other model | - | Unpriced | Named in the session report; never priced at a guessed rate |

### Output Tokens

| Model | Tier | Cost/1K | Consultant |
|-------|------|---------|------------|
| Gemini 4 Argon (High) | Maximum/Premium | $0.020 | Gemini (CLI smoke passed; API-equivalent list-rate estimate) |
| Gemini 4 Argon (Medium/Low) | CLI opt-in | $0.020 | Gemini (agy CLI; API-equivalent list-rate estimate) |
| gemini-4-argon | API Maximum/Premium | $0.020 | Gemini API (list rate; offline-tested) |
| Gemini 3.8 Flash (High) | Standard | $0.00375 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Low) | Economy | $0.00375 | Gemini (CLI smoke passed; API-equivalent estimate; promotional through 2026-12-31) |
| Gemini 3.8 Flash (Medium) | CLI opt-in | $0.00375 | Gemini (agy CLI; promotional through 2026-12-31) |
| gemini-3.8-flash | API Standard/Economy | $0.00375 | Gemini API (promotional through 2026-12-31; offline-tested) |
| gpt-6-astra | Maximum | $0.050 | Codex |
| gpt-6.1-sol | Default/Premium/Standard | $0.010 | Codex |
| gpt-6-luna | Economy | $0.0005 | Codex |
| claude-fable-5-1 | Maximum/Premium | $0.050 | Claude |
| claude-opus-5-5 | Standard | $0.020 | Claude |
| claude-haiku-5-5 | Economy | $0.0005 | Claude (prompts over 100K: 5x for the whole request) |
| mistral-large-4 / mistral-large-4-0 | API all tiers (preview, list rate) | $0.00418 | Mistral |
| mistral-medium-3.5 / mistral-medium-3-5 | CLI all tiers / API opt-in | $0.0075 | Mistral |
| mistral-small-2603 | API opt-in | $0.0006 | Mistral |
| deepseek-flash | All tiers | $0.0012 | DeepSeek (peak, cache miss) |
| deepseek-v4-pro | Opt-in | $0.00396 | DeepSeek (peak, cache miss) |
| grok-4.7 | All tiers | $0.006 | Grok |
| MiniMax-M3.1-Flash | All tiers | $0.0006 | MiniMax |
| muse-wonder-1.0 | Default/Maximum/Premium | $0.020 | Meta (preview, Standard mode) |
| muse-spark-1.3 | Standard/Economy | $0.00425 | Meta (Standard mode) |
| muse-spark-1.3-contributor | Opt-in | $0.0002 | Meta (Contributor mode: Meta may train on the content) |
| glm-5.3 | Maximum | Unpriced | GLM coding-plan endpoint |
| glm-5.3-flash | Premium/Standard/Economy | Unpriced | GLM coding-plan endpoint |
| qwen3.8-max | Maximum/Premium | Unpriced | Qwen3 Token Plan |
| qwen3.8-flash | Standard/Economy | Unpriced | Qwen3 Token Plan |
| kimi-code/k3.1-pro | All tiers | Unpriced | Kimi subscription |
| any other model | - | Unpriced | Named in the session report; never priced at a guessed rate |

## Retired models (5.5.0)

5.5.0 removed every superseded model from the catalog, the tiers, the tests
and the documentation. `retired_models` in `docs/cost_rates.json` maps each
one (94 IDs, from GPT-4 and Claude 3 to Gemini 3.7, Grok 4.6, Qwen 3.7,
GLM 5.2, Kimi K3 and MiniMax M3) to its family's current model.

- `ai-consultants configure` replaces a persisted retired value, pinned or
  not, keeps its marker, records `migrated-from=<old>` and writes the usual
  timestamped backup. `--set` refuses a retired model and names the replacement.
- A retired or uncatalogued model selected at run time (for example by an
  environment variable) still runs. The run warns, and the session report
  names it as unpriced instead of applying a default rate.
- Models of removed consultants (Cursor Composer) and free OpenRouter IDs have
  no replacement.

## Verification (2026-10-24)

Every price in the catalog was checked against the provider's official
pricing page on 2026-10-24: [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing),
[OpenAI](https://developers.openai.com/api/docs/pricing),
[Google](https://ai.google.dev/gemini-api/docs/pricing),
[xAI](https://docs.x.ai/docs/models),
[Mistral](https://docs.mistral.ai/getting-started/models/models_overview/) (model pages),
[DeepSeek](https://api-docs.deepseek.com/quick_start/pricing/),
[MiniMax](https://platform.minimax.io/docs/guides/pricing),
[Z.ai](https://docs.z.ai/guides/overview/pricing),
[Alibaba Model Studio](https://www.alibabacloud.com/help/en/model-studio/model-pricing) and
[Kimi](https://platform.kimi.ai/docs/pricing/chat) and
[Meta](https://dev.meta.ai/docs/pricing-rate-limits). DeepSeek V4 Pro moved from
$0.435/$0.87 to its current $1.32/$3.96 per 1M. The subscription-billed models
have published API prices for reference: Kimi K3.1 Pro $2/$10, Qwen3.8-Max
$2/$6, Qwen3.8-Flash $0.15/$0.47, GLM-5.3 $1.40/$4.40 and GLM-5.3-Flash
$0.15/$0.50 per 1M; their CLI or plan transports are billed by quota instead.

Meta bills Muse Wonder and Muse Spark per token with no long-context premium;
cached input ($0.20 and $0.15 per 1M) is excluded from the estimate, and
reasoning tokens bill as output. A Muse Code subscription is billed by quota,
so a CLI run on a subscription is estimated at the API list rate.

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

Rates are defined in `docs/cost_rates.json` and are updated from the
providers' official pricing pages (see Verification above). The Gemini 3.8
Flash rate is the promotion effective through December 31, 2026; Gemini 4
Argon and Mistral Large 4 use their list rates, not the introductory or preview
prices. A small built-in table in `lib/costs.sh` prices the current tier models
when the catalog file is missing.

`glm-5.3-flash`, `glm-5.3`, `qwen3.8-max`, `qwen3.8-flash` and
`kimi-code/k3.1-pro` are explicitly unpriced on the transports used here. Their zero catalog entries prevent the estimator from
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
The retired V4 Flash and Flash Vision Exp aliases (still served and billed as
V4.1 Flash) are migrated to `deepseek-flash`. `deepseek-v4-pro` stays an
opt-in at $1.32/M input and $3.96/M output (peak, cache miss).
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
are excluded: a CLI estimate is not a subscription invoice. Since 5.5.0
`gemini-3.8-flash` also serves the API standard/economy tiers (offline-tested),
and `gemini-4-argon` the default and maximum tiers.
Source: [Google latest-model guide](https://ai.google.dev/gemini-api/docs/latest-model),
checked 2026-09-27.

## Mistral Large 4 (API)

`mistral-large-4` (alias of `mistral-large-4-0`) is the Mistral API target for
every tier. It is a public preview since 2026-10-06. The model page lists
$1.36/M input, $0.14/M cached input and $4.18/M output (no preview discount
shown on 2026-10-24). The estimator uses the list rate. Cached-input discounts are
excluded. Vibe CLI usage (`MISTRAL_CLI_MODEL`) is unaffected. A minimal API
call on 2026-10-15 reported `service_tier: standard`. Sources: [Mistral Large 4](https://docs.mistral.ai/models/mistral-large-4)
and the [announcement](https://mistral.ai/news/mistral-large-4/), checked 2026-10-07.
