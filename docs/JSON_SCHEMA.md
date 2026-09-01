# AI Consultants JSON Schema

This document describes the JSON schema used for consultant responses.

## Complete Schema

The schema is defined in `scripts/lib/schema.json` following JSON Schema Draft-07.

## Response Structure

```json
{
  "consultant": "Gemini",
  "model": "Gemini 3.7 Flash (High)",
  "persona": "The Architect",
  "response": {
    "summary": "TL;DR in 2-3 sentences (max 500 characters)",
    "detailed": "Complete and detailed response",
    "approach": "Name of the proposed approach",
    "code_snippets": [...],
    "pros": [...],
    "cons": [...],
    "alternatives": [...],
    "caveats": [...],
    "references": [...],
    "findings": [
      {"id": "gemini:1", "kind": "summary", "field": "summary", "text": "..."}
    ]
  },
  "confidence": {
    "score": 8,
    "reasoning": "Reasoning for the score",
    "uncertainty_factors": [...]
  },
  "metadata": {
    "tokens_used": 1500,
    "tokens_source": "measured",
    "tokens_input": 1200,
    "tokens_output": 300,
    "latency_ms": 2345,
    "model_version": "Gemini 3.7 Flash (High)",
    "requested_model": "Gemini 3.7 Flash (High)",
    "model_identity_source": "capability-probed",
    "cli_version": "0.27.0",
    "cli_compatibility": "capability-probed",
    "timestamp": "2024-01-14T12:34:56Z"
  }
}
```

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `consultant` | string | Consultant name |
| `response` | object | Response object |
| `response.summary` | string | TL;DR (max 500 char) |
| `response.detailed` | string | Complete response |
| `response.approach` | string | Approach name |
| `confidence` | object | Confidence object |
| `confidence.score` | integer | Score 1-10 |
| `confidence.reasoning` | string | Reasoning |
| `metadata` | object | Response metadata |

## Optional Fields

### response.findings

`findings` is added locally by the synthesis stage to successful consultant
responses. It preserves all legacy fields and never trusts provider-supplied
IDs. Each item has a deterministic local `id` of
`<consultant-slug>:<one-based-index>`, plus `kind`, source `field`, and the
atomically attributable `text`. The shared slug rule ASCII-lowercases the
consultant name, retains `[a-z0-9_]`, replaces other runs with `_`, trims edge
underscores, and uses `unknown` if empty. Thus the public custom name
`My_agent` has IDs such as `my_agent:1`.

The conservative normalization contract derives findings only from `summary`,
`pros`, `cons`, `alternatives`, `caveats`, and `references`; alternatives may
be meaningful strings or objects with meaningful name/reason text. Empty,
null, or whitespace alternatives create no finding. Free-form fallback prose
(`response_quality: fallback`) and successful envelopes with zero atomic
findings are retained for human review but are non-normalizable; neither can
be presented as audited coverage. Error envelopes remain excluded from
synthesis.

## Synthesis Coverage Attribution

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

### response.code_snippets

Array of code snippets:

```json
{
  "code_snippets": [
    {
      "language": "python",
      "code": "def hello():\n    print('Hello')",
      "description": "Example function"
    }
  ]
}
```

### response.pros / response.cons

Array of advantages and disadvantages:

```json
{
  "pros": [
    "Simple to implement",
    "Excellent performance"
  ],
  "cons": [
    "Requires more memory",
    "Maintenance complexity"
  ]
}
```

### response.alternatives

Array of considered alternatives:

```json
{
  "alternatives": [
    {
      "name": "Approach B",
      "reason_not_chosen": "Greater complexity without significant benefits"
    }
  ]
}
```

### response.caveats

Array of assumptions or limitations:

```json
{
  "caveats": [
    "Assumes Python 3.8+",
    "Not tested on Windows"
  ]
}
```

### response.references

Array of links or references:

```json
{
  "references": [
    "https://docs.python.org/3/library/...",
    "RFC 7231"
  ]
}
```

### confidence.uncertainty_factors

Factors that reduce confidence:

```json
{
  "uncertainty_factors": [
    "Limited context provided",
    "Depends on unspecified requirements"
  ]
}
```

## Metadata Object

