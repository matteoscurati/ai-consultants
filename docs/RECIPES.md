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

Use four complementary CLI consultants, synthesize their answers, and keep the
dynamic planner available without forcing debate on every question.

```dotenv
DEFAULT_PRESET=balanced
DEFAULT_STRATEGY=majority
ENABLE_SYNTHESIS=true
ENABLE_DEBATE=true
ORCHESTRATION_MODE=auto
ENABLE_DEBATE_OPTIMIZATION=true
```

```bash
ai-consultants "Redis or Memcached for a write-heavy session store?"
```

## 2. Fast and inexpensive check

The `fast` preset selects two consultants, economy models, and no debate.

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

## 3. Debate until the panel converges

Use the dynamic convergence loop for architectural questions. It stops when
consensus reaches the target, progress stalls, or the round cap is reached.

```dotenv
ENABLE_DEBATE=true
ORCHESTRATION_MODE=converge
CONVERGENCE_MAX_ROUNDS=4
CONVERGENCE_TARGET_CONSENSUS=75
CONVERGENCE_STALL_EPSILON=5
ENABLE_DEBATE_OPTIMIZATION=true
DEBATE_USE_SUMMARIES=true
```

```bash
ai-consultants --strategy risk_averse \
  "Should this service use an event log or mutable relational state?"
```

## 4. Exactly two debate rounds

Use fixed mode when a benchmark or repeatable workflow requires a predictable
number of calls.

```dotenv
ENABLE_DEBATE=true
ORCHESTRATION_MODE=fixed
DEBATE_ROUNDS=2
ENABLE_DEBATE_OPTIMIZATION=false
```

```bash
ai-consultants "Review this migration plan" docs/migration.md@PRIMARY
```

`DEBATE_ROUNDS=1` means initial answers only. Values `2` and `3` add one and two
cross-critique rounds respectively.

## 5. Security review with an adversarial gate

The adversarial shape forces critique and enables peer review as a refutation
gate before synthesis.

```dotenv
DEFAULT_STRATEGY=security_first
ENABLE_DEBATE=true
ORCHESTRATION_MODE=adversarial
ENABLE_ADVERSARIAL_VERIFY=true
ENABLE_PEER_REVIEW=true
PEER_REVIEW_MIN_RESPONSES=3
ENABLE_REFLECTION=true
REFLECTION_CYCLES=1
```

```bash
ai-consultants --preset security \
  "Find authentication bypasses and unsafe trust boundaries" \
  src/auth.ts@PRIMARY src/session.ts@PRIMARY src/config.ts@CONTEXT
```

Never include credentials, tokens, or private keys in consultation context.

## 6. Compare two approaches and choose one

Force tournament mode when the answer must end with one winner.

```bash
ORCHESTRATION_MODE=tournament \
ENABLE_DEBATE=true \
ai-consultants --strategy majority \
  "For this API, choose REST or GraphQL and justify one winner"
```

Use `--strategy compare_only` instead when you want the trade-offs without a
recommendation.

## 7. Exhaustive audit

Continue until a round surfaces no new approach or finding.

```bash
ORCHESTRATION_MODE=exhaustive \
ENABLE_DEBATE=true \
CONVERGENCE_MAX_ROUNDS=4 \
ai-consultants --preset high-stakes \
  "Find all correctness and failure-mode risks in this worker" \
  src/worker.ts@PRIMARY src/queue.ts@CONTEXT
```

## 8. Reliable panel with health gate and quorum

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

## 9. Hard budget ceiling

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

## 10. CLI-only operation

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

## 11. Hybrid CLI and API panel

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

## 12. Exact semantic consensus

Ask the panel to choose from shared stance options so differently worded answers
can still count as agreement. This adds roughly one LLM call per run.

```dotenv
ENABLE_STANCE_CONSENSUS=true
STANCE_MAX_OPTIONS=5
STANCE_TIMEOUT=60
```

```bash
ai-consultants "Should package lockfiles always be committed for applications?"
```

## 13. Large or awkward prompts

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
