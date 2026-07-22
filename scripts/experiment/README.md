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

> **Harness status:** `run_experiment.sh` / `grade.sh` / `analyze.sh` still implement the v1
> consensus design (they score the synthesized answer, not the verified union). Running the v2
> pre-registration needs three additions, not yet built: (1) arm W extracts the **union** of
> distinct per-consultant findings instead of reading `synthesis.json`; (2) an **adversarial
> verifier** pass over each finding (a different model tries to refute it against the code);
> (3) `analyze.sh` computes coverage rates + McNemar on discordant pairs. Until then the scripts
> answer the v1 question; do not treat their output as the v2 coverage result.

## Files

| File | Role |
|---|---|
| `PREREGISTRATION.md` | Frozen choices + decision rule. Freeze **before** any real run. |
| `benchmark.json` | Held-out defect-finding questions with rubric answer keys + grader-calibration pairs. **Seed only** — extend to n≥30 before the real run. |
| `run_experiment.sh` | Driver: arms A (single strong model), B (full panel), C (self-consistency). |
| `grade.sh` | Blind YES/NO grader vs the key rubric (fork of `taste_elo.sh::_judge`). |
| `analyze.sh` | Per-arm hit rate, paired sign test, the pre-registered verdict, secondary metric. |

## Run order

```bash
cd scripts/experiment

# 0. Prove the plumbing with no model calls ($0):
./run_experiment.sh --smoke && echo "smoke ok"

# 1. Validate the grader BEFORE trusting it. Pick a JUDGE_CLI that is NOT the arm-A model.
JUDGE_CLI=<cheap-clerk-cli> ./grade.sh --calibrate     # must print GATE PASSED

# 2. Freeze the pre-registration (fill in date, commit hash, grader), then:
touch .frozen

# 3. Real run (spends model calls; mostly subscription CLIs). Cache is forced off,
#    budget guard on, config isolated from your own .env.
STRONG_CONSULTANT=Claude ./run_experiment.sh --run > /tmp/exp/results_path
RES=scripts/experiment/out/results.jsonl
JUDGE_CLI=<cheap-clerk-cli> ./grade.sh benchmark.json "$RES" out/grades.jsonl

# 4. Verdict:
./analyze.sh out/grades.jsonl "$RES"

# 5. Hand-label 10 random verdicts; if grader/human agreement < 90%, the run is
#    inconclusive, not a loss for any arm (PREREGISTRATION.md).
```

## Pilot findings (2026-07-22) — read before a real run

A pilot on the seed set surfaced environment constraints that a binding run must respect:

- **Do not drive the strong model from inside a Claude Code session.** With
  `STRONG_CONSULTANT=Claude`, arm A/C call the `claude` CLI, which contends with the
  driving session and intermittently degrades (synthesis fell back to "Manual review
  required"). Run the experiment from a plain terminal, or pick a strong model whose CLI
  is not the one running the harness.
- **Keep the user's credentials; isolate only composition.** The first pilot ran arm B
  with an *empty* config dir (for `ENABLE_*` hermeticity) and saw only 3 consultants —
  because the empty dir also stripped the API keys that GLM/Grok/DeepSeek/Qwen need.
  `doctor --live` with the real config showed **8 of 11 actually respond**. The driver now
  copies only the credential lines (`*_API_KEY`, `*_API_URL`) into the isolated dir, so
  auth survives while arm composition stays controlled by the explicit per-arm `ENABLE_*`.
- **Confirm the live panel with `doctor --live`, not static doctor.** The 3 that stay down
  are credential/quota, not code: Cursor (usage limit → Cursor Pro), Qwen3 (401, expired
  DashScope key), Grok (xAI "incorrect API key", returned as HTTP 400). Fix those keys or
  accept an 8-consultant panel; arm B is only as full as what actually answers.
- **Arm B runs with peer review OFF** (`_full_panel`) — it runs after synthesis and cannot
  change the scored recommendation, so dropping it cuts the slowest stage without altering
  what is measured.
- **Arm A is scored on the consultant's own response**, not a synthesis-of-one (which can
  degrade independently of answer quality).
- **Arm C's k is capped** (`K_MAX`, default 12) so a failed sample cannot explode it.
- Budget the wall clock: even a 3-consultant arm B took minutes per item; size the outer
  timeout and prefer running in the background.

## Guardrails baked in

- `run_experiment.sh --run` **refuses** unless `.frozen` exists — you cannot run before
  freezing the pre-registration.
- Every arm runs with `ENABLE_SEMANTIC_CACHE=false` (a cache hit would collapse arm C's
  samples and void token accounting) and `AI_CONSULTANTS_CONFIG_DIR=<empty>` (your `.env`
  must not change arm composition — the trap that produced a wrong local test pass this
  release cycle).
- The grader never sees arm labels and grades in shuffled order.
- Cost: ~n × (1 + ~8–11 + k≈8) model calls + ~n grader calls. Budget-guarded per run.
