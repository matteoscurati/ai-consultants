# AI Consultants JSON Contracts

Two JSON contracts are written for every consultation, both defined in
`scripts/lib/schema.json` (JSON Schema draft-07):

- **Consultant envelope** (`<consultant>.json`) — the schema's root.
- **Synthesis artifact** (`synthesis.json`) — `definitions.synthesis_artifact`.

The schema is executable: `scripts/lib/json_schema_check.jq` checks a document
against it with `jq` alone, and the test suites run it on every envelope and
synthesis shape the runtime can produce.

```bash
# Consultant envelope
jq -n --slurpfile schema scripts/lib/schema.json --slurpfile doc gemini.json \
  -f scripts/lib/json_schema_check.jq
# Synthesis artifact
jq -n --slurpfile schema scripts/lib/schema.json --slurpfile doc synthesis.json \
  --arg definition synthesis_artifact -f scripts/lib/json_schema_check.jq
```

The output is an array of errors; `[]` means the document conforms. (Any
draft-07 validator, e.g. `jsonschema`, works too.)

## Consultant Envelope

Every consultant file has the same outer shape, whatever happened:

| `metadata.response_quality` | Meaning | `confidence.score` |
|---|---|---|
| `structured` | The answer satisfied the JSON contract (after canonicalization) | 1-10, from the consultant |
| `fallback` | Usable prose outside the contract; kept as context, never as attributed coverage | synthetic 5 |
| `error` | The query failed, or the answer was malformed/truncated/schema-invalid | 0 |

```json
{
  "consultant": "Gemini",
  "model": "Gemini 4 Argon (High)",
  "persona": "The Architect",
  "response": {
    "summary": "TL;DR in 2-3 sentences",
    "detailed": "Complete response",
    "approach": "Name of the proposed approach",
    "pros": ["..."],
    "cons": ["..."],
    "alternatives": [{"name": "...", "reason_not_chosen": "..."}],
    "caveats": ["..."],
    "references": ["..."],
    "code_snippets": [{"language": "python", "code": "...", "description": "..."}],
    "findings": [{"id": "gemini:1", "kind": "summary", "field": "summary", "text": "..."}]
  },
  "confidence": {"score": 8, "reasoning": "...", "uncertainty_factors": ["..."]},
  "metadata": {
    "tokens_used": 1500,
    "tokens_source": "estimated",
    "tokens_input": 1200,
    "tokens_output": 300,
    "latency_ms": 2345,
    "model_version": "Gemini 4 Argon (High)",
    "requested_model": "Gemini 4 Argon (High)",
    "model_identity_source": "capability-probed",
    "response_quality": "structured",
    "timestamp": "2026-09-29T12:34:56+02:00"
  }
}
```

### Required fields

| Field | Type | Notes |
|-------|------|-------|
| `consultant` | string | A roster name or a custom API agent name |
| `model` | string | Best effective model identifier |
| `persona` | string | Catalog persona name, `{AGENT}_PERSONA_NAME`, `Custom Persona`, or `External Consultant` |
| `response.summary` | string | May be blank (then it yields no summary finding) |
| `response.detailed` | string | Never atomized into coverage findings |
| `response.approach` | string | `unspecified` when not given; `unstructured-provider-response` for fallback; `error` for failures |
| `confidence.score` | integer 0-10 | See the table above |
| `confidence.reasoning` | string | |
| `metadata.*` | | `tokens_used`, `tokens_source`, `latency_ms`, `model_version`, `requested_model`, `model_identity_source`, `response_quality`, `timestamp` |

`pros`, `cons`, `caveats`, `references` and `confidence.uncertainty_factors`
are arrays of strings; `alternatives` items are strings or
`{name, reason_not_chosen}` objects.

### How a provider answer becomes an envelope

Consultants are asked (persona + shared output contract in
`scripts/lib/personas.sh`) to reply with
`{"response": {...}, "confidence": {...}}`. The raw answer then goes through
`normalize_consultant_response_text` (`scripts/lib/common.sh`):

1. A Markdown fence is removed and JSON string wrappers are decoded.
2. A parsed object is canonicalized by `scripts/lib/response_canonicalize.jq`,
   which applies only deterministic, content-preserving repairs of shapes
   observed from providers:
   - a single wrapper key around the answer (`{"answer": {...}}`);
   - a flat answer without the `response` object;
   - `confidence` nested inside `response`, or given as a bare number/string;
   - a score given as `"8/10"`, a 0-1 fraction, a 0-100 percentage, or a word
     (`very low|low|medium|moderate|high|very high`);
   - list fields given as one string or with non-string items.
   `summary` is never derived from `detailed`.
