# AI Consultants - Full Configuration Reference

Configuration sources, in order of precedence (highest wins):

1. **CLI flags** — `--preset`, `--strategy`, etc.
2. **Existing env vars** — `export FOO=bar` before invoking
3. **User config dir** (v2.12+) — `~/.config/ai-consultants/{config.sh,.env}`
4. **`config.sh` defaults** — the `${VAR:-default}` fallbacks
5. **Hardcoded defaults** in individual scripts

For goal-oriented, copy-paste configurations, start with
[`docs/RECIPES.md`](../docs/RECIPES.md). This file is the variable reference;
[`scripts/config.sh`](../scripts/config.sh) is the executable source of truth.

## Automatic Configurator

The public configurator detects all 11 supported consultants, chooses CLI or API
transport from the available CLI binaries and credentials, and writes the
persistent XDG configuration:

```bash
ai-consultants configure
```

It preserves existing custom values and secrets, refreshes `ENABLE_*` flags from
detected availability, creates a timestamped backup, writes the result with mode
`600`, and warns when fewer than two consultants are usable. Pin an availability
decision with a final `--set ENABLE_<NAME>=true|false` override.
Automatically chosen `*_USE_API` modes are stored with an
`# ai-consultants:auto` marker and are recalculated on later runs. Remove the
marker or use an environment variable/`--set` to pin a transport explicitly.
It never performs a billed authentication probe; use `ai-consultants doctor
--live` when you explicitly want a live provider check.

```bash
# Guided consultant and transport review
ai-consultants configure --interactive

# Review every supported persistent parameter
ai-consultants configure --advanced

# Fully automated, repeatable configuration
ai-consultants configure \
  --set DEFAULT_PRESET=security \
  --set ENABLE_HEALTH_GATE=true \
  --set QUORUM_ACTION=stop

# Discover the exact accepted keys or preview without exposing secrets
ai-consultants configure --show-parameters
ai-consultants configure --dry-run
```

`--set KEY=VALUE` is repeatable and fails closed for unknown or removed keys.
Use the hidden interactive credential prompts (or exported environment variables)
for API keys; command-line arguments may be visible in shell history and process
inspection.
The exhaustive parameter contract is [`.env.example`](../.env.example); the
configurator derives its accepted keys from that template, while
[`scripts/config.sh`](../scripts/config.sh) remains the runtime source of truth.
A regression test fails when a persistent runtime default is missing from the
configurator.

## User Config Dir (v2.12+)

Persistent overrides live in `~/.config/ai-consultants/`. The directory and starter files are scaffolded by:

```bash
ai-consultants init           # creates the dir + .env + config.sh
ai-consultants init --force   # overwrites existing files
```

