---
name: ai-consultants
description: Consult Gemini, Codex, Mistral Vibe, Cursor, Claude, Kimi, Qwen, MiniMax, GLM, Grok, and DeepSeek as external experts for coding questions. Automatically excludes the invoking agent from the panel to avoid self-consultation. Use when you have doubts about implementations, want a second opinion, need to choose between different approaches, or when explicitly requested with phrases like "ask the consultants", "what do the other models think", "compare solutions", "get expert opinions", "I'm not sure about this approach", "what would other models say". Make sure to consult this skill whenever the user is weighing trade-offs, comparing architectures, validating complex solutions, or wants multiple perspectives on any non-trivial coding decision. Do NOT use for simple questions that only need one model's answer or when you already have high confidence in a solution.
license: MIT
compatibility: Requires bash, jq, and at least 2 AI CLI tools (agy, codex, vibe, etc.). macOS and Linux.
metadata:
  author: matteoscurati
  version: 2.25.2
---

# AI Consultants v2.25.2 - AI Expert Panel

**Coverage, not a single guess.** Convene a panel of AI "consultants" from different vendors for coding questions: they fan out in parallel and you get the *union* of what they collectively see — the risks, edge cases, and approaches a single model misses. Each consultant has a **configurable persona** that decorrelates its analysis.

## Quick Start

```
/ai-consultants:consult "Your question here"
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/ai-consultants:consult` | Main consultation - ask AI consultants a coding question |
| `/ai-consultants:help` | Show all commands and usage |

Configuration (presets, strategies, features, personas, API keys) can be managed via natural language — just ask.

## Consultants and Personas

| Consultant | CLI | Persona | Focus |
|------------|-----|---------|-------|
| **Google Gemini** | `agy` | The Architect | Design patterns, scalability |
| **OpenAI Codex** | `codex` | The Pragmatist | Simplicity, proven solutions |
| **Mistral Vibe** | `vibe` | The Devil's Advocate | Edge cases, vulnerabilities |
| **Cursor** | `agent` | The Integrator | Full-stack perspective |
| **Kimi K3** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis |
| **Qwen** | `qwen` | The Analyst | Data-driven, metrics |
| **MiniMax** | `mmx` | The Pragmatic Optimizer | Performance, efficiency, pragmatism |

**API-only consultants**: GLM (The Methodologist), Grok (The Provocateur), DeepSeek (The Code Specialist)

**CLI/API Mode**: Gemini, Codex, Claude, Mistral, Qwen, and MiniMax can switch between CLI and API mode via `*_USE_API` environment variables. Gemini auto-selects API mode when `GEMINI_API_KEY` is set (no `agy` install needed) and the CLI otherwise.

**Self-Exclusion**: The invoking agent is automatically excluded from the panel. When invoked from Claude Code, Claude is excluded; when invoked from Codex CLI, Codex is excluded, etc.

## Requirements

- **At least 2 consultant CLIs** installed and authenticated
- **jq** for JSON processing

### Quick Install

```bash
# Option A: npx (recommended, no install needed)
npx ai-consultants doctor --fix
npx ai-consultants install  # Install slash commands for Claude Code

# Option B: curl | bash
curl -fsSL https://raw.githubusercontent.com/matteoscurati/ai-consultants/main/scripts/install.sh | bash
~/.claude/skills/ai-consultants/scripts/doctor.sh --fix
```

For detailed CLI installation instructions, see [Setup Guide](docs/SETUP.md).

## Usage Examples

```
/ai-consultants:consult "How to optimize this SQL query?"
/ai-consultants:consult "Review this authentication flow" src/auth.ts
/ai-consultants:consult "What could go wrong with this design?" src/service.ts
```

Presets: `minimal`, `balanced`, `thorough`, `high-stakes`, `security`, `cost-capped`, `max_quality`, `medium`, `fast`. Strategies: `coverage` (default; union of distinct points), `compare_only`, `majority`, `risk_averse`, `security_first`, `cost_capped`. See [Reference Details](references/details.md) for full tables, bash usage, and best practices.

