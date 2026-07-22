# Pre-registration — cross-vendor workflow coverage experiment

**This file is frozen before the first real run.** Its purpose is to make the result
un-rationalisable after the fact: the metric, the arms, and the decision rule are fixed
here, in git, before any answer is seen. If the harness or the rule changes after a run has
been graded, that run is void and must be re-collected.

## What changed from v1, and why

The first design (and the pilot that ran it) scored the panel's **synthesized consensus
recommendation** against a defect key — a single-answer task. That measured the *consensus*
premise, which two independent reviews (Codex, Fable) judged weak: voting/consensus rewards
agreement, not correctness. The pilot bore this out uninformatively: on the items where the
panel "lost", a single model and the panel had *both* found the defect — the panel simply
added no consensus benefit, which is unsurprising and not the point.

The reframing (grounded in https://code.claude.com/docs/en/workflows): ai-consultants is the
**Claude Code dynamic-workflow pattern with cross-vendor agents**. A workflow earns trust from
**adversarial verification against ground truth**, not from voting/averaging. Its value is
**coverage** — a diverse fan-out catches defects a single model misses (uncorrelated errors) —
verified so plausible-but-wrong findings are filtered out. That is what this experiment now
measures.

## Hypothesis under test

Running the roster as a workflow — **fan out → take the union of distinct findings →
adversarially verify each → keep the survivors** — catches keyed defects that a single strong
model, one shot, misses. And it does so at a cost multiple worth paying.

The null: the panel's verified union covers no more defects than a single model (diversity buys
nothing), or than the same model sampled k times (diversity ≠ more samples).

## The arms (per item; matched on token spend where a baseline needs it)

- **A — single strong model, one shot.** Its finding(s). Coverage = does the keyed defect
  appear in A's finding?
- **W — the panel as a workflow.** Fan out to every working consultant; take the **union** of
  distinct findings (not a synthesized consensus); run an **adversarial verifier** on each
  finding (a different model tries to refute it against the code); keep the findings that
  survive. Coverage = does the keyed defect appear in W's *verified* union?
- **C — self-consistency union.** The same single model sampled k times (k sized to W's token
  spend), union of its distinct findings, same adversarial verifier. Isolates "diverse models"
  (W) from "one model, more tries" (C). **C is the control that decides whether diversity, not
  just volume, is what pays.**

## Fixed choices

| Choice | Value | Rationale |
|---|---|---|
| Strong model (A, C) | a model reliable in the run environment and **not** the grader/verifier | The pilot proved Claude is unusable driven from a Claude Code session; pick per environment, record it here before freezing |
| Verifier (W, C) | a HALLUCINATION filter (codex sol-high) — keeps a finding if the code contains the defect (even if terse), prunes only absent/wrong/unspecific claims | Must not check its own answer, and must not prune correct-but-terse findings: the 2-item pilot showed the old "reject if vague" bar killed a correct arm-W finding, biasing the panel down. Bar aligned with the grader's |
| Grader (coverage scoring) | **codex `gpt-5.6-sol` @high** (the default backend), a model **different** from A/C | Measured both directions: claude default 5/12 on an obvious-YES pair, opus over-matches (3/6 on an obvious-NO pair), codex-sol 6/6 + 4/4. The grader IS the experiment; pick the reliable one, not the convenient one |
| Verifier (W, C) — reliability | same codex sol-high backend | A weak/single-call verifier corrupts coverage exactly as a weak grader does |
| Panel (W) | live consultants (`doctor --live`), **excluding** the grader/verifier vendor (CODEX), the strong model (arms A/C), any CLI that contends with the harness, and dead-key/Cursor | Vendor-disjointness is required (a codex consultant self-verified by the codex verifier is worthless); a shared CLI degrades under contention. Measure the real, disjoint working panel, not a static roster |
| n | ≥ 30 items | Sign/McNemar test needs it; the pilot's n=3 is not a result |
| Cache | `ENABLE_SEMANTIC_CACHE=false` | A cache hit collapses C's samples and voids token accounting |

## Metric

**Primary — coverage.** Per item, per arm: does the arm's **verified** finding set contain the
keyed defect (blind YES/NO by the grader against the rubric)? Report each arm's coverage rate.

**The decisive comparison — uncorrelated value.** Count the items where **A missed but W
caught** (W's genuine contribution) and where **W missed but A caught** (diversity cost /
verification over-pruning). McNemar's test on the discordant pairs.

**Cost.** Tokens per item per arm, and **tokens per keyed defect actually found**. The pilot
measured the panel at ~113× a single model's tokens; a coverage win must be weighed against
that multiple.

**Verification value (reported).** How many raw findings the adversarial verifier removed, and
whether any removed finding was in fact the keyed defect (verification pruning a correct
answer is a failure mode to watch).

## Decision rule (pre-registered)

Evaluated on coverage over ≥30 items, McNemar on discordant pairs:

- **W covers defects A misses, significantly, and W ≥ C** → the cross-vendor workflow earns
  its cost: keep fan-out + adversarial verify + union; **cut the consensus machinery** (voting,
  lexical consensus, capability weighting, panic mode) — it was never what delivered this.
- **W ≈ C** (diversity ties self-consistency) → the win is volume, not diverse models: a single
  strong model sampled k times + verify is the cheaper equal; the roster's diversity is not
  justified for this task.
- **W ≈ A** (union catches nothing extra) → the panel adds no coverage over one shot; the
  workflow framing does not rescue it either. Codex's cut stands.

A result resting on a grader/verifier below the hand-label gate (below) is **inconclusive**,
not a win or loss for any arm.

## Grader / verifier validity gate

Before any real coverage grade is trusted: the grader must clear the fixed calibration pairs in
`benchmark.json` (obvious-correct / obvious-wrong), run with the codex sol-high backend above. After
the run, hand-label a random 10 of the grader's verdicts AND 10 of the verifier's refute/keep
decisions; below **90%** human agreement on either, the run is inconclusive. The pilot is the
cautionary case, now quantified: the *default* claude grader scored a verbatim-correct answer wrong
~half the time, and opus flips both ways — which is why the backend is codex sol-high (measured 6/6
+ 4/4), not the convenient CLI. One caveat on the gate itself: the calibration set is only 4 pairs,
so one flip is a 25% swing — expand it alongside the n≥30 benchmark. A gate fail is conservative:
re-run or investigate the pair; never proceed on a grader that failed.

## What this experiment does NOT do

- It does not score a synthesized consensus answer — that was the wrong metric.
- It does not cut, keep, or change any machinery. It produces the coverage data; the decision
  (cut the consensus arithmetic, keep the workflow) is taken afterward, on the data.

---

_Frozen: fill the date and the commit hash of this file at freeze time before the first run._
_Strong model: ______  Verifier: ______  Grader: ______ (record before freezing)._
