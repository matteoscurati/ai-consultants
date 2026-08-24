---
name: ai-consultants
description: Consult Gemini, Codex, Mistral Vibe, Claude, Kimi, Qwen, MiniMax, GLM, Grok, and DeepSeek as external experts for coding questions. Automatically excludes the invoking agent from the panel to avoid self-consultation. Use when you have doubts about implementations, want a second opinion, need to choose between different approaches, or when explicitly requested with phrases like "ask the consultants", "what do the other models think", "compare solutions", "get expert opinions", "I'm not sure about this approach", "what would other models say". Make sure to consult this skill whenever the user is weighing trade-offs, comparing architectures, validating complex solutions, or wants multiple perspectives on any non-trivial coding decision. Do NOT use for simple questions that only need one model's answer or when you already have high confidence in a solution.
license: MIT
compatibility: Requires bash, jq, and at least 2 AI CLI tools (agy, codex, vibe, etc.). macOS and Linux.
metadata:
  author: matteoscurati
  version: 4.0.0
---

# AI Consultants v4.0.0 - AI Expert Panel

**Coverage, not a single guess.** Convene a panel of AI "consultants" from different vendors for coding questions: they fan out in parallel and you get the *union* of what they collectively see — the risks, edge cases, and approaches a single model misses. Each consultant has a **configurable persona** that decorrelates its analysis.

## Quick Start

```
/ai-consultants:consult "Your question here"
```

## Agent execution contract

When this skill is selected by an agent, execute the consultation instead of
only telling the user to type the slash command. Route through
`scripts/consult_all.sh`; do not call provider adapters individually.

1. Identify the invoking host and set `INVOKING_AGENT` explicitly:
   `claude` for Claude Code, `codex` for Codex CLI, or `gemini` for Gemini CLI.
   This is the boundary that prevents the host from consulting or synthesizing
   with itself.
2. Resolve the skill root from `AI_CONSULTANTS_DIR` when set. Otherwise use the
   host installation (`~/.claude/skills/ai-consultants` for Claude Code,
   `~/.codex/skills/ai-consultants` for Codex, or
   `~/.gemini/skills/ai-consultants` for Gemini).
3. Preserve consultation options such as `--preset` and `--strategy` as CLI
   arguments before the question. Pass referenced files as paths, optionally
   suffixed with `@PRIMARY` or `@CONTEXT`; do not paste their contents. Capture
   the caller's project directory before entering the skill root and pass it as
   `--context-root`, so the runtime can privately stage only regular in-project
   files.
4. Create a private question file with Bash `mktemp`, mode 600, and a
   single-quoted heredoc delimiter that does not occur as a line in the
   question. Use `--query-file`; never pass raw user text as a shell argument or
   through an unquoted heredoc. Shell-quote every context-file path as one
   argument, and install a shell trap that removes only that exact temporary
   question file. Capture the last stdout line as the output directory, then
   read `report.md` and
   `synthesis.json` (or the individual consultant JSON files when synthesis is
   unavailable).
5. Keep `INVOKING_AGENT` and the private `--query-file` handoff on follow-ups.
   A targeted follow-up to the invoking consultant must fail closed. For a
   Claude invocation, `claude.json` must not be produced and Claude must not be
   the synthesis provider. Treat either condition as a self-exclusion failure,
   not a valid consultation.

Claude Code example:

```bash
caller_root="$PWD"
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && \
  INVOKING_AGENT=claude ./scripts/consult_all.sh --preset balanced \
    --context-root "$caller_root" --query-file "<private-question-file>"
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
| **Kimi K3** | `kimi` | The Eastern Sage | Holistic, balanced perspectives |
| **Claude** | `claude` | The Synthesizer | Big picture, synthesis |
| **Qwen** | `qwen` | The Analyst | Data-driven, metrics |
| **Grok** | `grok` | The Provocateur | Challenge conventions |
| **MiniMax** | `mmx` | The Pragmatic Optimizer | Performance, efficiency, pragmatism |

**API-only consultants**: GLM (The Methodologist), DeepSeek (The Code Specialist)

**CLI/API Mode**: Gemini, Codex, Claude, Mistral, Qwen, Grok, and MiniMax can switch between CLI and API mode via `*_USE_API` environment variables. Grok is CLI-first on Grok Build with `grok-4.6` and falls back to the xAI API when the CLI cannot run. Gemini auto-selects API mode when `GEMINI_API_KEY` is set (no `agy` install needed) and the CLI otherwise. Mistral keeps separate API (`MISTRAL_MODEL`) and Vibe (`MISTRAL_CLI_MODEL`) identifiers.

Grok and Kimi are compatible by capability rather than by CLI version. Before
dispatch, their adapters verify the required headless arguments, requested
model, and structured-output surface. Compatible version changes are accepted;
the observed version is recorded only as response provenance.

The `max_quality` preset enables all 10 consultants. It uses the separately
smoke-tested K3-256k and MiniMax M3 targets, plus Qwen3.8-Max when an authenticated Token Plan transport is
already configured. Gemini 3.7 Flash High is the exact-transport-smoked `agy`
default for maximum, premium, and standard CLI tiers; Low serves economy. The
Gemini API target remains 3.1 Pro until `gemini-3.7-flash` completes a separate
API smoke. Claude Fable 5 and the new Mistral API IDs remain explicit opt-ins.
Grok, GLM, and DeepSeek receive their
highest accepted reasoning effort in this preset (`xhigh`, `max`, and `max`
respectively); no failed target is silently replaced.

Maximum-quality transports use smoke-tested runtime budgets: four advisory
turns for Mistral/Grok, extended Qwen/DeepSeek timeouts, and larger response
budgets for reasoning APIs and a compact native-system Markdown contract for
MiniMax M3. Responses carry an explicit `structured`,
`fallback`, or `error` quality. Truncated JSON fails closed; usable prose is
retained and disclosed, and synthesis consumes successful envelopes only.

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
