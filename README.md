# AI Consultants v5.5.0

> **Coverage, not a single guess.** A panel of up to 11 frontier models from different vendors fans out on your question in parallel and hands you the *union* of what they collectively see — the risks, edge cases, and approaches a single model misses.

[![Version](https://img.shields.io/badge/version-5.5.0-blue.svg)](https://github.com/reasance/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)
[![GitHub stars](https://img.shields.io/github/stars/reasance/ai-consultants?style=social)](https://github.com/reasance/ai-consultants)
[![agentskills.io](https://img.shields.io/badge/agentskills.io-compatible-blue.svg)](https://agentskills.io)

---

## Table of Contents

- [Why AI Consultants?](#why-ai-consultants)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Supported CLI Agents](#supported-cli-agents)
  - [Claude Code](#claude-code)
  - [OpenAI Codex CLI](#openai-codex-cli)
  - [Antigravity (agy)](#antigravity-agy)
  - [Gemini CLI (legacy)](#gemini-cli-legacy)
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

A single model gives you one perspective. AI Consultants sends your question to a **panel of models from different vendors**, each answering once on its own, and returns the **union of their distinct points**, each tagged with the models that raised it. A point only one model raised stays in the list instead of being voted out.

- **Cross-vendor diversity → breadth** — different model families often raise different points. In a small internal test with three open-ended tasks ("what could go wrong with this design?", "enumerate the risks"), the merged list covered more items on a reference checklist than one strong model alone, or one model sampled several times. That is a direction, not a benchmark: there is no evidence that a panel is more *accurate* than one strong model, and models agreeing is not proof.
- **Parallel fan-out** — every consultant runs at once; no serial deliberation rounds.
- **Coverage synthesis** — the default synthesis is the deduplicated *union* of every distinct point, not a single voted winner (use `--strategy compare_only` for a side-by-side, or `majority` for a blended recommendation).
- **11 supported consultants** with distinct personas (Architect, Pragmatist, Devil's Advocate, …) — the personas deliberately decorrelate the panel.
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
curl -fsSL https://raw.githubusercontent.com/reasance/ai-consultants/main/scripts/install.sh | bash

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
| **Bash 3.2+** | Script execution (the stock macOS `/bin/bash` 3.2 is supported) |
| **bc** | Cost arithmetic |

### Installation by Platform

#### macOS

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required dependencies (coreutils is optional: it provides
# `timeout`; a built-in fallback is used without it)
brew install jq coreutils

# Verify installation
jq --version && bash --version | head -1
```

> **Note:** the scripts target the stock macOS Bash 3.2 (`#!/bin/bash`); installing a newer Bash is not required.

#### Linux (Ubuntu/Debian)

```bash
# Install required dependencies
sudo apt-get update
sudo apt-get install -y jq curl bash bc

# Verify installation
jq --version && bash --version | head -1
```

#### Linux (Fedora/RHEL/CentOS)

```bash
# Install required dependencies
sudo dnf install -y jq curl bash bc

# Verify installation
jq --version && bash --version | head -1
```

#### Linux (Arch)

```bash
# Install required dependencies
sudo pacman -S jq curl bash bc

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
sudo apt-get install -y jq curl bash bc
```

Alternatively, use **Git Bash** or **MSYS2** with the required packages.

### Optional Dependencies

For CLI-based consultants, you'll also need:

| Dependency | Required for |
|------------|--------------|
| **Node.js 18+** | Codex CLI, Qwen CLI, MiniMax CLI |
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

> **Status:** ✅ Native support (headless run verified with Claude Code 2.1.303 on 2026-10-19)

**Installation:**

```bash
curl -fsSL https://raw.githubusercontent.com/reasance/ai-consultants/main/scripts/install.sh | bash
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

> **Status:** ✅ Compatible (headless run verified with Codex CLI 0.163 on 2026-10-19)

**Installation:**

```bash
git clone https://github.com/reasance/ai-consultants.git ~/.codex/skills/ai-consultants
~/.codex/skills/ai-consultants/scripts/doctor.sh --fix
# Or share an existing installation through the cross-agent skills directory:
# ln -s ~/.claude/skills/ai-consultants ~/.agents/skills/ai-consultants
```

**Usage:**

Codex has no custom slash commands: it loads the skill from `~/.codex/skills/`
or `~/.agents/skills/` and runs it when asked, for example *"use the
ai-consultants skill to review src/auth.ts"*. The consultation calls other CLIs
and APIs over the network and writes under `~/.cache` and `~/.config`, so
Codex's default sandbox cannot run it: approve the escalation when Codex asks,
or start Codex with `--sandbox danger-full-access`. Codex's automatic approval
review (`--approve-for-me`) rejects that escalation because it sends your files
to external providers, so the approval has to come from you.

**Self-Exclusion:** Codex consultant is automatically excluded when invoked from Codex CLI.

**Verify:**

```bash
~/.codex/skills/ai-consultants/scripts/doctor.sh
```

---

### Antigravity (agy)

> **Status:** ✅ Compatible (headless run verified with agy 1.4.2 on 2026-10-19)

Antigravity (`agy`) replaced the Gemini CLI for individual Google accounts.

**Installation:**

```bash
# Per project (agy reads <project>/.agents/skills/)
mkdir -p .agents/skills
git clone https://github.com/reasance/ai-consultants.git .agents/skills/ai-consultants
# Or for every project: agy's user skill directory is ~/.gemini/config/skills/
```

**Usage:** ask in natural language, for example *"use the ai-consultants skill
to compare these two designs"*. agy runs the consultation as a background task
and follows its progress; in print mode (`agy -p`) it waits at most 30 minutes
for background tasks.

**Self-Exclusion:** the Gemini consultant is excluded when invoked from agy
(`INVOKING_AGENT=gemini`).

---

### Gemini CLI (legacy)

> **Status:** ⚠️ Legacy. Google stopped serving the Gemini CLI to individual
> accounts on 2026-06-18; use [Antigravity (agy)](#antigravity-agy) instead.

Accounts that can still use it get the skill from `~/.gemini/skills/` or
`~/.agents/skills/`, through natural language: the Gemini CLI loads only
`.toml` custom commands, so the `/ai-consultants:*` slash commands are not
available there. The Gemini consultant is excluded as for agy.

---

### Cursor / Copilot / Windsurf (via SkillPort)

> **Status:** ✅ Via SkillPort

**Installation:**

```bash
# Install SkillPort if not already installed
npm install -g skillport

# Add AI Consultants skill
skillport add github.com/reasance/ai-consultants

# Load skill in your agent
skillport show ai-consultants
```

Or clone and use the included installer:

```bash
git clone https://github.com/reasance/ai-consultants.git
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
git clone https://github.com/reasance/ai-consultants.git
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
| **Kimi K3.1 Pro** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis, connecting ideas |
| **Qwen3** | `qwen` | The Analyst | Data-driven analysis |
| **Grok** | `grok` | The Provocateur | Challenge conventions |
| **MiniMax** | `mmx` | The Pragmatic Optimizer | Performance, efficiency, pragmatism |
| **Meta Muse** | `muse` | The Systems Thinker | System design, interactions, cascading effects |

Grok uses Grok Build with `grok-4.7` in an isolated, tool-free sandbox. Prompts
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
never serialized by that bootstrap. Qwen3, MiniMax and Meta can also switch
from their CLI to API transport. Gemini, Codex, Claude, and Mistral are
CLI/API switchable. Gemini, Grok, and Kimi verify the requested model
against the CLI inventory before dispatch when that inventory exists. Grok and
Kimi compatibility is capability-probed before
dispatch: the requested model, headless arguments, and structured-output
surface must be available. Any CLI version is accepted when those checks pass;
the observed version is response provenance only.

Meta runs Muse Code headless (`muse exec`) advisory-only: a private empty
workspace, no shell, no workspace writes, no web tools, no sandbox network, no
personal rules or skills, no session log and `--contributor-mode off` (Muse
Code subscriptions default to Contributor mode, which lets Meta train on the
content). The prompt goes through `--prompt-file`. Its `muse exec` flags are
capability-probed before dispatch. With `META_API_KEY` set (and no explicit
`META_USE_API`), Meta uses the Meta Model API instead. Meta is opt-in
(`ENABLE_META=false` until `configure` finds the CLI or a key).

### API-Only Consultants

| Consultant | Default Model | Persona | Focus |
|------------|---------------|---------|-------|
| **GLM** | glm-5.3-flash | The Methodologist | Structured approaches |
| **DeepSeek** | deepseek-flash (V4.1 Flash) | The Code Specialist | Algorithms, code generation |

### Installing Consultant CLIs

At least 2 consultants are required (a CLI, or an API key for API mode). The
first three below make up the `balanced` preset:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash  # Gemini (Antigravity CLI: agy)
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral

# Optional CLI-based consultants
curl -L code.kimi.com/install.sh | bash            # Kimi K3.1 Pro
npm install -g @qwen-code/qwen-code@latest  # Qwen (alternative to API)
curl -fsSL https://x.ai/cli/install.sh | bash # Grok Build (grok-4.7)
npm install -g mmx-cli                       # MiniMax
curl -fsSL https://dev.meta.ai/install.sh | sh  # Meta (Muse Code; run muse once to sign in)

```

Kimi is pinned to K3.1 Pro at max thinking effort for every consultation, even
if the user's Kimi CLI has a different default model or effort
(`KIMI_REASONING_EFFORT` reaches the CLI as `KIMI_MODEL_THINKING_EFFORT`):

```bash
KIMI_MODEL=kimi-code/k3.1-pro ai-consultants \
  "Review this API design from a holistic perspective"
```

---

## Quality Tiers

Choose the right balance of quality, speed, and cost with model quality tiers.

### Tier Presets

| Preset | Tier | Agents | Use Case |
|--------|------|--------|----------|
| `max_quality` | Maximum + max effort | All 11 | Critical decisions |
| `medium` | Standard | 3 | General questions |
| `fast` | Economy | 2 | Quick checks |

A preset only chooses the **consultant set and model tier** — every run then fans out in
parallel and returns the coverage union.
Preset panels use statically configured transports only (a CLI on `PATH`, or selected API mode with its key). Host self-exclusion is fail-closed; lost canonical slots are filled from `ALL_CONSULTANTS` in canonical order. If the effective target cannot be met, including after an enabled health gate prunes the panel, the run stops with promised/selected/missing-capacity guidance. Configured custom API agents are appended and may satisfy capacity, so a full preset can exceed its advertised count. `max_quality` still advertises 11 consultants, with an effective target of 10 for a canonical invoking host.
For `max_quality`, Grok, GLM, DeepSeek and Meta are also pinned to their highest
accepted reasoning effort: Grok Build uses `xhigh`, while GLM, DeepSeek and Meta
use `max`. Unsupported transport capabilities fail explicitly instead of reducing
effort silently.

The maximum preset also applies the transport budgets proven by the live panel
smoke: four bounded advisory turns for Mistral/Grok, the maximum-tier Qwen3.8-Max
and DeepSeek timeouts (`QWEN3_MAX_QUALITY_TIMEOUT`/`DEEPSEEK_MAX_QUALITY_TIMEOUT`,
default 0: no limit), and larger OpenAI-compatible output budgets for Qwen, GLM,
and DeepSeek. MiniMax-M3.1-Flash always reasons, so it receives a 16,384-token
completion budget (32,768 for `mmx` in the maximum tier) and the shared JSON response
contract through mmx's native system channel.
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
| Claude | claude-fable-5-1 | claude-fable-5-1 | claude-opus-5-5 | claude-haiku-5-5 |
| Gemini CLI | Gemini 4 Argon (High) | Gemini 4 Argon (High) | Gemini 3.8 Flash (High) | Gemini 3.8 Flash (Low) |
| Gemini API | gemini-4-argon | gemini-4-argon | gemini-3.8-flash | gemini-3.8-flash |
| Codex | gpt-6-astra | gpt-6.1-sol | gpt-6.1-sol | gpt-6-luna |
| Mistral CLI | mistral-medium-3.5 | mistral-medium-3.5 | mistral-medium-3.5 | mistral-medium-3.5 |
| Mistral API | mistral-large-4 | mistral-large-4 | mistral-large-4 | mistral-large-4 |
| DeepSeek | deepseek-flash | deepseek-flash | deepseek-flash | deepseek-flash |
| GLM | glm-5.3 | glm-5.3-flash | glm-5.3-flash | glm-5.3-flash |
| Grok | grok-4.7 | grok-4.7 | grok-4.7 | grok-4.7 |
| Qwen3 | qwen3.8-max | qwen3.8-max | qwen3.8-flash | qwen3.8-flash |
| Kimi | kimi-code/k3.1-pro | kimi-code/k3.1-pro | kimi-code/k3.1-pro | kimi-code/k3.1-pro |
| MiniMax | MiniMax-M3.1-Flash | MiniMax-M3.1-Flash | MiniMax-M3.1-Flash | MiniMax-M3.1-Flash |
| Meta | muse-wonder-1.0 | muse-wonder-1.0 | muse-spark-1.3 | muse-spark-1.3 |

Every tier uses current models only. 5.5.0 retired the superseded ones (94
IDs, listed with their replacements in `docs/cost_rates.json`): `configure`
migrates them, and a retired model selected at run time still runs with a
warning and is reported as unpriced. The economy tier moved to Claude Haiku 5.5,
GPT-6 Luna, Grok 4.7 and GLM-5.3-Flash, standard Codex to GPT-6.1 Sol (there is
no GPT-6 mid model), and the Gemini API standard/economy tiers to
`gemini-3.8-flash`. Authorized CLI smokes on 2026-10-24 returned structured
answers from Claude Haiku 5.5 (provider-reported identity, 6 s) and GPT-6 Luna
(requested-only, 4 s); the Gemini API target is offline-tested.

MiniMax-M3.1-Flash (released 2026-10-19, $0.15/$0.60 per 1M tokens) serves every
MiniMax tier. It always reasons; set `MINIMAX_REASONING_EFFORT` (API mode) to
`low`..`max` to trade depth for latency, while `mmx` uses the provider default
(`max`). An authorized `mmx` smoke returned a structured answer in 30 s on
2026-10-20 with requested-only identity; the API transport is offline-tested.

Meta (new in 5.5.0) uses Muse Wonder (`muse-wonder-1.0`, preview, $4/$20 per 1M
tokens) for the default, premium and maximum tiers and Muse Spark 1.3
(`muse-spark-1.3`, $1.25/$4.25) for standard and economy, both in Standard mode,
where Meta does not train on the content. Both always reason: effort is `high`
by default and `max` in `max_quality` (`META_REASONING_EFFORT`, `minimal`..`max`;
`none` is rejected), and the reasoning shares the 32,768-token API completion
budget. A Contributor-mode model (`muse-spark-1.3-contributor`, $0.10/$0.20)
must be pinned by hand and is logged with a warning on every run. A non-streaming
API request that runs past Meta's server time limit returns HTTP 504
`gateway_timeout` and is not retried. One authorized `muse exec` smoke (Muse
Code 1.4.12, Muse Wonder, 2026-10-24) returned a structured persona answer in
12 s with requested-only identity and estimated tokens; the API transport is
offline-tested.

Promotion is transport-specific. Gemini 4 Argon (GA 2026-10-13) is the Gemini
default and maximum target: `Gemini 4 Argon (High)` on `agy` and `gemini-4-argon`
on the API. An authorized `agy` consultation smoke returned a structured answer
with capability-probed identity on 2026-10-16; the API transport is covered by
offline tests only. Google excludes Argon from the Free tier and the AI Pro
plan, so the `agy` listing alone is not an access check. Gemini 3.8 Flash serves
the standard (High) and economy (Low) tiers on the CLI and, as `gemini-3.8-flash`,
on the API; that API transport is offline-tested. Mistral Large 4 (`mistral-large-4`, public preview) is the
Mistral API target for every tier. An authorized consultation smoke returned a
structured answer with provider-reported identity on 2026-10-15; the preview is absent from
`GET /v1/models`, so that listing is not an access check. Vibe keeps
`mistral-medium-3.5`. The other Mistral
API IDs (`mistral-medium-3-5`, `mistral-small-2603`) remain catalogued
opt-ins. Claude
Fable 5.1 is the default/premium/maximum target; use
`CLAUDE_MODEL=claude-opus-5-5` for the lower-cost standard override. Selecting a preset later intentionally reapplies that
preset's tier and can replace an explicit model override for the run.
Qwen3.8-Max serves the default, premium and maximum tiers on every Qwen
transport (the `qwen` CLI, the Token Plan and DashScope); `max_quality` adds
`xhigh` effort only on the OpenAI-compatible wire and never repoints a key or
endpoint.

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

<!-- ai-consultants:public-registry:start -->
<!-- ai-consultants:default-synthesis-strategy=coverage -->
### Public Modes

| Mode | Preset | Default strategy | Use case |
|---|---|---|---|
| `fast-check` | `fast` | `coverage` | Fast economy panel for a quick coverage check |
| `coverage-review` | `balanced` | `coverage` | Balanced panel for a general coverage review |
| `max-coverage` | `max_quality` | `coverage` | Maximum-quality panel for the broadest coverage |

### Configuration Presets

| Preset | Alias | Target | Tier | Use case |
|---|---|---:|---|---|
| `minimal` | — | 2 | base | Quick questions |
| `balanced` | — | 3 | base | Standard coverage |
| `thorough` | — | 3 | base | Comprehensive analysis |
| `high-stakes` | — | 4 | premium | Critical decisions |
| `security` | — | 3 | base | Security reviews |
| `cost-capped` | — | 3 | economy | Budget-conscious options |
| `max_quality` | `max-quality` | 11 | maximum | Maximum coverage for critical decisions |
| `medium` | — | 3 | standard | General questions |
| `fast` | — | 2 | economy | Quick checks |

### Synthesis Strategies

| Strategy | Description |
|---|---|
| `coverage` | Union of every distinct point across the panel **Default** |
| `compare_only` | Present each consultant side-by-side, without a synthesized union |
| `majority` | Produce one blended recommendation, weighting all equally |
| `risk_averse` | Weight conservative responses higher |
| `security_first` | Prioritize security-focused insights |
| `cost_capped` | Prefer cheaper consultant opinions within budget |
<!-- ai-consultants:public-registry:end -->

**Bash:**
```bash
./scripts/consult_all.sh --preset balanced "Question"
```

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
historical generated Claude default and the retired models described below.
Managed model defaults use `# ai-consultants:default`; `configure` upgrades
the exact historical defaults it generated when they are not pinned (for
example `CLAUDE_MODEL=claude-opus-4-8`/`claude-opus-5` to Fable 5.1, and the
previous Gemini, Codex, Mistral API, Qwen, GLM, Grok and DeepSeek defaults),
and turns the fixed timeouts it generated through 5.1.2 into 0 (no limit).
To keep a model, run for example
`ai-consultants configure --set CLAUDE_MODEL=claude-opus-5-5`; explicit model
overrides are stored with `# ai-consultants:pin` and never migrated while the
model is current. A retired model (see `retired_models` in
`docs/cost_rates.json`) is replaced even when pinned: the marker is kept, the
old value is recorded as `migrated-from=`, and `--set` refuses a retired model.

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
KIMI_MODEL=kimi-code/k3.1-pro # Pin the Kimi consultant to K3.1 Pro
KIMI_REASONING_EFFORT=max    # Kimi thinking effort (empty = the Kimi CLI's own)
CLAUDE_API_MAX_TOKENS=16384  # Shared thinking + visible-output budget in API mode
MISTRAL_CLI_MODEL=mistral-medium-3.5 # Vibe alias; MISTRAL_MODEL remains API-only
GEMINI_MODEL="Gemini 4 Argon (High)" # agy CLI; API uses GEMINI_API_MODEL
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

### Waiting and stopping

Consultants and synthesis have **no time limit by default**: reasoning models
can take minutes, and a call cut off by a client timeout is usually still
billed while its answer is lost. Whoever started the run decides when to stop
waiting. The run logs `Output: <dir>` near the start and
`Still waiting after Ns for: <names>` every 30 seconds, and accepts:

- `touch <dir>/.proceed` (or `kill -USR1 <pid>`, or a first Ctrl-C): continue
  with the answers already received. Consultants still running are stopped and
  reported as `stopped`; sent during synthesis, it skips the synthesis.
- `touch <dir>/.abort` (or SIGTERM, or a second Ctrl-C): end the run and keep
  the partial output.

A stopped call may still be billed for what it generated. Never stop a run with
SIGKILL: the shell cannot clean up, so consultant CLIs would keep running. A
positive `<NAME>_TIMEOUT` restores a hard limit for that consultant; see
[`references/configuration.md`](references/configuration.md#timeouts-waiting-and-retries).

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
- [Changelog](https://github.com/reasance/ai-consultants/blob/main/CHANGELOG.md) - Complete version history
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
