# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For longer-form release notes (rationale, upgrade guides, performance numbers), see `docs/releases/v<VERSION>.md`.

## [2.15.1] - 2026-06-22

### Fixed
- **Gemini responses are no longer degraded.** The default model (`Gemini 3.1 Pro (High)`) returns its JSON wrapped in a ```` ```json ```` markdown fence, which v2.15.0 failed to parse — every Gemini reply collapsed to a generic "Unstructured response" with confidence 5 and empty pros/cons. Responses are now de-fenced and parsed correctly (bare-JSON models like Flash are unaffected). The fix covers all paths that consume Gemini output: the main response processor, self-reflection/refinement, and synthesis.
- **Synthesis no longer hangs when Gemini (agy) is the synthesizer.** The agy CLI was invoked without its non-interactive flag, so it launched an interactive session instead of reading the prompt; it now runs in print mode like the other synthesizers.
- **Gemini now works out-of-the-box for `npx` users.** The Gemini consultant defaulted to the agy (Antigravity) CLI, which can't be installed via npm and needs interactive OAuth — so fresh `npx ai-consultants` runs silently dropped Gemini even when `GEMINI_API_KEY` was set. The transport is now auto-resolved: with `GEMINI_USE_API` unset, API mode is selected when a `GEMINI_API_KEY` is present, CLI mode otherwise. An explicit `GEMINI_USE_API=true/false` is still honored.
- `doctor` no longer reports a missing agy CLI as a failure when Gemini runs in API mode, and now suggests setting `GEMINI_API_KEY` (no CLI install needed) when agy is missing in CLI mode.

### Changed
- Just export `GEMINI_API_KEY` to use Gemini over the API — no need to also set `GEMINI_USE_API=true`.

## [2.15.0] - 2026-06-19

### Changed
- **Gemini consultant now runs on the Antigravity CLI (`agy`)** instead of the deprecated Gemini CLI. Google retired the Gemini CLI for individual/Pro/Ultra users on 2026-06-18. The consultant is still called "Gemini" (The Architect) — only the underlying CLI changed. Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`, then run `agy` once to sign in (OAuth).
- Default Gemini models are now agy display names: premium `Gemini 3.1 Pro (High)`, standard `Gemini 3.5 Flash (High)`, economy `Gemini 3.5 Flash (Low)`. Override with `GEMINI_MODEL`.
- API mode (`GEMINI_USE_API=true`) is unchanged but now reads its model ID from the new `GEMINI_API_MODEL` (default `gemini-3.1-pro-preview`), keeping it independent of the CLI display name.
- `cost_rates.json` / `COST_RATES.md` updated with the new Gemini model names (old API IDs retained for API mode and historical lookups).

### Migration
- Install `agy` and sign in once (`agy`). No config changes needed if you use defaults. To pin a model, set `GEMINI_MODEL="Gemini 3.1 Pro (High)"` (see `agy models` for options). Enterprise users who still have the Gemini CLI can keep it by setting `GEMINI_CMD=gemini` and `GEMINI_MODEL=<api-id>`.

### Not included
- Running ai-consultants *from* Gemini CLI as a slash-command host is affected by the same deprecation but is **not** migrated in this release — only the Gemini consultant (the model being queried) was changed.

## [2.14.2] - 2026-05-29

### Changed
- Claude premium tier upgraded from `claude-opus-4-7` to `claude-opus-4-8` (Opus 4.8 release). The default `CLAUDE_MODEL` and the `max_quality`/`premium` tier now resolve to `claude-opus-4-8`. Standard (`claude-sonnet-4-6`) and economy (`claude-haiku-4-5`) tiers unchanged.
- `docs/cost_rates.json`: added a `claude-opus-4-8` entry; repointed Claude premium fallback + tier to it; moved `claude-opus-4-7` to the legacy block for historical cost lookups.

