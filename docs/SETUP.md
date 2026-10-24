# AI Consultants Setup Guide

This guide walks you through installing and configuring AI Consultants for various AI coding agents.

---

## Supported Agents

AI Consultants follows the open [Agent Skills standard](https://agentskills.io), enabling cross-platform compatibility:

| Agent | Skills Directory | Status |
|-------|-----------------|--------|
| **Claude Code** | `~/.claude/skills/` | ✅ Native (slash commands) |
| **OpenAI Codex CLI** | `~/.codex/skills/` or `~/.agents/skills/` | ✅ Compatible (skill, no slash commands) |
| **Antigravity (agy)** | `<project>/.agents/skills/` or `~/.gemini/config/skills/` | ✅ Compatible (skill) |
| **Gemini CLI** | `~/.gemini/skills/` or `~/.agents/skills/` | ⚠️ Legacy (no longer served to individual accounts) |
| **GitHub Copilot** | Via SkillPort | ✅ Via AGENTS.md |
| **Cursor** | Via SkillPort | ✅ Via SkillPort |
| **Windsurf** | Via SkillPort | ✅ Via SkillPort |

---

## Claude Code Setup (Recommended)

AI Consultants is designed as a **Claude Code skill**. This is the fastest and easiest way to get started.

### Step 1: Install the Skill

```bash
# One-liner installation
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

This installs to `~/.claude/skills/ai-consultants/` and makes slash commands available in Claude Code.

### Step 2: Configure the Available Consultants

```bash
ai-consultants configure
```

This detects installed CLIs and available API keys for the complete 10-consultant
roster, selects CLI/API transport, and saves a private persistent configuration
under `~/.config/ai-consultants/`.

### Step 3: Verify Installation

```bash
./scripts/doctor.sh --fix
```

You should see at least 2 consultants marked as available.

### Step 4: Your First Consultation

```
/ai-consultants:consult "What's the best way to structure a REST API?"
```

That's it! You're ready to go.

---

## Claude Code Slash Commands

AI Consultants provides 2 slash commands:

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:help` | Show all commands and usage |

Configuration can be managed with `ai-consultants configure`, including presets,
strategies, features, personas, API keys, transports, models, timeouts, budgets,
and advanced optimization controls. Settings are saved to the XDG user config
directory, normally `~/.config/ai-consultants/.env`.

---

## OpenAI Codex CLI Setup

Codex CLI supports the Agent Skills standard and can use AI Consultants directly.

### Step 1: Install the Skill

```bash
# Option A: Clone directly
git clone https://github.com/matteoscurati/ai-consultants.git ~/.codex/skills/ai-consultants

# Option B: Symlink from existing installation
ln -s ~/.claude/skills/ai-consultants ~/.codex/skills/ai-consultants

# Option C: Symlink from any location
ln -s /path/to/ai-consultants ~/.codex/skills/ai-consultants
```

### Step 2: Verify Installation

```bash
~/.codex/skills/ai-consultants/scripts/doctor.sh --fix
```

### Step 3: Use in Codex

Codex discovers the skill in `~/.codex/skills/` or `~/.agents/skills/`; it has
no custom slash commands, so ask for it in natural language ("use the
ai-consultants skill to …"). The consultation needs network access and writes
under `~/.cache` and `~/.config`, which Codex's default sandbox blocks: approve
the escalation when Codex asks, or start it with `--sandbox danger-full-access`.
Approve it yourself: Codex's automatic approval review (`--approve-for-me`)
rejects it because it sends your files to external providers. Without network
access every consultant fails with a network error, and the run reports 0
answers. Codex also rejects `rm -f`; the skill's private question file is
removed with `unlink` instead.

---

## Antigravity (agy) Setup

Antigravity (`agy`) replaced the Gemini CLI for individual Google accounts. It
reads skills from `<project>/.agents/skills/<name>/` and from its user skill
directory `~/.gemini/config/skills/<name>/`.

```bash
# Per project
mkdir -p .agents/skills
ln -s ~/.claude/skills/ai-consultants .agents/skills/ai-consultants

# Or for every project
mkdir -p ~/.gemini/config/skills
ln -s ~/.claude/skills/ai-consultants ~/.gemini/config/skills/ai-consultants
```

Ask in natural language ("use the ai-consultants skill to …"). agy runs the
consultation as a background task and follows its log; in print mode
(`agy -p`) it waits at most 30 minutes for background tasks.

## Gemini CLI (legacy)

Google stopped serving the Gemini CLI to individual accounts on 2026-06-18.
Where it still works, it discovers the skill in `~/.gemini/skills/` or
`~/.agents/skills/` (natural language only: it loads `.toml` custom commands,
not the Markdown slash commands shipped here).

---

## SkillPort Setup (Multi-Agent)

[SkillPort](https://github.com/gotalab/skillport) is a universal skill manager that enables skill portability across agents like Cursor, Copilot, and Windsurf.

### Step 1: Install SkillPort

```bash
npm install -g skillport
```

### Step 2: Add AI Consultants

```bash
# From GitHub
skillport add github.com/matteoscurati/ai-consultants

# Or from local clone
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
./scripts/skillport-install.sh
```

### Step 3: Verify Installation

```bash
skillport list                    # Should show ai-consultants
./scripts/skillport-install.sh status  # Detailed status
```

### Step 4: Use in Your Agent

```bash
# Load skill on demand
skillport show ai-consultants
```

SkillPort also generates `AGENTS.md` for agents that use that format (Copilot and Cursor).

---

## Generic agentskills Setup

For any agent that supports the [agentskills.io](https://agentskills.io) standard:

### Installation

```bash
# Clone to the agent's skills directory
git clone https://github.com/matteoscurati/ai-consultants.git ~/.{agent}/skills/ai-consultants

# Replace {agent} with your agent name (claude, codex, gemini, etc.)
```

### Files Available

| File | Purpose |
|------|---------|
| `SKILL.md` | Primary skill specification (agentskills.io format) |
| `AGENTS.md` | Alternative discovery format (Copilot/Cursor) |
| `scripts/` | Executable scripts for consultations |

---

## Prerequisites

Before installing consultant CLIs, ensure you have:

### Required
- **jq** for JSON processing
- **curl** for API connectivity checks

- **Bash 3.2+** (the stock macOS `/bin/bash` 3.2 is supported; no newer Bash needed)
- **bc** for cost calculations (usually pre-installed)

### Recommended
- **Node.js 18+** for npm-based CLIs (Codex, Qwen, MiniMax)
- **Python 3.8+** for pip-based CLIs (Mistral Vibe)

### Optional
- **timeout/gtimeout**, used only when you set a positive `*_TIMEOUT` (a
  built-in fallback is used without it)

### Install jq

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Verify
jq --version
```

### Install timeout (macOS, optional)

Consultants have no time limit by default. If you set a positive `*_TIMEOUT`,
coreutils provides `gtimeout` (macOS does not include `timeout`):

```bash
brew install coreutils

# Verify (gtimeout on macOS, timeout on Linux)
gtimeout --version
```

> **Note:** If timeout/gtimeout is not available, AI Consultants uses a POSIX fallback.

---

## Consultant CLIs

You need **at least 2 consultants** configured for AI Consultants to work.

### Antigravity CLI — `agy` (The Architect)

The Gemini consultant runs on the Antigravity CLI (`agy`), the successor to the
deprecated Gemini CLI (transitioned 2026-06-18).

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash

# Authentication (OAuth — sign in once, credentials are cached)
agy            # launch without arguments to sign in

# Optional: list available models (after sign-in)
agy models
```

> API mode (`GEMINI_USE_API=true`) is an alternative that talks to the Google AI
> endpoint with `GEMINI_API_KEY` and `GEMINI_API_MODEL` instead of the agy CLI.

Get API key: [Google AI Studio](https://aistudio.google.com/apikey)

### Codex CLI (The Pragmatist)

```bash
npm install -g @openai/codex

# Authentication
export OPENAI_API_KEY="sk-your-key"
```

Get API key: [OpenAI Platform](https://platform.openai.com/api-keys)

### Mistral Vibe CLI (The Devil's Advocate)

```bash
pip install mistral-vibe

# Authentication
export MISTRAL_API_KEY="your-key"
```

Get API key: [Mistral Console](https://console.mistral.ai/api-keys/)

### Claude CLI (The Synthesizer) - v2.2

```bash
# Claude CLI is part of Claude Code
# See https://docs.anthropic.com/en/docs/claude-code for installation

# Verify installation
claude --version
```

### Qwen CLI (The Analyst) - v2.7

```bash
npm install -g @qwen-code/qwen-code@latest

# Verify installation
qwen --version

# Or use API mode
export QWEN3_USE_API=true
export QWEN3_API_KEY="your-dashscope-key"
```

Get API key: [Alibaba Cloud DashScope](https://dashscope.console.aliyun.com/)

**CLI/API Mode**: Qwen3 defaults to CLI mode (`QWEN3_USE_API=false`). Set to `true` to use the DashScope API.

### Kimi K3.1 Pro via Kimi Code CLI (The Eastern Sage) - v5.4

```bash
curl -L code.kimi.com/install.sh | bash
```

Verify: `kimi --version`

AI Consultants pins K3.1 Pro at max thinking effort for every consultation,
independently of the model and effort in your user-level Kimi configuration:

```bash
export KIMI_MODEL=kimi-code/k3.1-pro
export KIMI_REASONING_EFFORT=max   # reaches the CLI as KIMI_MODEL_THINKING_EFFORT
./scripts/query_kimi.sh "Review this API boundary"
```

Every tier, `max_quality` included, uses `kimi-code/k3.1-pro`; its availability
is verified from the Kimi provider inventory before the request. K3.1 Pro needs
a Kimi Code Plus plan or higher. If the alias is missing, run `kimi` once and
`/login` to refresh the model list (`~/.kimi-code/config.toml`).

### MiniMax (CLI via mmx) - v2.21

MiniMax runs via the `mmx` CLI by default (CLI-first, OAuth). Install and sign in:

```bash
npm install -g mmx-cli
mmx auth login          # OAuth (browser); or: mmx auth login --api-key <key>
```

API mode is opt-in: set `MINIMAX_USE_API=true` with `MINIMAX_API_KEY`.

Verify: `mmx --version`

### Meta (Muse Code CLI or Meta Model API) - v5.5

Meta is opt-in. Install Muse Code and sign in once (browser sign-in or an API
key); a Muse Code subscription or pay-as-you-go both work:

```bash
curl -fsSL https://dev.meta.ai/install.sh | sh
muse                    # first run: trust prompt and sign-in, then exit
ai-consultants configure   # enables ENABLE_META once muse is on PATH
```

Or use the Meta Model API with a pay-as-you-go key from the Model API
dashboard (keys start with `LLM_`): set `META_API_KEY`, and Meta selects the
API unless `META_USE_API=false`. Muse Code also reads `META_API_KEY` for headless
runs.

The CLI runs `muse exec` advisory-only: a private empty workspace, no shell, no
workspace writes, no web tools, no sandbox network, no personal rules or
skills, no session log and `--contributor-mode off`. Subscriptions default to
Contributor mode, in which Meta may train on prompts, code and responses, so
it is switched off on every run. Muse Wonder (`muse-wonder-1.0`, preview) serves
the default, premium and maximum tiers; Muse Spark 1.3 (`muse-spark-1.3`) serves
standard and economy. Pin `META_MODEL=muse-spark-1.3-contributor` only if you
accept Contributor mode for the API; every run logs a warning.

Verify: `muse --version`

---

## Self-Exclusion (v2.2)

When AI Consultants is invoked from a specific AI agent, that agent is automatically excluded from the consultant panel to prevent self-consultation.

### How It Works

| Invoking Agent | Excluded Consultant | Other Consultants |
|----------------|---------------------|-------------------|
| Claude Code | Claude | Gemini, Codex, Mistral, Qwen, etc. |
| Codex CLI | Codex | Claude, Gemini, Mistral, Qwen, etc. |
| Antigravity (agy) / Gemini CLI | Gemini | Claude, Codex, Mistral, Qwen, etc. |
| Cursor | None | All enabled consultants; Cursor is a host, not a panel member |
| Qwen CLI | Qwen3 | Claude, Gemini, Codex, Mistral, etc. |
| Kimi CLI | Kimi | All except Kimi |
| Bash (direct) | None | All enabled consultants (up to 10) |

### Automatic Detection

The host sets `INVOKING_AGENT` itself:
- Claude Code: `/ai-consultants:consult` sets `INVOKING_AGENT=claude`
- Codex CLI: the skill's execution contract (`SKILL.md`) sets `INVOKING_AGENT=codex`
- Antigravity (agy) and the legacy Gemini CLI: the contract sets `INVOKING_AGENT=gemini`

The same identity excludes the host from synthesis. A Claude-hosted run must
not create `claude.json` or report `synthesis_provider=claude`; equivalent
invariants apply to Codex and Gemini. Natural-language skill invocations follow
the execution contract in `SKILL.md`.

### Manual Usage (Bash)

```bash
# Claude excluded from panel
INVOKING_AGENT=claude ./scripts/consult_all.sh "Question"

# Codex excluded from panel
INVOKING_AGENT=codex ./scripts/consult_all.sh "Question"

# No exclusion (all enabled consultants)
./scripts/consult_all.sh "Question"
```

---

## CLI/API Mode Switching (v2.6+)

Eight consultants can switch between CLI mode (using local CLI tools) and API mode (direct API calls): **Gemini, Codex, Claude, Mistral, Qwen3, Grok, MiniMax, and Meta**. Grok is CLI-first and runs in an isolated, tool-free strict sandbox. It falls back automatically only when Grok Build is missing, cannot launch, or lacks usable authentication and a key is available; request failures after launch are surfaced without an API fallback.

Grok's normal OAuth mode is `GROK_OAUTH_MODE=shared`, which is safe for the
parallel panel: each call gets a private HOME/workspace/prompt/output, while a
runner-owned persistent `GROK_HOME` lets Grok Build coordinate token refresh
with its own lock. A short ai-consultants lock atomically seeds and publishes
valid generations; a concurrent external `grok login` wins the CAS and makes
the affected run fail without an API fallback. Use
`GROK_OAUTH_MODE=serialized` only as a diagnostic fallback. Forced API mode is
stateless and does not read or create the shared OAuth generation. A newly
created shared generation runs one locked inventory bootstrap to let Grok 1.0.4
initialize its home metadata; the lock is released before inference.

### Why Use API Mode?

- **No CLI installation required**: Use API keys without installing CLI tools
- **Consistent behavior**: API responses are more predictable
- **Easier deployment**: No need to manage CLI binaries

### Configuration

```bash
# Enable API mode for individual consultants
export GEMINI_USE_API=true
export GEMINI_API_KEY="your-google-ai-key"

export CODEX_USE_API=true
export OPENAI_API_KEY="sk-..."

export CLAUDE_USE_API=true
export ANTHROPIC_API_KEY="sk-ant-..."

export MISTRAL_USE_API=true
export MISTRAL_API_KEY="your-mistral-key"

export GROK_USE_API=true
export GROK_API_KEY="your-xai-key"

export QWEN3_USE_API=true   # Enable API mode for Qwen3
export QWEN3_API_KEY="your-dashscope-key"
```

### API Endpoints (Custom)

```bash
GEMINI_API_URL=https://generativelanguage.googleapis.com/v1beta/models
CODEX_API_URL=https://api.openai.com/v1/chat/completions
CLAUDE_API_URL=https://api.anthropic.com/v1/messages
MISTRAL_API_URL=https://api.mistral.ai/v1/chat/completions
QWEN3_API_URL=https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation
```

The Qwen default is the native DashScope endpoint (`QWEN3_FORMAT=qwen`). For an
OpenAI-compatible endpoint such as the Token Plan, set `QWEN3_FORMAT=openai` and
the full `/chat/completions` URL; see [`RECIPES.md`](RECIPES.md).

### Mode Detection

Check current mode with doctor command:

```bash
./scripts/doctor.sh --verbose
# Shows:
#   ✓ Gemini: API mode (key: AIza...1234)
#   ○ Codex: CLI mode
#   ○ Claude: CLI mode
#   ○ Mistral: CLI mode
#   ✓ Qwen3: API mode (key: sk-...abcd)
```

---

## Configuration Presets (v2.2)

Presets let you quickly configure how many consultants to use.

### Available Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick, cheap |
| `balanced` | 3 (+ Mistral) | Standard |
| `thorough` | 3 | Comprehensive |
| `max_quality` | All 11, maximum models and max provider effort | Critical decisions |
| `high-stakes` | Expanded panel | Critical decisions |
| `security` | Security-focused | Security reviews |
| `cost-capped` | Budget-friendly | Low cost |

### Set Default Preset

**Bash:**
```bash
# Add to .env
DEFAULT_PRESET=balanced
```

### Override Per Consultation

**Claude Code:** Specify in your question context.

**Bash:**
```bash
./scripts/consult_all.sh --preset high-stakes "Critical question"
```

---

## Synthesis Strategies (v2.2)

Strategies control how consultant responses are combined.

### Available Strategies

| Strategy | Description |
|----------|-------------|
| `coverage` | Union of every distinct point/risk across consultants, deduplicated (default) |
| `majority` | Produce one blended recommendation |
| `risk_averse` | Weight conservative responses higher |
| `security_first` | Prioritize security-focused insights |
| `cost_capped` | Prefer simpler, cheaper solutions |
| `compare_only` | No recommendation, just comparison |

### Set Default Strategy

**Bash:**
```bash
# Add to .env
DEFAULT_STRATEGY=risk_averse
```

### Strategy Recommendations

| Use Case | Recommended Strategy |
|----------|---------------------|
| General questions | `coverage` |
| Production deployments | `risk_averse` |
| Security audits | `security_first` |
| Budget constraints | `cost_capped` |
| Learning/exploration | `compare_only` |

---

## Ready-to-run configurations

These examples can be prefixed to one command or saved in
`~/.config/ai-consultants/.env`.

### Security gate with a required quorum

```bash
ENABLE_HEALTH_GATE=true \
QUORUM_MIN=3 \
QUORUM_ACTION=stop \
ai-consultants --preset security --strategy security_first \
  "Find authentication bypasses" src/auth.ts@PRIMARY
```

More scenarios—including CLI-only, hybrid API, hard-budget, and
large-context runs—are in [`docs/RECIPES.md`](RECIPES.md).

---

## Environment Configuration

### Automatic configuration (recommended)

```bash
# Detect the full roster and write ~/.config/ai-consultants/.env
ai-consultants configure

# Set any supported parameter non-interactively
ai-consultants configure \
  --set DEFAULT_PRESET=balanced \
  --set ENABLE_SYNTHESIS=true

# Guided or exhaustive review
ai-consultants configure --interactive
ai-consultants configure --advanced

# Parameter discovery and safe preview
ai-consultants configure --show-parameters
ai-consultants configure --dry-run
```

Existing custom values and credentials are preserved automatically;
availability-derived `ENABLE_*` flags are refreshed and can be pinned with
`--set`. Unless `--force` is supplied, the previous file is retained as a
timestamped mode-600 backup.
Automatically selected `*_USE_API` modes carry an `# ai-consultants:auto`
marker, so rerunning the command can react to installed or removed CLIs and new
credentials. Unmarked modes, environment values, and `--set` remain user pins.
The configurator uses the complete [`.env.example`](../.env.example) contract,
so advanced parameters are also accepted through repeatable `--set KEY=VALUE`
arguments.

Do not place API keys in `--set` arguments: command lines can be retained in
shell history or observed by other local processes. Use `--interactive`,
`--advanced`, or exported environment variables for credentials.

### Using .env file

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/ai-consultants"
# For a new configuration only; keep existing credentials/settings if present.
cp -n .env.example "${XDG_CONFIG_HOME:-$HOME/.config}/ai-consultants/.env"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/ai-consultants/.env"
```

Edit that user configuration `.env`. A different existing private directory must
be selected explicitly with `AI_CONSULTANTS_CONFIG_DIR`; project `.env` files
are not discovered automatically:


```bash
# Enable/disable consultants (10 available)
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_CLAUDE=false    # Auto-excluded when invoked from Claude Code
ENABLE_MISTRAL=false
ENABLE_QWEN3=false     # v2.7: The Analyst (CLI/API)
ENABLE_GROK=true       # Grok Build CLI; API fallback when unavailable
ENABLE_GLM=false
ENABLE_DEEPSEEK=false
ENABLE_KIMI=true
ENABLE_MINIMAX=true
MINIMAX_API_KEY=your-key
ENABLE_META=false      # v5.5: The Systems Thinker (muse CLI or META_API_KEY)

# Self-exclusion (v2.2)
INVOKING_AGENT=unknown  # Set automatically by slash commands

# API Keys
GEMINI_API_KEY=your-key
OPENAI_API_KEY=sk-your-key
MISTRAL_API_KEY=your-key
ANTHROPIC_API_KEY=sk-ant-your-key
QWEN3_API_KEY=your-dashscope-key
GROK_API_KEY=your-xai-key  # optional fallback; Grok Build normally uses login

# CLI/API Mode Switching (v2.6+)
# GEMINI_USE_API auto-resolves when unset (v2.15.1): API if GEMINI_API_KEY is
# set, else the agy CLI. Set it explicitly only to force a specific mode.
CODEX_USE_API=false
CLAUDE_USE_API=false
MISTRAL_USE_API=false
QWEN3_USE_API=false    # Default: CLI mode
MINIMAX_USE_API=false  # Default: mmx CLI mode
# META_USE_API         # Unset: API when META_API_KEY is set, else muse CLI

# Defaults (v2.8)
DEFAULT_PRESET=balanced
DEFAULT_STRATEGY=coverage

# Features
ENABLE_SYNTHESIS=true
ENABLE_HEALTH_GATE=false
QUORUM_MIN=2
QUORUM_ACTION=warn

# Budget (v2.4)
ENABLE_BUDGET_LIMIT=false
MAX_SESSION_COST=1.00
BUDGET_ACTION=warn
```

### Minimum Requirements

**At least 2 consultants must be enabled.**

Example configurations:

**OpenAI + Google:**
```bash
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=false
```

**OpenAI + Anthropic:**
```bash
ENABLE_CODEX=true
ENABLE_CLAUDE=true
ENABLE_GEMINI=false
ENABLE_MISTRAL=false
```

---

## Verification

### Doctor Command

```bash
./scripts/doctor.sh
```

Checks:
- CLI tools installed
- API keys configured
- Configuration valid

**Auto-fix issues:**
```bash
./scripts/doctor.sh --fix
```

### Configuration

Auto-detect the available CLI and API transports:

```bash
./bin/ai-consultants configure
```

Use `--interactive` for a guided review, `--advanced` for every supported
parameter, or `--dry-run` to preview the generated configuration without
writing it. The deprecated `setup_wizard.sh` and `preflight_check.sh` entry
points remain compatibility forwarders but are not the maintained interface.

---

## Troubleshooting

### "Command not found" errors

```bash
# Check npm global path
npm list -g --depth=0

# Check pip packages
pip list | grep mistral
```

### Authentication failures

**Gemini (Antigravity CLI):**
```bash
agy            # launch with no arguments to (re-)sign in via browser OAuth
agy models     # verify auth: lists available models when signed in
```
(Or skip the CLI entirely: set `GEMINI_API_KEY` to run Gemini over the API.)

**Codex:**
```bash
echo $OPENAI_API_KEY  # Verify set
```

### Timeout errors

Consultants have no time limit by default. A `Timeout after Ns` message means a
`*_TIMEOUT` is set to a positive value in `.env` or the environment; set it to
`0` to remove the limit:
```bash
GEMINI_TIMEOUT=0
CODEX_TIMEOUT=0
```

### A consultant is taking too long

The run logs `Still waiting after Ns for: <names>` while it waits. To continue
with the answers already received, run `touch <output dir>/.proceed` (the
directory is logged as `Output: <dir>` at the start) or press Ctrl-C once;
press Ctrl-C again, or `touch <output dir>/.abort`, to end the run.

### "At least 2 consultants are required" error

Either:
1. Install another CLI
2. Configure an API-backed consultant
3. Run `./scripts/doctor.sh --fix`

### Claude Code Issues

| Issue | Solution |
|-------|----------|
| "Unknown skill" | Run install script again |
| Commands not showing | Restart Claude Code |
| "Exit code 1" | Run `./scripts/doctor.sh` |
| Configuration not saving | Check permissions on `~/.config/ai-consultants/` (or `$AI_CONSULTANTS_CONFIG_DIR`) |

---

## Platform-Specific Notes

### macOS

The stock `/bin/bash` 3.2 works. Install coreutils only if you set a positive
`*_TIMEOUT`:
```bash
brew install coreutils
```

### Windows

Use WSL (Windows Subsystem for Linux):
```bash
wsl --install
# Then follow Linux instructions
```

### Linux

No special requirements (`timeout` from coreutils is used when a positive
`*_TIMEOUT` is set).

---

## Next Steps

After setup:

**Claude Code:**
```
/ai-consultants:consult "How do I optimize a SQL query?"
```

**Bash:**
```bash
# Test your configuration
output_dir=$(./scripts/consult_all.sh --preset minimal "How do I optimize a SQL query?")

# View the report
less "$output_dir/report.md"
```

See [README.md](../README.md) for usage examples and full documentation.

For a configuration outside the standard user config directory, set
`AI_CONSULTANTS_CONFIG_DIR=/absolute/private/config-directory` explicitly.
The loader does not discover project `.env` files. Keep credentials in your
existing private configuration; do not copy them into this repository.

Claude CLI uses `stream-json --verbose`. Only response-bearing assistant
messages attest the content model; terminal `modelUsage` records billing
participants separately. A missing or conflicting content model remains
`requested-only` and cannot pass a model-promotion gate. Successful terminal
completion is required even when partial response text or billing is available.

Codex defaults to `gpt-6.1-sol` (default and premium); `max_quality` selects
`gpt-6-astra`, standard also selects `gpt-6.1-sol` (there is no GPT-6 mid
model, and Sol costs less than GPT-5.6 Terra did), and economy selects `gpt-6-luna`.
GPT-6.1 Sol is close to Astra on agentic coding at one fifth of its token price.
Configure migrates exact unpinned persisted `gpt-5.5`, `gpt-5.6-sol` and
`gpt-6-astra` values to `gpt-6.1-sol` and records `migrated-from` provenance
(the earliest origin is kept across chained migrations). Use
`# ai-consultants:pin`, an environment override or `--set` to keep a model,
for example `--set CODEX_MODEL=gpt-6-astra` to keep Astra as the default.

GPT-6 Astra and GPT-6.1 Sol use `high` effort when no effort is configured
(their provider default is `medium`); economy GPT-6 Luna keeps the provider
default. Explicit `low`, `medium`, `high`, `xhigh`, and `max` prevail;
`none`/`minimal` fail before dispatch on all three.
The default completion budget is 16384 tokens, including reasoning; override
`CODEX_API_MAX_TOKENS` explicitly as needed. The text-only Chat Completions
request uses `max_completion_tokens` and `reasoning_effort`, without tools.
See the [official migration guide](https://developers.openai.com/api/docs/guides/latest-model).
CLI JSON events supply token telemetry; the final message file supplies content.
A CLI `-m` selection remains `requested-only`, not provider attestation.

[GPT-6.1 Sol Standard pricing](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
is $2/M input and $10/M output;
[Astra Standard pricing](https://developers.openai.com/api/docs/models/gpt-6-astra)
is $10/M input and $50/M output. For both, more than 272K input tokens doubles
input and multiplies output by 1.5 for the whole request. Reported cost is an estimate
unless a provider cost is supplied: cache writes, cached-input discounts and
service processing rates can change the invoice.

Grok CLI and doctor passively inspect the container-runtime socket deny paths,
including Docker Desktop locations. Symlink endpoints (including dangling links)
block CLI dispatch because the sandbox cannot safely resolve those deny rules.
Absent paths and ordinary socket files pass this check. Nothing is removed and
Docker configuration is never changed. Runtime `sandbox_profile_refused` and
`sandbox_not_applied` diagnostics fail even with exit zero; they cannot trigger
retry or API fallback. OAuth synchronization and per-run isolation remain active.


Grok compatibility includes a provider-free parser probe of the complete advisory
argument list. Hidden flags such as `--no-memory` are still required in the
actual request even when omitted from public help. Unsupported mandatory flags
block dispatch; the optional `--no-auto-update` guard is used when its parser
probe succeeds, including on CLIs that hide it from help.

### Retired models (5.5.0)

Each tier uses only current models. Superseded models are listed in
`retired_models` in `docs/cost_rates.json`, each with its family's current
replacement (for example `claude-haiku-4-5` -> `claude-haiku-5-5`,
`gpt-5.6-luna` -> `gpt-6-luna`, `grok-4.5` -> `grok-4.7`, `glm-4-flash` ->
`glm-5.3-flash`, `kimi-code/k3` -> `kimi-code/k3.1-pro`).

- `ai-consultants configure` replaces a persisted retired value even when it is
  pinned. The marker is kept, the old value is recorded as `migrated-from=`
  (spaces become underscores), and the timestamped backup keeps the original.
- `configure --set` refuses a retired model and names the replacement.
- A retired or uncatalogued model selected at run time, for example by an
  environment variable, still runs. The run warns, and the cost report names
  it as unpriced instead of applying a default rate.

### DeepSeek V4.1 Flash

DeepSeek uses the HTTP API with `DEEPSEEK_MODEL=deepseek-flash` in every tier.
This is the official API alias for DeepSeek-V4.1-Flash as of 2026-09-10, not a
version identity inferred from the requested name. Provider-reported model
metadata is retained unchanged. `max_quality` continues to request `max` effort;
other tiers leave effort to the provider unless explicitly configured. The
provider defaults to thinking mode at high effort. Existing text-only Chat
Completions requests and the 16,384-token completion budget remain compatible.

`configure` migrates an exact unpinned `deepseek-v4-pro` default to
`deepseek-flash`; a pinned `deepseek-v4-pro` (a current opt-in at $1.32/$3.96
per 1M) is kept. The retired `deepseek-v4-flash` aliases, which the provider
still routes to V4.1 Flash, are migrated even when pinned. Peak cache-miss costs are estimates, excluding cache/off-peak
discounts. An authorized one-attempt API smoke on 2026-09-10 passed with a structured
response and provider-reported `deepseek-flash`; no version identity was invented
from the alias. No CLI transport is introduced.

Sources: [models/pricing](https://api-docs.deepseek.com/quick_start/pricing/) and
[thinking mode](https://api-docs.deepseek.com/guides/thinking_mode/).

### Grok 4.7 and Claude Opus 5.5

Grok uses `grok-4.7` in every tier since 5.5.0 (same price as Grok 4.5).
`grok-4.5` and `grok-4.6` are retired: configure migrates them even when
pinned, and `--set` refuses them. Unrelated IDs survive.
The existing capability/model inventory probes, strict sandbox and OAuth
isolation still apply; the Grok 4.7 Fast variant is not implicitly selected.

Claude standard/medium selects `claude-opus-5-5`; default/premium/maximum
remain Fable 5.1 and economy uses Haiku 5.5 (since 5.5.0). Select Opus directly with
`configure --set CLAUDE_MODEL=claude-opus-5-5`. The historical unpinned Claude
default migration to Fable is unchanged; pinned retired Opus, Sonnet and Fable
models move to their family's current model and stay pinned.

Opus 5.5 has always-on adaptive thinking, including empty thinking display
blocks. Our tool-free single-turn API request omits thinking overrides, sampling
parameters and forced tool choice; parsing selects visible text by block type.
The API therefore uses the provider's default effort (medium), with the existing
16384 total-output budget. The CLI retains explicit `CLAUDE_REASONING_EFFORT`
control. Content identity and terminal success remain separate checks.

These additions have offline regression coverage. Grok 4.7 and Opus 5.5 CLI
smokes passed on 2026-09-28. New API transports remain separately unverified. Frozen
P1.6 benchmark IDs/efforts/preregistration are not changed by this update.
See the [Opus migration guide](https://platform.claude.com/docs/en/models/opus-5-5/migration-guide)
and [Grok 4.7](https://docs.x.ai/developers/grok-4-7).

### Gemini 4 Argon

Gemini 4 Argon (GA 2026-10-13) serves the default (premium) and maximum tiers:
`Gemini 4 Argon (High)` on `agy` (listed by `agy models` 1.3.6 with Medium and
Low variants) and `gemini-4-argon` on the API. One authorized `agy` consultation
smoke passed on 2026-10-16: structured answer, capability-probed identity, about
49 s for a short question. The API transport has offline tests only; it needs a
paid-tier key, because Google excludes Argon from the Free tier and the AI Pro
plan. On the API, Argon defaults to the `high` thinking level, takes no sampling
parameters, and spends thinking from `GEMINI_API_MAX_TOKENS` (default 32768).

Configure migrates an unpinned `Gemini 3.8 Flash (High)`, `Gemini 3.7 Flash (High)`
or `Gemini 3.1 Pro (High)` CLI value to `Gemini 4 Argon (High)`, and an unpinned
`gemini-3.1-pro-preview` API value to `gemini-4-argon`. Pin `Gemini 3.8 Flash
(High)` with `# ai-consultants:pin` to keep it; Gemini 3.7 Flash and 3.1 Pro
are retired and migrate even when pinned.

### Gemini 3.8 Flash

The installed `agy models` inventory on 2026-09-27 lists Gemini 3.8 Flash
(High), (Medium) and (Low). CLI standard selects High and economy selects Low.
Medium remains an explicit `GEMINI_MODEL` choice. Inventory
evidence is capability-probed, not provider attestation of a generated answer.

Configure migrates Flash 3.7 (and 3.6/3.5) values to the same-level 3.8
Flash, pinned or not; unrelated models are preserved. Since 5.5.0 the API
standard and economy tiers use `gemini-3.8-flash` (offline-tested); its
native thinking levels are low/medium/high. Other explicit efforts fail before
dispatch. With no effort setting, the provider's API default is medium.

Inventory discovery performed no inference. Separately authorized High/Low CLI
smokes passed on 2026-09-28, using the named variant without --effort. This is
capability-probed provenance, not provider content-model attestation. Prices are promotional estimates
through 2026-12-31; see [Google's model guide](https://ai.google.dev/gemini-api/docs/latest-model).
The frozen P1.6 inputs remain unchanged.

For Google GenerateContent accounting, output tokens include both
`candidatesTokenCount` and `thoughtsTokenCount`. Input uses `promptTokenCount`,
which already includes cached content. This avoids dropping billed thinking
or adding cache tokens twice; it applies to the existing Google API path too.
See [UsageMetadata](https://ai.google.dev/api/generate-content).

For named Gemini 3.8 Flash High/Medium/Low CLI variants, leave
`GEMINI_REASONING_EFFORT` unset: the level is selected by `GEMINI_MODEL`, and
`agy` rejects an additional `--effort` for these variants. The CLI's general
help lists effort values for other supported model selections; it does not
establish support for every model. Native API thinking remains separately
configured with low/medium/high.
