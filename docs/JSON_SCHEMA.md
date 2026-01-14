# JSON Schema - AI Consultants v2.0

This document describes the JSON schema used for consultant responses.

## Complete Schema

The schema is defined in `scripts/lib/schema.json` following JSON Schema Draft-07.

## Response Structure

```json
{
  "consultant": "Gemini",
  "model": "gemini-2.5-pro",
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
    "references": [...]
  },
  "confidence": {
    "score": 8,
    "reasoning": "Reasoning for the score",
    "uncertainty_factors": [...]
  },
  "debate": {...},
  "metadata": {
    "tokens_used": 1500,
    "latency_ms": 2345,
    "model_version": "gemini-2.5-pro",
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

## Debate Object

Present only if Multi-Agent Debate is enabled (round >= 2):

```json
{
  "debate": {
    "round": 2,
    "position_changed": true,
    "critiques": [
      {
        "target": "Codex",
        "critique": "The proposed approach does not consider edge case X",
        "severity": "moderate"
      }
    ],
    "incorporated_from": [
      {
        "source": "Mistral",
        "idea": "Added input validation"
      }
    ]
  }
}
```

### Debate Fields

| Field | Type | Description |
|-------|------|-------------|
| `round` | integer | Current round (1, 2, 3) |
| `position_changed` | boolean | Whether position has changed |
| `critiques` | array | Critiques of other consultants |
| `critiques[].target` | string | Criticized consultant |
| `critiques[].critique` | string | Critique text |
| `critiques[].severity` | enum | minor, moderate, major |
| `incorporated_from` | array | Incorporated ideas |
| `incorporated_from[].source` | string | Source of the idea |
| `incorporated_from[].idea` | string | Description of the idea |

## Metadata Object

```json
{
  "metadata": {
    "tokens_used": 1500,
    "latency_ms": 2345,
    "model_version": "gemini-2.5-pro",
    "timestamp": "2024-01-14T12:34:56Z"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `tokens_used` | integer | Tokens consumed (estimate) |
| `latency_ms` | integer | Response time in ms |
| `model_version` | string | Exact model version |
| `timestamp` | string | ISO 8601 timestamp |

## Enum Values

### consultant

```
"Gemini" | "Codex" | "Mistral" | "Kilo"
```

### persona

```
"The Architect" | "The Pragmatist" | "The Devil's Advocate" | "The Innovator"
```

### critiques[].severity

```
"minor" | "moderate" | "major"
```

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
  "model": "gemini-2.5-pro",
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
    "latency_ms": 1850,
    "model_version": "gemini-2.5-pro",
    "timestamp": "2024-01-14T12:34:56Z"
  }
}
```