### Fixed
- **Cost reporting was ~1000× too high for premium/standard models.** `lib/costs.sh` treats every rate in `cost_rates.json` as USD **per-1K tokens**, but the premium/standard blocks held **per-MTok** figures (e.g. `claude-opus-4-7: 5.00`, `gpt-5.5: 3.00`), so a ~1k-token Opus query was reported as **$30** instead of **$0.03**. Normalized the entire catalog (premium/standard/legacy/`default_rate`) to per-1K; economy entries (incl. `claude-haiku-4-5`) were already correct and unchanged. Added a `_comment_units` note + a regression test to prevent recurrence. **If you tuned `MAX_SESSION_COST` or cost-aware-routing thresholds against the old inflated numbers, revisit them.**
- `docs/COST_RATES.md`: Claude rows synced to the corrected per-1K values and relabeled to `claude-opus-4-8` (non-Claude rows may still lag; `cost_rates.json` is the source of truth).
- Stale short-alias defaults replaced with canonical IDs: `opus-4.6` in `scripts/query_claude.sh`, `.env.example`, `references/configuration.md`, and the README "Models by Tier" table → `claude-opus-4-8`; `sonnet-4.6` fallback in `lib/api.sh::build_anthropic_request` → `claude-sonnet-4-6`.

## [2.14.1] - 2026-05-13

### Added
- **Pre-commit hook** (`scripts/hooks/pre-commit`) runs `shellcheck` on staged `.sh` files under `scripts/` using the exact CI invocation (`-S warning -x -e SC1091,SC1090,SC2034,SC2155`). Install once per checkout via `npm run install-hooks` (or `bash scripts/install-hooks.sh`). No-ops gracefully when `shellcheck` isn't installed or no `.sh` files are staged. Bypass with `git commit --no-verify`.
- `scripts/install-hooks.sh` installer: idempotent, backs up any pre-existing hook to `.git/hooks/pre-commit.backup.<timestamp>` (or `FORCE=1` to skip backup). Silent no-op outside a git checkout (safe for npm tarball consumption).
- `package.json` scripts: `npm run install-hooks` and `npm run lint` (full-repo shellcheck for ad-hoc verification).

### Fixed
- CI fail in v2.14.0 due to shellcheck SC2164 in `scripts/test_context_optimization.sh:18` (`cd "$PROJECT_ROOT"` without `|| exit`). Fixed pre-release in the same v2.14.0 cycle; the pre-commit hook prevents this class of issue locally going forward.

## [2.14.0] - 2026-05-13

### Added
- **Context handoff: AST optimization now engages on the slash-command path** — slash commands now pass file paths as positional args instead of inlining contents, letting `build_context.sh` run the previously-dead `lib/code_optimizer.sh` + `lib/chunking.sh` + `lib/symbol_map.sh` pipeline
- **File relevance tags**: `path/to/file@PRIMARY` (focus) vs `path/to/file@CONTEXT` (ambient). Default `PRIMARY` when omitted; unknown tags fall back to `PRIMARY` with a `log_warn`
- **Category-aware project tree**: `build_context.sh` reads `QUESTION_CATEGORY` (already exported by `consult_all.sh`) and skips the 100-file project listing for `SECURITY`, `QUICK_SYNTAX`, `ALGORITHM`, `BUG_DEBUG`, `DATABASE`, `TESTING`
- **`FORCE_PROJECT_TREE=true`** env var to bypass the category filter
- **`--query-file <path>`** flag on `consult_all.sh` for queries exceeding shell `ARG_MAX` (~256KB) or containing awkward quoting; conflicts with positional question
- **First test coverage** for `lib/code_optimizer.sh` and `lib/chunking.sh` via new `scripts/test_context_optimization.sh` (17 assertions, 14 tests)
- **Test fixtures**: `scripts/test_fixtures/context/{sample.py,sample.sh,sample.json,sample.txt}`
- **Documentation**: `docs/releases/v2.14.0.md` release note; `references/configuration.md` § Context Handoff section; `references/details.md` bash usage examples

### Changed
- Slash commands `.{claude,codex,gemini}/commands/ai-consultants:{consult,debate}.md` rewritten: file detection delegated to agent reasoning (replaces hardcoded extension regex that missed `Makefile`/`Dockerfile`/dotfiles and false-matched URLs)
- `.claude/commands/ai-consultants:consult.md` adds Claude-only note: don't pass `Read` tool output (`N\t` line-number prefix) — `build_context.sh` reads files itself
- `build_context.sh` help text documents `QUESTION_CATEGORY`, `FORCE_PROJECT_TREE`, and `@TAG` syntax
- `consult_all.sh --help` documents `--query-file` and `@TAG` examples
- Total test assertions: 510 across 7 suites (was 493/6)

