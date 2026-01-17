# AI Consultants

Multi-model AI consultation system for coding questions. Query multiple AI experts simultaneously and get synthesized recommendations with confidence scores.

## Skills

| Skill | Description |
|-------|-------------|
| `ai-consultants` | Consult multiple AI models for diverse perspectives on coding problems |

## Usage

### Claude Code / Codex CLI / Gemini CLI

```bash
# Install as a skill
mkdir -p ~/.claude/skills  # or ~/.codex/skills, ~/.gemini/skills
ln -s /path/to/ai-consultants ~/.claude/skills/ai-consultants
```

Then use slash commands:
```
/ai-consultants:consult "Your coding question"
/ai-consultants:debate "Architecture decision"
```

### SkillPort (Multi-Agent)

```bash
# Install via SkillPort for Cursor, Copilot, Windsurf
skillport add github.com/matteoscurati/ai-consultants
skillport show ai-consultants
```

### Direct Bash

```bash
./scripts/consult_all.sh "Your question"
./scripts/consult_all.sh --preset balanced "Question with 4 consultants"
```

## Features

- **10+ AI consultants** with unique personas
- **Automatic synthesis** with weighted recommendations
- **Multi-agent debate** for controversial decisions
- **Anonymous peer review** for unbiased evaluation
- **Local model support** via Ollama

## Requirements

- At least 2 consultant CLIs installed (gemini, codex, vibe, kilocode, etc.)
- `jq` for JSON processing
- Bash 4.0+

## Documentation

- [SKILL.md](SKILL.md) - Full skill specification
- [docs/SETUP.md](docs/SETUP.md) - Installation guide
- [README.md](README.md) - Complete documentation
