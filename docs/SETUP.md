# Setup Guide - AI Consultants v2.0

This guide walks you through installing and configuring the CLI tools required for AI Consultants.

## Prerequisites

- **Bash 4.0+** (required for associative arrays)
  - macOS ships with Bash 3.2 - you need to install a newer version
  - Linux usually has Bash 4+ already
- **Node.js 18+** for npm-based CLIs
- **Python 3.8+** for pip-based CLIs
- **jq** for JSON processing (required)
- **bc** for cost calculations (usually pre-installed)

## Quick Start

```bash
# 1. Run the setup wizard (recommended)
./scripts/setup_wizard.sh

# 2. Or manually check your setup
./scripts/preflight_check.sh
```

---

## Required: Bash 4+

AI Consultants uses Bash features (like associative arrays) that require Bash 4.0 or later.

**Check your version:**
```bash
bash --version
```

**macOS users:** macOS ships with Bash 3.2. Install a newer version:
```bash
# Install Bash 4+
brew install bash

# Add to allowed shells
sudo bash -c 'echo /opt/homebrew/bin/bash >> /etc/shells'

# Option 1: Run scripts explicitly with new bash
/opt/homebrew/bin/bash ./scripts/consult_all.sh "Your question"

# Option 2: Change your default shell (optional)
chsh -s /opt/homebrew/bin/bash
```

**Linux:** Usually has Bash 4+ pre-installed. If not:
```bash
# Ubuntu/Debian
sudo apt-get install bash

# Fedora/RHEL
sudo dnf install bash
```

---

## Required: jq

jq is required for JSON processing. Install it first:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora/RHEL
sudo dnf install jq

# Windows (via Chocolatey)
choco install jq
```

Verify installation:
```bash
jq --version
```

---

## Optional: bc

bc (basic calculator) is used for cost calculations. It's usually pre-installed on most systems.

**Check if installed:**
```bash
which bc
```

**If not installed:**
```bash
# macOS (usually pre-installed)
brew install bc

# Ubuntu/Debian
sudo apt-get install bc

# Fedora/RHEL
sudo dnf install bc
```

---

## Consultant CLIs

You need **at least 2 consultants** configured for AI Consultants to work.

### Gemini CLI (The Architect)

Google's Gemini CLI for enterprise-focused architectural advice.

**Installation:**
```bash
npm install -g @google/gemini-cli
```

**Authentication:**
```bash
# Option 1: Interactive login (recommended)
gemini auth login

# Option 2: API key
export GOOGLE_API_KEY="your-api-key-here"
```

**Get API Key:**
1. Go to [Google AI Studio](https://makersuite.google.com/app/apikey)
2. Create a new API key
3. Set it as `GOOGLE_API_KEY` environment variable

**Verify:**
```bash
gemini --version
```

---

### Codex CLI (The Pragmatist)

OpenAI's Codex CLI for practical, proven solutions.

**Installation:**
```bash
npm install -g @openai/codex
```

**Authentication:**
```bash
export OPENAI_API_KEY="sk-your-api-key-here"
```

**Get API Key:**
1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Create a new API key
3. Set it as `OPENAI_API_KEY` environment variable

**Verify:**
```bash
codex --help
```

---

### Mistral Vibe CLI (The Devil's Advocate)

Mistral's Vibe CLI for critical analysis and edge case detection.

**Installation:**
```bash
pip install mistral-vibe
```

**Authentication:**
```bash
export MISTRAL_API_KEY="your-api-key-here"
```

**Get API Key:**
1. Go to [Mistral AI Console](https://console.mistral.ai/api-keys/)
2. Create a new API key
3. Set it as `MISTRAL_API_KEY` environment variable

**Verify:**
```bash
vibe --help
```

---

### Kilo CLI (The Innovator)

Kilo Code CLI for creative and unconventional approaches.

**Installation:**
```bash
npm install -g @kilocode/cli
```

**Authentication:**
```bash
# Run the auth flow
kilocode auth login
```

**Verify:**
```bash
kilocode --version
```

---

## Optional: Claude CLI

Claude CLI is used for automatic synthesis of responses. If not installed, a local fallback is used.

**Installation:**
```bash
npm install -g @anthropic-ai/claude-code
```

**Authentication:**
```bash
export ANTHROPIC_API_KEY="sk-ant-your-api-key-here"
```

---

## Environment Configuration

### Using .env file

Create a `.env` file in the project root (use `.env.example` as template):

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```bash
# Enable/disable consultants based on what you have configured
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=false  # Set to false if not configured
ENABLE_KILO=false     # Set to false if not configured

# API Keys (if not using CLI auth)
GOOGLE_API_KEY=your-key
OPENAI_API_KEY=sk-your-key
MISTRAL_API_KEY=your-key
```

### Minimum Requirements

**At least 2 consultants must be enabled** for AI Consultants to function. The system requires multiple perspectives for meaningful comparison and voting.

Example configurations:

**OpenAI + Google only:**
```bash
ENABLE_GEMINI=true
ENABLE_CODEX=true
ENABLE_MISTRAL=false
ENABLE_KILO=false
```

**OpenAI + Mistral only:**
```bash
ENABLE_GEMINI=false
ENABLE_CODEX=true
ENABLE_MISTRAL=true
ENABLE_KILO=false
```

---

## Verification

### Run Preflight Check

```bash
./scripts/preflight_check.sh
```

Expected output for a working setup:
```
[OK] jq installed
[OK] Gemini CLI installed and authenticated
[OK] Codex CLI installed and authenticated
[WARN] Mistral CLI not found (optional)
[WARN] Kilo CLI not found (optional)

Status: Ready (2/4 consultants available)
```

### Run Setup Wizard

For an interactive setup experience:

```bash
./scripts/setup_wizard.sh
```

The wizard will:
1. Check which CLIs are installed
2. Test authentication for each CLI
3. Suggest configuration based on your setup
4. Optionally generate a `.env` file

---

## Troubleshooting

### "Command not found" errors

Ensure the CLI is installed globally and in your PATH:

```bash
# Check npm global path
npm list -g --depth=0

# Check pip packages
pip list | grep mistral
```

### Authentication failures

**Gemini:**
```bash
# Re-authenticate
gemini auth logout
gemini auth login
```

**Codex:**
```bash
# Verify API key is set
echo $OPENAI_API_KEY

# Test with a simple request
codex --help
```

**Mistral:**
```bash
# Verify API key
echo $MISTRAL_API_KEY

# Test
vibe --help
```

### Timeout errors

Increase timeout in your `.env`:

```bash
GEMINI_TIMEOUT=300
CODEX_TIMEOUT=300
MISTRAL_TIMEOUT=300
KILO_TIMEOUT=300
```

### "Less than 2 consultants" error

At least 2 consultants must be enabled and working. Either:
1. Install and configure another CLI
2. Run `./scripts/setup_wizard.sh` for guidance

---

## Platform-Specific Notes

### macOS

Install coreutils for better timeout handling:
```bash
brew install coreutils
```

### Windows (WSL recommended)

AI Consultants works best in WSL (Windows Subsystem for Linux):
```bash
# Install WSL
wsl --install

# Then follow Linux instructions
```

### Linux

No special requirements. Ensure `timeout` command is available (usually pre-installed).

---

## Next Steps

After setup is complete:

```bash
# Test your configuration
./scripts/consult_all.sh "How do I optimize a SQL query?"

# View the generated report
cat /tmp/ai_consultations/*/report.md
```

See [README.md](../README.md) for usage examples and advanced configuration.
