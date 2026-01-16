# Setup Guide - AI Consultants v2.2

This guide walks you through installing and configuring AI Consultants, with a focus on Claude Code integration.

---

## Claude Code Setup (Recommended)

AI Consultants is designed as a **Claude Code skill**. This is the fastest and easiest way to get started.

### Step 1: Install the Skill

```bash
# One-liner installation
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
```

This installs to `~/.claude/skills/ai-consultants/` and makes slash commands available in Claude Code.

### Step 2: Run the Setup Wizard

Open Claude Code and type:

```
/ai-consultants:config-wizard
```

The wizard will:
1. Detect which CLIs are installed
2. Test authentication for each
3. Help configure missing consultants
4. Generate your `.env` file

### Step 3: Verify Installation

```
/ai-consultants:config-check
```

You should see at least 2 consultants marked as available.

### Step 4: Your First Consultation

```
/ai-consultants:consult "What's the best way to structure a REST API?"
```

That's it! You're ready to go.

---

## Claude Code Slash Commands

AI Consultants provides 12 slash commands for seamless integration:

### Main Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Ask AI consultants a coding question |
| `/ai-consultants:ask-experts` | Quick query (alias for consult) |
| `/ai-consultants:debate` | Run consultation with multi-round debate |
| `/ai-consultants:help` | Show all commands and usage |

### Configuration Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:config-wizard` | Full interactive setup |
| `/ai-consultants:config-check` | Verify CLIs are installed and authenticated |
| `/ai-consultants:config-status` | View current configuration |
| `/ai-consultants:config-preset` | Set default preset (minimal, balanced, high-stakes, local) |
| `/ai-consultants:config-strategy` | Set default synthesis strategy |
| `/ai-consultants:config-features` | Toggle features (debate, synthesis, peer review) |
| `/ai-consultants:config-personas` | Change consultant personas |
| `/ai-consultants:config-api` | Configure API-based consultants |

### Configuration Workflow

Use slash commands to configure AI Consultants without editing files:

```
# Set your preferred preset
/ai-consultants:config-preset

# Set synthesis strategy
/ai-consultants:config-strategy

# Enable/disable features
/ai-consultants:config-features

# View your configuration
/ai-consultants:config-status
```

All settings are saved to `~/.claude/skills/ai-consultants/.env`.

---

## Prerequisites

Before installing consultant CLIs, ensure you have:

- **Bash 4.0+** (macOS ships with 3.2 - install newer version)
- **Node.js 18+** for npm-based CLIs
- **Python 3.8+** for pip-based CLIs
- **jq** for JSON processing (required)
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

---

## Consultant CLIs

You need **at least 2 consultants** configured for AI Consultants to work.

### Gemini CLI (The Architect)

```bash
npm install -g @google/gemini-cli

# Authentication
gemini auth login
# OR: export GOOGLE_API_KEY="your-key"
```

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

### Kilo CLI (The Innovator)

```bash
npm install -g @kilocode/cli

# Authentication
kilocode auth login
```

### Cursor CLI (The Integrator)

```bash
curl https://cursor.com/install -fsS | bash

# Uses Cursor subscription - no additional key needed
```

### Aider CLI (The Pair Programmer)

```bash
pip install aider-chat

# Authentication
export OPENAI_API_KEY="sk-your-key"  # Or other provider
```

---

## Ollama (Local Models) - v2.2

Run consultations 100% locally with zero API cost and full privacy.

### Installation

**macOS/Linux:**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**macOS (Homebrew):**
```bash
brew install ollama
```

**Verify installation:**
```bash
ollama --version
```

### Start Server

Ollama needs a running server:

```bash
# Start in background
ollama serve &

# Or start manually before consultation
ollama serve
```

### Pull Models

```bash
# Recommended for general use
ollama pull llama3.2

# For code-specific tasks
ollama pull codellama
ollama pull deepseek-coder

# Smaller/faster options
ollama pull mistral
ollama pull qwen2.5-coder
```

### Configuration

**Claude Code:**
```
/ai-consultants:config-features     # Enable ENABLE_OLLAMA
```

