# AI Consultants - Full Configuration Reference

Configuration sources, in order of precedence (highest wins):

1. **CLI flags** — `--preset`, `--strategy`, etc.
2. **Existing env vars** — `export FOO=bar` before invoking
3. **User config dir** (v2.12+) — `~/.config/ai-consultants/{config.sh,.env}`
4. **`config.sh` defaults** — the `${VAR:-default}` fallbacks
5. **Hardcoded defaults** in individual scripts

## User Config Dir (v2.12+)

Persistent overrides live in `~/.config/ai-consultants/`. The directory and starter files are scaffolded by:

```bash
ai-consultants init           # creates the dir + .env + config.sh
ai-consultants init --force   # overwrites existing files
```

Search order for the directory:

| Priority | Source |
|----------|--------|
| 1 | `$AI_CONSULTANTS_CONFIG_DIR` |
| 2 | `$XDG_CONFIG_HOME/ai-consultants` |
| 3 | `$HOME/.config/ai-consultants` |

Files loaded from that dir (in order, both optional):

- **`.env`** — KEY=value lines, parsed and exported. Existing env vars are NOT overridden. `export` prefix and `# comments` supported. Recommended chmod 600 (contains API keys).
- **`config.sh`** — full bash, sourced after `.env`. Use `${VAR:-default}` to defer to env.
- **`affinity.json`** — picked up by `lib/routing.sh` if present (overrides bundled matrix; superseded by `AFFINITY_FILE`).

`./scripts/doctor.sh` reports which user config files are loaded under "Checking User Config (v2.12)".

## Defaults

```bash
DEFAULT_PRESET=balanced      # Preset when --preset not given
DEFAULT_STRATEGY=majority    # Strategy when --strategy not given
```

## Context Handoff (v2.14+)

The way file context flows from the invoking agent to the consultants. Agents pass file paths as positional arguments to `consult_all.sh` rather than inlining file contents into the query string — this is what lets `build_context.sh` run the AST/chunking optimizer.

### File path syntax — `path@TAG`

When passing files to `consult_all.sh` (directly or via slash command), each path may carry a `@TAG` suffix:

| Tag | Meaning |
|---|---|
| `@PRIMARY` | Focus of the question; what consultants should critique. Default if `@TAG` omitted. |
| `@CONTEXT` | Ambient reference; read but not the target of the critique. |

```bash
./scripts/consult_all.sh "Why does auth fail under load?" \
    src/auth.ts@PRIMARY src/cache.ts@CONTEXT src/logger.ts@CONTEXT
```

Unknown tags fall back to `PRIMARY` with a `log_warn` message. The tag appears in the rendered `### File: ... (TAG)` header so consultants can weigh files differently.

### `--query-file <path>` flag

Escape hatch when the question would exceed shell `ARG_MAX` (~256KB on macOS) or contains awkward quoting (JSON, Python dicts with mixed quotes). Conflicts with a positional question argument.

```bash
echo "Long multi-paragraph question..." > /tmp/q.txt
./scripts/consult_all.sh --query-file /tmp/q.txt src/big.py@PRIMARY
```

### Category-aware project tree

`build_context.sh` reads `QUESTION_CATEGORY` (already exported by `consult_all.sh` after `classify_question.sh` runs) to decide whether to include the project-tree listing.

| Category | Project tree included? |
|---|---|
| `ARCHITECTURE`, `CODE_REVIEW`, `API_DESIGN`, `GENERAL` | Yes |
| `SECURITY`, `QUICK_SYNTAX`, `ALGORITHM`, `BUG_DEBUG`, `DATABASE`, `TESTING` | No |
| Unknown category | Yes (conservative default) |

Override:

```bash
FORCE_PROJECT_TREE=true ./scripts/consult_all.sh "..."   # Always include
```

### Token optimization mode (v2.2+, now actually engaged)

```bash
TOKEN_OPTIMIZATION_MODE=ast      # none, basic, ast (default), full
ENABLE_AST_EXTRACTION=true       # AST-based code skeleton
ENABLE_SYMBOL_COMPRESSION=false  # Symbol compression (opt-in)
ENABLE_SEMANTIC_CHUNKING=true    # Semantic chunking for large files
MAX_CONTEXT_FILE_BYTES=8000      # Threshold before optimization kicks in
```

