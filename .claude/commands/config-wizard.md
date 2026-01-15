---
description: Run the full interactive configuration wizard
allowed-tools: Bash Read
---

# AI Consultants - Configuration Wizard

Run the full interactive configuration wizard to set up all consultants, API keys, and personas.

## Instructions

**Run the interactive wizard:**

```bash
cd /Users/matteoscurati/work/ai-consultants
./scripts/configure.sh
```

This wizard will guide you through:

1. **CLI Agent Detection** - Automatically detects installed CLI tools
2. **CLI Agent Selection** - Choose which detected CLIs to enable
3. **Custom CLI Agents** - Add custom CLI tools if needed
4. **API Agent Configuration** - Set up Qwen3, GLM, Grok with API keys
5. **Custom API Agents** - Add OpenRouter, Groq, Together, or other APIs
6. **Persona Assignment** - Customize personalities for each consultant
7. **Validation** - Ensures at least 2 agents are enabled
8. **Save Configuration** - Writes secure .env file

## Non-Interactive Mode

For automated setup (uses detected CLIs and existing API keys):

```bash
./scripts/configure.sh --non-interactive
```

## Custom Output Location

```bash
./scripts/configure.sh --output /path/to/custom.env
```

## After Configuration

The wizard creates a `.env` file. To use it:

```bash
source .env
./scripts/consult_all.sh "Your question"
```

## Quick Alternative Commands

For specific configuration tasks, you can also use:
- `/project:config-status` - View current configuration
- `/project:config-check` - Verify CLI installations
- `/project:config-personas` - Change persona assignments
- `/project:config-api` - Configure API consultants only
