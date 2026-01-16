# Setup Guide - AI Consultants v2.2

This guide walks you through installing and configuring AI Consultants.

## Quick Start

```bash
# One-liner installation
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash

# Verify and fix issues
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix

# Run setup wizard
~/.claude/skills/ai-consultants/scripts/setup_wizard.sh
```

---

## Prerequisites

- **Bash 4.0+** (macOS ships with 3.2 - install newer version)
- **Node.js 18+** for npm-based CLIs
- **Python 3.8+** for pip-based CLIs
- **jq** for JSON processing (required)
- **bc** for cost calculations (usually pre-installed)

---

## Required: Bash 4+

AI Consultants uses Bash features that require Bash 4.0 or later.

**Check your version:**
```bash
bash --version
```

**macOS users:** Install newer Bash:
```bash
brew install bash
sudo bash -c 'echo /opt/homebrew/bin/bash >> /etc/shells'

# Run scripts with new bash
/opt/homebrew/bin/bash ./scripts/consult_all.sh "Your question"
```

**Linux:** Usually has Bash 4+ pre-installed.

---

## Required: jq

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

# Ollama
OLLAMA_MODEL=llama3.2
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

### Doctor Command (Recommended)

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

### Setup Wizard

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

## Claude Code Configuration

If using as a Claude Code skill:

```bash
~/.claude/skills/ai-consultants/scripts/setup_wizard.sh
```

Or use `/ai-consultants:config-wizard` command.

---

## Configuration Presets (v2.2)

Quick configuration with presets:

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick, cheap |
| `balanced` | 4 (+ Mistral + Kilo) | Standard |
| `thorough` | 5 (+ Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical |
| `local` | Ollama only | Privacy |

```bash
./scripts/consult_all.sh --preset balanced "Question"
```

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

```bash
# Test your configuration
./scripts/consult_all.sh --preset minimal "How do I optimize a SQL query?"

# View the report
cat /tmp/ai_consultations/*/report.md
```

See [README.md](../README.md) for usage examples.
