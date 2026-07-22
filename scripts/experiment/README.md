# Cross-vendor workflow coverage experiment

Maintainer instrumentation — **not shipped** (excluded from the npm tarball via
`package.json` `files`). Not user calibration (`roster_calibrate.sh` / `taste_elo.sh`
are shipped; this is not). It changes no default, no roster, no shipped code path.

## What it now asks (v2 — coverage, not consensus)

ai-consultants is the Claude Code dynamic-workflow pattern with **cross-vendor agents**
(see https://code.claude.com/docs/en/workflows). A workflow earns trust from **adversarial
verification against ground truth**, not from voting/averaging — so the value to measure is
**coverage**: does a diverse fan-out, with each finding verified, catch defects a single
strong model misses (uncorrelated errors)?

The v1 design scored the panel's synthesized **consensus** recommendation and the pilot bore
out the reviews' critique uninformatively (where the panel "lost", one model and the panel had
both found the defect). `PREREGISTRATION.md` is now the **coverage** design: arm A (one model),
arm W (panel → union of findings → adversarial verify → survivors), arm C (self-consistency
union). Primary metric = coverage; decisive comparison = items W catches that A misses.

The harness implements this v2 coverage design end to end (validated for $0 via `--smoke`):
arm W runs the roster as a pure **fan-out with debate/consensus OFF** and takes the **union**
of independent findings; `verify.sh` adversarially prunes each finding against the code; `grade.sh`
scores coverage; `analyze.sh` reports discordant-pair value + cost per covered defect.

## Files

