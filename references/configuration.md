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

The public configurator detects all 10 supported consultants, chooses CLI or API
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
Model defaults carry an `# ai-consultants:default` marker. On rewrite,
`configure` upgrades the exact historical defaults it generated, marked or
unmarked, unless they are pinned: `CLAUDE_MODEL=claude-opus-4-8`/`claude-opus-5`
to Fable 5.1, plus the previous Gemini (CLI and API), Codex, Mistral API, Qwen,
GLM, Grok and DeepSeek defaults, and the fixed timeouts described under
[Timeouts, Waiting and Retries](#timeouts-waiting-and-retries). An explicit
model override supplied with `--set` is stored with `# ai-consultants:pin`, so
`--set CLAUDE_MODEL=claude-opus-5-5` keeps Opus 5.5 (the standard/medium
target) as the default.
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
DEFAULT_PRESET=              # Preset when --preset is not given; empty = every enabled consultant
DEFAULT_STRATEGY=coverage    # Strategy when --strategy is not given
```

`.env.example` leaves `DEFAULT_PRESET=balanced` commented out; set it (for
example with `configure --set DEFAULT_PRESET=balanced`) to run three
consultants by default instead of every enabled one.

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

Use it when the question would exceed the shell's argument limits (128 KiB per argument on Linux, about 1 MiB in total on macOS), contains awkward quoting (JSON, Python dicts with mixed quotes), or should stay out of the process list. Conflicts with a positional question argument.

```bash
q=$(mktemp) && chmod 600 "$q"
printf '%s\n' "Long multi-paragraph question..." > "$q"
./scripts/consult_all.sh --query-file "$q" src/big.py@PRIMARY
rm -f "$q"
```

### Category-aware project tree

`build_context.sh` reads `QUESTION_CATEGORY` (already exported by `consult_all.sh` after `classify_question.sh` runs) to decide whether to include the project-tree listing.

| Category | Project tree included? |
|---|---|
| `ARCHITECTURE`, `CODE_REVIEW`, `API_DESIGN`, `GENERAL` | Yes |
| `SECURITY`, `QUICK_SYNTAX`, `ALGORITHM`, `BUG_DEBUG`, `DATABASE`, `TESTING` | No |
| Unknown category | Yes (conservative default) |

The tree is never listed when the context root is a home directory or `/`:
walking it is slow and would send personal file names to every consultant.

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
SYNTH_DETAIL_MAX_CHARS=4000  # Per-response detail included in synthesis
SYNTHESIS_TIMEOUT=0          # Per synthesis CLI; 0 = no limit (default)
SYNTHESIS_TOTAL_TIMEOUT=0    # All provider attempts together; 0 = no limit
ENABLE_SMART_ROUTING=false   # Category-based consultant selection
ENABLE_COST_TRACKING=true    # Track API usage costs
```

`SYNTHESIS_CMD` may be `claude`, `codex`, or `gemini`. The invoking agent is excluded automatically;
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

Seven consultants support switching between CLI and API mode. **The default is the CLI** for every consultant that has one. Grok additionally falls back to the xAI API after a failed CLI launch when a key is available. When API mode is explicitly enabled, the CLI is not used.

**Gemini auto-resolution (v2.15.1):** leave `GEMINI_USE_API` unset and the mode is chosen for you — API mode when `GEMINI_API_KEY` is present (no `agy` install or OAuth needed; ideal for `npx`), CLI mode (`agy`) otherwise. Set `GEMINI_USE_API` explicitly only to force a mode (an explicit value disables auto-detection).

```bash
# GEMINI_USE_API unset = auto (API if GEMINI_API_KEY set, else agy CLI)
GEMINI_USE_API=false         # Force agy CLI; set true to force Google AI API
CODEX_USE_API=false          # Use OpenAI API instead of codex CLI
CLAUDE_USE_API=false         # Use Anthropic API instead of claude CLI
MISTRAL_USE_API=false        # Use Mistral API instead of vibe CLI
QWEN3_USE_API=false          # Use qwen CLI (default) or DashScope API
GROK_USE_API=false           # Use Grok Build (default); API is fallback
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
| Grok | `GROK_API_KEY` | xAI API fallback key; Grok Build CLI uses its own login |
| DeepSeek | `DEEPSEEK_API_KEY` | Required when `ENABLE_DEEPSEEK=true` |

## Consultant Toggles and Models

```bash
# Consultants enabled by default
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KIMI=true             # Kimi CLI - The Eastern Sage
ENABLE_QWEN3=true            # Qwen CLI/API - The Analyst
ENABLE_GROK=true             # Grok Build CLI/API fallback - The Provocateur
ENABLE_MINIMAX=true          # MiniMax CLI/API (mmx) - The Pragmatic Optimizer
ENABLE_CLAUDE=true           # Claude CLI - The Synthesizer (auto-excluded under Claude Code)

# API-only consultants (off by default - require API keys)
ENABLE_GLM=false
ENABLE_DEEPSEEK=false
```

### Model Overrides

```bash
GEMINI_MODEL="Gemini 4 Argon (High)" # CLI smoke passed; capability-probed identity; API uses GEMINI_API_MODEL
GEMINI_API_MODEL=gemini-4-argon       # API only; needs a paid-tier key
GEMINI_API_MAX_TOKENS=32768           # API only: Argon thinking + visible output
CODEX_MODEL=gpt-6.1-sol    # max_quality uses gpt-6-astra
CODEX_API_MAX_TOKENS=16384
CLAUDE_MODEL=claude-fable-5-1
# Lower-cost standard override: CLAUDE_MODEL=claude-opus-5-5
CLAUDE_API_MAX_TOKENS=16384  # API only: adaptive thinking + visible output
MISTRAL_MODEL=mistral-large-4
MISTRAL_CLI_MODEL=mistral-medium-3.5
MISTRAL_MAX_TURNS=4
MISTRAL_API_MAX_TOKENS=16384  # API only: Large 4 thinking + visible output
KIMI_MODEL=kimi-code/k3
QWEN3_MODEL=qwen3.8-max     # standard/economy tiers use qwen3.8-flash
QWEN3_MAX_QUALITY_TIMEOUT=0  # 0 = no limit
QWEN3_API_MAX_TOKENS=16384
GLM_MODEL=glm-5.3-flash
GLM_API_MAX_TOKENS=16384
GLM_REASONING_EFFORT=       # max_quality sets max
GROK_MODEL=grok-4.7
GROK_MAX_TURNS=4
GROK_API_MAX_TOKENS=4096
GROK_REASONING_EFFORT=      # max_quality sets xhigh (Grok Build maximum)
GROK_OAUTH_MODE=shared      # shared (parallel default) | serialized (diagnostic)
DEEPSEEK_MODEL=deepseek-flash  # DeepSeek-V4.1-Flash API alias
DEEPSEEK_API_MAX_TOKENS=16384
DEEPSEEK_MAX_QUALITY_TIMEOUT=0  # 0 = no limit
DEEPSEEK_REASONING_EFFORT=  # max_quality sets max
MINIMAX_MODEL=MiniMax-M2.7
MINIMAX_API_MAX_TOKENS=4096
MINIMAX_MAX_TOKENS=4096
MINIMAX_MAX_QUALITY_TOKENS=16384
MAX_QUALITY_API_MAX_TOKENS=16384
```

Anthropic counts adaptive thinking and visible response tokens against the same
`CLAUDE_API_MAX_TOKENS` limit. The default is 16,384; a response that reaches
that limit is rejected as truncated instead of entering synthesis as a complete
answer.

`GROK_MODEL` is passed explicitly to `grok -m`. The default transport is the
headless Grok Build CLI using a private `--prompt-file` inside an isolated,
tool-free strict sandbox. If the CLI is missing, cannot execute, or has no
usable authentication, the same query and model fall back to `GROK_API_URL`
when `GROK_API_KEY` is set. Failures after a request launches (including
timeouts, model errors, and empty output) are returned without API fallback.
Set `GROK_USE_API=true` only to force the API path. The adapter accepts any CLI
version that exposes the complete required headless interface and requested
model; `metadata.cli_version` is provenance, not a version pin.

`GROK_OAUTH_MODE=shared` is the normal CLI path because ai-consultants launches
consultants in parallel. Each Grok invocation keeps a private HOME, workspace,
prompt, output, permissions, and tool-free agent policy. Concurrent Grok
processes share only a runner-owned persistent `GROK_HOME` generation under
`$XDG_DATA_HOME/ai-consultants/grok-shared-oauth` (or the standard XDG data
fallback). Grok Build's own auth lock coordinates refreshes inside that shared
generation; a short ai-consultants lock protects seeding, adoption, atomic
runner-policy reconciliation, and atomic publication back to the ambient
`~/.grok/auth.json`. An external `grok login` always wins the digest-based CAS:
the affected consultation fails temporarily and never overwrites the new login
or falls back to a separately billed API request. Malformed credentials and
unpersisted refreshes fail closed. Use `GROK_OAUTH_MODE=serialized` only to hold
the adapter lock across the complete CLI run for diagnostic comparison. Forced
API mode is stateless and never creates or reads the shared OAuth generation.
Each new generation also performs exactly one model-inventory bootstrap under
the short lock because Grok 1.0.4 lazily initializes home metadata; all later
inventory probes and every inference remain concurrent.
Grok 1.0.4 retains ownership of its generated `config.toml`; ai-consultants does
not replace provider-required sections. Instead it atomically reconciles a
separate `.ai-consultants-policy.json`, while the actual enforced surface stays
pinned by the per-invocation CLI arguments.

`max_quality` sets `GROK_REASONING_EFFORT=xhigh` (the highest value accepted by
Grok Build),
`GLM_REASONING_EFFORT=max`, and `DEEPSEEK_REASONING_EFFORT=max`. Grok passes
the value to the CLI as `--reasoning-effort`; the API transports include the
standard `reasoning_effort` field. Unsupported values or CLI capability gaps
fail explicitly rather than silently reducing effort. A provider-rejected CLI
value fails after launch and never triggers API fallback.

Those three effort values are tier-managed: `max_quality` temporarily overrides
an ambient lower pin and restores it when another tier is applied. Qwen is the
intentional exception because Token Plan access is separately configured: an
explicit `QWEN3_REASONING_EFFORT` pin is preserved in the maximum tier.

The preset gives Mistral and Grok four bounded advisory turns, applies
`QWEN3_MAX_QUALITY_TIMEOUT` and `DEEPSEEK_MAX_QUALITY_TIMEOUT` (default 0, no
limit) to Qwen3.8-Max and DeepSeek, and uses the configured
per-consultant `*_API_MAX_TOKENS` budget. Maximum temporarily raises Codex,
Mistral, Grok, and MiniMax API budgets to `MAX_QUALITY_API_MAX_TOKENS` and
restores them when leaving the tier; Qwen, GLM, and DeepSeek already default to
their proven 16,384-token budgets. OpenAI-compatible responses ending with
`finish_reason=length` fail closed rather than entering synthesis as partial
answers. Claude CLI mode is preflighted and dispatched without session
persistence, ambient setting sources, tools, or MCP servers.

`KIMI_MODEL` is passed directly to `kimi --model`, so `kimi-code/k3` overrides
any older default stored in the user's Kimi CLI configuration. Kimi CLI
compatibility is also capability-probed: prompt mode, `stream-json`, provider
inventory, and the requested model must be present. No numeric CLI version is
used as a gate.

`MISTRAL_MODEL` is used only by the HTTP API. Vibe receives
`MISTRAL_CLI_MODEL` through `VIBE_ACTIVE_MODEL` and runs its read-only `plan`
agent in a temporary workspace. The current Vibe default is
`mistral-medium-3.5`. The API default for every tier is `mistral-large-4`
(public preview since 2026-10-06). An authorized consultation smoke returned a
structured answer with the provider-reported model `mistral-large-4` on
2026-10-15. The
preview is absent from `GET /v1/models` even for keys that can call it, so that
listing is not an access check. Use
`MISTRAL_MODEL=mistral-large-3 # ai-consultants:pin` to keep the previous
target. The official API IDs `mistral-medium-3-5`, `mistral-large-2512`, and
`mistral-small-2603` remain catalogued opt-ins until an authenticated API smoke
passes in this project.

Gemini 4 Argon (GA 2026-10-13) is the Gemini default and maximum target:
`GEMINI_MODEL="Gemini 4 Argon (High)"` on `agy` and `GEMINI_API_MODEL=gemini-4-argon`
on the API. An authorized `agy` consultation smoke returned a structured answer
on 2026-10-16 (capability-probed identity, about 49 s for a short question). The
API transport has offline tests only. On the API, Argon defaults to the `high`
thinking level of its CLI target (`GEMINI_REASONING_EFFORT` accepts
low|medium|high), sends no sampling parameters, and spends thinking tokens from
`GEMINI_API_MAX_TOKENS` (default 32768). Google excludes Argon from the Free tier
and the AI Pro plan, so an `agy models` listing is not an access check. Pin
`GEMINI_MODEL="Gemini 3.8 Flash (High)" # ai-consultants:pin` or
`GEMINI_API_MODEL=gemini-3.1-pro-preview # ai-consultants:pin` to keep the previous
targets.

The current Vibe CLI exposes only `--prompt TEXT`, not stdin or a prompt-file
surface, and the same holds for `agy` and `kimi`. Their adapters keep an
isolated workspace, but the prompt remains visible in the CLI process argv, and
a prompt above the single-argument limit (`ARGV_PROMPT_MAX_BYTES`, computed by
default) fails before dispatch. Avoid secrets in consultation context until
those CLIs ship a non-argv input mode. Agentic CLIs (`agy`, `qwen`, `kimi`) run
from a private empty directory unless `CLI_WORKSPACE_ISOLATION=false`.

`metadata.requested_model` records what ai-consultants asked for, while
`metadata.model_identity_source` is `provider-reported`, `capability-probed`,
or `requested-only`. The top-level `model` remains the strongest effective
identifier the transport can honestly attest.

## Model Quality Tiers (v2.5)

```bash
# Set all consultants to a tier programmatically
source scripts/config.sh
apply_model_tier "premium"   # Latest flagship models
apply_model_tier "maximum"   # max_quality-only / separate-plan models
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
ENABLE_SEMANTIC_CACHE=true   # Cache responses by query, context and consultant model/transport/persona
CACHE_TTL_HOURS=24           # Cache expiration
ENABLE_RESPONSE_LIMITS=false # Deprecated no-op (never applied); use *_API_MAX_TOKENS
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

## Timeouts, Waiting and Retries

Consultants and synthesis have **no time limit by default** (every `*_TIMEOUT`
is 0). Reasoning models can legitimately take minutes, and a call cut off by a
client timeout is usually still billed while its answer is lost. The invoking
host decides when to stop waiting instead. While `consult_all.sh` waits it logs
`Output: <dir>` at the start and `Still waiting after Ns for: <names>` every
`WAIT_HEARTBEAT_SECONDS` (0 = silent), and it accepts:

| Request | How | Effect |
|---|---|---|
| Proceed | `touch <dir>/.proceed`, `kill -USR1 <pid>`, or a first Ctrl-C | Stop the current phase and continue with the answers received. During Round 1 the consultants still running are stopped and reported as `stopped`; during synthesis the synthesis is skipped. |
| Abort | `touch <dir>/.abort`, SIGTERM/SIGHUP, or a second Ctrl-C | End the run (exit 130, 143 or 129) and keep the partial output directory. |

Stopped work ends with its whole process tree, so no consultant CLI keeps
running. Its partial output is discarded and excluded from synthesis and cost;
the provider may still bill what it generated. Do not stop a run with SIGKILL:
the shell cannot clean up, so consultant CLIs would keep running. Probes keep
short limits because they detect a dead service rather than cut paid
generation: model inventory, auth status, `HEALTH_GATE_TIMEOUT`,
`DOCTOR_LIVE_TIMEOUT` and the LLM classifier's `CLASSIFICATION_TIMEOUT` (which
falls back to pattern classification).

agy can print its whole answer and then never exit (seen with agy 1.4.2, as
a synthesizer). When agy's output is one complete JSON object that has not
changed for `AGY_EXIT_GRACE_SECONDS` (default 60), the run ends agy and keeps
the answer; prose or a partial answer still waits for agy to exit. 0 disables
this and always waits for the exit.

```bash
MAX_RETRIES=2
RETRY_DELAY_SECONDS=5
WAIT_HEARTBEAT_SECONDS=30
AGY_EXIT_GRACE_SECONDS=60  # keep a complete agy answer when agy never exits
GEMINI_TIMEOUT=0       # 0 = no limit; a positive value restores a hard limit
CODEX_TIMEOUT=0
MISTRAL_TIMEOUT=0
MISTRAL_MAX_TURNS=4
KIMI_TIMEOUT=0
CLAUDE_TIMEOUT=0
QWEN3_TIMEOUT=0
QWEN3_MAX_QUALITY_TIMEOUT=0
MINIMAX_TIMEOUT=0
GLM_TIMEOUT=0
GROK_TIMEOUT=0
GROK_MAX_TURNS=4
DEEPSEEK_TIMEOUT=0
DEEPSEEK_MAX_QUALITY_TIMEOUT=0
```

`configure` migrates the fixed limits it generated through 5.1.2 (180 s per
consultant, 240 s for Claude and synthesis, 480 s synthesis total, 600 s for
maximum-tier Qwen/DeepSeek) to 0. A value marked `# ai-consultants:pin`, or any
other custom value, stays a hard limit.
