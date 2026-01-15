# AI Consultants v2.1

> A multi-model AI deliberation system with automatic synthesis, consultant debate, and confidence-weighted voting.

[![Version](https://img.shields.io/badge/version-2.1.0-blue.svg)](https://github.com/matteoscurati/ai-consultants)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/matteoscurati/ai-consultants?style=social)](https://github.com/matteoscurati/ai-consultants)

## Overview

AI Consultants simultaneously queries **up to 10 AI models** as "expert consultants", each with a **unique persona** that influences their response style.

### CLI Consultants

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `gemini` | The Architect | Design patterns, scalability, enterprise |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, quick wins, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Problems, edge cases, vulnerabilities |
| **Kilo Code** | `kilocode` | The Innovator | Creativity, unconventional approaches |
| **Cursor** | `agent` | The Integrator | Full-stack perspective, cross-cutting concerns |
| **Aider** | `aider` | The Pair Programmer | Collaborative coding, step-by-step |

### API Consultants

| Consultant | Model | Persona | Focus |
|------------|-------|---------|-------|
| **Qwen3** | qwen-max | The Analyst | Data-driven analysis, metrics |
| **GLM** | glm-4 | The Methodologist | Structured approaches, processes |
| **Grok** | grok-beta | The Provocateur | Challenge conventions |
| **DeepSeek** | deepseek-coder | The Code Specialist | Code generation, algorithms |

## Features

- **Configurable Personas**: 17 predefined personas to assign to each consultant
- **Confidence Scoring**: 1-10 score on every response
- **Auto-Synthesis**: Automatic synthesis with weighted recommendation
- **Multi-Agent Debate (MAD)**: Deliberation rounds with cross-critique
- **Smart Routing**: Automatic selection of best consultants
- **Session Management**: Follow-up and continuity between consultations
- **Cost Tracking**: Cost estimation and tracking
- **AI Agent Skill**: Works as a skill in Claude Code, Codex, and other AI assistants

## Quick Start

### Prerequisites

**Minimum requirement**: At least **2 consultants** must be configured for the system to work.

**System requirements:**
- **Bash 4.0+** (macOS users: `brew install bash` - macOS ships with Bash 3.2)
- **jq** for JSON parsing
- **bc** for cost calculations (usually pre-installed)

```bash
# Required: jq for JSON parsing
brew install jq                        # macOS
# or: sudo apt-get install jq          # Ubuntu/Debian

# Install CLI tools (install at least 2)
npm install -g @google/gemini-cli      # Gemini
npm install -g @openai/codex           # Codex
pip install mistral-vibe               # Mistral Vibe
npm install -g @kilocode/cli           # Kilo
curl https://cursor.com/install -fsS | bash  # Cursor
pip install aider-chat                 # Aider
```

For detailed installation and authentication setup, see **[docs/SETUP.md](docs/SETUP.md)**.

### Installation

**Option A: As Claude Code Skill (Recommended)**

```bash
# Install as a Claude Code skill
git clone https://github.com/matteoscurati/ai-consultants.git ~/.claude/skills/ai-consultants

# Then in Claude Code:
# /ai-consultants:config-check    - Verify installation
# /ai-consultants:config-wizard   - Configure consultants
# /ai-consultants:consult "question"  - Start consulting!
```

**Option B: Standalone**

```bash
git clone https://github.com/matteoscurati/ai-consultants.git
cd ai-consultants

# Make scripts executable
chmod +x scripts/*.sh scripts/lib/*.sh

# Run interactive setup wizard (recommended)
./scripts/setup_wizard.sh

# Or manually verify installation
./scripts/preflight_check.sh
```

### Partial Setup (Not All CLIs)

If you only have access to some APIs (e.g., only OpenAI + Google):

```bash
# Option 1: Use setup wizard to auto-detect and configure
./scripts/setup_wizard.sh

# Option 2: Manually disable unavailable consultants
ENABLE_GEMINI=true ENABLE_CODEX=true ENABLE_MISTRAL=false ENABLE_KILO=false \
./scripts/consult_all.sh "Your question"

# Option 3: Create .env file (see .env.example)
cp .env.example .env
# Edit .env to set ENABLE_*=false for consultants you don't have
```

**Note**: At least 2 consultants must be enabled for comparison and voting to work.

### Update & Uninstall

**Update to latest version:**
```bash
cd ~/.claude/skills/ai-consultants && git pull
cp .claude/commands/*.md ~/.claude/commands/
```

**Uninstall:**
```bash
rm -rf ~/.claude/skills/ai-consultants
rm -f ~/.claude/commands/ai-consultants:*.md
```

### Basic Usage

```bash
# Simple consultation
./scripts/consult_all.sh "How to optimize this function?" src/utils.py

# With multiple context files
./scripts/consult_all.sh "Redis or Memcached for this use case?" src/cache.py src/config.py
```

### Advanced Usage

```bash
# With multi-round debate (consultants critique each other)
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "Best architecture?"

# With smart routing (selects best consultants for the question)
ENABLE_SMART_ROUTING=true ./scripts/consult_all.sh "Bug in auth code"

# Follow-up to a previous consultation
./scripts/followup.sh "Elaborate on the architecture point"
./scripts/followup.sh -c Gemini "Can you provide a code example?"
```

## Workflow

```
Query -> [Classify] -> [Parallel Round 1] -> [Debate Round 2] -> [Synthesis] -> Report
              |              |                    |                |
         ARCHITECTURE    Gemini (8)           Cross-critique    Recommendation
         BUG_DEBUG       Codex (7)            Position updates  Comparison table
         SECURITY        Mistral (6)          Critiques         Risk assessment
         ...             Kilo (9)             Final stance      Action items
```

## Configuration

Edit `scripts/config.sh` or use environment variables:

```bash
# Personas and Synthesis
ENABLE_PERSONA=true
ENABLE_SYNTHESIS=true

# Multi-Agent Debate
ENABLE_DEBATE=false
DEBATE_ROUNDS=2

# Smart Routing
ENABLE_CLASSIFICATION=true
ENABLE_SMART_ROUTING=false
MIN_AFFINITY=7

# Cost Management
ENABLE_COST_TRACKING=true
MAX_SESSION_COST=1.00
WARN_AT_COST=0.50

# CLI consultants
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KILO=true
ENABLE_CURSOR=true
ENABLE_AIDER=false

# API consultants (require API keys)
ENABLE_QWEN3=false
ENABLE_GLM=false
ENABLE_GROK=false
ENABLE_DEEPSEEK=false
```

### Configurable Personas

Each consultant can be assigned a different persona from a catalog of 17 predefined roles:

```bash
# Run interactive persona configuration
./scripts/configure.sh

# Or set via environment variables (by ID)
GEMINI_PERSONA_ID=9     # The Mentor
CODEX_PERSONA_ID=11     # The Security Expert

# Or use custom persona text
GEMINI_PERSONA="You are a database optimization specialist..."

# List all 17 personas
source scripts/lib/personas.sh && list_personas
```

See [SKILL.md](SKILL.md#configurable-personas) for the complete persona catalog.

## Output

Each consultation generates:

```
/tmp/ai_consultations/TIMESTAMP/
├── context.md         # Automatically generated context
├── gemini.json        # Gemini response (with confidence)
├── codex.json         # Codex response (with confidence)
├── mistral.json       # Mistral response (with confidence)
├── kilo.json          # Kilo response (with confidence)
├── cursor.json        # Cursor response (with confidence)
├── voting.json        # Voting and consensus results
├── synthesis.json     # Automatic synthesis
├── report.md          # Combined report with recommendation
└── round_2/           # (if ENABLE_DEBATE) Debate responses
```

## Project Structure

```
ai-consultants/
├── README.md
├── CLAUDE.md                   # Claude Code instructions
├── SKILL.md                    # Skill documentation
├── CONTRIBUTING.md             # Contributing guide
├── LICENSE
├── .env.example                # Environment variables template
├── docs/
│   ├── SETUP.md                # Installation and auth guide
│   ├── COST_RATES.md           # Rates and costs
│   ├── SMART_ROUTING.md        # Smart routing
│   └── JSON_SCHEMA.md          # Output schema
├── scripts/
│   ├── config.sh               # Centralized configuration
│   ├── consult_all.sh          # Main orchestrator
│   ├── setup_wizard.sh         # Interactive setup wizard
│   ├── preflight_check.sh      # Health check
│   ├── classify_question.sh    # Question classifier
│   ├── synthesize.sh           # Auto-synthesis engine
│   ├── debate_round.sh         # MAD implementation
│   ├── followup.sh             # Follow-up queries
│   ├── build_context.sh        # Context builder
│   ├── query_gemini.sh         # Gemini wrapper
│   ├── query_codex.sh          # Codex wrapper
│   ├── query_mistral.sh        # Mistral wrapper
│   ├── query_kilo.sh           # Kilo wrapper
│   ├── query_cursor.sh         # Cursor wrapper
│   ├── query_aider.sh          # Aider wrapper
│   ├── query_qwen3.sh          # Qwen3 API wrapper
│   ├── query_glm.sh            # GLM API wrapper
│   ├── query_grok.sh           # Grok API wrapper
│   ├── query_deepseek.sh       # DeepSeek API wrapper
│   └── lib/
│       ├── common.sh           # Shared functions
│       ├── personas.sh         # Persona definitions
│       ├── schema.json         # JSON output schema
│       ├── voting.sh           # Confidence-weighted voting
│       ├── routing.sh          # Smart routing
│       ├── progress.sh         # Progress bars
│       ├── session.sh          # Session management
│       ├── costs.sh            # Cost tracking
│       └── reflection.sh       # Self-reflection
└── templates/
    ├── consultation_report.md  # Report template
    └── synthesis_prompt.md     # Synthesis prompt
```

## Consensus and Voting

The system automatically calculates:

- **Consensus Score**: 0-100% (how many consultants agree)
- **Confidence-Weighted Vote**: Recommendation weighted by confidence
- **Approach Groups**: Grouping by similar approach

```
100%    Unanimous - All agree
75-99%  High - 3+ agree
50-74%  Medium - 2 vs 2 or partial agreement
25-49%  Low - Strong disagreement
0-24%   None - No convergence
```

## Interpreting Results

- **High confidence + High consensus**: Proceed with confidence
- **Low confidence OR Low consensus**: Consider more options
- **Mistral disagrees**: Investigate identified risks
- **Kilo proposes alternative**: Evaluate innovation vs risk

## Claude Code Installation

```bash
# One-command install
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Or manual install
git clone git@github.com:matteoscurati/ai-consultants.git ~/.claude/skills/ai-consultants
chmod +x ~/.claude/skills/ai-consultants/scripts/*.sh ~/.claude/skills/ai-consultants/scripts/lib/*.sh
```

After installation, configure with the setup wizard:

```bash
~/.claude/skills/ai-consultants/scripts/setup_wizard.sh
```

Or use `/ai-consultants:config-wizard` in Claude Code.

The skill triggers automatically on phrases like "ask the consultants" or "what do other models think". Use `/ai-consultants:consult` for explicit invocation.

See **[SKILL.md](SKILL.md#claude-code-slash-commands)** for all available commands.

## Security

- **NEVER** include credentials, API keys, or sensitive data in queries
- Review context before sending
- Files in `/tmp` are automatically cleaned up

## Extended Documentation

- [Setup Guide](docs/SETUP.md) - CLI installation and authentication
- [Cost Rates](docs/COST_RATES.md) - Model rates and budget management
- [Smart Routing](docs/SMART_ROUTING.md) - Affinity matrix and intelligent routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output schema and validation

## Error Handling and Retry

The system implements:
- **Automatic retry** with `MAX_RETRIES` attempts (default: 2)
- **Configurable delay** between retries with `RETRY_DELAY_SECONDS` (default: 5s)
- **Per-consultant timeout** configurable in `config.sh`
- **Local fallback** if Claude CLI not available for synthesis

To configure:
```bash
MAX_RETRIES=3
RETRY_DELAY_SECONDS=10
GEMINI_TIMEOUT=240
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for complete guidelines.

Quick start:
1. Fork the repository
2. `cp .env.example .env` and configure
3. `./scripts/preflight_check.sh` to verify setup
4. Create branch: `git checkout -b feature/amazing-feature`
5. Open a Pull Request

## License

Distributed under the MIT License. See `LICENSE` for more information.

## Changelog

### v2.1.0
- **New CLI consultant**: Aider (The Pair Programmer)
- **New API consultant**: DeepSeek (The Code Specialist)
- Added 2 new personas (17 total)
- Simplified `consult_all.sh` with convention-based script discovery
- Updated routing affinities for all 10 consultants

### v2.0.0
- **Configurable personas**: 15 predefined personas, assignable to any consultant
- Confidence scoring (1-10) on every response
- Auto-synthesis with weighted recommendation
- Multi-Agent Debate (MAD) with cross-critique
- Smart routing based on question category
- Session management for follow-up
- Cost tracking and budget limits
- Pre-flight health checks
- Interactive progress bars
- **AI Agent Skill support**: Integration with Claude Code, Codex CLI, and other tools
