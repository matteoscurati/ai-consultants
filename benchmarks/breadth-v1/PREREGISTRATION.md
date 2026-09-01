# Breadth v1 binding preregistration

Status: **frozen before any binding dispatch**. The expected corpus content
hash and manifest hash are in `manifest.json`. Any drift voids a run.

## Question set and withheld material

There are exactly 30 real held-out items: 10 `security`, 10
`architecture-risk`, and 10 `operational-failure-mode`. Each private item has
an atomic, deep rubric and primary-source references. The private corpus is not
committed or packed. The public manifest contains only IDs, category, source
metadata and item hashes.

## Frozen arms and judge

| Arm | Exact roster | Calls/item |
|---|---|---:|
| A | Gemini CLI `Gemini 3.7 Flash (High)`, high, one-shot | 1 |
| B | Gemini CLI `Gemini 3.7 Flash (High)`, high, self-consistency | 9 |
| C | Gemini + Mistral Vibe CLI `mistral-medium-3.5` (`native/default`) | 2 |
| D | Gemini + Mistral Vibe + Kimi CLI `kimi-code/k3` (`native/default`) | 3 |
| E | Frozen exact nine-family roster in `manifest.json`; native/default where transport has no effort control | 9 |
| Judge | Codex `gpt-5.6-sol`, effort `high`, one structured joint grading call | 1 |

Codex is excluded from every primary arm. There is no fallback model, model
substitution, provider preflight, health request, or separate synthesis call.
All source normalization and arm synthesis is deterministic local work; the
judge receives all arm results together.

The exact adapter bridge is deliberately not live-ready by default:
provider-backed model, effort, transport, billing and pricing evidence has not
yet been supplied. No actionable confirmation receipt is issued until a fresh,
hash-bound evidence file covers the complete premium roster and schedule.

## Binding limits and decision gate

Primary dispatches: `(1 + 9 + 2 + 3 + 9) * 30 = 720`; judge dispatches:
`30`; total planned dispatches: **750**. Hard limits are 750 dispatch attempts
(including retry), USD 150 countable cost, and 24 elapsed hours. One
preregistered transient retry is permitted only for an incomplete transient
failure. Since planned work is already 750, a retry makes the run incomplete;
the harness records this instead of skipping or exceeding a cap. No retry is
allowed for identity, schema, or judge-validity failure.

A binding claim requires all 30 items, the exact 750 planned call IDs, zero
retry/incomplete/orphan records, exact provider-backed
requested/effective/billing identities, valid structured judges, integer-cent
accounting within USD 150, completion within 24 hours, frozen hashes, and a
separate manual-audit gate. The audit binds the evidence, deterministic record
set and analysis hashes. Otherwise the result is negative or inconclusive,
never binding.

Primary outcomes: rubric recall, precision, high-severity capture, unique
consultant contribution, and source-ID retention. Secondary evidence records
per-item/arm measured or estimated token/cost/latency. Results must explicitly
identify unavailable pricing as unpriced rather than pretending it is zero.