3. The one-brace-short form observed from GLM 5.3 Flash (`confidence` opened
   inside `response`, outer object never closed) is repaired only in that
   exact shape.
4. An answer object embedded in prose is accepted when the span from the
   first `{` to the last `}` parses and canonicalizes; an incidental JSON
   example inside a prose answer keeps the prose fallback.
5. `{"response": "<prose>"}` becomes a `fallback` envelope.

Everything else that looks like JSON but cannot be canonicalized — missing
`summary` or confidence, truncated or malformed text (also when pretty-printed
over several lines), or more than one JSON value — fails closed as an `error`
envelope with `metadata.raw_excerpt` (the first 2000 characters of the rejected
answer). "Looks like JSON" means the first non-blank character opens an object,
or opens an array of values; prose that merely starts with `[` (such as
`[Note] ...`) is prose. Plain prose becomes a `fallback` envelope.

### Metadata

| Field | Type | Description |
|-------|------|-------------|
| `tokens_used` | integer | Tokens consumed; read `tokens_source` before treating it as exact |
| `tokens_source` | string | `measured` (provider usage: API, Claude CLI, Codex CLI telemetry) \| `estimated` (local 4-chars-per-token) \| `unknown` |
| `tokens_input` / `tokens_output` | integer | Split of `tokens_used` (measured or estimated); prefer it over re-splitting the total |
| `tokens_cached_input` | integer | Cached subset of `tokens_input` (Codex CLI); not added again |
| `provider_cost_usd` | number | Provider-reported cost (Claude CLI); preferred over any estimate |
| `billing_models` | array | Billing participants (Claude CLI); not content-model attestation |
| `cost_source` / `cost_note` | string | Codex estimate provenance and limitations |
| `latency_ms` | integer | Response time in ms |
| `model_version` | string | Best effective model identifier |
| `requested_model` | string | Model requested before provider resolution |
| `model_identity_source` | string | `provider-reported` \| `capability-probed` \| `requested-only` |
| `response_quality` | string | `structured` \| `fallback` \| `error` \| `unknown` |
| `error` | string | Failure reason (error envelopes) |
| `raw_excerpt` | string | First 2000 characters of a rejected answer |
| `transport` | string | `cli` \| `api` \| `api_fallback` (Grok) |
| `cli_version` / `cli_compatibility` | string | CLI provenance; compatibility is capability-probed, never version-gated |
| `timestamp` | string | ISO 8601 |

A response replayed from the semantic cache also carries
`cache_metadata: {cached_at, fingerprint, from_cache}`.

### `response.findings`

`findings` is added locally by the synthesis stage to successful consultant
responses. It never trusts provider-supplied IDs. Each item has a
deterministic local `id` of `<consultant-slug>:<one-based-index>`, plus
`kind`, source `field`, and the atomically attributable `text`. The shared
slug rule ASCII-lowercases the consultant name, retains `[a-z0-9_]`, replaces
other runs with `_`, trims edge underscores, and uses `unknown` if empty
(`My_agent` -> `my_agent:1`).

Findings are derived only from `summary`, `pros`, `cons`, `alternatives`,
`caveats`, and `references`. Fallback prose and successful envelopes with zero
atomic findings are kept for human review but are non-normalizable; neither
can be presented as audited coverage. Error envelopes are excluded from
synthesis.

## Synthesis Artifact

`synthesis.json` is canonicalized by `scripts/lib/synthesis_canonicalize.jq`
before and after the local integrity audit:

