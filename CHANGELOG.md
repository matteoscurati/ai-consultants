# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For longer-form release notes (rationale, upgrade guides, performance numbers), see `docs/releases/v<VERSION>.md`.

## [3.0.0] - 2026-07-23

A held-out experiment settled a question two independent reviews had raised: does the panel beat a single strong model? The answer is **task-dependent**. On convergent defect-finding a single strong model saturates (it caught 19/19 hard bugs, including CVEs and a concurrency bug found by formal verification), so the panel adds nothing. On **breadth** questions — "what could go wrong with this design?", enumerate the risks — a diverse cross-vendor panel covers materially more than one model (measured rubric coverage: one model 51%, self-consistency 70%, the panel **93%**), and it wins as a raw **union of distinct answers**, not through deliberation. So this release keeps the diverse fan-out and cuts the machinery that averaged it away.

### Changed
- **The default output is now the coverage union, not a voted recommendation.** `DEFAULT_STRATEGY` defaults to the new `coverage` strategy: the deduplicated union of every distinct point, recommendation, risk, and edge case raised across the panel, preserving what only one model raised. `compare_only` (side-by-side), `majority` (a single blended recommendation), `risk_averse`, `security_first`, and `cost_capped` remain available via `--strategy`.
- **The pipeline is now classify → route → parallel fan-out → coverage synthesis.** No deliberation rounds, no consensus scoring.
- **Presets choose only the consultant set and model tier** — they no longer enable debate or peer review.

### Removed (breaking)
- **Multi-round debate and dynamic orchestration** — `ENABLE_DEBATE`, `DEBATE_ROUNDS`, `ORCHESTRATION_MODE`, `CONVERGENCE_*`, `ENABLE_DEBATE_OPTIMIZATION`, the orchestration shapes (quick/converge/adversarial/tournament/exhaustive), and the `debate` slash command.
- **Voting and consensus scoring** — the voted recommendation, the 1–10 final score, consensus %/level, and the `voting.json` output.
- **Capability weighting and routing** — `ENABLE_CAPABILITY_WEIGHTING`, `ENABLE_CAPABILITY_ROUTING`, `CAPABILITY_*`, and the capability axes in `affinity.json` (category-affinity routing is unchanged).
- **Panic mode** — `ENABLE_PANIC_MODE`, `PANIC_*`, and `panic_diagnosis.json`.
- **Peer review** — `ENABLE_PEER_REVIEW`, `PEER_REVIEW_MIN_RESPONSES` (it ran after synthesis and could not change the recommendation).
- **Stance consensus** — `ENABLE_STANCE_CONSENSUS`, `STANCE_*`.
- **The capability-calibration tooling** — `roster_audit.sh`, `roster_calibrate.sh`, `run_calibration.sh`, `taste_elo.sh`, `doctor --roster-audit`, and the `roster-audit` slash command (they existed only to feed the removed weighting).
- Setting any removed variable via `configure --set` now fails closed; installers prune the removed slash commands.

### Kept
- The diverse parallel fan-out to all 11 consultants, category-affinity smart routing, `doctor` (including `--live`, `--suggest-preset`, `--suggest-config`), cost tracking and budgets, quorum grading and the opt-in health gate, semantic caching, and every CLI/API adapter.

### Upgrade
- No configuration change is required. If you relied on a debate/consensus setting, remove it — the tool now fans out and returns the coverage union by default. See `docs/releases/v3.0.0.md`.

## [2.25.2] - 2026-07-22

### Fixed
- **`doctor` no longer reports "healthy" from static checks alone.** The default `doctor` confirms a CLI is installed and a key is present — not that a consultant can actually answer. A consultant with an expired key or an exhausted quota passed every static check, yet `doctor` printed "All systems healthy!" and its JSON reported `status: "healthy"`. Measured: static `doctor` called all 11 consultants healthy while only 8 responded to a real query. A static-only run now says so explicitly and points to `doctor --live`; the word "healthy" is reserved for a `--live` run that actually pinged them. The `--json` output gains a `verified: "live"|"static"` field and a `static_ok` status, so tooling can tell a real all-clear from an unverified one. `--live` behavior is unchanged, and a plain `doctor` still makes no billed calls.

## [2.25.1] - 2026-07-21

