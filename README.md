# AI Consultants v2.22.0

> **A harness for every question.** A panel of up to 11 frontier models that writes its own playbook per question — fan out, debate to convergence, cross-examine under adversarial review, or run a tournament — and checks its work before it reaches you.

[![Version](https://img.shields.io/badge/version-2.22.0-blue.svg)](https://github.com/matteoscurati/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)
[![GitHub stars](https://img.shields.io/github/stars/matteoscurati/ai-consultants?style=social)](https://github.com/matteoscurati/ai-consultants)
[![agentskills.io](https://img.shields.io/badge/agentskills.io-compatible-blue.svg)](https://agentskills.io)

---

## Table of Contents

- [Why AI Consultants?](#why-ai-consultants)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Supported CLI Agents](#supported-cli-agents)
  - [Claude Code](#claude-code)
  - [OpenAI Codex CLI](#openai-codex-cli)
  - [Gemini CLI](#gemini-cli)
  - [Cursor / Copilot / Windsurf](#cursor--copilot--windsurf-via-skillport)
  - [Standalone Bash](#standalone-bash)
- [Consultants](#consultants)
- [Quality Tiers](#quality-tiers)
- [Configuration](#configuration)
  - [Configuration Recipes](#configuration-recipes)
- [How It Works](#how-it-works)
- [Best Practices](#best-practices)
- [Documentation](#documentation)
- [Changelog](#changelog)
- [License](#license)

---

## Why AI Consultants?

A single model gives you a single guess. AI Consultants gives you a **panel that deliberates — and adapts how it deliberates to the question in front of it.**

Instead of running a fixed script, it classifies your question, picks an orchestration **shape**, and iterates until the answers hold up — the way a workflow builds a harness for the task at hand:

- **Dynamic orchestration** — the engine chooses the strategy per question: a quick read, a convergence loop, an adversarial refutation gate, a tournament of approaches, or an exhaustive sweep
- **Convergence, not fixed rounds** — debate iterates until the panel actually agrees (or provably won't), instead of a hardcoded count
- **Self-checking** — security answers are stress-tested by consultants trying to refute them before anything reaches you
- **11 supported consultants** with distinct personas (Architect, Pragmatist, Devil's Advocate, …)
- **Confidence-weighted synthesis** — one recommendation, with the dissent and the path it took surfaced so you know how much to trust it

---

## Quick Start

Get started in 30 seconds:

### Option A: npx (recommended)

```bash
# Run directly - no install needed
npx ai-consultants "How should I structure my authentication system?"

# With a preset
npx ai-consultants --preset balanced "Redis or Memcached?"

# Run diagnostics
npx ai-consultants doctor --fix

# Install slash commands for Claude Code
npx ai-consultants install
```

### Option B: curl | bash (Claude Code skill)

```bash
# Install the skill
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Ask your first question
/ai-consultants:consult "How should I structure my authentication system?"
```

### Update & Uninstall

```bash
# npx always runs latest (or pin a version)
npx ai-consultants@latest "question"

# curl | bash update
~/.claude/skills/ai-consultants/scripts/install.sh --update

# Uninstall (curl | bash only)
~/.claude/skills/ai-consultants/scripts/install.sh --uninstall
```

---

## Prerequisites

Before installing AI Consultants, ensure you have the following dependencies installed.

### Required Dependencies

| Dependency | Purpose |
|------------|---------|
| **jq** | JSON processing |
| **curl** | HTTP requests and connectivity |
| **Bash 4.0+** | Script execution (macOS ships with 3.2) |

### Installation by Platform

#### macOS

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required dependencies
brew install jq bash coreutils

# Verify installation
jq --version && bash --version | head -1
```

> **Note:** macOS ships with Bash 3.2. The Homebrew version (4.x) is installed to `/opt/homebrew/bin/bash`.

#### Linux (Ubuntu/Debian)

```bash
# Install required dependencies
sudo apt-get update
sudo apt-get install -y jq curl bash

# Verify installation
jq --version && bash --version | head -1
```

#### Linux (Fedora/RHEL/CentOS)

```bash
# Install required dependencies
sudo dnf install -y jq curl bash

# Verify installation
jq --version && bash --version | head -1
```

#### Linux (Arch)

```bash
# Install required dependencies
sudo pacman -S jq curl bash

# Verify installation
jq --version && bash --version | head -1
```

#### Windows

Use **WSL (Windows Subsystem for Linux)**:

```powershell
# Install WSL (run in PowerShell as Administrator)
wsl --install

# After restart, open WSL and follow Linux instructions
sudo apt-get update
sudo apt-get install -y jq curl bash
```

Alternatively, use **Git Bash** or **MSYS2** with the required packages.

### Optional Dependencies

For CLI-based consultants, you'll also need:

| Dependency | Required for |
|------------|--------------|
| **Node.js 18+** | Gemini CLI, Codex CLI, Qwen CLI, MiniMax CLI |
| **Python 3.8+** | Mistral Vibe CLI |

```bash
# macOS
brew install node python

# Ubuntu/Debian
sudo apt-get install -y nodejs npm python3 python3-pip

# Verify
node --version && python3 --version
```

### Verify All Prerequisites

Run the doctor command to check everything is installed:

```bash
./scripts/doctor.sh
```

---

## Supported CLI Agents

AI Consultants follows the open [Agent Skills standard](https://agentskills.io), enabling cross-platform compatibility.

### Claude Code

> **Status:** ✅ Native support

**Installation:**

```bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

**Slash Commands:**

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show all commands and usage |

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

**Self-Exclusion:** Claude consultant is automatically excluded when invoked from Claude Code.

**Verify:**

```bash
./scripts/doctor.sh
```

---

### OpenAI Codex CLI

> **Status:** ✅ Compatible

**Installation:**

```bash
git clone https://github.com/matteoscurati/ai-consultants.git ~/.codex/skills/ai-consultants
~/.codex/skills/ai-consultants/scripts/doctor.sh --fix
```

**Commands:**

Use the same slash commands as Claude Code. Codex CLI loads skills from `~/.codex/skills/`.

**Self-Exclusion:** Codex consultant is automatically excluded when invoked from Codex CLI.

**Verify:**

```bash
~/.codex/skills/ai-consultants/scripts/doctor.sh
```

---

### Gemini CLI

> **Status:** ✅ Compatible

**Installation:**

```bash
git clone https://github.com/matteoscurati/ai-consultants.git ~/.gemini/skills/ai-consultants
~/.gemini/skills/ai-consultants/scripts/doctor.sh --fix
```

**Commands:**

Use the same slash commands as Claude Code. Gemini CLI loads skills from `~/.gemini/skills/`.

**Self-Exclusion:** Gemini consultant is automatically excluded when invoked from Gemini CLI.

**Verify:**

```bash
~/.gemini/skills/ai-consultants/scripts/doctor.sh
```

---

### Cursor / Copilot / Windsurf (via SkillPort)

> **Status:** ✅ Via SkillPort

**Installation:**

```bash
# Install SkillPort if not already installed
npm install -g skillport

# Add AI Consultants skill
skillport add github.com/matteoscurati/ai-consultants

# Load skill in your agent
skillport show ai-consultants
```

Or clone and use the included installer:

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
./scripts/skillport-install.sh
```

**Commands:**

SkillPort translates skill commands to the native agent format.

**Self-Exclusion:** Cursor consultant is automatically excluded when invoked from Cursor.

**Verify:**

```bash
skillport status ai-consultants
```

---

### Standalone Bash

> **Status:** ✅ Direct execution

**Installation:**

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
./scripts/doctor.sh --fix
./scripts/setup_wizard.sh
```

**Commands:**

```bash
# Basic consultation
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# With preset
./scripts/consult_all.sh --preset balanced "Redis or Memcached?"

# With debate
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "Microservices vs monolith?"

# With smart routing
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh "Bug in auth code"

# Follow-up questions
./scripts/followup.sh "Can you elaborate on that point?"
./scripts/followup.sh -c Gemini "Show me code example"
```

**Self-Exclusion:** Set `INVOKING_AGENT` environment variable:

```bash
INVOKING_AGENT=claude ./scripts/consult_all.sh "Question"   # Claude excluded
INVOKING_AGENT=codex ./scripts/consult_all.sh "Question"    # Codex excluded
./scripts/consult_all.sh "Question"                          # No exclusion
```

**Verify:**

```bash
./scripts/doctor.sh
```

---

## Consultants

### CLI-Based Consultants

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `agy` | The Architect | Design patterns, scalability, enterprise |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, quick wins, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Problems, edge cases, vulnerabilities |
| **Cursor** | `agent` | The Integrator | Full-stack perspective |
| **Kimi K3** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis, connecting ideas |
| **Qwen3** | `qwen` | The Analyst | Data-driven analysis |
| **MiniMax** | `mmx` | The Pragmatic Optimizer | Performance, efficiency, pragmatism |

Qwen3 and MiniMax can switch from their CLI to API transport. Gemini, Codex,
Claude, and Mistral are also CLI/API switchable.

### API-Only Consultants

| Consultant | Default Model | Persona | Focus |
|------------|---------------|---------|-------|
| **GLM** | glm-5.2 | The Methodologist | Structured approaches |
| **Grok** | grok-4.5 | The Provocateur | Challenge conventions |
| **DeepSeek** | deepseek-v4-pro | The Code Specialist | Algorithms, code generation |

### Installing Consultant CLIs

At least 2 consultant CLIs are required:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash  # Gemini (Antigravity CLI: agy)
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
curl https://cursor.com/install -fsS | bash  # Cursor

# Optional CLI-based consultants
curl -L code.kimi.com/install.sh | bash            # Kimi K3
npm install -g @qwen-code/qwen-code@latest  # Qwen (alternative to API)
npm install -g mmx-cli                       # MiniMax

```

Kimi is pinned to K3 for every consultation, even if the user's Kimi CLI has a
different default model:

```bash
KIMI_MODEL=kimi-code/k3 ai-consultants \
  "Review this API design from a holistic perspective"
```

---

## Quality Tiers

Choose the right balance of quality, speed, and cost with model quality tiers.

### Tier Presets

| Preset | Tier | Agents | Use Case |
|--------|------|--------|----------|
| `max_quality` | Premium | 8 of 11 | Critical decisions |
| `medium` | Standard | 4 | General questions |
| `fast` | Economy | 2 | Quick checks |

**Deliberation depth is not fixed by the preset.** Under the default
`ORCHESTRATION_MODE=auto` the planner picks the shape per question, so the
`DEBATE_ROUNDS` a preset pins applies only under `ORCHESTRATION_MODE=fixed`,
and a `SECURITY`-classified question runs the adversarial shape — including a
peer-review round — whatever preset you chose. `max_quality` additionally
enables peer review outright; `medium` and `fast` do not *clear* it, so an
enabled peer review carries into them.

### Models by Tier

| Consultant | Premium | Standard | Economy |
|------------|---------|----------|---------|
| Claude | claude-opus-4-8 | claude-sonnet-4-6 | claude-haiku-4-5 |
| Gemini | Gemini 3.1 Pro (High) | Gemini 3.5 Flash (High) | Gemini 3.5 Flash (Low) |
| Codex | gpt-5.5 | gpt-5.4 | gpt-5.4-nano |
| Mistral | mistral-large-3 | mistral-medium-latest | devstral-small-2 |
| Cursor | composer-2.5 | composer-2 | gemini-3-flash |
| DeepSeek | deepseek-v4-pro | deepseek-v4-flash | deepseek-v4-flash |
| GLM | glm-5.2 | glm-5.2 | glm-4-flash |
| Grok | grok-4.5 | grok-4.1-fast | grok-4.1-fast |
| Qwen3 | qwen3.7-max | qwen3.6-35b-a3b | qwen3-32b |
| Kimi | kimi-code/k3 | kimi-code/k3 | kimi-code/k3 |
| MiniMax | MiniMax-M2.7 | MiniMax-M2.7 | MiniMax-M2.5 |

### Usage

**Claude Code:**
```
/ai-consultants:consult --preset max_quality "critical architecture decision"
/ai-consultants:consult --preset fast "quick syntax question"
```

**Bash:**
```bash
./scripts/consult_all.sh --preset max_quality "microservices vs monolith?"
./scripts/consult_all.sh --preset fast "how to use async/await?"

# Programmatic tier selection
source scripts/config.sh
apply_model_tier "premium"   # Set all to premium models
apply_model_tier "economy"   # Set all to economy models
```

---

## Configuration

### Presets

Choose how many consultants to use:

| Preset | Consultants | Tier | Use Case |
|--------|-------------|------|----------|
| `max_quality` | 8 of 11 (+ peer review) | Premium | Critical decisions |
| `medium` | 4 | Standard | General questions |
| `fast` | 2 | Economy | Quick checks |
| `minimal` | 2 (Gemini + Codex) | Default | Quick questions, low cost |
| `balanced` | 4 (+ Mistral + Cursor) | Default | Standard consultations |
| `thorough` | 4 | Default | Comprehensive analysis |
| `high-stakes` | Expanded panel + debate | Default | Critical decisions |
| `security` | Security-focused + debate | Default | Security reviews |
| `cost-capped` | Budget-conscious | Default | Minimal API costs |

**Bash:**
```bash
./scripts/consult_all.sh --preset balanced "Question"
```

### Synthesis Strategies

Control how responses are combined:

| Strategy | Description |
|----------|-------------|
| `majority` | Most common answer wins (default) |
| `risk_averse` | Weight conservative responses higher |
| `security_first` | Prioritize security considerations |
| `cost_capped` | Prefer simpler, cheaper solutions |
| `compare_only` | No recommendation, just comparison |

**Bash:**
```bash
./scripts/consult_all.sh --strategy risk_averse "Question"
```

### Environment Variables

**Automatic configuration (recommended):**

```bash
# Detect installed CLIs and available API keys, then write the persistent config
ai-consultants configure

# Review the consultant selection and transports interactively
ai-consultants configure --interactive

# Set any persistent parameter without opening an editor
ai-consultants configure \
  --set DEFAULT_PRESET=balanced \
  --set ENABLE_DEBATE=true \
  --set ORCHESTRATION_MODE=converge

# Inspect the complete machine-readable parameter surface
ai-consultants configure --show-parameters
```

The configurator covers every persistent setting in `scripts/config.sh`, plus
credentials, persona overrides, transport controls, advanced context knobs, and
calibration commands. Existing custom values and secrets are preserved, while
`ENABLE_*` flags are refreshed from detected availability (and can be pinned
with `--set`). Rewrites create a private timestamped backup. Use `--advanced` to
review every parameter or `--dry-run` to preview a redacted result.
Auto-selected `*_USE_API` values are marked `# ai-consultants:auto`, allowing a
later run to adapt when a CLI or credential changes. Environment variables,
`--set`, and unmarked values remain explicit user choices.

Enter credentials through `--interactive`/`--advanced` or export them before the
run; avoid passing API keys through `--set`, where the shell may retain them in
history or expose them in the process list.

For a manual starter template instead, run `ai-consultants init` and edit
`~/.config/ai-consultants/.env`.

For ad-hoc overrides without persisting, the most common knobs:

```bash
DEFAULT_PRESET=balanced      # minimal | balanced | thorough | high-stakes | fast | security
DEFAULT_STRATEGY=majority    # majority | risk_averse | security_first | cost_capped | compare_only
ENABLE_DEBATE=true           # Multi-agent debate (auto-skipped when consensus is high since v2.13)
MAX_SESSION_COST=1.00        # USD budget cap (paired with ENABLE_BUDGET_LIMIT=true to enforce)
KIMI_MODEL=kimi-code/k3      # Pin the Kimi consultant to K3
```

Full reference: [`references/configuration.md`](references/configuration.md). Copy-paste workflows: [`docs/RECIPES.md`](docs/RECIPES.md). For category-aware preset suggestions: `ai-consultants doctor --suggest-preset --question "..."`.

### Configuration Recipes

**Dynamic debate until convergence:**

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=converge \
CONVERGENCE_MAX_ROUNDS=4 \
CONVERGENCE_TARGET_CONSENSUS=75 \
ai-consultants --strategy risk_averse \
  "Event log or mutable relational state for this service?"
```

**Repeatable two-round review:**

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=fixed \
DEBATE_ROUNDS=2 \
ENABLE_DEBATE_OPTIMIZATION=false \
ai-consultants "Review this migration plan" docs/migration.md@PRIMARY
```

**Security review with adversarial verification:**

```bash
ENABLE_DEBATE=true \
ORCHESTRATION_MODE=adversarial \
ENABLE_PEER_REVIEW=true \
ai-consultants --preset security --strategy security_first \
  "Find authentication bypasses" src/auth.ts@PRIMARY
```

**Live health gate plus hard quorum:**

```bash
ENABLE_HEALTH_GATE=true \
QUORUM_MIN=3 \
QUORUM_ACTION=stop \
ai-consultants "Make a release recommendation"
```

See [13 complete recipes](docs/RECIPES.md) for fast, high-stakes, tournament,
exhaustive audit, budget-capped, CLI-only, hybrid API, semantic-consensus, and
large-context workflows.

### Doctor Command

Diagnose, suggest, and fix:

```bash
ai-consultants doctor                                          # Installation and configuration checks
ai-consultants doctor --fix                                    # Auto-fix common issues
ai-consultants doctor --json                                   # JSON for automation
ai-consultants doctor --live                                   # Real ping per consultant — catches installed-but-unauthenticated CLIs
ai-consultants doctor --suggest-config                         # Print recommended ENABLE_* based on detected CLIs
ai-consultants doctor --suggest-preset --question "..."        # Recommend preset + strategy for a question
ai-consultants update-clis                                     # Check & update every installed consultant CLI
ai-consultants update-clis --dry-run                           # Preview: each CLI's install method + update command
```

> When a consultant fails mid-consultation, the run surfaces the captured reason (e.g. `CLI not found`, `401 Unauthorized`) instead of a bare "Failed", so you can tell *not installed* from *not authenticated* from *transient*.

---

## How It Works

```
Classify -> Plan shape -> Fan out -> Deliberate & converge -> Synthesize
   |            |             |               |
 category   orchestration  Gemini (8)    convergence loop /
 complexity    shape       Codex (7)     adversarial gate /
 intent                    Mistral (6)   tournament / exhaustive
                           Cursor (9)
```

The **shape** is chosen per question (or pinned via `ORCHESTRATION_MODE`):

| Shape | When | What happens |
|-------|------|--------------|
| `quick` | simple questions | one fan-out, no debate |
| `converge` | most questions | debate rounds until consensus is reached (not a fixed count) |
| `adversarial` | security | a forced critique round + peer-review refutation gate |
| `tournament` | "compare X vs Y" | converge, then declare a single winning approach |
| `exhaustive` | "find all / audit" | loop until a round surfaces no new angle |

Set `ORCHESTRATION_MODE=fixed` for the classic fixed-round pipeline.

Consensus is measured lexically by default; set `ENABLE_STANCE_CONSENSUS=true`
(opt-in, v2.21) to have the panel pick from a shared set of enumerated stance
options and score agreement by exact match instead — see
[references/configuration.md](references/configuration.md#semantic-consensus-v221-opt-in).

With peer review:
```
Responses -> Anonymize -> Peer Ranking -> De-anonymize -> Peer Scores
```

### Output

Each consultation generates:

```
/tmp/ai_consultations/TIMESTAMP/
├── gemini.json          # Individual responses
├── codex.json           #   with confidence scores
├── mistral.json
├── cursor.json
├── voting.json          # Consensus calculation
├── synthesis.json       # Weighted recommendation
├── report.md            # Human-readable report
└── round_2/             # (if debate enabled)
```

---

## Best Practices

### When to Use High-Stakes Mode

- Architectural decisions affecting system design
- Security-critical code changes
- Performance-critical optimizations
- Decisions that are difficult to reverse

### Interpreting Results

| Scenario | Recommendation |
|----------|----------------|
| High confidence + High consensus | Proceed with confidence |
| Low confidence OR Low consensus | Consider more options |
| Mistral (Devil's Advocate) disagrees | Investigate the risks |
| Panic mode triggered | Add more consultants or debate rounds |

### Security

- **Never** include credentials or API keys in queries
- Review and redact sensitive code before sending it to any external consultant
- Files in `/tmp` are automatically cleaned up

---

## Documentation

- [Setup Guide](docs/SETUP.md) - Installation, authentication, Claude Code setup
- [Configuration Recipes](docs/RECIPES.md) - Copy-paste workflows for debate, routing, budgets, and transport
- [Cost Rates](docs/COST_RATES.md) - Model pricing and budgets
- [Smart Routing](docs/SMART_ROUTING.md) - Category-based routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format specification
- [Reference Details](references/details.md) - Presets, strategies, best practices
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## Changelog

### v2.22.0

- **`ai-consultants configure`**: a public automatic configurator. It detects your installed CLIs and API keys, picks CLI-first transports, and writes a private XDG config while preserving your existing settings and secrets. Drive it with repeatable `--set KEY=VALUE`, review it with `--interactive` / `--advanced`, or preview it with `--dry-run`. See the [v2.22.0 release note](docs/releases/v2.22.0.md).

### v2.21.1

- **Kimi K3**: Kimi now defaults to `kimi-code/k3`, and the adapter passes the model explicitly with `--model`.
- **Focused 11-consultant roster**: Kilo, Aider, Amp, and Ollama were removed end-to-end, including their adapters and configuration variables. See the [v2.21.1 release note](docs/releases/v2.21.1.md) for migration guidance.

### v2.15.1

- **Gemini fixes (Antigravity CLI)**: the default model (`Gemini 3.1 Pro (High)`) wraps its JSON in a ```` ```json ```` fence; v2.15.0 didn't strip it, so every Gemini reply degraded to a generic fallback. Now de-fenced on all paths (response processing, self-reflection, synthesis).
- **Works out-of-the-box for `npx`**: Gemini auto-selects API mode when `GEMINI_API_KEY` is set (the `agy` CLI can't be npm-installed and is OAuth-only), so a key-only environment no longer silently drops Gemini.
- **Synthesis no longer hangs** when `agy` is the synthesizer (it was launched interactively instead of in print mode).

### v2.10.0

- **MiniMax M2.5 support**: New API-based consultant with "The Pragmatic Optimizer" persona
- **15 consultants total**: Gemini, Codex, Mistral, Kilo, Cursor, Aider, Amp, Kimi, Claude, Qwen3, GLM, Grok, DeepSeek, MiniMax, Ollama
- **npx distribution**: `npx ai-consultants "question"` - run directly without install
- **npm packaging**: `package.json` with zero dependencies, `.npmignore` for clean publishing

### v2.8.1

- **Bug fixes**: Fixed `((count++))` abort under `set -e`, missing Amp in consultant map, hardcoded `claude` in synthesize.sh
- **Security**: Variable name validation before `export` in escalation and cost-aware routing
- **DRY refactoring**: Rewrote `query_kilo.sh` and `query_cursor.sh` using shared `process_consultant_response()`; added `get_model_for_tier()` as single source of truth

### v2.8.0

- **Amp CLI support**: New consultant with "The Systems Thinker" persona
- **13 consultants total**: Gemini, Codex, Mistral, Kilo, Cursor, Aider, Amp, Claude, Qwen3, GLM, Grok, DeepSeek, Ollama
- **Installation**: `curl -fsSL https://ampcode.com/install.sh | bash`

### v2.7.0

- **Qwen CLI support**: CLI/API mode switching for Qwen3 via qwen-code
- **5 switchable agents**: Gemini, Codex, Claude, Mistral, and now Qwen3 support CLI/API mode
- **CLI default**: `QWEN3_USE_API` defaults to `false` (CLI mode via qwen-code)

### v2.6.0

- **CLI/API mode switching**: Gemini, Codex, Claude, and Mistral can switch between CLI and API mode
- **New environment variables**: `*_USE_API` and `*_API_URL` for each switchable agent
- **Unified API query module**: `lib/api_query.sh` for consistent API handling

### v2.5.0

- **Model quality tiers**: Premium, standard, and economy tiers for all consultants
- **New presets**: `max_quality`, `medium`, `fast` for quick tier selection
- **Premium defaults**: All consultants now use premium models by default (March 2026)
- **`apply_model_tier()` function**: Programmatically switch all models to a tier
- **Updated models**: opus-4.6, gemini-3.1-pro-preview, gpt-5.3-codex, mistral-large-3, etc.

### v2.4.0

- **Budget enforcement**: Optional budget limits with configurable actions (warn/stop)
- **Budget checks**: 4 enforcement points (before/after consultation, debate, synthesis)
- **Budget configuration**: Configurable via natural language or environment variables

### v2.3.0

- **Semantic caching**: Cache responses to avoid redundant API calls (15-25% savings)
- **Cost-aware routing**: Route simple queries to cheaper models (30-50% savings)
- **Fallback escalation**: Auto-escalate to premium model if confidence < 7
- **Debate optimization**: Skip debate if all consultants agree (opt-in)
- **Category exceptions**: SECURITY/ARCHITECTURE always trigger debate
- **Quality monitoring**: `optimization_metrics.json` tracks optimization impact
- **Compact reports**: Shorter reports by default (summaries only)
- **Response limits**: Per-category token limits (opt-in)

### v2.2.0

- **Claude consultant**: New consultant with "The Synthesizer" persona
- **Self-exclusion**: Invoking agent automatically excluded from panel
- **Presets**: Quick configuration with `--preset minimal/balanced/high-stakes/security`
- **Doctor command**: Diagnostic and auto-fix tool
- **Synthesis strategies**: `--strategy majority/risk_averse/security_first/compare_only`
- **Confidence intervals**: Statistical confidence ranges (e.g., "8 +/- 1.2")
- **Anonymous peer review**: Unbiased evaluation of responses
- **Ollama support**: Local model inference for privacy
- **Panic mode**: Automatic rigor when uncertainty detected
- **One-liner install**: `curl | bash` installation

### v2.1.0

- New consultants: Aider, DeepSeek
- 17 configurable personas
- Token optimization with AST extraction

### v2.0.0

- Persona system with 15 predefined roles
- Confidence scoring (1-10) on every response
- Auto-synthesis with weighted recommendations
- Multi-Agent Debate (MAD)
- Smart routing by question category
- Session management and cost tracking

---

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
