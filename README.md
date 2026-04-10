# AI Consultants v2.10.4

> Query multiple AI models simultaneously for expert opinions on coding questions. Get diverse perspectives, automatic synthesis, confidence-weighted recommendations, and multi-agent debate.

[![Version](https://img.shields.io/badge/version-2.10.4-blue.svg)](https://github.com/matteoscurati/ai-consultants)
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
  - [Aider](#aider)
  - [Standalone Bash](#standalone-bash)
- [Consultants](#consultants)
- [Quality Tiers](#quality-tiers)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Best Practices](#best-practices)
- [Documentation](#documentation)
- [Changelog](#changelog)
- [License](#license)

---

## Why AI Consultants?

Making important technical decisions? Get **multiple expert perspectives** instantly:

- **15 AI consultants** with unique personas (Architect, Pragmatist, Devil's Advocate, etc.)
- **Automatic synthesis** combines all responses into a weighted recommendation
- **Confidence scoring** tells you how certain each consultant is
- **Multi-agent debate** lets consultants critique each other
- **Anonymous peer review** identifies the strongest arguments without bias
- **Local model support** via Ollama for complete privacy

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
| **Node.js 18+** | Gemini CLI, Codex CLI, Kilo CLI |
| **Python 3.8+** | Mistral Vibe CLI, Aider |

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

### Aider

> **Status:** ✅ Via AGENTS.md

**Installation:**

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
# Aider reads AGENTS.md for skill instructions
```

**Usage:**

Reference the skill in your Aider session:

```
/add AGENTS.md
# Then ask: "Use ai-consultants to review my code"
```

**Self-Exclusion:** When using Aider as the invoking agent, set `INVOKING_AGENT=aider`.

**Verify:**

```bash
./scripts/doctor.sh
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
| **Google Gemini** | `gemini` | The Architect | Design patterns, scalability, enterprise |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, quick wins, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Problems, edge cases, vulnerabilities |
| **Kilo Code** | `kilocode` | The Innovator | Creativity, unconventional approaches |
| **Cursor** | `agent` | The Integrator | Full-stack perspective |
| **Aider** | `aider` | The Pair Programmer | Collaborative coding |
| **Amp** | `amp` | The Systems Thinker | System design, interactions, emergent behavior |
| **Kimi** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis, connecting ideas |

### API-Based Consultants

| Consultant | Default Model | Persona | Focus |
|------------|---------------|---------|-------|
| **Qwen3** | qwen3.5-plus | The Analyst | Data-driven analysis |
| **GLM** | glm-5.1 | The Methodologist | Structured approaches |
| **Grok** | grok-4.20-0309-reasoning | The Provocateur | Challenge conventions |
| **DeepSeek** | deepseek-reasoner | The Code Specialist | Algorithms, code generation |
| **MiniMax** | MiniMax-M2.7 | The Pragmatic Optimizer | Performance, efficiency, pragmatism |

### Local Consultants

| Consultant | Default Model | Persona | Focus |
|------------|---------------|---------|-------|
| **Ollama** | qwen2.5-coder:32b | The Local Expert | Privacy-first, zero API cost |

### Installing Consultant CLIs

At least 2 consultant CLIs are required:

```bash
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
npm install -g @kilocode/cli           # Kilo
curl https://cursor.com/install -fsS | bash  # Cursor

# Optional CLI-based consultants
curl -fsSL https://ampcode.com/install.sh | bash  # Amp
curl -L code.kimi.com/install.sh | bash            # Kimi
npm install -g @qwen-code/qwen-code@latest  # Qwen (alternative to API)

# For local inference (optional)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2
```

---

## Quality Tiers

Choose the right balance of quality, speed, and cost with model quality tiers.

### Tier Presets

| Preset | Tier | Agents | Debate | Reflection | Use Case |
|--------|------|--------|--------|------------|----------|
| `max_quality` | Premium | 7 (all) | 3 rounds | 2 cycles + peer review | Critical decisions |
| `medium` | Standard | 4 | 1 round | No | General questions |
| `fast` | Economy | 2 | No | No | Quick checks |
| `local` | Economy | 1 (Ollama) | No | No | Full privacy |

### Models by Tier

| Consultant | Premium | Standard | Economy |
|------------|---------|----------|---------|
| Claude | opus-4.6 | sonnet-4.6 | haiku-4.5 |
| Gemini | gemini-3.1-pro-preview | gemini-3-flash-preview | gemini-2.0-flash |
| Codex | gpt-5.3-codex | gpt-5.3 | gpt-4o-mini |
| Mistral | mistral-large-3 | mistral-medium-latest | devstral-small-2 |
| Cursor | composer-1.5 | composer-1.5 | gemini-2.0-flash |
| DeepSeek | deepseek-reasoner | deepseek-v3.2 | deepseek-chat |
| GLM | glm-5.1 | glm-5.1 | glm-4-flash |
| Grok | grok-4.20-0309-reasoning | grok-3 | grok-3-mini |
| Qwen3 | qwen3.5-plus | qwen3.5-plus | qwen3-32b |
| Aider | gpt-5.3-codex | gpt-5.3 | gpt-4o-mini |
| MiniMax | MiniMax-M2.7 | MiniMax-M2.7 | MiniMax-M2.5 |
| Ollama | qwen2.5-coder:32b | llama3.3 | llama3.2 |

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
| `max_quality` | 7 (all) + debate + reflection | Premium | Critical decisions |
| `medium` | 4 + light debate | Standard | General questions |
| `fast` | 2 | Economy | Quick checks |
| `minimal` | 2 (Gemini + Codex) | Default | Quick questions, low cost |
| `balanced` | 4 (+ Mistral + Kilo) | Default | Standard consultations |
| `thorough` | 5 (+ Cursor) | Default | Comprehensive analysis |
| `high-stakes` | All + debate | Default | Critical decisions |
| `local` | Ollama only | Economy | Full privacy |
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

```bash
# Core features
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_SMART_ROUTING=true    # Intelligent consultant selection
ENABLE_PANIC_MODE=auto       # Automatic rigor for uncertainty

# Defaults
DEFAULT_PRESET=balanced      # Preset when --preset not given
DEFAULT_STRATEGY=majority    # Strategy when --strategy not given

# Ollama (local models)
ENABLE_OLLAMA=true           # Enable Ollama consultant
OLLAMA_MODEL=qwen2.5-coder:32b  # Model to use (premium default)
OLLAMA_HOST=http://localhost:11434

# Cost management
MAX_SESSION_COST=1.00        # Budget limit in USD
WARN_AT_COST=0.50            # Warning threshold

# Panic mode
PANIC_CONFIDENCE_THRESHOLD=5 # Trigger threshold
PANIC_EXTRA_DEBATE_ROUNDS=1  # Additional rounds in panic mode
```

### Doctor Command

Diagnose and fix configuration issues:

```bash
./scripts/doctor.sh              # Full diagnostic
./scripts/doctor.sh --fix        # Auto-fix common issues
./scripts/doctor.sh --json       # JSON output for automation
```

---

## How It Works

```
Query -> Classify -> Parallel Queries -> Voting -> Synthesis -> Report
                          |                |           |
                     Gemini (8)      Consensus    Recommendation
                     Codex (7)       Analysis     Comparison
                     Mistral (6)                  Risk Assessment
                     Kilo (9)                     Action Items
```

With debate enabled:
```
Round 1 -> Cross-Critique -> Round 2 -> Updated Positions -> Final Synthesis
```

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
├── kilo.json
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
- Use `--preset local` for sensitive code
- Files in `/tmp` are automatically cleaned up

---

## Documentation

- [Setup Guide](docs/SETUP.md) - Installation, authentication, Claude Code setup
- [Cost Rates](docs/COST_RATES.md) - Model pricing and budgets
- [Smart Routing](docs/SMART_ROUTING.md) - Category-based routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format specification
- [Reference Details](references/details.md) - Presets, strategies, best practices
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## Changelog

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
- **Presets**: Quick configuration with `--preset minimal/balanced/high-stakes/local`
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