### Known issues (documented, not introduced)
- `_supports_ast_extraction` declares 13 languages but `lib/code_optimizer.sh` has dedicated extractors for only 4 (Python, JS/TS, Bash, Go); the other 9 fall back to a `grep`-based generic extractor

## [2.13.1] - 2026-05-04

### Changed
- **Perf**: XDG roots resolved once at first `config.sh` source and exported as `_AI_CONSULTANTS_XDG_{CACHE,STATE,DATA}` — eliminates ~84 forks per consultation (~200-400ms on macOS)
- **Perf**: `apply_launch_stagger()` switched from `awk` to pure-bash `printf` — 14 forks eliminated (~50-70ms)
- **Perf**: `_count_available_consultants` entries pre-uppercased — 15 `to_upper` subshells eliminated per `--suggest-preset`
- **DRY**: extracted `scripts/lib/test_helpers.sh` (~80 LOC): `assert_eq`, `assert_match`, `run_test`, `test_summary`, `_reset_state`
- **CI**: `scripts/test_all.sh` now includes `test_suite.sh` (258 library assertions). Total: 6 suites, ~493 assertions
- **Style**: 37 → 0 shellcheck warnings under project exclusions

### Fixed
- **Latent**: 5 `lib/*.sh` files had hardcoded `/tmp/...` defaults that drifted from v2.13 XDG migration; now reference `${_AI_CONSULTANTS_XDG_*}`
- **Latent**: `lib/session.sh::cleanup_old_sessions` no longer hardcodes `/tmp/ai_consultations` — uses `$DEFAULT_OUTPUT_DIR_BASE`

## [2.13.0] - 2026-05-04

### Added
- **`doctor --suggest-preset --question "..."`** recommends a preset + strategy combo for a question, based on category classification and available consultant count
- **`--json`** output mode for `--suggest-preset` (schema_version: 1, recommended_command field)
- **`scripts/test_all.sh`** master runner aggregates all standalone test suites
- **`scripts/test_doctor.sh`** with 31 assertions covering `--suggest-preset` paths
- **`lib/user_config.sh::get_xdg_dir()`** helper as single source of truth for XDG resolution

### Changed
- **XDG Base Directory compliance** per freedesktop.org spec:
  - `DEFAULT_OUTPUT_DIR_BASE`: `/tmp/ai_consultations` → `$XDG_CACHE_HOME/ai-consultants/consultations`
  - `CACHE_DIR`, `RATE_LIMIT_DIR`, `CHUNK_TEMP_DIR` → `$XDG_CACHE_HOME/ai-consultants/{cache,ratelimit,chunks}`
  - `SESSION_DIR` → `$XDG_STATE_HOME/ai-consultants/sessions`
  - `COST_TRACKING_FILE` → `$XDG_DATA_HOME/ai-consultants/costs.json`
- **`ENABLE_DEBATE_OPTIMIZATION`** promoted from opt-in to default `true` (debate auto-skipped when confidence spread is low; SECURITY/ARCHITECTURE remain mandatory)
- README slimmed: env-var section now points to `references/configuration.md`
- Classifier failures surface explicitly as `Warning: classification of your question failed` instead of silent degradation to `GENERAL`

### Fixed
- `_count_available_consultants()` self-exclusion was dead code due to UPPERCASE vs MixedCase mismatch — now uppercases entry names; `INVOKING_AGENT` correctly drops 1
- `_count_available_consultants()` now respects `ENABLE_*` flags
- `--suggest-preset` short-circuits with install hint when fewer than 2 consultants are usable
- `config.sh` hard-fails with `FATAL` if `lib/user_config.sh` is missing (was silently regressing to `/tmp/...`)

## [2.12.0] - 2026-05-04

