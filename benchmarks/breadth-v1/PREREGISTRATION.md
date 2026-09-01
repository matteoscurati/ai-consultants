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
| A | Gemini `gemini-3.7-flash`, High, one-shot | 1 |
| B | Gemini `gemini-3.7-flash`, High, self-consistency | 9 |
| C | Gemini `gemini-3.7-flash`, High + Mistral premium | 2 |
| D | Gemini `gemini-3.7-flash`, High + Mistral premium + Kimi premium | 3 |
| E | Gemini, Mistral, Kimi, Claude, Qwen, GLM, Grok, DeepSeek, MiniMax (premium-equivalent) | 9 |
| Judge | Codex `gpt-5.6-sol`, effort `high`, one structured joint grading call | 1 |

Codex is excluded from every primary arm. There is no fallback model, model
substitution, provider preflight, health request, or separate synthesis call.
All source normalization and arm synthesis is deterministic local work; the
judge receives all arm results together.

## Binding limits and decision gate

Primary dispatches: `(1 + 9 + 2 + 3 + 9) * 30 = 720`; judge dispatches:
`30`; total planned dispatches: **750**. Hard limits are 750 dispatch attempts
(including retry), USD 150 countable cost, and 24 elapsed hours. One
preregistered transient retry is permitted only for an incomplete transient
failure. Since planned work is already 750, a retry makes the run incomplete;
the harness records this instead of skipping or exceeding a cap. No retry is
allowed for identity, schema, or judge-validity failure.

A binding claim requires all 30 items, exactly 750 planned calls, zero
cap-consuming retries, exact requested/effective/billing identities, valid
structured judges, frozen hashes, and a separate manual-audit gate. Otherwise
the result is negative or inconclusive, never binding.

Primary outcomes: rubric recall, precision, high-severity capture, unique
consultant contribution, and source-ID retention. Secondary evidence records
per-item/arm measured or estimated token/cost/latency. Results must explicitly
identify unavailable pricing as unpriced rather than pretending it is zero.