### Fixed
- **The final score reported 2/10 even when every consultant agreed.** The recommendation was emitted as a key with spaces and punctuation stripped, while scoring compared each consultant's original answer against that stripped version — so nothing ever matched and everyone was counted as a dissenter. Three consultants unanimous at confidence 9 on "Use JWT with rotating sessions" scored 2/10; the same panel on "JWT" scored 10/10. Real answers are multiword, so the headline number was wrong on essentially every consultation. The same stripping also merged genuinely different answers: "Use JWT + sessions" and "Use JWT sessions" became one option.
- **Peer-review artifacts were billed as consultations.** The recursive scan v2.25.0 introduced to catch debate rounds also reached everything peer review writes: anonymized copies keep the original token counts, and bookkeeping files fall back to 1000 tokens each. A run whose real cost was $0.125 reported $0.244. Billing now covers only the responses and debate rounds, and a response is recognised by its structure rather than by its filename.
- **Smart routing queried consultants you had disabled.** `ENABLE_*` and self-exclusion were applied only on the non-smart path, so with `ENABLE_SMART_ROUTING=true` a disabled consultant — or the agent invoking the skill — could still be sent the question and billed for it. Custom API agents were excluded from smart routing entirely; they are now included.
- **Gemini in API mode was costed as the wrong model.** The request used `GEMINI_API_MODEL` while the response recorded `GEMINI_MODEL`, mispricing by 2.24x at the shipped rates.
- **Peer review crashed on the stock macOS shell.** Two bash 4 constructs (an uppercase expansion and a negative array index) ran under `/bin/bash` 3.2, which `doctor` explicitly reports as supported.
- **Consensus reported 100% for panels that disagreed.** Answers were grouped transitively, so A resembling B and B resembling C put A and C in one group even when they had nothing in common. Consensus now requires the members of a group to resemble each other, which also stops a convergence loop from ending early on false agreement.
- **`estimate_tokens ""` could hang.** Given an explicit empty string it read standard input instead of returning zero, so a caller with an open pipe on stdin blocked indefinitely. It now returns zero for an empty argument and reads stdin only when called with no argument at all.

## [2.25.0] - 2026-07-21

### Fixed
- **The reported session cost measured how many pipeline stages ran, not what you spent.** `build_response_metadata` hardcoded `tokens_used: 0` on every response it ever wrote, and `calculate_session_cost` multiplies that field by the model rate — so every real consultant contributed exactly $0.00, in both transports. The figure you saw came entirely from the pipeline's own metadata files (`voting.json`, `orchestration.json`, `optimization_metrics.json`), which carry no token count at all and so fell to a 1000-token fallback at the default rate, roughly $0.009 each. Measured on a realistic three-consultant run: v2.24 reported **$0.0270** — three phantom files, zero real consultations. In API mode the real figure was even being computed and then discarded: `run_api_mode_query` extracted the provider's usage numbers, logged them at debug level, and threw them away. Responses now carry a real count, and a new `metadata.tokens_source` field records where it came from. **If you tuned `MAX_SESSION_COST` against the old always-zero reports, revisit it** — the same direction of advice as v2.14.2, opposite sign.
- **The `*_FORMAT` settings did nothing.** `QWEN3_FORMAT`, `GLM_FORMAT`, `GROK_FORMAT`, `DEEPSEEK_FORMAT` and `MINIMAX_FORMAT` have been declared in `config.sh` and documented in `.env.example` since v2.6, but `get_api_format()` hardcoded the wire format per consultant and never read them. All five are now honored. An unrecognized value falls back to the consultant's default with a warning rather than building a malformed request.
- **Two consultants mislabeled the model they had just used.** `query_qwen3.sh` recorded `qwen3.6-plus` and `query_codex.sh` recorded `gpt-5.3-codex` when their `*_MODEL` variable was empty, neither of which had been the default for several releases. Qwen now records `unknown` in that case, which is the honest answer: with no model passed, the CLI uses its own configured one and the script cannot know which.
- `query_qwen3.sh` in API mode now rejects an empty `QWEN3_MODEL` up front instead of sending `"model": ""` and taking a 400 from the provider.