**Environment variables:**
```bash
# Enable Ollama consultant
export ENABLE_OLLAMA=true

# Choose model (default: llama3.2)
export OLLAMA_MODEL=llama3.2

# Server URL (default: localhost)
export OLLAMA_HOST=http://localhost:11434

# Timeout (default: 300s - longer for local inference)
export OLLAMA_TIMEOUT=300
```

### Usage

**Claude Code:**
```
/ai-consultants:config-preset       # Select "local" preset
/ai-consultants:consult "Your private question"
```

**Bash:**
```bash
# Use local preset (Ollama only)
./scripts/consult_all.sh --preset local "Your question"

# Add Ollama to other presets
ENABLE_OLLAMA=true ./scripts/consult_all.sh --preset balanced "Question"
```

### Multi-Model Local

Query multiple local models:

```bash
export OLLAMA_MODELS="llama3.2,codellama,mistral"
./scripts/consult_all.sh --preset local "Question"
```

### Troubleshooting Ollama

**Server not running:**
```bash
# Check if running
curl http://localhost:11434/api/tags

# Start server
ollama serve
```

**Model not found:**
```bash
# List available models
ollama list

# Pull missing model
ollama pull llama3.2
```

**Slow inference:**
- Use smaller models (`mistral`, `qwen2.5-coder:7b`)
- Increase timeout: `OLLAMA_TIMEOUT=600`

---

## Configuration Presets (v2.2)

Presets let you quickly configure how many consultants to use.

### Available Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick, cheap |
| `balanced` | 4 (+ Mistral + Kilo) | Standard |
| `thorough` | 5 (+ Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Privacy |
| `security` | Security-focused + debate | Security reviews |
| `cost-capped` | Budget-friendly | Low cost |

### Set Default Preset

**Claude Code:**
```
/ai-consultants:config-preset
```

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

**Claude Code:**
```
/ai-consultants:config-strategy
```

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

## Environment Configuration

### Using .env file

```bash
cp .env.example .env
```

Edit `.env`:

```bash
# Enable/disable consultants
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=false
ENABLE_KILO=false
ENABLE_OLLAMA=true

# API Keys
GOOGLE_API_KEY=your-key
OPENAI_API_KEY=sk-your-key
MISTRAL_API_KEY=your-key

# Defaults (v2.2)
DEFAULT_PRESET=balanced
DEFAULT_STRATEGY=majority

# Ollama
OLLAMA_MODEL=llama3.2

# Features
ENABLE_DEBATE=false
ENABLE_SYNTHESIS=true
ENABLE_PANIC_MODE=auto
```

### Minimum Requirements

**At least 2 consultants must be enabled.**

Example configurations:

**OpenAI + Google:**
```bash
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=false
ENABLE_KILO=false
```

**OpenAI + Local:**
```bash
ENABLE_CODEX=true
ENABLE_OLLAMA=true
ENABLE_GEMINI=false
ENABLE_MISTRAL=false
```

**Local only:**
```bash
ENABLE_OLLAMA=true
OLLAMA_MODELS="llama3.2,codellama"
# All others false
```

---

## Verification

### Claude Code (Recommended)

```
/ai-consultants:config-check        # Quick check
/ai-consultants:config-status       # Full status
```

### Doctor Command

```bash
./scripts/doctor.sh
```

Checks:
- CLI tools installed
- API keys configured
- Ollama server running
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
[OK] Ollama server running

Status: Ready (3/4 consultants available)
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

**Gemini:**
```bash
gemini auth logout
gemini auth login
```

**Codex:**
```bash
echo $OPENAI_API_KEY  # Verify set
```

### Timeout errors

Increase timeout in `.env`:
```bash
GEMINI_TIMEOUT=300
CODEX_TIMEOUT=300
OLLAMA_TIMEOUT=600  # Local models need more time
```

### "Less than 2 consultants" error

Either:
1. Install another CLI
2. Enable Ollama for local inference
3. Run `./scripts/doctor.sh --fix`

### Claude Code Issues

| Issue | Solution |
|-------|----------|
| "Unknown skill" | Run install script again |
| Commands not showing | Restart Claude Code |
| "Exit code 1" | Run `/ai-consultants:config-check` |
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
