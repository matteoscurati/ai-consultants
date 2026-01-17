# AI Consultants v2.2

> Query multiple AI models simultaneously for expert opinions on coding questions. Get diverse perspectives, automatic synthesis, confidence-weighted recommendations, and multi-agent debate.

[![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)](https://github.com/matteoscurati/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-orange.svg)](https://docs.anthropic.com/en/docs/claude-code/skills)
[![GitHub stars](https://img.shields.io/github/stars/matteoscurati/ai-consultants?style=social)](https://github.com/matteoscurati/ai-consultants)
[![agentskills.io](https://img.shields.io/badge/agentskills.io-compatible-blue.svg)](https://agentskills.io)

## Supported Agents

AI Consultants follows the open [Agent Skills standard](https://agentskills.io), enabling cross-platform compatibility:

| Agent | Installation | Status |
|-------|--------------|--------|
| **Claude Code** | `~/.claude/skills/` | ✅ Native |
| **OpenAI Codex CLI** | `~/.codex/skills/` | ✅ Compatible |
| **Gemini CLI** | `~/.gemini/skills/` | ✅ Compatible |
| **Kilo Code** | Via agentskills | ✅ Compatible |
| **GitHub Copilot** | Via [SkillPort](https://github.com/gotalab/skillport) | ✅ Via AGENTS.md |
| **Cursor** | Via SkillPort | ✅ Via SkillPort |
| **Windsurf** | Via SkillPort | ✅ Via SkillPort |
| **Aider** | Via AGENTS.md | ✅ Via AGENTS.md |

See [Installation Options](#installation-options) for agent-specific setup.

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

## Claude Code Quick Start

AI Consultants is designed as a **Claude Code skill** - the fastest way to get started is within Claude Code.

### Install the Skill

```bash
# One-liner installation (installs to ~/.claude/skills/)
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

### Your First Consultation

Once installed, use slash commands directly in Claude Code:

```
/ai-consultants:config-wizard       # Initial setup - configure your consultants
/ai-consultants:consult "How should I structure my authentication system?"
```

### Essential Slash Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Ask AI consultants a coding question |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show all available commands |

That's it! Claude Code handles everything else.

---

## Claude Code Integration

### All Slash Commands

AI Consultants provides 12 slash commands for seamless Claude Code integration:

#### Consultation Commands

| Command | Description | Example |
|---------|-------------|---------|
| `/ai-consultants:consult` | Main consultation | `/ai-consultants:consult "Redis vs Memcached?"` |
| `/ai-consultants:ask-experts` | Quick query (alias) | `/ai-consultants:ask-experts "Best caching strategy?"` |
| `/ai-consultants:debate` | With multi-round debate | `/ai-consultants:debate "Microservices or monolith?"` |

#### Configuration Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:config-wizard` | Full interactive setup |
| `/ai-consultants:config-check` | Verify CLIs are installed |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset (minimal, balanced, high-stakes) |
| `/ai-consultants:config-strategy` | Set default synthesis strategy |
| `/ai-consultants:config-features` | Toggle features (debate, synthesis, etc.) |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API consultants (Qwen3, GLM, Grok, DeepSeek) |
| `/ai-consultants:help` | Show all commands and usage |

### Claude Code Workflows

#### Quick Question

```
/ai-consultants:consult "How to optimize this SQL query?"
```

#### Code Review with Multiple Files

```
/ai-consultants:consult "Review this authentication flow" src/auth.ts src/middleware.ts
```

#### Architectural Decision with Debate

```
/ai-consultants:debate "Should we use GraphQL or REST for our new API?"
```

#### Configure Once, Use Everywhere

Set your preferred defaults with configuration commands:

```
/ai-consultants:config-preset       # Choose: minimal, balanced, high-stakes, local
/ai-consultants:config-strategy     # Choose: majority, risk_averse, security_first
/ai-consultants:config-features     # Toggle: debate, synthesis, peer review
```

Your settings persist in `~/.claude/skills/ai-consultants/.env`.

### Benefits of Using Claude Code

| Feature | Claude Code | Standalone Bash |
|---------|-------------|-----------------|
| Configuration | Slash commands | Edit .env manually |
| Results | Integrated in chat | Read from /tmp/ |
| Follow-ups | Natural conversation | Separate followup.sh |
| File context | Automatic | Pass file paths |
| Setup | `/ai-consultants:config-wizard` | Run scripts manually |

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

### Local Consultants (v2.2)

| Consultant | Model | Persona | Focus |
|------------|-------|---------|-------|
| **Ollama** | llama3.2 | The Local Expert | Privacy-first, zero API cost |

### Self-Exclusion (v2.2)

The invoking agent is automatically excluded from the consultant panel to prevent self-consultation:

| Invoking Agent | Excluded Consultant |
|----------------|---------------------|
| Claude Code | Claude |
| Codex CLI | Codex |
| Gemini CLI | Gemini |
| Cursor | Cursor |

This is handled automatically via the `INVOKING_AGENT` environment variable. When invoked from slash commands, it's set automatically. For bash usage:

```bash
# Claude will be excluded from the panel
INVOKING_AGENT=claude ./scripts/consult_all.sh "Question"

# Codex will be excluded from the panel
INVOKING_AGENT=codex ./scripts/consult_all.sh "Question"

# No exclusion (all enabled consultants participate)
./scripts/consult_all.sh "Question"
```

---

## What's New in v2.2

### Configuration Presets

Choose how many consultants to use:

**Claude Code:**
```
/ai-consultants:config-preset       # Interactive selection
```

**Bash:**
```bash
./scripts/consult_all.sh --preset minimal "Quick question"      # 2 models
./scripts/consult_all.sh --preset balanced "Design question"    # 4 models
./scripts/consult_all.sh --preset high-stakes "Critical choice" # All + debate
./scripts/consult_all.sh --preset local "Private question"      # Ollama only
```

### Synthesis Strategies

Control how responses are combined:

**Claude Code:**
```
/ai-consultants:config-strategy     # Interactive selection
```

**Bash:**
```bash
./scripts/consult_all.sh --strategy majority "Question"       # Most common wins
./scripts/consult_all.sh --strategy risk_averse "Question"    # Prioritize safety
./scripts/consult_all.sh --strategy security_first "Question" # Security focus
./scripts/consult_all.sh --strategy compare_only "Question"   # No recommendation
```

### Doctor Command

Diagnose and fix configuration issues:

```bash
./scripts/doctor.sh              # Full diagnostic
./scripts/doctor.sh --fix        # Auto-fix common issues
./scripts/doctor.sh --json       # JSON output for automation
```

### Anonymous Peer Review

Consultants evaluate each other's responses without knowing the source:

```bash
./scripts/peer_review.sh /tmp/ai_consultations/latest /tmp/peer_review
```

### Local Model Support (Ollama)

Run consultations 100% locally with zero API cost:

```bash
ENABLE_OLLAMA=true ./scripts/consult_all.sh "Private question"
```

### Panic Button Mode

Automatically adds rigor when uncertainty is detected:

```bash
ENABLE_PANIC_MODE=auto ./scripts/consult_all.sh "Complex question"
# Triggers when average confidence < 5 or uncertainty keywords detected
```

### Confidence Intervals

See statistical confidence ranges:

```
Gemini: 8 +/- 1.2 (high confidence)
Codex: 6 +/- 2.1 (moderate variance)
```

---

## Usage

### With Claude Code (Recommended)

```
# Basic consultation
/ai-consultants:consult "How to optimize this function?"

# With file context
/ai-consultants:consult "Review this code" src/utils.py

# With debate for controversial topics
/ai-consultants:debate "Which database should we use?"
```

### With Bash

```bash
# Simple question
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# With preset
./scripts/consult_all.sh --preset balanced "Redis or Memcached?"

# With debate
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "Microservices vs monolith?"

# With smart routing
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh "Bug in auth code"
```

### Follow-up Questions

**Claude Code:** Just continue the conversation naturally.

**Bash:**
```bash
# Follow-up to all consultants
./scripts/followup.sh "Can you elaborate on that point?"

# Follow-up to specific consultant
./scripts/followup.sh -c Gemini "Show me code example"
```

---

## Configuration

### Available Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions, low cost |
| `balanced` | 4 (+ Mistral + Kilo) | Standard consultations |
| `thorough` | 5 (+ Cursor) | Comprehensive analysis |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |
| `security` | Security-focused + debate | Security reviews |
| `cost-capped` | Budget-conscious | Minimal API costs |

### Available Strategies

| Strategy | Description |
|----------|-------------|
| `majority` | Most common answer wins (default) |
| `risk_averse` | Weight conservative responses higher |
| `security_first` | Prioritize security considerations |
| `cost_capped` | Prefer simpler, cheaper solutions |
| `compare_only` | No recommendation, just comparison |

### Environment Variables

```bash
# Core features
ENABLE_DEBATE=true           # Multi-agent debate
ENABLE_SYNTHESIS=true        # Automatic synthesis
ENABLE_SMART_ROUTING=true    # Intelligent consultant selection
ENABLE_PANIC_MODE=auto       # Automatic rigor for uncertainty

# Defaults (v2.2)
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

See [docs/SETUP.md](docs/SETUP.md) for complete configuration guide.

---

## Output

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

---

## Installation Options

### Option A: Claude Code Skill (Recommended)

```bash
# One-liner installation
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Verify and fix issues
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
```

Then in Claude Code:
```
/ai-consultants:config-wizard
```

### Option B: OpenAI Codex CLI

```bash
# Clone to Codex skills directory
git clone https://github.com/matteoscurati/ai-consultants.git ~/.codex/skills/ai-consultants

# Or symlink if already installed elsewhere
ln -s /path/to/ai-consultants ~/.codex/skills/ai-consultants

# Verify installation
~/.codex/skills/ai-consultants/scripts/doctor.sh --fix
```

### Option C: Gemini CLI

```bash
# Clone to Gemini skills directory
git clone https://github.com/matteoscurati/ai-consultants.git ~/.gemini/skills/ai-consultants

# Or symlink
ln -s /path/to/ai-consultants ~/.gemini/skills/ai-consultants
```

### Option D: SkillPort (Multi-Agent)

For Cursor, Copilot, Windsurf, and other SkillPort-compatible agents:

```bash
# Install SkillPort if not already installed
npm install -g skillport

# Add AI Consultants skill
skillport add github.com/matteoscurati/ai-consultants

# Load skill in your agent
skillport show ai-consultants
```

Or use the included installer:

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
./scripts/skillport-install.sh
```

### Option E: Manual Git Clone

```bash
git clone https://github.com/matteoscurati/ai-consultants.git ~/.claude/skills/ai-consultants
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
~/.claude/skills/ai-consultants/scripts/setup_wizard.sh
```

### Option F: Standalone (No Agent)

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants
./scripts/doctor.sh --fix
./scripts/setup_wizard.sh
```

### Update

```bash
~/.claude/skills/ai-consultants/scripts/install.sh --update
```

### Uninstall

```bash
~/.claude/skills/ai-consultants/scripts/install.sh --uninstall
```

---

## Requirements

- **Bash 4.0+** (macOS: `brew install bash`)
- **jq** for JSON processing
- **At least 2 consultant CLIs** installed and authenticated

### Install Consultant CLIs

```bash
# At least 2 required
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral
npm install -g @kilocode/cli           # Kilo
curl https://cursor.com/install -fsS | bash  # Cursor

# For local inference (optional)
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.2
```

### Verify Installation

**Claude Code:**
```
/ai-consultants:config-check
```

**Bash:**
```bash
./scripts/doctor.sh
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
- **Self-exclusion**: Invoking agent automatically excluded from panel (Claude Code won't query Claude, etc.)
- **Presets**: Quick configuration with `--preset minimal/balanced/high-stakes/local`
- **Doctor command**: Diagnostic and auto-fix tool
- **Synthesis strategies**: `--strategy majority/risk_averse/security_first/compare_only`
- **Confidence intervals**: Statistical confidence ranges (e.g., "8 +/- 1.2")
- **Anonymous peer review**: Unbiased evaluation of responses
- **Ollama support**: Local model inference for privacy
- **Panic mode**: Automatic rigor when uncertainty detected
- **Judge step**: Overconfidence detection in self-reflection
- **One-liner install**: `curl | bash` installation
- **New slash commands**: `/ai-consultants:config-preset`, `/ai-consultants:config-strategy`

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
