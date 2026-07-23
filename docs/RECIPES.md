# AI Consultants Recipes

Copy-paste configurations for common workflows. Persistent settings belong in
`~/.config/ai-consultants/.env`; prefix a single command with variables when you
only need a temporary override.

Start once with:

```bash
ai-consultants init
$EDITOR ~/.config/ai-consultants/.env
ai-consultants doctor --live
```

All boolean values are lowercase `true` or `false`. At least two consultants
must be enabled.

## 1. Everyday balanced panel

Use four complementary CLI consultants and synthesize their answers with the
default coverage strategy.

```dotenv
DEFAULT_PRESET=balanced
DEFAULT_STRATEGY=coverage
ENABLE_SYNTHESIS=true
```

```bash
ai-consultants "Redis or Memcached for a write-heavy session store?"
```

## 2. Fast and inexpensive check

The `fast` preset selects two consultants and economy models.

```bash
ai-consultants --preset fast "Is this SQL index definition valid?"
```

For a persistent low-cost setup:

```dotenv
DEFAULT_PRESET=fast
DEFAULT_STRATEGY=cost_capped
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=0.10
BUDGET_ACTION=stop
```

## 3. Security review

```dotenv
DEFAULT_STRATEGY=security_first
```

```bash
ai-consultants --preset security \
  "Find authentication bypasses and unsafe trust boundaries" \
  src/auth.ts@PRIMARY src/session.ts@PRIMARY src/config.ts@CONTEXT
```

Never include credentials, tokens, or private keys in consultation context.

## 4. Compare two approaches without a recommendation

Use `--strategy compare_only` when you want the trade-offs laid out without a
single winner.

```bash
ai-consultants --strategy compare_only \
  "For this API, compare REST and GraphQL"
```

## 5. Reliable panel with health gate and quorum

Ping selected consultants before the full run and stop when too few respond.
The health gate adds one small call per selected consultant.

```dotenv
ENABLE_HEALTH_GATE=true
HEALTH_GATE_TIMEOUT=30
QUORUM_MIN=3
QUORUM_ACTION=stop
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
```

```bash
ai-consultants doctor --live
ai-consultants "Make a release recommendation from the attached evidence" \
  release-notes.md@PRIMARY test-results.md@CONTEXT
```

## 6. Hard budget ceiling

Track estimated spend and stop with partial results rather than crossing the
session limit.

```dotenv
ENABLE_COST_TRACKING=true
ENABLE_BUDGET_LIMIT=true
MAX_SESSION_COST=0.50
WARN_AT_COST=0.25
BUDGET_ACTION=stop
ENABLE_COST_AWARE_ROUTING=true
ENABLE_RESPONSE_LIMITS=true
```

```bash
ai-consultants --preset cost-capped --strategy cost_capped \
  "Propose the smallest safe fix for this regression"
```

## 7. CLI-only operation

Keep every switchable consultant on its installed CLI. CLI authentication is
handled by each provider's own login flow.

```dotenv
GEMINI_USE_API=false
CODEX_USE_API=false
CLAUDE_USE_API=false
MISTRAL_USE_API=false
QWEN3_USE_API=false
MINIMAX_USE_API=false
KIMI_MODEL=kimi-code/k3

ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
```

```bash
ai-consultants doctor --live
```

`KIMI_MODEL` is passed to the Kimi CLI with `--model`, so this recipe uses K3
even when `~/.kimi/config.toml` still names an older default model.

## 8. Hybrid CLI and API panel

Enable API transport only where needed. Gemini and MiniMax automatically choose
API mode when their API key is present unless `*_USE_API` is explicitly set.

```dotenv
CODEX_USE_API=false
CLAUDE_USE_API=false
MISTRAL_USE_API=false
QWEN3_USE_API=true
QWEN3_API_KEY=your-dashscope-key

ENABLE_GROK=true
GROK_API_KEY=your-xai-key
GROK_MODEL=grok-4.5

ENABLE_GLM=false
ENABLE_DEEPSEEK=false
```

Keep `~/.config/ai-consultants/.env` at mode `600` because it may contain keys.

## 9. Large or awkward prompts

Use `--query-file` to avoid shell quoting and argument-size problems. Mark the
main files with `@PRIMARY` and supporting files with `@CONTEXT`.

```bash
ai-consultants --query-file /tmp/review-question.md \
  src/auth.ts@PRIMARY \
  src/cache.ts@CONTEXT \
  docs/architecture.md@CONTEXT
```

## Useful diagnostics

```bash
ai-consultants doctor
ai-consultants doctor --live
ai-consultants doctor --json
ai-consultants doctor --suggest-config
ai-consultants doctor --suggest-preset --question "How should I secure uploads?"
ai-consultants update-clis --dry-run
```

For every available variable and its default, see
[`references/configuration.md`](../references/configuration.md). The executable
source of truth is [`scripts/config.sh`](../scripts/config.sh).

## Qwen via Qwen Cloud Token Plan (opt-in, preview)

`qwen3.8-max-preview` is **not** served by DashScope/ModelStudio. It is reachable
only through a Qwen Cloud **Token Plan** subscription, which has its own base URL
and its own API key. This is opt-in: nothing below is a default, and the panel's
premium Qwen model remains `qwen3.7-max`.

Understand the tradeoffs before enabling it:

- **Preview, not GA.** Alibaba describes it as continuously evolving. No open
  weights, no published benchmarks, no stable per-token price.
- **Billed in prepaid credits**, not per token — and credit consumption varies
  with reasoning depth. Cost reports therefore exclude it and say so explicitly
  rather than estimating a figure.

### API mode (the effort knob works here)

```bash
QWEN3_USE_API=true
QWEN3_FORMAT=openai      # Token Plan is OpenAI-compatible; DashScope is not
QWEN3_API_URL=https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions
QWEN3_MODEL=qwen3.8-max-preview
QWEN3_API_KEY=<your Token Plan key>
QWEN3_REASONING_EFFORT=high    # none|minimal|low|medium|high|xhigh|max; default xhigh
```

Pass the **full** URL including `/chat/completions` — it is used verbatim. Use
`QWEN3_API_KEY` for the Token Plan key; there is deliberately no separate
key variable, so the key always matches whatever `QWEN3_API_URL` points at.

Accepted effort values are the provider's own enum:
`none|minimal|low|medium|high|xhigh|max`. Verified against the live endpoint on
2026-07-21 — note this is wider than the `low|high|xhigh` reported in the public
write-ups. The one value this model rejects is `none`: thinking is always
enabled and cannot be disabled (`The value of the enable_thinking parameter is
restricted to True`). Anything unsupported comes back as a 400, never as a
silently ignored setting.

### CLI mode (the effort knob does NOT work here)

The `qwen` CLI has no reasoning-effort flag. Effort is a user-owned setting, so
ai-consultants cannot deliver it per call and warns if you set
`QWEN3_REASONING_EFFORT` in CLI mode. Configure it yourself in
`~/.qwen/settings.json`:

```json
{
  "modelProviders": {
    "openai": [
      {
        "id": "qwen3.8-max-preview",
        "name": "[Token Plan] qwen3.8-max-preview",
        "baseUrl": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
        "envKey": "BAILIAN_TOKEN_PLAN_API_KEY",
        "generationConfig": { "reasoning": { "effort": "high" } }
      }
    ]
  }
}
```

**Caveat worth knowing**: if you also set `generationConfig.samplingParams` on an
OpenAI-compatible provider, Qwen Code ships those keys to the wire verbatim and
**skips the `reasoning` injection entirely** — so setting both silently gives you
no effort control at all.
