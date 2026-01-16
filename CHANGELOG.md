# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-01-16

### Added

#### Quick Configuration
- **Configuration Presets**: Use `--preset` flag for instant setup
  - `minimal` (2 models): Gemini + Codex - fast, cheap
  - `balanced` (4 models): + Mistral + Kilo - good coverage
  - `thorough` (5 models): + Cursor - comprehensive
  - `high-stakes` (all + debate): maximum rigor
  - `local` (Ollama): full privacy, zero API cost
  - `security` (security-focused): + debate for security reviews
  - `cost-capped` (budget-conscious): minimal API costs

- **Doctor Command**: Diagnostic and auto-fix tool (`scripts/doctor.sh`)
  - `--fix` flag to auto-correct common issues
  - `--json` for machine-readable output
  - `--verbose` for detailed diagnostics
  - Checks CLIs, API keys, Ollama server, configuration

#### Synthesis and Analysis
- **Multiple Synthesis Strategies**: Use `--strategy` flag
  - `majority` - most common answer wins (default)
  - `risk_averse` - weight conservative responses higher
  - `security_first` - prioritize security considerations
  - `cost_capped` - prefer simpler solutions
  - `compare_only` - no recommendation, just comparison

- **Confidence Intervals**: Statistical confidence ranges
  - Shows "8 ± 1.2" instead of just "8"
  - New functions: `calculate_confidence_stddev()`, `calculate_confidence_interval()`, `format_confidence_range()`
  - High variance detection with `has_high_confidence_variance()`

- **Anonymous Peer Review**: Unbiased evaluation (`scripts/peer_review.sh`)
  - Anonymizes all responses before review
  - Each consultant ranks others without knowing source
  - Aggregates peer scores to identify strongest arguments
  - De-anonymizes in final report with peer scores

#### Local Model Support
- **Ollama Integration**: Run consultations 100% locally
  - New script: `scripts/query_ollama.sh`
  - Configuration: `ENABLE_OLLAMA`, `OLLAMA_MODEL`, `OLLAMA_HOST`
  - Default model: llama3.2
  - Zero API cost, full privacy
  - Use with `--preset local`

#### Reliability Features
- **Panic Button Mode**: Automatic rigor when uncertainty detected
  - Triggers on low average confidence (< 5)
  - Triggers on uncertainty keywords ("maybe", "not sure", "unclear")
  - Automatically adds debate rounds
  - Configuration: `ENABLE_PANIC_MODE`, `PANIC_CONFIDENCE_THRESHOLD`

- **Judge Step**: Overconfidence detection in self-reflection
  - New functions: `judge_response()`, `judge_all_responses()`
  - Heuristic fallback: `heuristic_overconfidence_check()`
  - Flags responses where confidence exceeds evidence quality

#### Installation
- **One-liner Install**: `curl -fsSL https://...install.sh | bash`
- **Install script improvements**:
  - `--update` flag to update existing installation
  - `--uninstall` flag to remove completely
  - `--branch` flag to install from specific branch
  - `--no-commands` to skip slash command installation

#### New Scripts
- `scripts/doctor.sh` - Diagnostic and auto-fix tool
- `scripts/peer_review.sh` - Anonymous peer review system
- `scripts/query_ollama.sh` - Ollama local model wrapper

### Changed
- `scripts/config.sh` - Added presets, Ollama config, panic mode settings
- `scripts/consult_all.sh` - Added `--preset`, `--strategy`, `--help` flags
- `scripts/synthesize.sh` - Multiple synthesis strategies
- `scripts/lib/voting.sh` - Confidence intervals
- `scripts/lib/common.sh` - Panic mode detection functions
- `scripts/lib/reflection.sh` - Judge step functions
- `scripts/install.sh` - One-liner support and new flags

### Improved
- Helper functions to reduce code duplication
- Simplified strategy instructions (single-line format)
- Compact consultant selection loop
- Better error messages and diagnostics

## [2.1.0] - 2026-01-15

### Added
- **New CLI consultant**: Aider (The Pair Programmer)
- **New API consultant**: DeepSeek (The Code Specialist)
- Added 2 new personas (17 total)
- Token optimization with AST-based extraction (~60% savings)

### Changed
- Simplified `consult_all.sh` with convention-based script discovery
- Updated routing affinities for all 10 consultants
- Improved token usage with semantic chunking

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