### Added
- **Persistent user-config dir** at `~/.config/ai-consultants/` (XDG-compliant; honors `AI_CONSULTANTS_CONFIG_DIR` and `XDG_CONFIG_HOME`)
- **`lib/user_config.sh::load_user_config()`** sourced from `config.sh` before any defaults; idempotent via `_AI_CONSULTANTS_USER_CONFIG_LOADED` guard
- **`ai-consultants init [--force]`** subcommand scaffolds `.env` (chmod 600) and `config.sh` template
- **`.env` parser** supports `KEY=value`, `export KEY=value`, comments, indented lines, quoted values
- `lib/routing.sh::_load_affinity_data` searches `~/.config/ai-consultants/affinity.json` as well as bundled default
- `doctor.sh::check_user_config()` reports dir presence, files loaded, and warns on lax `.env` permissions
- `scripts/test_user_config.sh` (20 assertions, 11 tests) and `scripts/test_bin.sh` (10 assertions, 8 tests)

### Fixed
- `.env` parser **strips trailing CR** so Windows CR-LF line endings don't corrupt values
- `bin/ai-consultants` no longer hardcodes version (was stuck at 2.10.0); reads from `config.sh` and validates as semver; falls back to `vunknown` on parse failure
- `get_user_config_dir` returns empty + exit 1 when both `HOME` and `XDG_CONFIG_HOME` are unset (distroless containers)
- `init` refuses to scaffold into symlinked dirs (security: prevents hostile symlink follow)

## [2.11.0] - 2026-05-03

### Changed
- **Externalized routing affinity matrix** from nested `case` statements in `lib/routing.sh` to `references/affinity.json` (~190 lines bash → 60 lines JSON)
- Custom matrix via `AFFINITY_FILE=/path/to/custom.json`
- `get_affinity()` uses two-level cache: file content cached on first read, per-(category, consultant) result cached after first lookup
- `docs/SMART_ROUTING.md` rewritten: removed stale per-consultant table; documents JSON schema + override

### Added
- `doctor.sh` adds 3 new checks: affinity file presence, JSON schema validity, coverage
- `scripts/test_routing_parity.sh` golden parity test (144 assertions: 9 categories × 14 consultants + edge cases)
- `scripts/test_set_e_safety.sh` static + dynamic lint for `((var++))` and `let var++` abort patterns

### Fixed
- Cache key uses leading-space delimiter to prevent substring collisions (e.g. `DEBUG|X=` would have falsely matched a cached `BUG_DEBUG|X=10`)
- `consult_all.sh` ENABLE_PREFLIGHT path no longer swallows doctor output — diagnostic captured to tmpfile and dumped on failure
- Cleaned `((attempt++)) || true || true` artifacts in `lib/api.sh`

## [2.10.9] - 2026-05-03

### Fixed
- **CRITICAL**: silent failure of `preflight_check.sh` under `set -euo pipefail` — helper functions returned non-zero on missing CLIs without `|| true`, script aborted after "Checking CLI installations..." with no diagnostic
- Defensive sweep: 15 latent `((var++))` increments across `peer_review.sh`, `setup_wizard.sh`, `lib/api.sh`, `lib/common.sh`, `lib/reflection.sh`, `doctor.sh` protected with `|| true`
- SC2059 unsafe printf format string in `lib/progress.sh`
- SC2012 `ls | wc -l` race in `install.sh` (replaced with `find`)

### Deprecated
- `preflight_check.sh` deprecated in favor of `doctor.sh` (stale v2.0 script covering only 6/15 consultants); now a thin wrapper that prints a warning and execs `doctor.sh`

### Changed
- Ported `--suggest-config` from `preflight_check.sh` to `doctor.sh`; coverage expanded from 6 to 15 consultants (now also detects API-only consultants via API key presence)
- `doctor.sh` accepts `--quick` flag as no-op for backward compat

## [2.10.8] - 2026-05-03

### Fixed
- `docs/cost_rates.json` drift introduced by v2.10.6: `consultant_fallbacks` (used at runtime by `lib/costs.sh`) and `model_tiers` were still pointing at old IDs (`opus-4.6`, `gpt-5.3-codex`, `composer-1.5`, `deepseek-reasoner`, `sonnet-4.6`, `haiku-4.5`)

