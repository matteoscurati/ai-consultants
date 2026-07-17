# Setup Guide - AI Consultants v2.21.1

This guide walks you through installing and configuring AI Consultants for various AI coding agents.

---

## Supported Agents

AI Consultants follows the open [Agent Skills standard](https://agentskills.io), enabling cross-platform compatibility:

| Agent | Skills Directory | Status |
|-------|-----------------|--------|
| **Claude Code** | `~/.claude/skills/` | ✅ Native |
| **OpenAI Codex CLI** | `~/.codex/skills/` | ✅ Compatible |
| **Gemini CLI** | `~/.gemini/skills/` | ✅ Compatible |
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

This detects installed CLIs and available API keys for the complete 11-agent
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

AI Consultants provides 3 slash commands:

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
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

Once installed, Codex CLI will discover the skill and make slash commands available.

---

## Gemini CLI Setup

Gemini CLI also supports the Agent Skills standard.

### Installation

```bash
# Option A: Clone directly
git clone https://github.com/matteoscurati/ai-consultants.git ~/.gemini/skills/ai-consultants

# Option B: Symlink
ln -s ~/.claude/skills/ai-consultants ~/.gemini/skills/ai-consultants
```

### Verify

```bash
~/.gemini/skills/ai-consultants/scripts/doctor.sh
```

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

### Recommended
- **Bash 4.0+** (macOS ships with 3.2 - install newer version)
- **timeout/gtimeout** for command timeouts (has POSIX fallback)
- **Node.js 18+** for npm-based CLIs
- **Python 3.8+** for pip-based CLIs

### Optional
- **bc** for cost calculations (usually pre-installed)

### Install Bash 4+ (macOS)

```bash
brew install bash
sudo bash -c 'echo /opt/homebrew/bin/bash >> /etc/shells'
```

### Install jq

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Verify
jq --version
```

### Install timeout (macOS)

macOS doesn't include `timeout` by default. Install coreutils for `gtimeout`:

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

Get API key: [Google AI Studio](https://makersuite.google.com/app/apikey)

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

### Cursor CLI (The Integrator)

```bash
curl https://cursor.com/install -fsS | bash

# Uses Cursor subscription - no additional key needed
```

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

### Kimi K3 via Kimi Code CLI (The Eastern Sage) - v2.21.1

```bash
curl -L code.kimi.com/install.sh | bash
```

Verify: `kimi --version`

AI Consultants pins K3 for every consultation, independently of the model in
your user-level Kimi configuration:

```bash
export KIMI_MODEL=kimi-code/k3
./scripts/query_kimi.sh "Review this API boundary"
```

### MiniMax (CLI via mmx) - v2.21

MiniMax runs via the `mmx` CLI by default (CLI-first, OAuth). Install and sign in:

```bash
npm install -g mmx-cli
mmx auth login          # OAuth (browser); or: mmx auth login --api-key <key>
```

API mode is opt-in: set `MINIMAX_USE_API=true` with `MINIMAX_API_KEY`.

Verify: `mmx --version`

---

## Self-Exclusion (v2.2)

When AI Consultants is invoked from a specific AI agent, that agent is automatically excluded from the consultant panel to prevent self-consultation.

### How It Works

| Invoking Agent | Excluded Consultant | Other Consultants |
|----------------|---------------------|-------------------|
| Claude Code | Claude | Gemini, Codex, Mistral, Cursor, Qwen, etc. |
| Codex CLI | Codex | Claude, Gemini, Mistral, Cursor, Qwen, etc. |
| Gemini CLI | Gemini | Claude, Codex, Mistral, Cursor, Qwen, etc. |
| Cursor | Cursor | Claude, Gemini, Codex, Mistral, Qwen, etc. |
| Qwen CLI | Qwen3 | Claude, Gemini, Codex, Mistral, Cursor, etc. |
| Kimi CLI | Kimi | All except Kimi |
| Bash (direct) | None | All enabled consultants (up to 11) |

### Automatic Detection

When using slash commands, `INVOKING_AGENT` is set automatically:
- Claude Code: `/ai-consultants:consult` sets `INVOKING_AGENT=claude`
- Codex CLI: `/ai-consultants:consult` sets `INVOKING_AGENT=codex`
- Gemini CLI: `/ai-consultants:consult` sets `INVOKING_AGENT=gemini`

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

Six consultants can switch between CLI mode (using local CLI tools) and API mode (direct API calls): **Gemini, Codex, Claude, Mistral, Qwen3, and MiniMax**.

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

export QWEN3_USE_API=true   # Enable API mode for Qwen3
export QWEN3_API_KEY="your-dashscope-key"
```

### API Endpoints (Custom)

```bash
GEMINI_API_URL=https://generativelanguage.googleapis.com/v1beta/models
CODEX_API_URL=https://api.openai.com/v1/chat/completions
CLAUDE_API_URL=https://api.anthropic.com/v1/messages
MISTRAL_API_URL=https://api.mistral.ai/v1/chat/completions
QWEN3_API_URL=https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
```

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
| `balanced` | 4 (+ Mistral + Cursor) | Standard |
| `thorough` | 4 | Comprehensive |
| `high-stakes` | Expanded panel + debate | Critical decisions |
| `security` | Security-focused + debate | Security reviews |
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
| `majority` | Simple voting, most common answer wins (default) |
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
| General questions | `majority` |
| Production deployments | `risk_averse` |
| Security audits | `security_first` |
| Budget constraints | `cost_capped` |
| Learning/exploration | `compare_only` |

---

## Ready-to-run configurations

These examples can be prefixed to one command or saved in
`~/.config/ai-consultants/.env`.

### Dynamic debate

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=converge \
CONVERGENCE_MAX_ROUNDS=4 \
CONVERGENCE_TARGET_CONSENSUS=75 \
ai-consultants --strategy risk_averse \
  "Should this service use an event log or mutable relational state?"
```

### Fixed two-round debate

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=fixed \
DEBATE_ROUNDS=2 \
ENABLE_DEBATE_OPTIMIZATION=false \
ai-consultants "Review this migration plan" docs/migration.md@PRIMARY
```

### Security gate with a required quorum

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=adversarial \
ENABLE_PEER_REVIEW=true \
ENABLE_HEALTH_GATE=true \
QUORUM_MIN=3 \
QUORUM_ACTION=stop \
ai-consultants --preset security --strategy security_first \
  "Find authentication bypasses" src/auth.ts@PRIMARY
```

More scenarios—including tournament, exhaustive audit, CLI-only, hybrid API,
hard-budget, semantic-consensus, and large-context runs—are in
[`docs/RECIPES.md`](RECIPES.md).

---

## Environment Configuration

### Automatic configuration (recommended)

```bash
# Detect the full roster and write ~/.config/ai-consultants/.env
ai-consultants configure

# Set any supported parameter non-interactively
ai-consultants configure \
  --set DEFAULT_PRESET=balanced \
  --set ENABLE_DEBATE=true

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
cp .env.example .env
```

Edit `.env`:

```bash
# Enable/disable consultants (11 available)
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_CLAUDE=false    # Auto-excluded when invoked from Claude Code
ENABLE_MISTRAL=false
ENABLE_CURSOR=false
ENABLE_QWEN3=false     # v2.7: The Analyst (CLI/API)
ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
ENABLE_KIMI=true
ENABLE_MINIMAX=true
MINIMAX_API_KEY=your-key

# Self-exclusion (v2.2)
INVOKING_AGENT=unknown  # Set automatically by slash commands

# API Keys
GEMINI_API_KEY=your-key
OPENAI_API_KEY=sk-your-key
MISTRAL_API_KEY=your-key
ANTHROPIC_API_KEY=sk-ant-your-key
QWEN3_API_KEY=your-dashscope-key

# CLI/API Mode Switching (v2.6+)
# GEMINI_USE_API auto-resolves when unset (v2.15.1): API if GEMINI_API_KEY is
# set, else the agy CLI. Set it explicitly only to force a specific mode.
CODEX_USE_API=false
CLAUDE_USE_API=false
MISTRAL_USE_API=false
QWEN3_USE_API=false    # Default: CLI mode
MINIMAX_USE_API=false  # Default: mmx CLI mode

# Defaults (v2.8)
DEFAULT_PRESET=balanced
DEFAULT_STRATEGY=majority

# Features
ENABLE_DEBATE=false
ENABLE_SYNTHESIS=true
ENABLE_PANIC_MODE=auto
ORCHESTRATION_MODE=auto
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
ENABLE_CURSOR=false
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

### Preflight Check

```bash
./scripts/preflight_check.sh
```

Expected output:
```
[OK] jq installed
[OK] Gemini CLI installed and authenticated
[OK] Codex CLI installed and authenticated
Status: Ready
```

### Setup Wizard (Bash)

Interactive configuration:

```bash
./scripts/setup_wizard.sh
```

The wizard will:
1. Check installed CLIs
2. Test authentication
3. Suggest configuration
4. Generate `.env` file

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

Increase timeout in `.env`:
```bash
GEMINI_TIMEOUT=300
CODEX_TIMEOUT=300
```

### "Less than 2 consultants" error

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
| Configuration not saving | Check file permissions on `~/.claude/skills/` |

---

## Platform-Specific Notes

### macOS

Install coreutils for better timeout handling:
```bash
brew install coreutils bash
```

### Windows

Use WSL (Windows Subsystem for Linux):
```bash
wsl --install
# Then follow Linux instructions
```

### Linux

No special requirements. Ensure `timeout` is available.

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
./scripts/consult_all.sh --preset minimal "How do I optimize a SQL query?"

# View the report
cat /tmp/ai_consultations/*/report.md
```

See [README.md](../README.md) for usage examples and full documentation.