| Field | Type | Source |
|-------|------|--------|
| `synthesis_version` | string | model or local fallback |
| `timestamp` | string | **local** |
| `strategy` | string | **local** (the selected strategy) |
| `consultants_analyzed` | integer | **local** (successful responses) |
| `coverage` | array of `synthesis_coverage_item` | model; audited locally |
| `weighted_recommendation` | `{approach, summary, detailed, supporting_consultants[], incorporated_insights[]}` | model (a bare string becomes `summary`) |
| `risk_assessment` | `{overall_risk, risks[{description, severity, mitigation, identified_by[]}]}` | model; levels normalized to `low\|medium\|high\|unknown` |
| `action_items` | `[{priority, action, rationale}]` | model; strings become items, priorities become integers |
| `follow_up_questions` | array of strings | model |
| `coverage_integrity` | object | **local** audit (below) |
| `coverage_input_truncated`, `truncated_consultants` | boolean, array | **local** |
| `synthesis_provider` | string | **local**: `claude`, `gemini`, `codex`, or `local-fallback` |
| `synthesis_metadata` | object | **local** estimate of the synthesis call (billed into the session cost) |

Under a non-coverage strategy a missing `coverage` list becomes `[]`; under
`coverage`/`union` a non-array `coverage` is a structural failure.

### Coverage attribution and integrity

Each synthesized `coverage` item requires `source_ids`, containing only local
IDs from normalized findings. `scripts/lib/schema.json` defines this as
`definitions.synthesis_coverage_item`; the model prompt requests it, but the
local post-check is authoritative.

Every synthesis includes `coverage_integrity`:

| Status | Meaning |
|-------|---------|
| `MET` | Every expected normalized source ID appears exactly once, with at least one expected ID and no non-normalizable success. It applies only to the audited fields. |
| `DEGRADED` | A coverage-union source is missing or duplicated, no atomic source exists, or a successful response is non-normalizable. It is never comprehensive. |
| `FAILED` | Coverage/source attribution is structurally unusable or includes an invented source ID; do not rely on coverage. |
| `NOT_APPLICABLE` | A non-coverage strategy was selected and no attribution failure was found; it makes no coverage-union claim. |

The object contains `expected_count`, `represented_count`, `missing_ids`,
`unknown_ids`, `duplicate_ids`, `non_normalizable_consultants`,
`structural_errors`, `audited_fields`, and `normalization_version`.
`represented_count` is the count of unique expected IDs actually represented;
unknown and duplicate IDs cannot inflate it. In coverage/union mode only
`audited_fields` reach the attributable prompt. Structured `detailed` text and
fallback prose are not atomized; fallback text is context-only and must never
produce coverage items or source IDs.

Every synthesis artifact also carries locally authoritative
`coverage_input_truncated` (boolean) and `truncated_consultants` (a stable,
first-occurrence-unique array of consultant names discovered in lexically
ordered response-file order). These fields overwrite any values supplied by a
model and are present even on local fallback or failed-closed artifacts.
`SYNTH_DETAIL_MAX_CHARS` applies only to usable, non-normalizable fallback
context, never to normalized finding text. Its unit is Unicode code points:
input with exactly the limit is retained and does not set the flag; only input
with more code points is shortened to that limit, preserving complete
multibyte UTF-8 characters. When such context is truncated, coverage/union is
at least `DEGRADED` and its disclosure names the affected consultants; it is
never a comprehensive claim. A non-coverage strategy can remain
`NOT_APPLICABLE`, but still exposes this metadata and disclosure.

## Confidence Score Guidelines

| Score | Meaning |
|-------|---------|
| 9-10 | Very confident, standard solution |
| 7-8 | Confident, with minor uncertainties |
| 5-6 | Moderately confident |
| 3-4 | Uncertain, requires verification |
| 1-2 | Very uncertain, hypothesis |

### Codex cost and cached-input metadata

When present, `metadata.cost_source` is `unavailable` without token data, otherwise
`estimated-standard-rates` or `estimated-long-context-standard-rates`.
`metadata.cost_note` discloses excluded cache/service adjustments; an estimate
is not a provider invoice. `metadata.tokens_cached_input`, when supplied by
CLI telemetry, is the cached subset of `tokens_input` and is not added again.
Unknown splits use the documented estimation heuristic; they cannot establish
an exact long-context bill. GPT-6.1 Sol (default/premium) and GPT-6 Astra (maximum) use `high` by default,
including in max_quality; valid explicit Codex effort always takes precedence.

### Claude streaming billing metadata

`metadata.billing_models` is an optional array of provider billing model IDs.
It does not attest the content model. Claude content identity comes only from
response-bearing assistant events; successful terminal completion is a separate
requirement. `provider_cost_usd`, when present, is the provider's terminal cost.
Token accounting prefers a supplied per-model billing aggregate over terminal
usage, without adding those two summaries together; absent usage is estimated.