- **Session costs were wrong in five further ways, each harmless only while the token count was zero.** Pipeline files (`voting.json` and friends) were priced as phantom 1000-token consultants (~2.8x inflation on a small run); a cache hit was billed at full price despite making no API call; debate and peer-review rounds were invisible because they live in subdirectories; an escalated consultant was billed twice; and the provider's real prompt/completion split was collapsed to a total and re-derived 60/40, overstating API-mode cost roughly 2.7x while still labelling it "measured". Responses now record `tokens_input`/`tokens_output` when the provider reports them, and cost is computed on the real split.
- **`QWEN3_REASONING_EFFORT` did nothing on Qwen's default API configuration.** The setting was only read on the OpenAI-compatible wire format, but Qwen defaults to DashScope's own format — so following the documented "API mode only" instruction produced no effect, no warning, and no validation of the value. Effort is now resolved for every consultant and every wire format, and the formats that cannot carry it say so. An invalid value also used to kill the query script outright, leaving an empty file and dropping the consultant from the panel with no explanation; it now produces a proper error response.
- **`roster_calibrate.sh` would have ranked a credit-billed model as the panel's cheapest consultant.** It falls back to a default rate only when a model is absent from the cost catalog; adding `qwen3.8-max-preview` at zero made the lookup succeed and return zero, and the cost axis normalizes "cheapest" to the maximum score. With `--write` that would have been persisted into `references/affinity.json`, preferentially routing questions to a model whose real consumption the calibrator cannot see. Credit-billed models are now excluded from the measured cost axis. **If you ran a calibration with `--write` against a build carrying that entry, re-check the `cost` values in your affinity file.**
- **Setting a reasoning effort in CLI mode only warned for Qwen.** Six consultants accept the setting in API mode; all of them now warn when it cannot be applied.
- **Three test suites could fail depending on your `LOG_LEVEL`.** Assertions that match on warning output are silent at `LOG_LEVEL=ERROR`, so `test_context_optimization.sh`, `test_update_clis.sh` and the new `test_api_transport.sh` failed for anyone running with that level and passed for everyone else. Two of the affected assertions are the v2.17.2 secret-exfiltration guards. All three suites now pin the level themselves.