`init` only scaffolds files for manual editing. Prefer `configure` when you want
automatic detection and a ready-to-use panel.

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
DEFAULT_STRATEGY=coverage    # Strategy when --strategy not given
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
ENABLE_PERSONA=true          # Give each consultant its configured role
ENABLE_SYNTHESIS=true        # Automatic synthesis
SYNTHESIS_CMD=claude         # CLI used to synthesize the panel
ENABLE_SMART_ROUTING=false   # Category-based consultant selection
ENABLE_COST_TRACKING=true    # Track API usage costs
```

`SYNTHESIS_CMD` may be `claude`, `codex`, `gemini`, `cursor`, `mistral`,
`kimi`, `qwen3`, or `minimax`. The invoking agent is excluded automatically;
set `INVOKING_AGENT` only for direct integrations that need to declare their
host explicitly.

## Classification and Smart Routing

```bash
ENABLE_CLASSIFICATION=true      # Classify every question before routing
CLASSIFICATION_MODE=pattern     # pattern (fast) | llm (more accurate, costs a call)
ENABLE_SMART_ROUTING=false      # Select consultants using the affinity matrix
MIN_AFFINITY=7                  # Minimum category score, from 1 to 10
```

The bundled matrix lives in [`references/affinity.json`](affinity.json). Set
`AFFINITY_FILE` or place `affinity.json` in the user config directory to
override it.

## CLI/API Mode Switching (v2.6+)

Six consultants support switching between CLI and API mode. **The default is the CLI** for every consultant that has one — API mode is opt-in (for CLI-less models or an explicit choice). When API mode is enabled, the CLI is not used.

**Gemini auto-resolution (v2.15.1):** leave `GEMINI_USE_API` unset and the mode is chosen for you — API mode when `GEMINI_API_KEY` is present (no `agy` install or OAuth needed; ideal for `npx`), CLI mode (`agy`) otherwise. Set `GEMINI_USE_API` explicitly only to force a mode (an explicit value disables auto-detection).

```bash
# GEMINI_USE_API unset = auto (API if GEMINI_API_KEY set, else agy CLI)
GEMINI_USE_API=false         # Force agy CLI; set true to force Google AI API
CODEX_USE_API=false          # Use OpenAI API instead of codex CLI
CLAUDE_USE_API=false         # Use Anthropic API instead of claude CLI
MISTRAL_USE_API=false        # Use Mistral API instead of vibe CLI
QWEN3_USE_API=false          # Use qwen CLI (default) or DashScope API
MINIMAX_USE_API=false        # Use mmx CLI (default) or MiniMax API
```

### API Keys

| Agent | API Key Variable | Notes |
|-------|------------------|-------|
| Gemini | `GEMINI_API_KEY` | Google AI API key |
| Codex | `OPENAI_API_KEY` | OpenAI API key |
| Claude | `ANTHROPIC_API_KEY` | Anthropic API key |
| Mistral | `MISTRAL_API_KEY` | Mistral API key |
| Qwen3 | `QWEN3_API_KEY` | DashScope API key |
| MiniMax | `MINIMAX_API_KEY` | MiniMax API key (API mode only; the mmx CLI uses OAuth) |
| GLM | `GLM_API_KEY` | Required when `ENABLE_GLM=true` |
| Grok | `GROK_API_KEY` | Required when `ENABLE_GROK=true` |
| DeepSeek | `DEEPSEEK_API_KEY` | Required when `ENABLE_DEEPSEEK=true` |

## Consultant Toggles and Models

```bash
# Consultants enabled by default
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_CURSOR=true
ENABLE_KIMI=true             # Kimi CLI - The Eastern Sage
ENABLE_QWEN3=true            # Qwen CLI/API - The Analyst
ENABLE_MINIMAX=true          # MiniMax CLI/API (mmx) - The Pragmatic Optimizer
ENABLE_CLAUDE=true           # Claude CLI - The Synthesizer (auto-excluded under Claude Code)

# API-only consultants (off by default - require API keys)
ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
```

### Model Overrides

```bash
GEMINI_MODEL=Gemini 3.1 Pro (High)   # agy CLI display name; API mode uses GEMINI_API_MODEL
CODEX_MODEL=gpt-5.5
CLAUDE_MODEL=claude-opus-4-8
MISTRAL_MODEL=mistral-large-3
CURSOR_MODEL=composer-2.5
KIMI_MODEL=kimi-code/k3
QWEN3_MODEL=qwen3.7-max
GLM_MODEL=glm-5.2
GROK_MODEL=grok-4.5
DEEPSEEK_MODEL=deepseek-v4-pro
MINIMAX_MODEL=MiniMax-M2.7
```

`KIMI_MODEL` is passed directly to `kimi --model`, so `kimi-code/k3` overrides
any older default stored in the user's Kimi CLI configuration.

## Model Quality Tiers (v2.5)

```bash
# Set all consultants to a tier programmatically
source scripts/config.sh
apply_model_tier "premium"   # Latest flagship models
apply_model_tier "standard"  # Good quality at reasonable cost
apply_model_tier "economy"   # Optimized for speed and low cost
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
ENABLE_COMPACT_REPORT=true   # Summaries only in reports
```

## Health Gate, Quorum, and Retries

```bash
ENABLE_HEALTH_GATE=false     # Ping each selected consultant before Round 1
HEALTH_GATE_TIMEOUT=30       # Maximum seconds for each parallel ping
QUORUM_MIN=2                 # Fewer successful responses => failed quorum
QUORUM_ACTION=warn           # warn | stop
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
```

The health gate adds one small call per selected consultant. It drops dead or
unauthenticated consultants before the full query; `QUORUM_ACTION=stop` aborts
when the remaining panel is smaller than `QUORUM_MIN`.

## Timeouts and Retries

```bash
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
GEMINI_TIMEOUT=240
CODEX_TIMEOUT=180
MISTRAL_TIMEOUT=180
CURSOR_TIMEOUT=180
KIMI_TIMEOUT=180
CLAUDE_TIMEOUT=240
QWEN3_TIMEOUT=180
MINIMAX_TIMEOUT=180
GLM_TIMEOUT=180
GROK_TIMEOUT=180
DEEPSEEK_TIMEOUT=180
```