### Added
- Price entries for v2.10.6 model IDs: `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5`, `gpt-5.5`, `composer-2`, `deepseek-v4-pro`, `nvidia/nemotron-3-super-120b-a12b:free`
- Moved superseded IDs to legacy section in cost catalog

### Changed
- Synced `COST_RATES.md` tables to match
- Pricing for `nvidia/nemotron-3-super-120b-a12b:free` set to $0/$0 (OpenRouter free tier)

## [2.10.7] - 2026-05-02

### Changed
- **Grok premium upgraded** from `grok-4.20-0309-reasoning` to `grok-4.3` (released 2026-04-30)
- ~75% cheaper input ($1.25/M vs $5.00/M), ~83% cheaper output ($2.50/M vs $15.00/M)
- 1M-token context window
- Moved `grok-4.20-0309-reasoning` to legacy section
- Standard (`grok-3`) and economy (`grok-3-mini`) tiers unchanged

## [2.10.6] - 2026-05-02

### Changed
- **Codex premium** upgraded from `gpt-5.3-codex` to `gpt-5.5`
- **Cursor premium** upgraded from `composer-1.5` to `composer-2`
- **DeepSeek premium** upgraded from `deepseek-reasoner` to `deepseek-v4-pro`
- **Aider** switched provider: `gpt-5.3-codex` → `nvidia/nemotron-3-super-120b-a12b:free` (free tier)
- **Claude model IDs** migrated from short aliases to canonical: `opus-4.6` → `claude-opus-4-7`, `sonnet-4.6` → `claude-sonnet-4-6`, `haiku-4.5` → `claude-haiku-4-5`

### Fixed
- Kilo SIGPIPE abort under `set -euo pipefail` (replaced `head -c` with parameter expansion)

## [2.10.5] - 2026-04-16

### Changed
- **Qwen3 premium** upgraded from `qwen3.5-plus` to `qwen3.6-plus` ($0.325/$1.95 per M tokens)
- **Qwen3 standard** tier now uses open-weight `qwen3.6-35b-a3b` (MoE, 35B total / 3B active)
- Refactored `get_economic_model()` to delegate to `get_model_for_tier()`, eliminating stale hardcoded mappings
- Moved `qwen3.5-plus` to legacy section in cost catalog

### Fixed
- `AI_CONSULTANTS_VERSION` in `config.sh` (was stuck at `2.10.0`)

## [2.10.4] - 2026-04-10

### Changed
- **GLM premium/standard** upgraded from `glm-5` to `glm-5.1`
- Collapsed 5-stage ANSI stripping pipeline into single sed invocation in `query_kilo.sh`
- Updated `.env.example` GLM signup URL to `open.z.ai`