AST extractors are dedicated for **Python, JavaScript, TypeScript, Bash, Go**. Other declared languages (Rust, Java, C, C++, C#, Ruby, PHP, Swift) fall back to a `grep`-based generic extractor.

## Core Features

```bash
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_PEER_REVIEW=false     # Anonymous peer review
ENABLE_PANIC_MODE=auto       # Auto-rigor for uncertainty
ENABLE_SMART_ROUTING=false   # Category-based consultant selection
ENABLE_COST_TRACKING=true    # Track API usage costs
```

## Dynamic Orchestration (v2.16+)

A planner picks an orchestration **shape** per question (from category, complexity,
and intent) and runs debate as a **convergence loop** — iterating until the panel's
answers converge instead of a fixed `DEBATE_ROUNDS` count.

```bash
ORCHESTRATION_MODE=auto              # auto (planner) | fixed (legacy) | <shape>
CONVERGENCE_MAX_ROUNDS=4             # hard cap on debate rounds
CONVERGENCE_TARGET_CONSENSUS=75      # consensus score (0-100) that counts as converged
CONVERGENCE_STALL_EPSILON=5          # min per-round gain; below it the loop stops "stalled"
ENABLE_ADVERSARIAL_VERIFY=true       # adversarial shape forces a critique round + peer review
```

**Shapes** (auto-selected, or force one via `ORCHESTRATION_MODE=<shape>`):

| Shape | Picked when | Behavior |
|-------|-------------|----------|
| `quick` | complexity ≤ `COMPLEXITY_THRESHOLD_SIMPLE` | single fan-out, no debate |
| `converge` | medium/high complexity (default) | debate until consensus ≥ target |
| `adversarial` | category `SECURITY` | ≥1 forced critique round + peer-review refutation gate |
| `tournament` | intent "compare X vs Y" | converge, then synthesis declares one winner |
| `exhaustive` | intent "find all / audit" | loop until a round surfaces no new approach |

`SECURITY` and `ARCHITECTURE` are mandatory-debate categories (as in the pre-2.16
pipeline): `SECURITY` → `adversarial`, `ARCHITECTURE` → `converge` with a forced
critique round, so they always get at least one debate round even when the panel
agrees on the first pass.

`ORCHESTRATION_MODE=fixed` restores the exact pre-2.16 pipeline (fixed `DEBATE_ROUNDS`).
The convergence trajectory and stop reason are recorded in `orchestration.json` /
`optimization_metrics.json`. Every round still respects `MAX_SESSION_COST` / budget limits.

## CLI/API Mode Switching (v2.6+)

Five consultants support switching between CLI and API mode. **The default is the CLI** for every consultant that has one — API mode is opt-in (for CLI-less models or an explicit choice). When API mode is enabled, the CLI is not used.

**Gemini auto-resolution (v2.15.1):** leave `GEMINI_USE_API` unset and the mode is chosen for you — API mode when `GEMINI_API_KEY` is present (no `agy` install or OAuth needed; ideal for `npx`), CLI mode (`agy`) otherwise. Set `GEMINI_USE_API` explicitly only to force a mode (an explicit value disables auto-detection).

```bash
# GEMINI_USE_API unset = auto (API if GEMINI_API_KEY set, else agy CLI)
GEMINI_USE_API=false         # Force agy CLI; set true to force Google AI API
CODEX_USE_API=false          # Use OpenAI API instead of codex CLI
CLAUDE_USE_API=false         # Use Anthropic API instead of claude CLI
MISTRAL_USE_API=false        # Use Mistral API instead of vibe CLI
QWEN3_USE_API=false          # Use qwen CLI (default) or DashScope API
```

### API Keys

| Agent | API Key Variable | Notes |
|-------|------------------|-------|
| Gemini | `GEMINI_API_KEY` | Google AI API key |
| Codex | `OPENAI_API_KEY` | OpenAI API key |
| Claude | `ANTHROPIC_API_KEY` | Anthropic API key |
| Mistral | `MISTRAL_API_KEY` | Mistral API key |
| Qwen3 | `QWEN3_API_KEY` | DashScope API key |

## Consultant Toggles and Models

```bash
# Consultants enabled by default
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KILO=true
ENABLE_CURSOR=true
ENABLE_AMP=true              # Amp CLI - The Systems Thinker
ENABLE_KIMI=true             # Kimi CLI - The Eastern Sage
ENABLE_QWEN3=true            # Qwen CLI/API - The Analyst
ENABLE_CLAUDE=true           # Claude CLI - The Synthesizer (auto-excluded under Claude Code)

# Off by default
ENABLE_AIDER=false           # Aider CLI - The Pair Programmer
ENABLE_OLLAMA=false          # Ollama - The Local Expert

# API-only consultants (off by default - require API keys)
ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
ENABLE_MINIMAX=false
```

### Model Overrides

```bash
GEMINI_MODEL=Gemini 3.1 Pro (High)   # agy CLI display name; API mode uses GEMINI_API_MODEL
CODEX_MODEL=gpt-5.5
CLAUDE_MODEL=claude-opus-4-8
MISTRAL_MODEL=mistral-large-3
KILO_MODEL=auto
CURSOR_MODEL=composer-2.5
AIDER_MODEL=qwen3-coder:free
AMP_MODEL=amp
KIMI_MODEL=kimi-code/kimi-for-coding
QWEN3_MODEL=qwen3.7-max
GLM_MODEL=glm-5.2
GROK_MODEL=grok-4.3
DEEPSEEK_MODEL=deepseek-v4-pro
MINIMAX_MODEL=MiniMax-M2.7
OLLAMA_MODEL=hf.co/prithivMLmods/VibeThinker-3B-GGUF
```

## Model Quality Tiers (v2.5)

```bash
# Set all consultants to a tier programmatically
source scripts/config.sh
apply_model_tier "premium"   # Latest flagship models
apply_model_tier "standard"  # Good quality at reasonable cost
apply_model_tier "economy"   # Optimized for speed and low cost
```

## Ollama (Local Models)

```bash
ENABLE_OLLAMA=true
OLLAMA_MODEL=hf.co/prithivMLmods/VibeThinker-3B-GGUF
OLLAMA_HOST=http://localhost:11434
OLLAMA_TIMEOUT=300
```

## Budget Management (v2.4)

```bash
ENABLE_BUDGET_LIMIT=false
MAX_SESSION_COST=1.00        # Maximum cost in USD
BUDGET_ACTION=warn           # warn or stop
```

## Caching and Optimization (v2.3)

```bash
ENABLE_SEMANTIC_CACHE=true   # Cache responses by query fingerprint
CACHE_TTL_HOURS=24           # Cache expiration
ENABLE_RESPONSE_LIMITS=false # Limit output tokens by category
ENABLE_COST_AWARE_ROUTING=false  # Route simple queries to cheaper models
ENABLE_DEBATE_OPTIMIZATION=false # Skip debate if all agree
ENABLE_COMPACT_REPORT=true   # Summaries only in reports
```

## Capability-Aware Routing & Voting (v2.20+)

Weight each consultant's vote (and rank the panel) by its capability on the
quality axis a question stresses — **intelligence** or **taste**, per the
`category_axis` map in [`references/affinity.json`](../references/affinity.json).
Per-consultant scores live in that file's `capabilities` block. `cost` is a
composition/budget axis only and is never a vote weight (tie-break order:
intelligence > taste > cost). Both features are opt-in and additive — with the
flags off, behavior is identical to before.

```bash
ENABLE_CAPABILITY_WEIGHTING=false  # capability-weighted voting
ENABLE_CAPABILITY_ROUTING=false    # capability-aware panel composition
CAPABILITY_WEIGHT_STRENGTH=10      # higher = gentler nudge: weight = conf*(S+cap)/S
CAPABILITY_DEFAULT=5               # fallback for a missing consultant/axis
```

## Timeouts and Retries

```bash
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
GEMINI_TIMEOUT=240
CODEX_TIMEOUT=180
MISTRAL_TIMEOUT=180
KILO_TIMEOUT=180
CURSOR_TIMEOUT=180
AMP_TIMEOUT=180
KIMI_TIMEOUT=180
OLLAMA_TIMEOUT=300           # Longer for local inference
```
