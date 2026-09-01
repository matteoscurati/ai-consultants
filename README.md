# AI Consultants v4.0.4

> **Coverage, not a single guess.** A panel of up to 10 frontier models from different vendors fans out on your question in parallel and hands you the *union* of what they collectively see — the risks, edge cases, and approaches a single model misses.

[![Version](https://img.shields.io/badge/version-4.0.4-blue.svg)](https://github.com/matteoscurati/ai-consultants)
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

A single model gives you a single guess — and it misses whatever falls in its blind spots. AI Consultants fans your question out to a **panel of models from different vendors** and returns the **union of their distinct answers**: the point one model raised and the others didn't is exactly the value.

- **Cross-vendor diversity → coverage** — different model families have different blind spots, so the union covers what any one misses. On open-ended questions ("what could go wrong with this design?", "enumerate the risks") a diverse panel covers materially more of the answer space than one strong model — or than sampling one model repeatedly.
- **Parallel fan-out** — every consultant runs at once; no serial deliberation rounds.
- **Coverage synthesis** — the default synthesis is the deduplicated *union* of every distinct point, not a single voted winner (use `--strategy compare_only` for a side-by-side, or `majority` for a blended recommendation).
- **10 supported consultants** with distinct personas (Architect, Pragmatist, Devil's Advocate, …) — the personas deliberately decorrelate the panel.
- **Best for breadth** — threat-modeling, design review, "what am I missing?", exhaustive enumeration. For a single-answer factual or defect-finding question, one strong model is usually enough.

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
| `/ai-consultants:help` | Show all commands and usage |

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

**Self-Exclusion:** Claude consultant is automatically excluded when invoked from Claude Code.
The command also prevents Claude from being selected as the synthesis provider;
Codex and every other enabled consultant remain eligible. Natural-language
skill invocations execute the panel directly rather than merely suggesting the
slash command.

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

Cursor remains a supported host through SkillPort; it is not itself a consultant in the panel.

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
./bin/ai-consultants configure
```

**Commands:**

```bash
# Basic consultation
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# With preset
./scripts/consult_all.sh --preset balanced "Redis or Memcached?"

# Side-by-side instead of the coverage union
./scripts/consult_all.sh --strategy compare_only "Microservices vs monolith?"

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
| **Kimi K3** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis, connecting ideas |
| **Qwen3** | `qwen` | The Analyst | Data-driven analysis |
| **Grok** | `grok` | The Provocateur | Challenge conventions |
| **MiniMax** | `mmx` | The Pragmatic Optimizer | Performance, efficiency, pragmatism |

Grok uses Grok Build with `grok-4.6` in an isolated, tool-free sandbox. Prompts
are passed through a private file rather than process arguments. It falls back
to the xAI API only when the CLI is missing, cannot launch, or has no usable
authentication and `GROK_API_KEY` is configured; post-launch request failures
are surfaced without a silent API charge. Grok CLI OAuth defaults to concurrent
`shared` mode: HOME, workspace, prompt, output, permissions, and agent state
remain isolated per invocation, while processes share one runner-owned
persistent `GROK_HOME` so the CLI's own auth lock can coordinate refresh.
Credential adoption/publication uses a short lock and digest CAS, so an
external `grok login` wins and the affected run fails without overwriting it or
falling back to the API. Set `GROK_OAUTH_MODE=serialized` only for diagnostic
full-run serialization. A new generation performs one locked inventory
bootstrap because Grok 1.0.4 lazily initializes home metadata; inference is
never serialized by that bootstrap. Qwen3 and MiniMax can also switch
from their CLI to API transport. Gemini, Codex, Claude, and Mistral are
CLI/API switchable. Gemini, Grok, and Kimi verify the requested model
against the CLI inventory before dispatch when that inventory exists. Grok and
Kimi compatibility is capability-probed before
dispatch: the requested model, headless arguments, and structured-output
surface must be available. Any CLI version is accepted when those checks pass;
the observed version is response provenance only.

### API-Only Consultants

| Consultant | Default Model | Persona | Focus |
|------------|---------------|---------|-------|
| **GLM** | glm-5.3-flash | The Methodologist | Structured approaches |
| **DeepSeek** | deepseek-v4-pro | The Code Specialist | Algorithms, code generation |

### Installing Consultant CLIs

At least 2 consultant CLIs are required:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash  # Gemini (Antigravity CLI: agy)
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral

# Optional CLI-based consultants
curl -L code.kimi.com/install.sh | bash            # Kimi K3
npm install -g @qwen-code/qwen-code@latest  # Qwen (alternative to API)
curl -fsSL https://x.ai/cli/install.sh | bash # Grok Build (grok-4.6)
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
| `max_quality` | Maximum + max effort | All 10 | Critical decisions |
| `medium` | Standard | 3 | General questions |
| `fast` | Economy | 2 | Quick checks |

A preset only chooses the **consultant set and model tier** — every run then fans out in
parallel and returns the coverage union.
Preset panels use statically configured transports only (a CLI on `PATH`, or selected API mode with its key). Host self-exclusion is fail-closed; lost canonical slots are filled from `ALL_CONSULTANTS` in canonical order. If the effective target cannot be met, including after an enabled health gate prunes the panel, the run stops with promised/selected/missing-capacity guidance. Configured custom API agents are appended and may satisfy capacity, so a full preset can exceed its advertised count. `max_quality` still advertises 10 consultants, with an effective target of 9 for a canonical invoking host.
For `max_quality`, Grok, GLM, and DeepSeek are also pinned to their highest
accepted reasoning effort: Grok Build uses `xhigh`, while GLM and DeepSeek use
`max`. Unsupported transport capabilities fail explicitly instead of reducing
effort silently.

The maximum preset also applies the transport budgets proven by the live panel
smoke: four bounded advisory turns for Mistral/Grok, a 600-second Token Plan
window for Qwen3.8-Max, a 600-second DeepSeek reasoning window, and larger
OpenAI-compatible output budgets for Qwen, GLM, and DeepSeek. MiniMax M3
likewise receives a 16,384-token completion budget in the maximum tier and a
provider-specific compact Markdown contract through mmx's native system channel.
Provider output is tagged `structured`, `fallback`, or `error`;
malformed/truncated JSON fails
closed. In coverage/union mode, only locally atomized `summary`, `pros`,
`cons`, `alternatives`, `caveats`, and `references` can be source-attributed;
fallback prose remains context-only for manual review. `synthesis.json` records
`coverage_integrity`: `MET` applies only to those audited fields, while
`DEGRADED`/`FAILED` must not be read as comprehensive coverage. It also records
locally authoritative `coverage_input_truncated` and `truncated_consultants`:
only non-normalizable fallback context is capped (at Unicode code-point
boundaries), never atomic findings; a truncated coverage input is disclosed
and cannot support a comprehensive coverage claim.

### Models by Tier

| Consultant | `max_quality` | Premium | Standard | Economy |
|------------|---------------|---------|----------|---------|
| Claude | claude-opus-5 | claude-opus-5 | claude-sonnet-5 | claude-haiku-4-5 |
| Gemini CLI | Gemini 3.7 Flash (High) | Gemini 3.7 Flash (High) | Gemini 3.7 Flash (High) | Gemini 3.7 Flash (Low) |
| Gemini API | gemini-3.1-pro-preview | gemini-3.1-pro-preview | gemini-3.1-pro-preview | gemini-3.1-pro-preview |
| Codex | gpt-5.6-sol | gpt-5.6-sol | gpt-5.6-terra | gpt-5.6-luna |
| Mistral CLI | mistral-medium-3.5 | mistral-medium-3.5 | mistral-medium-3.5 | devstral-small-2 |
| Mistral API | mistral-large-3 | mistral-large-3 | mistral-large-3 | mistral-large-3 |
| DeepSeek | deepseek-v4-pro | deepseek-v4-pro | deepseek-v4-flash | deepseek-v4-flash |
| GLM | glm-5.3-flash | glm-5.3-flash | glm-5.3-flash | glm-4-flash |
| Grok | grok-4.6 | grok-4.6 | grok-4.5 | grok-4.5 |
| Qwen3 | qwen3.8-max when Token Plan is configured; otherwise qwen3.7-max | qwen3.7-max | qwen3.6-35b-a3b | qwen3-32b |
| Kimi | kimi-code/k3-256k | kimi-code/k3 | kimi-code/k3 | kimi-code/k3 |
| MiniMax | MiniMax-M3 | MiniMax-M2.7 | MiniMax-M2.7 | MiniMax-M2.5 |

Promotion is transport-specific. Gemini 3.7 Flash High completed an exact live
smoke through the `agy` adapter and is now the CLI default; Low is the CLI
economy target. The Google API model remains `gemini-3.1-pro-preview`, while
`gemini-3.7-flash` stays an API-only opt-in until that separate transport is
verified. The new Mistral API IDs (`mistral-medium-3-5`,
`mistral-large-2512`, `mistral-small-2603`) and Claude Fable 5 likewise remain
catalogued opt-ins. Selecting a preset later intentionally reapplies that
preset's tier and can replace an explicit model override for the run.
Qwen3.8-Max is likewise selected by `max_quality` only when API mode already
points at an authenticated OpenAI-compatible Token Plan `/chat/completions`
endpoint; the preset never repoints a DashScope key or CLI installation.

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
apply_model_tier "maximum"   # max_quality-only / separate-plan models
apply_model_tier "economy"   # Set all to economy models
```

---

## Configuration

### Presets

Choose how many consultants to use:

| Preset | Consultants | Tier | Use Case |
|--------|-------------|------|----------|
| `max_quality` | All 10 | Maximum + max effort | Critical decisions |
| `medium` | 3 | Standard | General questions |
| `fast` | 2 | Economy | Quick checks |
| `minimal` | 2 (Gemini + Codex) | Default | Quick questions, low cost |
| `balanced` | 3 (+ Mistral) | Default | Standard consultations |
| `thorough` | 3 | Default | Comprehensive analysis |
| `high-stakes` | Expanded panel (4 of 10) | Default | Critical decisions |
| `security` | Security-focused (3) | Default | Security reviews |
| `cost-capped` | Budget-conscious | Default | Minimal API costs |

**Bash:**
```bash
./scripts/consult_all.sh --preset balanced "Question"
```

### Synthesis Strategies

Control how responses are combined:

<!-- ai-consultants:default-synthesis-strategy=coverage -->
| Strategy | Default | Description |
|----------|---------|-------------|
| `coverage` | **Default** | Union of distinct points from every response |
| `majority` |  | Most common answer wins |
| `risk_averse` |  | Weight conservative responses higher |
| `security_first` |  | Prioritize security considerations |
| `cost_capped` |  | Prefer simpler, cheaper solutions |
| `compare_only` |  | No recommendation, just comparison |

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
  --set DEFAULT_STRATEGY=coverage \
  --set ENABLE_SMART_ROUTING=true

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
`--set`, and unmarked values remain explicit user choices, except for the exact
historical generated Claude default described below.
Managed model defaults use `# ai-consultants:default`; `configure` upgrades the
historical unmarked `CLAUDE_MODEL=claude-opus-4-8` default to Opus 5 and upgrades
the exact managed Gemini CLI, GLM, and Grok defaults. To keep
4.8 intentionally, run
`ai-consultants configure --set CLAUDE_MODEL=claude-opus-4-8`; explicit model
overrides are stored with `# ai-consultants:pin`.

Enter credentials through `--interactive`/`--advanced` or export them before the
run; avoid passing API keys through `--set`, where the shell may retain them in
history or expose them in the process list.

For a manual starter template instead, run `ai-consultants init` and edit
`~/.config/ai-consultants/.env`.

For ad-hoc overrides without persisting, the most common knobs:

```bash
DEFAULT_PRESET=balanced      # minimal | balanced | thorough | high-stakes | fast | security
DEFAULT_STRATEGY=coverage    # coverage | compare_only | majority | risk_averse | security_first | cost_capped
ENABLE_SMART_ROUTING=true    # Auto-select consultants by question category
MAX_SESSION_COST=1.00        # USD budget cap (paired with ENABLE_BUDGET_LIMIT=true to enforce)
KIMI_MODEL=kimi-code/k3      # Pin the Kimi consultant to K3
CLAUDE_API_MAX_TOKENS=16384  # Shared thinking + visible-output budget in API mode
MISTRAL_CLI_MODEL=mistral-medium-3.5 # Vibe alias; MISTRAL_MODEL remains API-only
GEMINI_MODEL="Gemini 3.7 Flash (High)" # agy CLI; API uses GEMINI_API_MODEL
```

Full reference: [`references/configuration.md`](references/configuration.md). Copy-paste workflows: [`docs/RECIPES.md`](docs/RECIPES.md). For category-aware preset suggestions: `ai-consultants doctor --suggest-preset --question "..."`.

### Configuration Recipes

**Breadth review — the coverage union (default):**

```bash
ai-consultants --preset high-stakes \
  "What could go wrong with this webhook-delivery design?" src/webhooks.ts@PRIMARY
```

**Security review, security-first framing:**

```bash
ai-consultants --preset security --strategy security_first \
  "Find authentication bypasses" src/auth.ts@PRIMARY
```

**Side-by-side comparison (no synthesized union):**

```bash
ai-consultants --strategy compare_only \
  "Event log or mutable relational state for this service?"
```

**Live health gate plus hard quorum:**

```bash
ENABLE_HEALTH_GATE=true \
QUORUM_MIN=3 \
QUORUM_ACTION=stop \
ai-consultants "Make a release recommendation"
```

See the [recipes](docs/RECIPES.md) for balanced, fast, security, compare-only,
budget-capped, CLI-only, hybrid API, and large-context workflows.

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
Classify -> Route -> Fan out (parallel) -> Coverage synthesis
   |          |            |                      |
 category  smart       Gemini (8)          union of every
          routing      Codex (7)           distinct point,
                       Mistral (6)         deduplicated
                       Kimi (7)
```

1. **Classify** the question into a category.
2. **Route** (optional, `ENABLE_SMART_ROUTING`) to the consultants with the best category affinity (`references/affinity.json`).
3. **Fan out** to every selected consultant in parallel — one shot each, no serial rounds.
4. **Synthesize** the **coverage union** over auditable normalized fields. Read
   `coverage_integrity` before treating it as complete: `MET` means every local
   atomic source ID is represented once; `DEGRADED` and `FAILED` are explicitly
   non-comprehensive. Override with `--strategy compare_only` (side-by-side) or
   `majority` (a single blended recommendation).

### Output

Each consultation generates:

```
${XDG_CACHE_HOME:-$HOME/.cache}/ai-consultants/consultations/TIMESTAMP/
├── context.md            # Built consultation context
├── gemini.json          # Individual responses
├── codex.json           #   with confidence scores
├── mistral.json
├── grok.json
├── synthesis.json       # Coverage union plus coverage_integrity/audited_fields
├── optimization_metrics.json
└── report.md            # Human-readable report
```

The command prints the exact output directory as its final stdout line.

---

## Best Practices

### When the Panel Helps Most

The panel's edge is **coverage** — surfacing what a single model misses. It pays off on
open-ended, breadth questions:

- Threat-modeling and design review ("what could go wrong with this?")
- Enumerating risks, edge cases, or failure modes
- "What am I missing?" / exhaustive audits
- Decisions that are difficult to reverse

For a single-answer factual or defect-finding question, a single strong model is usually
enough — the panel adds little.

### Interpreting Results

| Scenario | Recommendation |
|----------|----------------|
| A point only one consultant raised | Weigh it — the diversity is the point |
| Mistral (Devil's Advocate) flags a risk | Investigate it |
| Consultants diverge on approach | Use `--strategy compare_only` to see each side-by-side |

### Security

- **Never** include credentials or API keys in queries
- Review and redact sensitive code before sending it to any external consultant
- Private query and context-staging files are removed automatically; generated
  reports remain in the XDG cache directory until you remove them

---

## Documentation

- [Setup Guide](docs/SETUP.md) - Installation, authentication, Claude Code setup
- [Configuration Recipes](docs/RECIPES.md) - Copy-paste workflows for routing, budgets, synthesis, and transport
- [Cost Rates](docs/COST_RATES.md) - Model pricing and budgets
- [Smart Routing](docs/SMART_ROUTING.md) - Category-based routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format specification
- [Reference Details](references/details.md) - Presets, strategies, best practices
- [Changelog](https://github.com/matteoscurati/ai-consultants/blob/main/CHANGELOG.md) - Complete version history
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
