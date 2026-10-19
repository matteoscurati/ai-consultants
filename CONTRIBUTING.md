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

1. **Bash 3.2+** — the runtime must stay compatible with the stock macOS
   `/bin/bash` 3.2 (no associative arrays; see the `map_*` helpers in
   `scripts/lib/common.sh`). Check syntax with `/bin/bash -n`.
2. **jq** - JSON processor (required)
3. **bc** - Calculator (for cost tracking)

### Consultant CLIs

The automated tests use stubs and need no consultant CLI. For live runs,
install at least two consultants:

```bash
# Gemini (Antigravity CLI: agy)
curl -fsSL https://antigravity.google/cli/install.sh | bash

# Codex CLI (OpenAI)
npm install -g @openai/codex

# Mistral Vibe
pip install mistral-vibe

```

### Verify Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/ai-consultants.git
cd ai-consultants

# Verify dependencies and configuration
./scripts/doctor.sh

# Install the git pre-commit hook (recommended)
npm run install-hooks      # or: bash scripts/install-hooks.sh

# Create your private configuration (optional; never inside the repository)
./bin/ai-consultants configure      # or: ./bin/ai-consultants init
```

Configuration lives in `~/.config/ai-consultants/.env`; a project `.env` is not
read. To use another private directory, set `AI_CONSULTANTS_CONFIG_DIR`.

### Pre-commit hook

`npm run install-hooks` installs a git pre-commit hook (`scripts/hooks/pre-commit`) that runs `shellcheck` on staged `.sh` files under `scripts/` using the exact same invocation the CI lint job uses. This catches issues like SC2164 locally before they reach CI.

Notes:
- **Idempotent**: re-running the installer is safe; an existing different hook is backed up to `.git/hooks/pre-commit.backup.<timestamp>` (or use `FORCE=1 npm run install-hooks` to skip the backup).
- **No-op without shellcheck**: if `shellcheck` isn't on PATH the hook prints a warning and lets the commit through. Install via `brew install shellcheck` (macOS) or `apt-get install shellcheck` (Linux).
- **Bypass**: `git commit --no-verify` skips the hook. Use sparingly — CI will reject the same warnings.
- **Manual lint**: `npm run lint` runs the same shellcheck invocation on the full repo.

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

Every consultant envelope must follow `scripts/lib/schema.json` and every
`synthesis.json` its `definitions.synthesis_artifact` (see
`docs/JSON_SCHEMA.md`). Build envelopes only through the response builders in
`scripts/lib/common.sh`; tests check them with `assert_schema_valid`.
Minimum shape:

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

### Automated Tests (required before a PR)

```bash
npm test         # every scripts/test_*.sh suite, offline, with stub CLIs
npm run lint     # ShellCheck, the same invocation as CI
for f in bin/ai-consultants scripts/*.sh scripts/lib/*.sh; do /bin/bash -n "$f"; done
scripts/generate_public_docs.sh --check   # generated tables in README/SKILL/references
```

`npm test` ignores your personal configuration by itself and makes no billed
calls. The full suite takes several minutes.

### Manual Testing

These commands call real providers and may be billed.

```bash
# Health check
./scripts/doctor.sh

# Basic test (requires at least 2 consultants)
./scripts/consult_all.sh "How to optimize a SQL query?"

# Test coverage-union synthesis
./scripts/consult_all.sh --strategy coverage "Microservices or monolith?"

# Test with smart routing
ENABLE_SMART_ROUTING=true \
  ./scripts/consult_all.sh "Review this code" file.py

# Test the minimum two-consultant panel
./scripts/consult_all.sh --preset minimal "Quick syntax question"
```

### Verify Output

```bash
# Verify JSON structure
output_dir=$(./scripts/consult_all.sh --preset minimal "Schema smoke")
jq . "$output_dir/gemini.json"

# Verify the envelope and the synthesis artifact against the schema (jq only)
jq -n --slurpfile schema scripts/lib/schema.json --slurpfile doc "$output_dir/gemini.json" \
  -f scripts/lib/json_schema_check.jq
jq -n --slurpfile schema scripts/lib/schema.json --slurpfile doc "$output_dir/synthesis.json" \
  --arg definition synthesis_artifact -f scripts/lib/json_schema_check.jq
```

## Pull Request

### Branch Naming

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `refactor/` - Refactoring without new features

Examples:
- `feature/add-consultant-support`
- `fix/timeout-handling`
- `docs/update-readme`

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`,
`fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `perf:`, `ci:`; scope
optional):

```
feat(routing): add support for a new consultant

- New query adapter
- Updated config.sh with the consultant toggle
- Updated documentation
```

**Format:**
- First line: short, imperative mood
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
