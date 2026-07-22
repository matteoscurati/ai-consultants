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
| Verifier (W, C) | a model **not** the one that produced the finding | Adversarial verification must not check its own answer |
| Grader (coverage scoring) | a model **different** from A/C, **pinned strong** (`JUDGE_MODEL=opus`) and **majority-voted** (`JUDGE_VOTES=5`) | The default headless grader graded an unambiguous pair YES only 5/12; even opus flips ~1/6 per call. Pin + vote, or the gate is noise (see README pilot findings). The grader IS the experiment |
| Verifier (W, C) — reliability | same pin + vote (`VERIFY_MODEL=opus`, `VERIFY_VOTES=5`) | A weak/single-call verifier corrupts coverage exactly as a weak grader does |
| Panel (W) | every consultant that answers live (`doctor --live`), Cursor and any dead-key consultants excluded | Measure the real working panel, not a static roster |
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
`benchmark.json` (obvious-correct / obvious-wrong), run with the pinned+voted config above. After
the run, hand-label a random 10 of the grader's verdicts AND 10 of the verifier's refute/keep
decisions; below **90%** human agreement on either, the run is inconclusive. The pilot is the
cautionary case, now quantified: a single call from the *default* grader scored a verbatim-correct
answer wrong ~half the time — which is why the gate requires a pinned strong model and a majority
vote, not one call. Two caveats on the gate itself: (a) the calibration set is only 4 pairs, so one
residual flip is a 25% swing — expand it alongside the n≥30 benchmark; (b) even at votes=5 a
~5–7% *spurious* fail remains, which is conservative (re-run; never proceed on a grader that failed).

## What this experiment does NOT do

- It does not score a synthesized consensus answer — that was the wrong metric.
- It does not cut, keep, or change any machinery. It produces the coverage data; the decision
  (cut the consensus arithmetic, keep the workflow) is taken afterward, on the data.

---

_Frozen: fill the date and the commit hash of this file at freeze time before the first run._
_Strong model: ______  Verifier: ______  Grader: ______ (record before freezing)._