## Workflow

The query is classified, optionally routed by category, then sent to all consultants in parallel. Their responses are synthesized into the **coverage union** — the deduplicated set of every distinct point, recommendation, and risk raised across the panel (not a single voted winner). Use `--strategy compare_only` for a side-by-side, or `majority` for a blended recommendation.

## Features

| Feature | Description | Toggle |
|---------|-------------|--------|
| **Personas** | Each consultant has a role that decorrelates responses | `ENABLE_PERSONA` |
| **Coverage synthesis** | Union of every distinct point across the panel (default) | `ENABLE_SYNTHESIS` |
| **Smart Routing** | Auto-select best consultants per question category | `ENABLE_SMART_ROUTING` |
| **Cost Tracking** | Track API usage costs | `ENABLE_COST_TRACKING` |
| **Health Gate** | Ping and prune dead consultants before the run (opt-in) | `ENABLE_HEALTH_GATE` |

## Configuration

All settings use environment variables. Key toggles:

```bash
ai-consultants configure     # Auto-detect CLIs/API keys and persist all settings
ENABLE_SYNTHESIS=true        # Coverage-union synthesis
ENABLE_SMART_ROUTING=true    # Route by question category
ENABLE_BUDGET_LIMIT=false    # Budget enforcement (v2.4)
```

Use `ai-consultants configure --show-parameters` for the exact accepted keys,
`--set KEY=VALUE` for repeatable automation, or `--advanced` to review all of
them interactively.

CLI/API switching: `GEMINI_USE_API`, `CODEX_USE_API`, `CLAUDE_USE_API`, `MISTRAL_USE_API`, `QWEN3_USE_API`.

See [Full Configuration Reference](references/configuration.md) for all variables, model overrides, tiers, timeouts, and optimization settings.

## Output

```
/tmp/ai_consultations/TIMESTAMP/
├── gemini.json        # Individual responses
├── codex.json
├── synthesis.json     # Coverage union
└── report.md          # Human-readable
```

## Doctor Command

Diagnose and fix issues:

```bash
./scripts/doctor.sh              # Full check (CLI installed?)
./scripts/doctor.sh --fix        # Auto-fix
./scripts/doctor.sh --json       # JSON output
./scripts/doctor.sh --live       # Real ping per consultant — catches installed-but-unauthenticated CLIs
```

Keep the consultant CLIs current with `ai-consultants update-clis` (`--dry-run` to
preview, `--only <cli>` to target one) — it detects how each CLI was installed
(brew/npm/uv/pipx/curl/self-update) and updates it.

When a consultant fails during a consultation, the run prints the captured reason (e.g. "CLI not found", "401 Unauthorized"). The run is also **graded** MET/DEGRADED/FAILED by how many responded (`QUORUM_MIN`), with a "Diagnosed Failures" section in the report. Set `ENABLE_HEALTH_GATE=true` to ping consultants and drop the dead ones *before* the run.

## Interpreting Results

| Scenario | Recommendation |
|----------|----------------|
| A point only one consultant raised | Weigh it — the diversity is the point |
| Mistral (Devil's Advocate) flags a risk | Investigate it |
| Consultants diverge on approach | Use `--strategy compare_only` to see each side-by-side |

## Troubleshooting

Run `./scripts/doctor.sh` to diagnose issues, or `./scripts/doctor.sh --fix` to auto-fix.

## Extended Documentation

- [Reference Details](references/details.md) - Presets, strategies, best practices, limitations
- [Full Configuration](references/configuration.md) - All environment variables, models, tiers, timeouts
- [Configuration Recipes](docs/RECIPES.md) - Copy-paste workflows for routing, budgets, and transport
- [Setup Guide](docs/SETUP.md) - Installation, authentication
- [Cost Rates](docs/COST_RATES.md) - Model pricing
- [Smart Routing](docs/SMART_ROUTING.md) - Category routing
- [JSON Schema](docs/JSON_SCHEMA.md) - Output format