```json
{
  "metadata": {
    "tokens_used": 1500,
    "tokens_source": "measured",
    "tokens_input": 1200,
    "tokens_output": 300,
    "latency_ms": 2345,
    "model_version": "gemini-3.1-pro-preview",
    "requested_model": "gemini-3.1-pro-preview",
    "model_identity_source": "provider-reported",
    "timestamp": "2024-01-14T12:34:56Z"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `tokens_used` | integer | Tokens consumed. Provider-reported in API mode; locally approximated in CLI mode |
| `tokens_source` | string | `measured` \| `estimated` \| `unknown` — how `tokens_used` was obtained |
| `tokens_input` | integer | Prompt tokens, when the provider reported them (API mode only) |
| `tokens_output` | integer | Completion tokens, when the provider reported them (API mode only) |
| `latency_ms` | integer | Response time in ms |
| `model_version` | string | Best effective model identifier available to the transport |
| `requested_model` | string | Model identifier requested before provider resolution |
| `model_identity_source` | string | `provider-reported` \| `capability-probed` \| `requested-only` |
| `response_quality` | string | `structured` \| `fallback` \| `error` \| `unknown` |
| `cli_version` | string | Observed CLI version for provenance; never a compatibility gate |
| `cli_compatibility` | string | Capability-probe result: `capability-probed` or `incompatible` |
| `timestamp` | string | ISO 8601 timestamp |

## Enum Values

### consultant

```
"Gemini" | "Codex" | "Mistral" | "Kimi" | "Claude" | "Qwen3" | "GLM" | "Grok" | "DeepSeek" | "MiniMax"
```

### persona

```
"The Architect" | "The Pragmatist" | "The Devil's Advocate" | "The Innovator" |
"The Integrator" | "The Pair Programmer" | "The Systems Thinker" | "The Eastern Sage" |
"The Synthesizer" | "The Analyst" | "The Methodologist" | "The Provocateur" |
"The Code Specialist" | "The Pragmatic Optimizer" | "The Local Expert"
```

### critiques[].severity

```
"minor" | "moderate" | "major"
```

### metadata.tokens_source

```
"measured" | "estimated" | "unknown"
```

- `measured` — the provider's own usage figures, available in API mode.
- `estimated` — a local 4-chars-per-token approximation over prompt + reply.
  CLI-backed consultants report no token counts, so this is what they get; it
  is the majority case, since CLI is the default transport.
- `unknown` — not recorded (error responses, and callers on the pre-v2.25.0
  metadata signature).

When `tokens_input`/`tokens_output` are present, price on those rather than
splitting `tokens_used`: output rates run several times input rates and
consultations are large-context/short-reply, so a fixed split overstates cost
substantially.

Consumers that add up cost should read this field: a total built partly on
estimates is not a measurement. `consult_all.sh` discloses the split on its
session-cost line for that reason.

## Confidence Score Guidelines

| Score | Meaning |
|-------|---------|
| 9-10 | Very confident, standard solution |
| 7-8 | Confident, with minor uncertainties |
| 5-6 | Moderately confident |
| 3-4 | Uncertain, requires verification |
| 1-2 | Very uncertain, hypothesis |

## Validation

To validate an output against the schema:

```bash
# With jsonschema (Python)
pip install jsonschema
jsonschema -i output.json scripts/lib/schema.json

# With jq (verify required fields)
jq 'has("consultant") and has("response") and has("confidence")' output.json
```

## Complete Example

```json
{
  "consultant": "Gemini",
  "model": "gemini-3.1-pro-preview",
  "persona": "The Architect",
  "response": {
    "summary": "I recommend using a Repository pattern to separate data access logic from business logic, improving testability and maintainability.",
    "detailed": "The Repository pattern provides an abstraction between business logic and the persistence layer...",
    "approach": "Repository Pattern",
    "code_snippets": [
      {
        "language": "python",
        "code": "class UserRepository:\n    def __init__(self, db_session):\n        self.session = db_session\n    \n    def get_by_id(self, user_id: int) -> User:\n        return self.session.query(User).get(user_id)",
        "description": "Basic Repository implementation"
      }
    ],
    "pros": [
      "Better separation of concerns",
      "Facilitates testing with mocks",
      "Easily supports database switching"
    ],
    "cons": [
      "Adds an abstraction layer",
      "May seem like over-engineering for small projects"
    ],
    "alternatives": [
      {
        "name": "Active Record",
        "reason_not_chosen": "Greater coupling with the database"
      }
    ],
    "caveats": [
      "Requires dependency injection for tests"
    ],
    "references": [
      "https://martinfowler.com/eaaCatalog/repository.html"
    ]
  },
  "confidence": {
    "score": 8,
    "reasoning": "Well-established pattern with extensive documentation. Score not 9-10 because it depends on project complexity.",
    "uncertainty_factors": [
      "Project size is unknown"
    ]
  },
  "metadata": {
    "tokens_used": 1250,
    "tokens_source": "estimated",
    "latency_ms": 1850,
    "model_version": "gemini-3.1-pro-preview",
    "requested_model": "gemini-3.1-pro-preview",
    "model_identity_source": "requested-only",
    "timestamp": "2024-01-14T12:34:56Z"
  }
}
```
