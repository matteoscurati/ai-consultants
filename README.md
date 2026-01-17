# AI Consultants v2.2

> Query multiple AI models simultaneously for expert opinions on coding questions. Get diverse perspectives, automatic synthesis, confidence-weighted recommendations, and multi-agent debate.

[![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)](https://github.com/matteoscurati/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)
[![GitHub stars](https://img.shields.io/github/stars/matteoscurati/ai-consultants?style=social)](https://github.com/matteoscurati/ai-consultants)
[![agentskills.io](https://img.shields.io/badge/agentskills.io-compatible-blue.svg)](https://agentskills.io)

---

## Table of Contents

- [Why AI Consultants?](#why-ai-consultants)
- [Quick Start](#quick-start)
- [Supported CLI Agents](#supported-cli-agents)
  - [Claude Code](#claude-code)
  - [OpenAI Codex CLI](#openai-codex-cli)
  - [Gemini CLI](#gemini-cli)
  - [Cursor / Copilot / Windsurf](#cursor--copilot--windsurf-via-skillport)
  - [Aider](#aider)
  - [Standalone Bash](#standalone-bash)
- [Consultants](#consultants)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Best Practices](#best-practices)
- [Documentation](#documentation)
- [Changelog](#changelog)
- [License](#license)

---

## Why AI Consultants?

Making important technical decisions? Get **multiple expert perspectives** instantly:

- **10+ AI consultants** with unique personas (Architect, Pragmatist, Devil's Advocate, etc.)
- **Automatic synthesis** combines all responses into a weighted recommendation
- **Confidence scoring** tells you how certain each consultant is
- **Multi-agent debate** lets consultants critique each other
- **Anonymous peer review** identifies the strongest arguments without bias
- **Local model support** via Ollama for complete privacy

---

## Quick Start

Get started in 30 seconds:

```bash
# Install the skill
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Run the setup wizard (in Claude Code)
/ai-consultants:config-wizard

# Ask your first question
/ai-consultants:consult "How should I structure my authentication system?"
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
| `/ai-consultants:consult` | Ask AI consultants a coding question |
| `/ai-consultants:ask-experts` | Quick query (alias for consult) |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:config-wizard` | Full interactive setup |
| `/ai-consultants:config-check` | Verify CLIs are installed |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset (minimal, balanced, high-stakes) |
| `/ai-consultants:config-strategy` | Set default synthesis strategy |
| `/ai-consultants:config-features` | Toggle features (debate, synthesis, etc.) |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API consultants (Qwen3, GLM, Grok, DeepSeek) |
| `/ai-consultants:help` | Show all commands and usage |

**Self-Exclusion:** Claude consultant is automatically excluded when invoked from Claude Code.

**Verify:**

```
/ai-consultants:config-check
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
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis, connecting ideas |

### API-Based Consultants

| Consultant | Model | Persona | Focus |
|------------|-------|---------|-------|
| **Qwen3** | qwen-max | The Analyst | Data-driven analysis |
| **GLM** | glm-4 | The Methodologist | Structured approaches |
| **Grok** | grok-beta | The Provocateur | Challenge conventions |
| **DeepSeek** | deepseek-coder | The Code Specialist | Algorithms, code generation |

### Local Consultants

| Consultant | Model | Persona | Focus |
|------------|-------|---------|-------|
| **Ollama** | llama3.2 | The Local Expert | Privacy-first, zero API cost |

### Installing Consultant CLIs

At least 2 consultant CLIs are required:

```bash
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
npm install -g @kilocode/cli           # Kilo
curl https://cursor.com/install -fsS | bash  # Cursor

# For local inference (optional)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2
```

---

## Configuration

### Presets

Choose how many consultants to use:

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions, low cost |
| `balanced` | 4 (+ Mistral + Kilo) | Standard consultations |
| `thorough` | 5 (+ Cursor) | Comprehensive analysis |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |
| `security` | Security-focused + debate | Security reviews |
| `cost-capped` | Budget-conscious | Minimal API costs |

**Claude Code:**
```
/ai-consultants:config-preset
```

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

**Claude Code:**
```
/ai-consultants:config-strategy
```

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
OLLAMA_MODEL=llama3.2        # Model to use
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
- [Contributing](CONTRIBUTING.md) - How to contribute

---

## Changelog

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
