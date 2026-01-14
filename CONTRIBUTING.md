# Contributing to AI Consultants

Thank you for your interest in contributing to AI Consultants! This document provides guidelines for contributing to the project.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Code Conventions](#code-conventions)
- [Testing](#testing)
- [Pull Request](#pull-request)
- [Project Structure](#project-structure)

## Development Environment Setup

### Prerequisites

1. **Bash 4.0+** (for associative arrays)
2. **jq** - JSON processor (required)
3. **bc** - Calculator (for cost tracking)

### Consultant CLIs

Install at least one of the consultant CLIs:

```bash
# Gemini CLI (Google)
# Follow: https://ai.google.dev/gemini-api/docs/quickstart

# Codex CLI (OpenAI)
npm install -g @openai/codex

# Mistral Vibe
pip install mistral-vibe

# Kilo Code
npm install -g kilocode
```

### Verify Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/ai-consultants.git
cd ai-consultants

# Verify dependencies
./scripts/preflight_check.sh

# Copy environment configuration (optional)
cp .env.example .env
```

## Code Conventions

### Bash Scripts

**Required header:**
```bash
#!/bin/bash
# script_name.sh - Brief description
#
# More detailed description if needed.

set -euo pipefail
```

**Library sourcing:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/config.sh"
```

**Logging:**
```bash
log_info "Informational message"
log_success "Operation completed"
log_warn "Warning: possible issue"
log_error "Critical error"
log_debug "Debug info (only if LOG_LEVEL=DEBUG)"
```

**Variables:**
- UPPERCASE for global configuration variables
- lowercase for local variables
- Always quote variables: `"$VAR"` not `$VAR`

**Array handling with `set -u`:**
```bash
# Correct
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    FILES=()
fi

# DO NOT use ${array[*]} without checking first
```

### JSON Output

Every JSON output must follow `lib/schema.json`:

```json
{
  "consultant": "ConsultantName",
  "model": "model-used",
  "persona": "The Architect|Pragmatist|Devil's Advocate|Innovator",
  "response": {
    "summary": "TL;DR max 500 chars",
    "detailed": "Full response",
    "approach": "Approach name"
  },
  "confidence": {
    "score": 8,
    "reasoning": "Score justification"
  },
  "metadata": {
    "timestamp": "2024-01-14T12:00:00Z",
    "latency_ms": 1234
  }
}
```

### Naming Conventions

- **Files**: `snake_case.sh`
- **Functions**: `snake_case`
- **Config variables**: `SCREAMING_SNAKE_CASE`
- **Local variables**: `snake_case`
- **JSON keys**: `snake_case`

## Testing

### Manual Testing

```bash
# Health check
./scripts/preflight_check.sh

# Basic test (requires at least 1 CLI)
./scripts/consult_all.sh "How to optimize a SQL query?"

# Test with debate
ENABLE_DEBATE=true DEBATE_ROUNDS=2 \
  ./scripts/consult_all.sh "Microservices or monolith?"

# Test with smart routing
ENABLE_SMART_ROUTING=true \
  ./scripts/consult_all.sh "Review this code" file.py

# Test single consultant
ENABLE_GEMINI=true ENABLE_CODEX=false ENABLE_MISTRAL=false ENABLE_KILO=false \
  ./scripts/consult_all.sh "Quick syntax question"
```

### Verify Output

```bash
# Verify JSON structure
jq . /tmp/ai_consultations/*/gemini.json

# Verify schema (if you have jsonschema)
jsonschema -i output.json scripts/lib/schema.json
```

## Pull Request

### Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `refactor/` - Refactoring without new features

Examples:
- `feature/add-ollama-support`
- `fix/timeout-handling`
- `docs/update-readme`

### Commit Messages

Use clear and concise messages:

```
Add support for Ollama as consultant

- New script query_ollama.sh
- Updated config.sh with ENABLE_OLLAMA
- Updated documentation
```

**Format:**
- First line: max 50 characters, imperative mood
- Blank line
- Body: details if needed

### PR Checklist

- [ ] I have tested the changes locally
- [ ] I have updated documentation if needed
- [ ] I have followed code conventions
- [ ] I have added `set -euo pipefail` to new scripts
- [ ] JSON outputs follow `lib/schema.json`
- [ ] I have updated `.env.example` if I added new variables

### Review Process

1. Open a PR with clear description
2. Wait for review
3. Respond to comments and make requested changes
4. Once approved, the PR will be merged

## Project Structure

```
ai-consultants/
├── scripts/               # Executable scripts
│   ├── consult_all.sh     # Main entry point
│   ├── config.sh          # Configuration
│   ├── query_*.sh         # Consultant wrappers
│   └── lib/               # Libraries (not executable)
├── templates/             # Markdown templates
├── docs/                  # Extended documentation
├── .env.example           # Environment variables template
├── README.md              # Main documentation
├── CLAUDE.md              # Claude Code instructions
├── SKILL.md               # Skill documentation
└── CONTRIBUTING.md        # This file
```

### Where to Put New Code

| Type | Location |
|------|----------|
| New consultant | `scripts/query_NAME.sh` |
| New utility | `scripts/lib/NAME.sh` |
| New config feature | `scripts/config.sh` |
| Documentation | `docs/` or README.md |
| Output template | `templates/` |

## Questions?

If you have questions or concerns, open an issue on GitHub.

Thanks for contributing!
