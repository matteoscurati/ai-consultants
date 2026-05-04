# Smart Routing - AI Consultants v2.11

The Smart Routing system automatically selects the most suitable consultants based on the question category.

## Enabling

```bash
# Enable classification (required)
ENABLE_CLASSIFICATION=true

# Enable smart routing
ENABLE_SMART_ROUTING=true

# Minimum affinity to include a consultant (1-10)
MIN_AFFINITY=7
```

## Affinity Matrix

Consultant-category affinity scores (scale 1-10) live in
[`references/affinity.json`](../references/affinity.json) — the single source
of truth at runtime. Prior to v2.11.0 the matrix was hard-coded as nested
case statements in `scripts/lib/routing.sh`; it was extracted to JSON to make
customization possible without editing bash.

**Highlights from the default matrix:**

| Category | Best match | Why |
|----------|-----------|-----|
| CODE_REVIEW | Codex (10), DeepSeek (10) | Code-specialist personas |
| BUG_DEBUG | Codex (10) | Pragmatic debugger |
| ARCHITECTURE | Gemini (10), Amp (10) | Big-picture design |
| ALGORITHM | DeepSeek (10) | Algorithm specialist |
| SECURITY | Mistral (10) | Devil's Advocate persona |
| QUICK_SYNTAX | Gemini (10) | Fast turnaround |
| API_DESIGN | Gemini (10) | API/system design |
| TESTING | Codex (10), GLM (10) | Test generation |

**Legend:**
- **10**: Perfect match
- 7-9: Good match
- 5-6: Medium match
- 1-4: Poor match

### Schema

```json
{
  "version": "1.0",
  "default_score": 5,
  "general_score": 8,
  "known_consultants": ["Gemini", "Codex", "..."],
  "categories": {
    "CODE_REVIEW": { "Gemini": 7, "Codex": 10, "..." },
    "BUG_DEBUG":   { "..." }
  }
}
```

Lookup logic in `get_affinity(category, consultant)`:

1. If `consultant` is not in `known_consultants` → `default_score`
2. Else if `category` is not in `categories` (e.g. `GENERAL` or unrecognized) → `general_score`
3. Else → `categories[category][consultant]`, falling back to `default_score` if missing

### Custom Matrix Override

Override the matrix at runtime by pointing `AFFINITY_FILE` at a custom JSON
file with the same schema:

```bash
AFFINITY_FILE=~/my-affinity.json ./scripts/consult_all.sh "your question"
```

This is useful for:
- Tweaking scores for a specific project (e.g., favoring DeepSeek for
  algorithm-heavy codebases)
- Disabling consultants for a category by setting their score below
  `MIN_AFFINITY`
- Experimenting with new categories before upstreaming them

`./scripts/doctor.sh` validates the JSON schema and reports coverage gaps
(consultants missing from a category).

The matrix is loaded once per shell and cached in memory — no jq overhead
on subsequent calls.

## Routing Modes

The system automatically determines how many consultants to involve:

| Mode | Consultants | Categories | Rationale |
|------|-------------|------------|-----------|
| **full** | All enabled | SECURITY, GENERAL | All for complete perspectives |
| **selective** | Top 5 by affinity | CODE_REVIEW, BUG_DEBUG, ARCHITECTURE, ALGORITHM, DATABASE, API_DESIGN, TESTING | Best matches for the category |
| **single** | 1 | QUICK_SYNTAX | Only the best for quick answers |

### Selection Logic

```
SECURITY      → full (all)     # Too important to exclude anyone
QUICK_SYNTAX  → single (1)    # A quick answer is sufficient
CODE_REVIEW   → selective (5) # Top 5 by affinity
BUG_DEBUG     → selective (5)
ARCHITECTURE  → selective (5)
*             → full (all)    # Default: all enabled
```

## Cost-Aware Routing (v2.3+)

When `ENABLE_COST_AWARE_ROUTING=true`, the system routes queries to cheaper models based on complexity:

```bash
ENABLE_COST_AWARE_ROUTING=true
COMPLEXITY_THRESHOLD_SIMPLE=3    # Score 1-3 = use economy models
COMPLEXITY_THRESHOLD_MEDIUM=6    # Score 4-6 = use standard models
                                 # Score 7-10 = use premium models
```

See [COST_RATES.md](COST_RATES.md) for model pricing by tier.

## Timeout per Category

Timeouts optimized based on category complexity:

| Category | Timeout | Rationale |
|----------|---------|-----------|
| QUICK_SYNTAX | 60s | Short answers |
| DATABASE | 120s | Medium-complexity queries |
| TESTING | 120s | Test case generation |
| CODE_REVIEW | 180s | Detailed analysis |
| BUG_DEBUG | 180s | Investigation |
| ALGORITHM | 180s | Reasoning |
| API_DESIGN | 180s | Detailed design |
| GENERAL | 180s | Default |
| ARCHITECTURE | 240s | Complex design |
| SECURITY | 240s | In-depth analysis |

## Supported Categories

### CODE_REVIEW
- Code quality review
- Best practices
- Code style

**Keywords:** review, quality, refactor, clean code

### BUG_DEBUG
- Debugging
- Error fixing
- Troubleshooting

**Keywords:** bug, error, crash, fix, debug, problem

### ARCHITECTURE
- System design
- Design patterns
- Scalability

**Keywords:** architect, design, pattern, microservic, scalabil, structur

### ALGORITHM
- Algorithms
- Data structures
- Complexity

**Keywords:** algorithm, complexity, O(n), recursive, sort, search, structur

### SECURITY
- Vulnerabilities
- Authentication
- Authorization

**Keywords:** security, vulnerabil, injection, XSS, auth

### QUICK_SYNTAX
- Quick syntax
- Fast how-tos
- Snippets

**Keywords:** how to, syntax, example, snippet

### DATABASE
- SQL queries
- Schema design
- DB optimization

**Keywords:** SQL, database, query, schema, index, join

### API_DESIGN
- REST API
- GraphQL
- Endpoint design

**Keywords:** API, REST, endpoint, GraphQL, HTTP

### TESTING
- Unit test
- Integration test
- Test strategy

**Keywords:** test, unit, integration, mock, coverage

### GENERAL
- Default for everything else

## Classification Modes

### Pattern-based (default)

```bash
CLASSIFICATION_MODE=pattern
```

- Fast, no API call
- Regex matching on keywords
- Good accuracy for clear questions

### LLM-based

```bash
CLASSIFICATION_MODE=llm
```

- More accurate
- Requires Claude CLI
- Falls back to pattern if Claude is unavailable

## Usage Example

```bash
# Consultation with smart routing
ENABLE_SMART_ROUTING=true \
./scripts/consult_all.sh "How can I improve the security of my API?"

# Output:
# [INFO] Category: SECURITY
# [INFO] Routing mode: full (all enabled consultants)
# [INFO] Timeout: 240s
```

## API Functions

Functions are exported from `scripts/lib/routing.sh`:

```bash
source scripts/lib/routing.sh

# Get affinity
get_affinity "SECURITY" "Mistral"  # → 10

# Select consultants
select_consultants "SECURITY" 7    # → All enabled consultants

# Check recommendation
is_recommended "SECURITY" "Kilo" 7 && echo "Recommended"

# Get timeout
get_category_timeout "ARCHITECTURE"  # → 240

# Get routing mode
get_routing_mode "QUICK_SYNTAX"      # → single

# Cost-aware selection (v2.3)
select_consultants_cost_aware "QUICK_SYNTAX" 7  # → Economy model selection
```
