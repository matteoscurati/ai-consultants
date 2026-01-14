# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-01-14

### Added

#### Core Features
- **Personas System**: Each consultant has a unique persona
  - Gemini: The Architect (design, scalability, enterprise)
  - Codex: The Pragmatist (simplicity, quick wins, YAGNI)
  - Mistral: The Devil's Advocate (problems, edge cases, vulnerabilities)
  - Kilo: The Innovator (creativity, unconventional approaches)

- **Confidence Scoring**: 1-10 score on every response with reasoning

- **Auto-Synthesis**: Automatic synthesis with Claude CLI
  - Confidence-weighted recommendation
  - Consultant comparison table
  - Risk assessment
  - Action items

- **Multi-Agent Debate (MAD)**: Cross-critique between consultants
  - Multiple deliberation rounds
  - Position change tracking
  - Critiques categorized by severity

- **Smart Routing**: Consultant selection by category
  - 10x4 affinity matrix (categories x consultants)
  - 10 categories: CODE_REVIEW, BUG_DEBUG, ARCHITECTURE, etc.
  - Routing modes: full, selective, single
  - Optimized timeouts per category

- **Session Management**: Follow-up and continuity
  - Persistent session state
  - Follow-up to all or single consultant
  - Session history

- **Cost Tracking**: Budget estimation and management
  - Per-model rates (input/output)
  - Configurable budget limits
  - Warning thresholds
  - Cumulative cost reports

#### New Scripts
- `scripts/preflight_check.sh` - CLI and API health check
- `scripts/classify_question.sh` - Question classifier
- `scripts/synthesize.sh` - Auto-synthesis engine
- `scripts/debate_round.sh` - MAD implementation
- `scripts/followup.sh` - Follow-up queries
- `scripts/build_context.sh` - Context builder

#### New Libraries
- `scripts/lib/personas.sh` - Persona definitions
- `scripts/lib/schema.json` - JSON output schema v2.0
- `scripts/lib/voting.sh` - Confidence-weighted voting
- `scripts/lib/routing.sh` - Smart routing
- `scripts/lib/session.sh` - Session management
- `scripts/lib/costs.sh` - Cost tracking
- `scripts/lib/progress.sh` - Interactive progress bars
- `scripts/lib/reflection.sh` - Self-reflection (experimental)

#### Documentation
- `.env.example` - Environment variables template
- `CONTRIBUTING.md` - Contributing guide
- `docs/COST_RATES.md` - Rates documentation
- `docs/SMART_ROUTING.md` - Routing documentation
- `docs/JSON_SCHEMA.md` - Output schema documentation

### Changed

- **Output Format**: Structured JSON with defined schema
- **Report Template**: Updated for v2.0 with synthesis and debate
- **Query Wrappers**: All updated for personas and JSON output
- **Config**: Centralized with new feature flags

### Breaking Changes

- Output files now in JSON format (no longer TXT for some consultants)
- Report includes Synthesis section instead of empty template
- Response schema modified (see `docs/JSON_SCHEMA.md`)

## [1.0.0] - 2025-12-01

### Added
- Initial release
- 4 consultants: Gemini, Codex, Mistral, Kilo
- Parallel queries
- Markdown report
- Automatic context from files

---

## Types of Changes

- `Added` for new features
- `Changed` for changes in existing functionality
- `Deprecated` for soon-to-be removed features
- `Removed` for now removed features
- `Fixed` for bug fixes
- `Security` for vulnerabilities
