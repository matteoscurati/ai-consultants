# Pre-registration — panel-vs-baseline held-out experiment

**This file is frozen before the first real run.** Its purpose is to make the result
un-rationalisable after the fact: the model choices, the decision rule, and the grading
protocol are fixed here, in git, before any answer is seen. If the harness or the rule
changes after a run has been graded, that run is void and must be re-collected.

Origin: two independent reviews (Codex `gpt-5.6-sol`, then Fable-5 judging Codex) agreed the
project has never shown held-out evidence that the 11-consultant panel beats a single strong
model at equal token spend. This experiment settles that one question and nothing else.

## Hypothesis under test

At matched token spend, the full panel's **synthesized recommendation** is more often correct
than (A) a single strong model answering once, and than (C) that same model sampled k times and
synthesized (self-consistency).

## Fixed choices

| Choice | Value | Rationale |
|---|---|---|
| Strong model (arms A, C) | **`claude-opus-4-8`** (the Claude consultant) | Repo premium default (`config.sh` `CLAUDE_MODEL`); chosen before any result |
| Grader model | **A model different from the strong model** (set via `JUDGE_CLI`; must not be `claude`) | Self-preference guard: the arm-A model must not grade its own answers |
| Panel (arm B) | Full roster, default deliberation (`--preset max_quality`) | The system as shipped |
| n | 30 questions | Sign test detects only large effects at this n — a go/no-go, not a precise estimate |
| Cache | `ENABLE_SEMANTIC_CACHE=false` on every run | A cache hit collapses arm C's samples and voids token accounting |
| Config isolation | `AI_CONSULTANTS_CONFIG_DIR=<empty dir>` | The maintainer's `.env` must not change arm composition |

## Grading protocol

- Binary YES/NO: does the candidate answer identify the defect described in the item's `key`
  rubric? The grader never sees which arm produced an answer, and answers are presented in
  randomised order.
- **Grader validity gate:** before any real grade is trusted, the grader must correctly score a
  fixed set of ~6 obviously-correct and ~6 obviously-wrong (key, answer) pairs. After the run, a
  random 10 real verdicts are hand-labelled; if grader/human agreement is below **90%**, the
  experiment is **inconclusive**, not a loss for any arm.

## Token matching

Arm C's k is set **per question** = round( arm-B token total / mean single-sample tokens ),
floored at 2. Spend-matching is therefore per-question and approximate; the matched quantity is
`sum(.metadata.tokens_used)` over billable response files, not dollars.

## Decision rule (paired, per question; sign test over decided pairs, n = 30)

Evaluated on the primary metric (hit rate on the synthesized answer):

- **B beats BOTH A and C** (≈ ≥ 20 wins among decided pairs, each direction) →
  **INVEST**: the deliberation machinery earns its complexity.
- **B ≈ C** (neither beats the other by the sign-test margin) →
  **CUT TO MINIMAL CORE**: model diversity may be real but multi-round deliberation is not;
  remove voting, lexical consensus, panic mode, convergence loops, capability weighting.
- **B < A** →
  **CODEX VINDICATED**: the machinery subtracts value.

A result resting on a grader below the 90% agreement gate is **inconclusive** regardless of which
branch the numbers point to.

## Secondary metric (reported, does not drive the primary decision)

Does arm-B consensus % predict when arm A is wrong? Compare mean arm-B `consensus_score` on the
items A got right vs the items A got wrong. If consensus is meaningfully lower when A is wrong,
the panel is worth keeping as an **uncertainty meter** even under a B ≈ C or B < A primary result.

## What this experiment does NOT do

- It does not cut, keep, or change any machinery. It produces the data; the decision is taken
  afterward, on the data.
- It does not settle the personas question (Codex: cut; Fable: keep). That is inferred, weakly,
  from whether arm C's diverse samples beat nothing — not decided here.

---

_Frozen: fill the date and the commit hash of this file at freeze time before the first run._
_Grader model chosen: ______________ (record here before freezing)._