### Added
- **Opt-in support for Qwen Cloud Token Plan**, including `qwen3.8-max-preview`. Token Plan is a separate subscription with its own OpenAI-compatible endpoint and its own key — it is not served by DashScope — so this is configuration, not a default change. The premium Qwen model remains `qwen3.7-max`. See the new recipe in `docs/RECIPES.md`.
- **`QWEN3_REASONING_EFFORT`** — reasoning depth for API mode, accepting the provider's own enum (`none|minimal|low|medium|high|xhigh|max`). **API mode only**: the `qwen` CLI has no effort flag, so in CLI mode the setting is ignored and says so, rather than looking effective. The valid subset is model-specific and enforced by the provider, not guessed locally.
- **`metadata.tokens_source`** on every response: `measured` (the provider's own figures, API mode), `estimated` (a local 4-chars-per-token approximation, CLI mode, which exposes no counts), or `unknown`.
- Credit-billed models can be declared in `docs/cost_rates.json` under `unpriced_models`. They contribute 0 to the total and the session-cost line names them, instead of an absent catalog entry silently falling through to the default rate — which for `qwen3.8-max-preview` would have been roughly 4x the real Qwen premium input rate, presented as a confident number.

### Changed
- The session-cost line now states what its number is built on, e.g. `Session cost: $0.0550 [token counts estimated for 3 of 3]`. A total resting partly on approximations is not a measurement, and CLI mode — the default transport — can only approximate.
- Budget enforcement projections now include actual accumulated spend. The pre-run checks were always driven by a context-size estimate and worked; the pre-debate and pre-synthesis checks added `CURRENT_COST`, which was always zero.

## [2.24.0] - 2026-07-20

### Fixed
- **Installing or updating now removes slash commands this project no longer ships.** Both entry points only ever copied commands in, so one deleted upstream stayed in `~/.claude/commands` forever. The v2.10.0 command consolidation dropped ten of them, which means every installation predating it still carries all ten — and they remain invocable. One is actively wrong: `ai-consultants:config-features` instructs you to set `ENABLE_REFLECTION`, which v2.23.0 removed and `ai-consultants configure --set` now rejects with a non-zero exit. Both `scripts/install.sh` (the `curl | bash` path) and `ai-consultants install` (the npx path) now prune before copying, and report how many they removed.

### Changed
- **The prune removes any `ai-consultants:*.md` this project does not ship — including one you wrote yourself under that prefix.** There is no way to distinguish a command you authored in this namespace from one of ours that was deleted upstream. If you have custom commands, rename them out of the `ai-consultants:` prefix before upgrading. Commands belonging to other tools are never considered.
- `scripts/release.sh` is no longer included in the npm package. It is maintainer-only version-bump automation, is not routed by `bin/ai-consultants`, and nothing shipped invokes it.

## [2.23.0] - 2026-07-20

### Removed
- **`ENABLE_REFLECTION` and `REFLECTION_CYCLES` are gone, along with `lib/reflection.sh`.** The self-reflection module was never sourced or called by any script, so neither setting had ever affected a consultation. The v2.16 dynamic orchestration engine covers the same ground: its `converge` and `adversarial` shapes run critique-refine driven by measured consensus rather than a fixed cycle count. **Action required if you set either key**: `ai-consultants configure` derives its accepted parameters from `.env.example`, so `--set ENABLE_REFLECTION=...` now exits non-zero instead of being accepted, and both keys are dropped (without warning) the next time an existing user `.env` is rewritten. Remove them from provisioning scripts and `.env` files. No runtime behavior changes — the flags controlled nothing.

### Fixed
- **`KNOWN_FEATURE_FLAGS` no longer enrolls feature flags as phantom consultants.** The registry that `_discover_custom_api_agents` uses to tell feature flags apart from custom API agents had drifted 18 flags out of date, so an `ENABLE_<FLAG>=true` paired with a `<FLAG>_API_URL` in the environment could be added to the panel as a consultant — `ENABLE_PEER_REVIEW` among them. All 27 non-consultant flags are now registered, and a test derives the expected set from `config.sh` so the next added flag fails the build instead of drifting silently.
- **`test_functions.sh` was under-reporting failures.** A test function is scored by its exit status, i.e. that of its last command, so a failing assertion followed by a passing one printed `FAIL` yet counted as a pass and the suite still exited 0. 8 of 13 test functions ran more than one assertion and were exposed. The `assert_*` helpers now flag failures globally and the runner honors that flag, so `npm test` reflects what actually failed.
- **The release gate could not go green.** `scripts/release.sh` sources `lib/common.sh` (and therefore `config.sh`) before running `npm test`, so the exported configuration leaked into two suites and failed them deterministically — meaning no release since 2.22.0 could pass its own gate. `test_user_config.sh` leaked `AI_CONSULTANTS_CONFIG_DIR` between tests and asserted on variable names an ambient environment overrides; `test_configure.sh` scrubbed the nine API keys but not the settings, so an exported `DEFAULT_PRESET` overrode the file its preservation tests assert on. Both suites now derive their isolation from the same contract they test against.
- `test_user_config.sh` no longer fails against a real user configuration. The suite leaked `AI_CONSULTANTS_CONFIG_DIR` between tests and asserted on config variable names that an ambient environment can override, so `npm test` — and therefore the `release.sh` gate, which sources `config.sh` first — failed for anyone who had run `ai-consultants configure`.

### Changed
- Preset documentation now reflects what the presets actually pin. The tier tables no longer claim a fixed debate/peer-review depth per preset: under the default `ORCHESTRATION_MODE=auto` the planner chooses per question, and a `SECURITY` question runs peer review regardless of preset. `max_quality` is described as 8 of 11 consultants rather than "all".

## [2.22.0] - 2026-07-17

### Added
- **`ai-consultants configure`.** The public automatic configurator detects the complete 11-consultant roster, selects CLI/API transports, preserves existing settings and secrets, writes private XDG configuration with backups, and accepts every persistent parameter through repeatable `--set KEY=VALUE` arguments or an exhaustive `--advanced` review.

### Fixed
- The npm package now includes the full `.env.example`, so `init` no longer falls back to a partial five-setting template.
- Gemini API setup now consistently uses the runtime-supported `GEMINI_API_KEY`; `.env` inline comments are parsed correctly, and the starter template no longer pins obsolete `/tmp` storage paths.
- Repeatable `--set` values now participate in transport detection with final precedence, including intentional empty values. Auto-selected transports carry provenance so later runs can adapt when CLIs or credentials change without overriding user-authored pins.
- Existing `export KEY=value` settings survive rewrites, `.env.example` is safely sourceable, and `--dry-run` no longer creates the persistent config directory while redacting credentials.
- The stale v2.0 setup wizard now forwards to the maintained configurator instead of advertising removed consultants and incomplete authentication checks.
- `configure --interactive` no longer exits without saving the moment you press Enter to keep a value.
- `configure --advanced` no longer writes wrong values: each prompt was reading the next parameter's name instead of your answer.
- `init` followed by `configure` no longer disables Codex, Claude, Mistral, and Qwen3 when only an API key is available — the starter template's transport switches are commented out, so auto-detection stays in charge until you deliberately set one. An installed CLI still takes precedence over an API key.
- Configuration backups can no longer overwrite each other when two runs land in the same second.

## [2.21.1] - 2026-07-16

### Changed
- **Kimi now runs on K3.** The default and every quality tier use the `kimi-code/k3` alias. The query adapter now passes `--model "$KIMI_MODEL"` explicitly, so the configured project model is actually used instead of silently inheriting the user's Kimi CLI default.
- **The supported panel is now 11 consultants.** Kilo, Aider, Amp, and Ollama have been removed from the runtime roster, presets, routing, personas, doctor/preflight checks, debate and synthesis paths, CLI updater, configuration surfaces, tests, and current documentation. Their query adapters are no longer shipped in the npm package.

### Removed
- **Kilo** (`kilocode`, `ENABLE_KILO`, `KILO_*`).
- **Aider** (`aider`, `ENABLE_AIDER`, `AIDER_*`).
- **Amp** (`amp`, `ENABLE_AMP`, `AMP_*`).
- **Ollama** (`ollama`, `ENABLE_OLLAMA`, `OLLAMA_*`, including the `local` preset).

Existing environments may keep obsolete variables safely, but they are ignored. Remove them from user configuration; use one of the remaining 11 consultants instead.

## [2.21.0] - 2026-07-14

### Added
- **CLI-first transport (now the default principle).** Any consultant that ships a CLI uses it by default; API mode is opt-in — for CLI-less models or an explicit `*_USE_API=true`. Amp and Claude are enabled by default.
- **MiniMax via the `mmx` CLI.** MiniMax was API-only; it now runs through the `mmx` CLI by default. `MINIMAX_USE_API` auto-resolves to API mode only when `MINIMAX_API_KEY` is set, so a pre-2.21 API-only setup keeps working on upgrade.
- **`ai-consultants update-clis`.** For each CLI-backed consultant, detect how its CLI was installed (brew formula/cask, npm, uv, pipx, pip, self-updating binary, curl installer) and update it via the matching method. `--dry-run` and `--only <cli>` supported.
- **Stance-based semantic consensus** (opt-in, `ENABLE_STANCE_CONSENSUS`). One LLM call enumerates a small set of mutually-exclusive stance options for the question; each consultant picks one verbatim; consensus becomes the plurality stance's share of the panel — exact-match agreement, immune to paraphrasing. Degrades to the lexical cluster on any failure. Tunables: `STANCE_MAX_OPTIONS`, `STANCE_TIMEOUT`.
- **Reliability tracking**, a `scripts/release.sh` version-bump automation, and an offline end-to-end integration test.

### Fixed
- **CLI adapters** (surfaced by a full-panel smoke test): Gemini (`agy -p "$QUERY"`, not the broken `-p -`), Kimi (`--output-format stream-json` + a hardened extractor), and Kilo (strip the ```json fence) now return structured responses instead of degrading to the unstructured fallback.
- **Metadata pollution** in voting / synthesis / peer-review: pipeline files (`voting.json`, `orchestration.json`, `stance_options.json`, …) are filtered out of every responses-dir glob, so they can no longer become phantom votes, peer-review reviewees, or synthesis inputs. Consensus is the largest agreeing cluster (single-linkage over Jaccard).
- **Orchestration**: a lexical "stalled" is relabeled "stable" when the panel's own per-round signal says positions stopped moving (now `set -e`-safe on a malformed round summary); a debate round's refined stance is validated before it is grafted.
- **GLM and DeepSeek personas were transposed at runtime** — each consultant ran under the other's persona name and prompt.
- **Calibration**: diagnosable peer-review failures + cost-only calibration path.

### Changed
- `npm test` now runs 18 suites. The v2.21 changeset was hardened by a multi-agent `/code-review max` pass.

## [2.20.0] - 2026-07-12

### Added
- **Capability-aware voting & panel composition (opt-in).** Beyond category *fit* (the affinity matrix), `references/affinity.json` v1.1 adds a per-consultant `capabilities` score on three axes — intelligence, taste, cost — and a `category_axis` map naming the quality axis each category stresses. With `ENABLE_CAPABILITY_WEIGHTING`, a consultant's vote weight becomes `confidence × (S + capability) / S` on that axis; with `ENABLE_CAPABILITY_ROUTING`, eligible consultants are ranked by `affinity + capability`. `cost` is a composition/budget axis only, never a vote weight (tie-break: intelligence > taste > cost). Both default off — behavior is unchanged until enabled.
- **Roster audit — uncorrelated value.** `scripts/roster_audit.sh` (also `doctor.sh --roster-audit` and the `/ai-consultants:roster-audit` slash command) scores each consultant's distinctiveness across past consultations: one that only echoes the panel is flagged redundant; one that often proposes a distinct approach earns its seat. Read-only.
- **Measured calibration — replace the heuristic seeds with data.** `scripts/roster_calibrate.sh` (Tier A) derives intelligence/taste from blind peer-review sliced by axis, and cost from observed `tokens_used` × catalog rate. `scripts/taste_elo.sh` (Tier B) refines taste via pairwise LLM-as-judge Elo. `scripts/run_calibration.sh` + `references/calibration_benchmark.json` (50 balanced questions) collect the data; both calibrators can `--write` measured scores into `affinity.json`.

### Changed
- `npm test` now runs 12 suites (added `test_capability_weighting`, `test_roster_audit`, `test_roster_calibrate`, `test_taste_elo`).

### Notes
- All new behavior is opt-in and additive; the shipped `capabilities` scores are subjective seeds (Claude/Codex grounded on the model-routing table, the rest heuristic) — run the calibration workflow to measure them for your panel.

## [2.19.2] - 2026-07-11

### Fixed
- **Cost tracking is no longer silently lost on a fresh install.** `track_session_cost` wrote to `costs.json` in the XDG data dir (`~/.local/share/ai-consultants/`) without creating that directory first, so on a fresh install every session failed with "No such file or directory" and cumulative cost tracking never accumulated. The parent directory is now created on demand.
- **A corrupt `costs.json` now self-heals** instead of wedging every future update: it is set aside as `costs.json.corrupt` and reset, rather than failing the `jq` update forever.

### Changed
- **`track_session_cost` is now concurrency-safe and strictly best-effort.** The read-modify-write of `costs.json` is serialized with a portable `mkdir` lock (bounded 5s wait, then proceeds unlocked — bookkeeping must never block a run) and writes go through a unique `mktemp` temp file instead of a shared `.tmp` sibling. Every failure path degrades to a warning and returns success, so cost bookkeeping can never abort a consultation under `set -e`.

## [2.19.1] - 2026-06-27

### Fixed
- **Diagnosed Failures report table no longer breaks when a failure reason contains a `|`** (e.g. a CLI error mentioning a piped command). The pipe is now escaped in the markdown table.
- **Health gate is cache-aware**: it no longer sends a billed ping to a consultant whose response is already cached.

### Changed
- Internal cleanup from code review: a single `render_diagnosed_failure` helper now renders both the console and report surfaces (no duplicated decode); `ping_consultant` takes the already-lowercased id (one fewer fork per consultant). Documented the health gate's pre-run startup latency.

## [2.19.0] - 2026-06-26

### Added
- **Quorum grading + Diagnosed Failures report.** A consultation is now graded MET / DEGRADED / FAILED by how many consultants actually responded (vs `QUORUM_MIN`, default 2), and the report lists each failed consultant with its diagnosed reason — so a panel that silently shrank no longer presents as authoritative. `QUORUM_ACTION=stop` aborts below quorum (default `warn` continues with a banner).
- **Health gate (`ENABLE_HEALTH_GATE`, opt-in).** Pings each selected consultant in parallel before the run and drops the non-responsive ones (installed-but-unauthenticated CLIs), so the panel only spends the full run on consultants that work. Costs one tiny query per consultant; `HEALTH_GATE_TIMEOUT` default 30s.

## [2.18.0] - 2026-06-26

### Added
- **`doctor.sh --live`** — sends a real ping query to each enabled consultant and reports which actually respond, catching CLIs that are installed but not authenticated (the static check reports those as healthy). Opt-in; costs one tiny query per consultant. Timeout via `DOCTOR_LIVE_TIMEOUT` (default 45s).

### Changed
- **Consultant failures now show why.** Previously a failed consultant produced a bare "Failed" with its error discarded. The run now captures each consultant's stderr and surfaces a one-line reason (e.g. "CLI not found", "401 Unauthorized") so you can tell *not installed* from *not authenticated* from *transient*. `run_query` also embeds the CLI's real error in its failure log.

## [2.17.2] - 2026-06-25

### Security
- **Context files could read arbitrary absolute paths and send them to external AI providers.** v2.17.1 widened `build_context.sh` to accept any absolute context path behind a small prefix blocklist that did not cover home secrets — so a context argument pointing at `~/.ssh/id_rsa`, `~/.aws/credentials`, `~/.netrc`, etc. would be read and forwarded to the consultant models. Context files are now restricted to relative in-tree paths or recognized temp roots (`/tmp`, `/private/tmp`, `$TMPDIR`); arbitrary absolute paths are rejected. The original macOS `/private/tmp` scratch-file fix is preserved. v2.17.1 was never published to npm; **use 2.17.2**.

### Fixed
- `build_context.sh` output-path validation no longer short-circuits past the traversal/sensitive-path guards for `/tmp` outputs.

## [2.17.1] - 2026-06-25

### Fixed
- **Context files at absolute paths outside `/tmp` were silently dropped.** `build_context.sh` only accepted relative paths or a literal `/tmp/*` prefix, so an absolute context file — notably macOS scratch files at `/private/tmp/...` (where `/tmp` is a symlink) — was skipped and a generic auto-context substituted, without the consultants ever receiving the intended context. Absolute paths are now accepted (the sensitive-path / traversal / null-byte guards still apply).

## [2.17.0] - 2026-06-24

### Changed
- **Refreshed every consultant's models (June 2026) across premium / standard / economy, with updated cost rates.** CLI-based agents were verified against the installed CLIs; API/provider models and pricing were researched against official sources.
  - Codex → `gpt-5.5` / `gpt-5.4` / `gpt-5.4-nano`
  - Cursor → `composer-2.5` / `composer-2` / `gemini-3-flash`
  - DeepSeek → `deepseek-v4-pro` / `deepseek-v4-flash` (×2; `deepseek-chat`/`deepseek-reasoner` are being deprecated)
  - GLM → `glm-5.2`
  - Grok → `grok-4.3` / `grok-4.1-fast` (×2)
  - Qwen3 → `qwen3.7-max` (premium)
  - Aider → `qwen3-coder:free`
  - Ollama → `hf.co/prithivMLmods/VibeThinker-3B-GGUF`
  - Claude, Gemini, Mistral, MiniMax, Kimi: verified current, unchanged.
- Corrected several cost rates to verified provider pricing (notably `gpt-5.5`, which was understated). Set `ORCHESTRATION_MODE`/per-agent `*_MODEL` env vars to override any default.

## [2.16.0] - 2026-06-22

### Added
- **Dynamic orchestration.** Instead of a fixed pipeline, a planner now picks an orchestration *shape* for each question and runs debate as a **convergence loop** — iterating until the panel's answers converge rather than for a fixed number of rounds. Shapes: `quick` (simple questions, no debate), `converge` (debate to consensus), `adversarial` (security: forced critique round + anonymous peer-review refutation gate), `tournament` (compare approaches, then pick one winner), `exhaustive` (find-all: loop until no new angle surfaces).
- New settings: `ORCHESTRATION_MODE` (`auto` default / `fixed` / a specific shape), `CONVERGENCE_MAX_ROUNDS`, `CONVERGENCE_TARGET_CONSENSUS`, `CONVERGENCE_STALL_EPSILON`, `ENABLE_ADVERSARIAL_VERIFY`.

### Changed
- The default deliberation is now adaptive (`ORCHESTRATION_MODE=auto`): complex or contested questions iterate further toward consensus, simple ones short-circuit. Budget limits (`MAX_SESSION_COST`) still cap every round. Set `ORCHESTRATION_MODE=fixed` to keep the previous fixed-round behavior exactly.

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