### Fixed
- Kilo CLI hanging indefinitely in non-TTY mode (query via stdin instead of CLI argument)
- Kilo CLI picking wrong provider when other consultants' API keys were in the environment
- Overly aggressive markdown fence filter in `query_kilo.sh` (only strips standalone ``` lines now)

## [2.10.3] - 2026-03-21

### Changed
- **Grok premium** upgraded to `grok-4.20-0309-reasoning` (replaces `grok-4-1-fast-reasoning`)
- **GLM API endpoint** migrated from `open.bigmodel.cn` to `api.z.ai/api/coding/paas/v4`

### Removed
- Non-functional MiniMax highspeed models (`MiniMax-M2.7-highspeed`, `MiniMax-M2.5-highspeed`)
- Legacy `grok-beta` from cost catalog

### Fixed
- GLM URL fallback in `common.sh` and `configure.sh` (were still using old endpoint)
- Duplicate `minimax-m2.5` entry with conflicting rates in `cost_rates.json`

## [2.10.2] - 2026-03-19

### Changed
- **MiniMax M2.7 upgrade**: premium/standard now use `MiniMax-M2.7`, economy uses `MiniMax-M2.5`

## [2.10.1] - 2026-03-15

### Changed
- Slash command quality improvements: file context handling, result presentation templates, error recovery guidance
- `debate_round.sh` hardening: Amp/Kimi/MiniMax case entries, `((count++)) || true` fixes, `*` default case, stderr to `.err` files, ROUND_NUMBER validation
- Token efficiency: SKILL.md trimmed (-17%), `help.md` slimmed (-77%), content moved to `references/details.md`
- Self-exclusion consistency in slash command descriptions

## [2.10.0] - 2026-03-04

### Added
- **MiniMax M2.5 API support** via OpenAI-compatible endpoint
- **New consultant**: MiniMax with "The Pragmatic Optimizer" persona (ID: 21)
- **npx distribution**: `npx ai-consultants "question"` (zero dependencies)
- New `bin/ai-consultants` wrapper with symlink resolution and subcommand routing (`doctor`, `install`, `version`, `help`)
- New environment variables: `ENABLE_MINIMAX`, `MINIMAX_API_KEY`, `MINIMAX_MODEL`, `MINIMAX_API_URL`
- Model tiers: premium (`MiniMax-M2.5`), standard (`MiniMax-M2.1`), economy (`MiniMax-M2.5`)

### Changed
- Consultant count: 14 → 15
- npm package metadata updated (zero runtime dependencies preserved)

## [2.9.1] - 2026-02-05

### Fixed
- **Gemini model names**: Updated to real API model names
  - Premium: `gemini-3.1-pro-preview` (was fictional `gemini-3.0-pro`)
  - Standard: `gemini-3-flash-preview` (was fictional `gemini-3.0-flash`)
  - Economy: `gemini-2.0-flash` (was fictional `gemini-2.0-flash-lite`)

## [2.9.0] - 2026-02-05

### Added
- **Kimi CLI Consultant**: New "The Eastern Sage" consultant via Kimi CLI (MoonshotAI)
  - New script: `scripts/query_kimi.sh`
  - Persona ID 20: Focus on holistic understanding, balance of perspectives, wisdom from diverse viewpoints
  - CLI command: `kimi --quiet --input-format text` for non-interactive execution
  - Installation: `curl -L code.kimi.com/install.sh | bash`
  - Configuration: `ENABLE_KIMI`, `KIMI_MODEL`, `KIMI_TIMEOUT`, `KIMI_CMD`
  - Default model: `kimi-code/kimi-for-coding`

### Changed
- Updated `scripts/config.sh` with Kimi configuration
- Updated `scripts/lib/personas.sh` with PERSONA_KIMI (ID 20)
- Updated `scripts/lib/common.sh` with KIMI in known CLI agents and self-exclusion
- Updated `scripts/lib/routing.sh` with Kimi affinity scores (also added missing Amp/Claude)
- Updated `scripts/doctor.sh` with Kimi CLI checks
- Reordered `_consultant_map` in consult_all.sh to match `ALL_CONSULTANTS` order
- Consultant count: 13 → 14

## [2.8.1] - 2026-01-30

### Fixed
- **CRITICAL**: `((count++))` abort under `set -e` in consult_all.sh (SUCCESS_COUNT, ESCALATED_COUNT) and routing.sh
- **HIGH**: Missing integer validation for jq confidence values in escalation
- **HIGH**: Amp missing from `_consultant_map` in consult_all.sh
- Hardcoded `"claude"` in synthesize.sh now uses `$CLAUDE_CMD`

### Security
- Variable name validation before `export` in escalation and cost-aware routing blocks

### Changed
- Rewrote `query_kilo.sh` using `process_consultant_response()` (224 to 94 lines)
- Rewrote `query_cursor.sh` using `process_consultant_response()` (165 to 72 lines)
- Added `get_model_for_tier()` as single source of truth for model tier mappings (config.sh)
- Simplified `apply_model_tier()` to iterate via `get_model_for_tier()`
- Simplified `get_premium_model()` to delegate to `get_model_for_tier()`
- Removed hardcoded version numbers from script headers (source of truth: `config.sh:AI_CONSULTANTS_VERSION`)

## [2.8.0] - 2026-01-21

### Added
- **Amp CLI Consultant**: New "The Systems Thinker" consultant via Amp CLI
  - New script: `scripts/query_amp.sh`
  - Persona ID 19: Focus on system design, component interactions, emergent behaviors
  - CLI command: `amp -x` for non-interactive execution
  - Installation: `curl -fsSL https://ampcode.com/install.sh | bash`
  - Configuration: `ENABLE_AMP`, `AMP_MODEL`, `AMP_TIMEOUT`, `AMP_CMD`

### Changed
- Updated `scripts/config.sh` with Amp configuration
- Updated `scripts/lib/personas.sh` with PERSONA_AMP (ID 19)
- Updated `scripts/lib/common.sh` with AMP in known CLI agents
- Updated `scripts/doctor.sh` with Amp CLI checks
- Consultant count: 12 → 13

## [2.7.0] - 2026-01-21

### Added
- **Qwen CLI Support**: CLI/API mode switching for Qwen3 consultant
  - New environment variable: `QWEN3_USE_API` (default: true for backward compatibility)
  - CLI mode uses `qwen-code` via `qwen -p -` command
  - Installation: `npm install -g @qwen-code/qwen-code@latest`
  - Configuration: `QWEN3_CMD` for custom command path

### Changed
- Rewrote `scripts/query_qwen3.sh` with CLI/API mode branching
- Moved Qwen3 from `API_CONSULTANTS` to `CLI_CONSULTANTS` array
- Updated `scripts/lib/common.sh` with Qwen3 in `KNOWN_CLI_AGENTS`
- Updated `scripts/doctor.sh` with Qwen3 CLI mode checks

## [2.6.0] - 2026-01-20

### Added
- **CLI/API Mode Switching**: Four consultants can switch between CLI and API mode
  - Gemini: `GEMINI_USE_API` (CLI: `gemini`, API: Google AI)
  - Codex: `CODEX_USE_API` (CLI: `codex`, API: OpenAI)
  - Claude: `CLAUDE_USE_API` (CLI: `claude`, API: Anthropic)
  - Mistral: `MISTRAL_USE_API` (CLI: `vibe`, API: Mistral)

- **New API Mode Library**: `scripts/lib/api_query.sh`
  - Unified API query execution for all formats
  - Request builders: OpenAI, Anthropic, Google AI
  - Response parsers: All API formats

- **API Configuration**: New environment variables
  - `*_USE_API` - Enable API mode (default: false)
  - `*_API_URL` - Custom API endpoints
  - `*_API_KEY` - API keys for authentication

### Changed
- Rewrote `scripts/query_gemini.sh` with CLI/API branching
- Rewrote `scripts/query_codex.sh` with CLI/API branching
- Rewrote `scripts/query_claude.sh` with CLI/API branching
- Rewrote `scripts/query_mistral.sh` with CLI/API branching
- Updated `scripts/lib/common.sh` with mode checking functions
- Updated `scripts/doctor.sh` with CLI/API mode diagnostics

## [2.5.0] - 2026-01-19

### Added
- **Model Quality Tiers**: Three tiers for model selection
  - `premium` - Latest flagship models (default)
  - `standard` - Good quality at reasonable cost
  - `economy` - Optimized for speed and low cost

- **Quality Tier Presets**: New presets using model tiers
  - `max_quality` - All + premium models + debate
  - `medium` - 4 consultants + standard models
  - `fast` - 2 consultants + economy models

- **New function**: `apply_model_tier()` for programmatic tier selection

### Changed
- **Premium Model Defaults** (January 2026):
  - Claude: `claude-opus-4-5-20251124`
  - Gemini: `gemini-3.1-pro-preview`
  - Codex: `gpt-5.2-codex`
  - Mistral: `mistral-large-3`
  - DeepSeek: `deepseek-reasoner`
  - GLM: `glm-4.7`
  - Grok: `grok-4.20-0309-reasoning`
  - Qwen3: `qwen3-max`
  - Aider: `gpt-5.2-codex`
  - Ollama: `qwen2.5-coder:32b`

- Updated `docs/cost_rates.json` with tier-based model rates

## [2.4.0] - 2026-01-18

### Added
- **Budget Enforcement** (opt-in): Configurable cost limits
  - New environment variable: `ENABLE_BUDGET_LIMIT` (default: false)
  - `BUDGET_ACTION` - Action on budget exceeded: `warn` or `stop`
  - Budget checks at 4 enforcement points:
    1. Before Round 1 - Check estimated cost
    2. After Round 1 - Check actual cost vs warning threshold
    3. Before Debate - Check cumulative + debate estimate
    4. Before Synthesis - Check cumulative + synthesis estimate

- **New functions in `lib/costs.sh`**:
  - `is_budget_enabled()` - Check if budget enforcement is enabled
  - `enforce_budget()` - Check budget and take action
  - `get_remaining_budget()` - Get remaining budget
  - `format_budget_status()` - Format budget status for display
  - `estimate_phase_cost()` - Estimate cost for a specific phase

- **New slash command**: `/ai-consultants:config-budget`

### Changed
- Updated `scripts/doctor.sh` to display budget status
- Updated `scripts/consult_all.sh` with budget enforcement points

## [2.3.0] - 2026-01-17

### Added

#### Token Cost Optimization
- **Semantic Caching**: Cache responses based on query + context fingerprints
  - New library: `scripts/lib/cache.sh`
  - Functions: `generate_fingerprint()`, `check_cache()`, `store_cache()`, `cleanup_cache()`
  - Configuration: `ENABLE_SEMANTIC_CACHE`, `CACHE_TTL_HOURS`, `CACHE_DIR`
  - Estimated savings: 15-25% on repeated/similar queries

- **Response Length Limits**: Limit output tokens by question category
  - Functions: `get_max_response_tokens()`, `is_response_limits_enabled()`
  - Configuration: `ENABLE_RESPONSE_LIMITS` (default: false, opt-in)
  - Per-category limits: `MAX_RESPONSE_TOKENS_BY_CATEGORY`
  - Estimated savings: 15-25% on output tokens

- **Cost-Aware Routing**: Route simple queries to cheaper models
  - Functions: `select_consultants_cost_aware()`, `get_cost_aware_model()`, `calculate_query_complexity()`
  - Configuration: `ENABLE_COST_AWARE_ROUTING`, `COMPLEXITY_THRESHOLD_SIMPLE`, `COMPLEXITY_THRESHOLD_MEDIUM`
  - Model tier functions: `get_economic_model()`, `get_model_tier()`
  - Estimated savings: 30-50% on simple queries

- **Fallback Escalation**: Re-query with premium model if confidence too low
  - Functions: `needs_escalation()`, `get_premium_model()`, `get_escalation_summary()`
  - Configuration: `FALLBACK_CONFIDENCE_THRESHOLD` (default: 7)
  - Prevents low-quality responses from economic models

- **Debate Optimization**: Skip debate if confidence spread is low
  - Functions: `should_skip_debate()`, `is_mandatory_debate_category()`, `extract_compact_summary()`
  - Configuration: `ENABLE_DEBATE_OPTIMIZATION` (default: false, opt-in)
  - `DEBATE_CONFIDENCE_SPREAD_THRESHOLD` (default: 2)
  - Category exceptions: SECURITY and ARCHITECTURE always trigger debate
  - Estimated savings: 40-60% on debate tokens

- **Quality Monitoring**: Track optimization metrics
  - New output file: `optimization_metrics.json`
  - Logs: cache hits, consensus score, optimization settings
  - Debug mode: `LOG_LEVEL=DEBUG` shows detailed metrics

- **Compact Reports**: Shorter reports by default
  - Configuration: `ENABLE_COMPACT_REPORT` (default: true)
  - `REPORT_MAX_JSON_LINES` for truncation control

### Changed
- `scripts/config.sh` - Added v2.3 token optimization settings, version 2.3.0
- `scripts/lib/costs.sh` - Added response limits and complexity scoring
- `scripts/lib/routing.sh` - Added cost-aware routing, fallback escalation, `_ensure_costs_sourced()` helper
- `scripts/debate_round.sh` - Added debate optimization, category exceptions
- `scripts/consult_all.sh` - Integrated cache, quality monitoring with `jq` for JSON generation

### Improved
- Extracted `_ensure_costs_sourced()` helper to reduce code duplication
- Replaced echo-based JSON with `jq -n` for cleaner generation
- Conservative defaults for risky optimizations (opt-in)

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
