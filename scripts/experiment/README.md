# Cross-vendor workflow coverage experiment

Maintainer instrumentation — **not shipped** (excluded from the npm tarball via
`package.json` `files`). Not user calibration (`roster_calibrate.sh` / `taste_elo.sh`
are shipped; this is not). It changes no default, no roster, no shipped code path.

## Bottom line (2026-07-22): panel value is TASK-DEPENDENT — wins on breadth, not on defect-finding

Two regimes, opposite results:

| task | measure | single strong model | cross-vendor panel (fan-out union) |
|---|---|---|---|
| **convergent** — find THE defect | caught? | **19/19 (saturates)** | no headroom to add |
| **divergent** — enumerate ALL risks (breadth) | rubric coverage | A = 19/32 (**59%**) | W = 32/32 (**100%**); C (same model ×8) = 84% |

On breadth the panel wins **W > C > A on every item** — it covers points one model misses *and*
beats resampling the same model at equal sample count, so the edge is **diversity, not volume**. The
panel ran as **raw fan-out with NO deliberation** (voting/consensus/debate off): the value is the
diverse UNION, not the averaging — which supports keeping the diverse agents and cutting the consensus
machinery. Hardened against the rubric-ceiling caveat: re-run on **deep 60-point rubrics** (21/21/18,
niche points added) the result strengthened — **A = 31/60 (51%), C = 42/60 (70%), W = 56/60 (93%),
W−C = +14** (the ceiling had *understated* diversity). Hand-checked against saved answer blobs: the
codex grader is accurate (a direct leniency test on the jku/x5u point graded YES and W's union
genuinely contains it), arm A genuinely misses the niche points, and diverse consultants genuinely
surfaced what one model missed. Remaining caveat: n=3 is directional; a statistically binding claim
needs n≥15–20 deep-rubric items.

## Regime 1 (2026-07-22): snippet defect-finding SATURATES — panel has no headroom

The full A/W/C run was NOT needed to answer the premise. The `difficulty_probe.sh` curation
step measures the precondition for any panel value — *does a single strong model miss the bug?*
— and the answer is essentially no. A single strong model (**Gemini 3.1 Pro**) caught **19/19**
hard bugs: 7 repo-internal (`benchmark_pool.json`) + 12 source-verified external
(`benchmark_pool_external.json`) spanning version footguns, expert concurrency (incl. the Rust
`Arc` bug found by RustBelt *formal verification*), famous crypto CVEs, and cross-module
interaction bugs. **0 were discriminating.** Since arm W's only edge is catching what arm A
misses (uncorrelated coverage), and arm A misses nothing here, the panel has no coverage headroom
on this task — direct empirical support for the premise critique, for a fraction of the cost of
the binding run (which would be INCONCLUSIVE-by-saturation, exactly as the 2-item pilot showed).