| File | Role |
|---|---|
| `PREREGISTRATION.md` | Frozen choices + decision rule. Freeze **before** any real run. |
| `benchmark.json` | Held-out defect-finding items (code + rubric key) + grader-calibration pairs. **Seed (8)** — extend to n≥30 before the real run. |
| `run_experiment.sh` | Driver: arm A (one model, direct), arm W (roster fan-out → union, no debate), arm C (self-consistency union). Emits `findings.jsonl`. |
| `verify.sh` | Adversarial verifier: a model (≠ the finding's author) tries to refute each finding against the code; keeps survivors. Emits `verified.jsonl`. |
| `grade.sh` | Coverage grader: does any **verified** finding identify the keyed defect? `--calibrate` is the validity gate. Emits `coverage.jsonl`. |
| `analyze.sh` | Coverage rate per arm, discordant-pair value (W-vs-A, W-vs-C), the pre-registered verdict, cost per covered defect, verifier pruning. |

## Run order

```bash
cd scripts/experiment

# 0. Prove the plumbing with no model calls ($0):
./run_experiment.sh --smoke && echo "smoke ok"

# 1. Validate the grader BEFORE trusting it. Pin a STRONG model and VOTE — a headless
#    `claude -p` at the session default grades an unambiguous pair YES only ~5/12 (measured),
#    and even opus flips ~1 in 6 on a single call. JUDGE_MODEL + JUDGE_VOTES fix both.
#    JUDGE_CLI/JUDGE_MODEL must NOT be the arm-A/C model.
JUDGE_CLI=claude JUDGE_MODEL=opus JUDGE_VOTES=5 ./grade.sh --calibrate   # must print GATE PASSED

# 2. Freeze the pre-registration (fill in date, commit hash, models), then:
touch .frozen

# 3. Real run. From a PLAIN TERMINAL (not a Claude Code session — the claude CLI
#    contends with it) and with a strong model that is reliable and not the grader.
STRONG_CONSULTANT=Gemini ./run_experiment.sh --run
FIND=out/findings.jsonl

# 4. Adversarial verify (VERIFY_CLI/VERIFY_MODEL must not be the finding's author; pin+vote
#    a strong model for the same reason as the grader). Then coverage-grade.
VERIFY_CLI=claude VERIFY_MODEL=opus VERIFY_VOTES=5 ./verify.sh benchmark.json "$FIND" out/verified.jsonl
JUDGE_CLI=claude  JUDGE_MODEL=opus  JUDGE_VOTES=5  ./grade.sh  benchmark.json out/verified.jsonl out/coverage.jsonl

# 5. Verdict:
./analyze.sh out/coverage.jsonl out/verified.jsonl

# 6. Hand-label 10 random grader verdicts AND 10 verifier decisions; if either agrees
#    with you < 90%, the run is inconclusive, not a loss for any arm (PREREGISTRATION.md).
```

## Pilot findings (2026-07-22) — read before a real run

A pilot on the seed set surfaced environment constraints that a binding run must respect:

- **The grader is the experiment, and a single LLM call is not an instrument (measured).** The
  calibration gate failed 3/4, and the cause was neither the parse nor the pairs: a headless
  `claude -p` at the *session default* model graded an **unambiguous** correct pair (`cal-correct-1`,
  where the answer restates the key almost verbatim) YES only **5/12** — a coin flip. Two levers
  fix it, and both are now baked in: (1) **pin a strong model** — `JUDGE_MODEL=opus` took that pair
  to ~0.82/call (the default resolves to a fast, unreliable model); (2) **majority-vote** —
  `JUDGE_VOTES=5` turns 0.82/call into ~0.96/pair, which is the difference between a usable gate and
  a brittle one. Also: the prompt now asks the grader to *reason then* emit a final YES/NO (`tail -1`
  takes the conclusion); forcing a bare single token measured worse. Same `VERIFY_MODEL`/`VERIFY_VOTES`
  levers apply to the verifier — a weak verifier corrupts coverage exactly as a weak grader does. A
  residual ~5–7% chance of a *spurious* single-run gate fail remains at votes=5 (raise to 7 if it
  bites); a spurious fail is conservative — re-run, don't proceed on it. **Note the 4-pair calibration
  set is itself too small** — one flip is a 25% swing; expanding it (toward the n≥30 benchmark work)
  is part of making the gate robust.
- **Do not drive the strong model from inside a Claude Code session.** With
  `STRONG_CONSULTANT=Claude`, arm A/C call the `claude` CLI, which contends with the
  driving session and intermittently degrades (synthesis fell back to "Manual review
  required"). Run the experiment from a plain terminal, or pick a strong model whose CLI
  is not the one running the harness.
- **Use the user's real config; don't isolate.** The first pilot ran the panel with an
  *empty* config dir (for `ENABLE_*` hermeticity) and saw only 3 consultants — the empty dir
  stripped the API keys AND Qwen's Token Plan transport. The driver now uses the real config
  (keys + transport survive) and controls composition via explicit per-arm `ENABLE_*`; a
  `DEFAULT_PRESET` like `balanced` must be cleared or it caps the panel at 4.
- **Confirm the live panel with `doctor --live`, not static doctor.** Consultants down for
  credential/quota reasons (a bad key, a usage limit) pass every static check and fail live;
  set `EXPERIMENT_SKIP_CONSULTANTS` to drop them from arm W (default drops `CURSOR`).
- **Arm W is a pure fan-out** — `ENABLE_DEBATE=false`, `ORCHESTRATION_MODE=fixed`, peer
  review off. The debate/convergence/consensus machinery is deliberately NOT run: it is the
  averaging part the experiment is testing *against*, not part of arm W.
- **Arm A is a direct query** — consult_all refuses fewer than 2 consultants, so a single
  model cannot go through it.
- **Arm C's k is capped** (`K_MAX`, default 12) so a failed sample cannot explode it.
- Budget the wall clock: even a fan-out (no debate) over 10 consultants took minutes per
  item in the pilot; run in the background. Note the v1 pilot found the *deliberating* panel
  cost ~113× a single model — arm W (fan-out only) is far cheaper, which is the point.

## Guardrails baked in

- `run_experiment.sh --run` **refuses** unless `.frozen` exists — you cannot run before
  freezing the pre-registration.
- Every arm runs with `ENABLE_SEMANTIC_CACHE=false` (a cache hit would collapse arm C's
  samples and void token accounting) and `AI_CONSULTANTS_CONFIG_DIR=<empty>` (your `.env`
  must not change arm composition — the trap that produced a wrong local test pass this
  release cycle).
- The grader never sees arm labels and grades in shuffled order.
- Cost: ~n × (1 + ~8–11 + k≈8) model calls + ~n grader calls. Budget-guarded per run.
