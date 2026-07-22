# Panel-vs-baseline experiment

Maintainer instrumentation — **not shipped** (excluded from the npm tarball via
`package.json` `files`). It answers one question raised by two independent reviews: at
matched token spend, does the 11-consultant panel's synthesized recommendation beat a
single strong model? See `PREREGISTRATION.md` for the frozen protocol and decision rule.

Not user calibration (`roster_calibrate.sh` / `taste_elo.sh` are shipped; this is not).
It changes no default, no roster, no shipped code path.

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

## Guardrails baked in

- `run_experiment.sh --run` **refuses** unless `.frozen` exists — you cannot run before
  freezing the pre-registration.
- Every arm runs with `ENABLE_SEMANTIC_CACHE=false` (a cache hit would collapse arm C's
  samples and void token accounting) and `AI_CONSULTANTS_CONFIG_DIR=<empty>` (your `.env`
  must not change arm composition — the trap that produced a wrong local test pass this
  release cycle).
- The grader never sees arm labels and grades in shuffled order.
- Cost: ~n × (1 + ~8–11 + k≈8) model calls + ~n grader calls. Budget-guarded per run.
