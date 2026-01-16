# AI Consultants v2.2

> Query multiple AI models simultaneously for expert opinions on coding questions. Get diverse perspectives, automatic synthesis, confidence-weighted recommendations, and multi-agent debate.

[![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)](https://github.com/matteoscurati/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/matteoscurati/ai-consultants?style=social)](https://github.com/matteoscurati/ai-consultants)

## Why AI Consultants?

Making important technical decisions? Get **multiple expert perspectives** instantly:

- **10+ AI consultants** with unique personas (Architect, Pragmatist, Devil's Advocate, etc.)
- **Automatic synthesis** combines all responses into a weighted recommendation
- **Confidence scoring** tells you how certain each consultant is
- **Multi-agent debate** lets consultants critique each other
- **Anonymous peer review** identifies the strongest arguments without bias
- **Local model support** via Ollama for complete privacy

## Quick Install

```bash
# One-liner installation
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Verify installation
~/.claude/skills/ai-consultants/scripts/doctor.sh
```

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

## What's New in v2.2

### Configuration Presets
Choose how many consultants to use with a single flag:

```bash
./scripts/consult_all.sh --preset minimal "Quick question"      # 2 models
./scripts/consult_all.sh --preset balanced "Design question"    # 4 models
./scripts/consult_all.sh --preset high-stakes "Critical choice" # All + debate
./scripts/consult_all.sh --preset local "Private question"      # Ollama only
```

### Doctor Command
Diagnose and fix configuration issues:

```bash
./scripts/doctor.sh              # Full diagnostic
./scripts/doctor.sh --fix        # Auto-fix common issues
./scripts/doctor.sh --json       # JSON output for automation
```

### Synthesis Strategies
Control how responses are combined:

```bash
./scripts/consult_all.sh --strategy majority "Question"       # Most common wins
./scripts/consult_all.sh --strategy risk_averse "Question"    # Prioritize safety
./scripts/consult_all.sh --strategy security_first "Question" # Security focus
./scripts/consult_all.sh --strategy compare_only "Question"   # No recommendation
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
Gemini: 8 ± 1.2 (high confidence)
Codex: 6 ± 2.1 (moderate variance)
```

## Usage

### Basic Consultation

```bash
# Simple question
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# With preset
./scripts/consult_all.sh --preset balanced "Redis or Memcached?"
```

### With Debate

```bash
# Enable multi-agent debate
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "Microservices vs monolith?"

# Or use high-stakes preset (includes debate)
./scripts/consult_all.sh --preset high-stakes "Critical architectural decision"
```

### With Smart Routing

```bash
# Auto-select best consultants for the question type
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh "Bug in auth code"
```

### Follow-up Questions

```bash
# Follow-up to all consultants
./scripts/followup.sh "Can you elaborate on that point?"

# Follow-up to specific consultant
./scripts/followup.sh -c Gemini "Show me code example"
```

### Claude Code Commands

If using as a Claude Code skill:

```
/ai-consultants:consult "Your question"
/ai-consultants:debate "Controversial topic"
/ai-consultants:config-check
/ai-consultants:config-wizard
```

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

## How It Works

```
Query → Classify → Parallel Queries → Voting → Synthesis → Report
                        ↓                ↓           ↓
                   Gemini (8)      Consensus    Recommendation
                   Codex (7)       Analysis     Comparison
                   Mistral (6)                  Risk Assessment
                   Kilo (9)                     Action Items
```

With debate enabled:
```
Round 1 → Cross-Critique → Round 2 → Updated Positions → Final Synthesis
```

With peer review:
```
Responses → Anonymize → Peer Ranking → De-anonymize → Peer Scores
```

## Installation Options

### Option A: One-Liner (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

### Option B: Claude Code Skill

```bash
git clone https://github.com/matteoscurati/ai-consultants.git ~/.claude/skills/ai-consultants
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
```

### Option C: Standalone

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

```bash
./scripts/doctor.sh
```

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

## Documentation

- [Setup Guide](docs/SETUP.md) - Installation and authentication
- [Cost Rates](docs/COST_RATES.md) - Model pricing and budgets
- [Smart Routing](docs/SMART_ROUTING.md) - Category-based routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format specification
- [Contributing](CONTRIBUTING.md) - How to contribute

## Changelog

### v2.2.0
- **Presets**: Quick configuration with `--preset minimal/balanced/high-stakes/local`
- **Doctor command**: Diagnostic and auto-fix tool
- **Synthesis strategies**: `--strategy majority/risk_averse/security_first/compare_only`
- **Confidence intervals**: Statistical confidence ranges (e.g., "8 ± 1.2")
- **Anonymous peer review**: Unbiased evaluation of responses
- **Ollama support**: Local model inference for privacy
- **Panic mode**: Automatic rigor when uncertainty detected
- **Judge step**: Overconfidence detection in self-reflection
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

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