**Scope it honestly** — this holds for: snippet-scale code (<~70 lines) + defect-finding + one
strong model. UNTESTED regimes where a panel could still earn its keep: huge multi-file / long
context (needle-in-haystack, division of labor) and open-ended BREADTH/design tasks (a union of
diverse answers beating one) — both are *different* experiments, not this one.

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
| `verify.sh` | Hallucination filter (codex sol-high, ≠ the finding's author): keeps a finding if the code actually contains the defect it points at — even if terse — and prunes only absent/wrong/unspecific claims. Bar aligned with the grader's. Emits `verified.jsonl`. |
| `grade.sh` | Coverage grader: does any **verified** finding identify the keyed defect? `--calibrate` is the validity gate. Emits `coverage.jsonl`. |
| `analyze.sh` | Coverage rate per arm, discordant-pair value (W-vs-A, W-vs-C), the pre-registered verdict, cost per covered defect, verifier pruning. |

## Run order

```bash
cd scripts/experiment

# 0. Prove the plumbing with no model calls ($0):
./run_experiment.sh --smoke && echo "smoke ok"

# 1. Validate the grader BEFORE trusting it. The DEFAULT backend is codex gpt-5.6-sol @high —
#    measured reliable both directions (6/6 on an obvious-correct pair, 4/4 on an obvious-wrong
#    one), where claude is a coin flip. It must NOT be the arm-A/C model (it isn't: A/C are
#    claude/gemini). No env needed for the default; votes optional insurance.
./grade.sh --calibrate                       # must print GATE PASSED

# 2. Freeze the pre-registration (fill in date, commit hash, models), then:
touch .frozen

# 3. Real run. From a PLAIN TERMINAL (not a Claude Code session — the claude CLI
#    contends with it) and with a strong model that is reliable and not the grader.
STRONG_CONSULTANT=Gemini ./run_experiment.sh --run
FIND=out/findings.jsonl

# 4. Adversarial verify then coverage-grade — both default to the codex sol-high backend
#    (VERIFY_MODEL/JUDGE_MODEL override; must not be the finding's author / arm-A model).
./verify.sh benchmark.json "$FIND" out/verified.jsonl
./grade.sh  benchmark.json out/verified.jsonl out/coverage.jsonl

# 5. Verdict:
./analyze.sh out/coverage.jsonl out/verified.jsonl

# 6. Hand-label 10 random grader verdicts AND 10 verifier decisions; if either agrees
#    with you < 90%, the run is inconclusive, not a loss for any arm (PREREGISTRATION.md).
```

## Pilot findings (2026-07-22) — read before a real run

A pilot on the seed set surfaced environment constraints that a binding run must respect:

- **The grader is the experiment — and choosing the grader model is not incidental, it was
  measured.** The calibration gate failed 3/4 on `cal-correct-1`, an **unambiguous** pair (the
  answer restates the key almost verbatim). The cause was the grader *model*, per-call, in **both**
  directions (N samples each):
  - `claude -p` session default: **5/12** YES on the correct pair — a coin flip (a fast, weak model).
  - `claude -p --model opus`: 6–8/10 on the correct pair, but only **3/6** NO on an obvious-*wrong*
    pair under a sharper prompt — it *over-matches*. Noisy both ways; no prompt or vote count rescues it.
  - **codex `gpt-5.6-sol` @high: 6/6** on the correct pair, **4/4** on the wrong pair. Reliable.

  So the grader/verifier **default backend is codex sol-high**, not claude (`JUDGE_BACKEND`/
  `VERIFY_BACKEND`, `JUDGE_MODEL`/`VERIFY_MODEL`, `JUDGE_EFFORT`/`VERIFY_EFFORT`). It's a different
  vendor from arms A/C (claude/gemini), which the pre-registration requires anyway, and matches what
  v1 found (Codex passed the gate 4/4) and the delegation policy (route judgment to the reasoning
  model). The prompt matches on *meaning* (same bug, cause **or** consequence) and reasons before a
  final YES/NO (`tail -1` grabs it); a bare single token measured worse. Voting (`JUDGE_VOTES`/
  `VERIFY_VOTES`, default 1) stays as cheap insurance — codex needs little. **The 4-pair calibration
  set is still too small** (one flip = a 25% swing); expand it alongside the n≥30 benchmark.
- **First clean end-to-end run (2 items, codex grader) — plumbing works; two design fixes fell out.**
  All four stages ran well-formed. Hand-checked, not just counted: arm A (Gemini) precisely nailed
  both defects (legit YES), and the verifier correctly pruned the 3/8 degraded `"Unstructured
  response"` stubs. Coverage was A/W/C = 2/2 each → 0 discordant → `INCONCLUSIVE` (correct; the seed
  items are documented textbook defects a strong model catches trivially — **the n≥30 set must target
  subtle bugs a single model plausibly MISSES**, or the design can't detect panel value even if it
  exists). Cost: arm W ≈ **12.4×** arm A (fan-out only, vs v1's ~113× with debate — the diversity is
  cheap, the deliberation was the cost). Two fixes it forced:
  - **Verifier bar aligned with the grader's.** The old verifier pruned "vague" findings and killed a
    terse-but-*correct* arm-W finding before grading (biasing the panel down). It is now a pure
    HALLUCINATION filter — keeps a finding if the code actually contains the defect (even if terse),
    prunes only absent/wrong/unspecific claims. Re-validated on item-1 code (votes=3): terse-correct →
    YES, detailed-correct → YES, junk-stub → NO, a fabricated `eval`-injection claim → NO (not a rubber
    stamp).
  - **Vendor-disjointness is a hard panel constraint.** The grader/verifier is codex and arm A/C is the
    strong model, so arm W must exclude **both** the grader/verifier vendor (CODEX — else self-verify)
    and the strong model, plus any consultant whose CLI contends with the harness (CLAUDE, when driven
    from a Claude Code session). Set via `EXPERIMENT_SKIP_CONSULTANTS` (pilot used `CURSOR CLAUDE CODEX`).
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
