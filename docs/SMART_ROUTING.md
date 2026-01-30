# Smart Routing - AI Consultants v2.8

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

Consultant-category affinity scores (scale 1-10):

| Category | Gemini | Codex | Mistral | Kilo | Cursor | Aider | Amp | Claude | Qwen3 | GLM | Grok | DeepSeek | Ollama |
|----------|--------|-------|---------|------|--------|-------|-----|--------|-------|-----|------|----------|--------|
| **CODE_REVIEW** | 7 | **10** | 8 | 9 | 8 | 9 | 7 | 8 | 7 | 7 | 6 | 8 | 6 |
| **BUG_DEBUG** | 7 | **10** | 9 | 8 | 8 | 9 | 7 | 7 | 7 | 6 | 6 | 8 | 6 |
| **ARCHITECTURE** | **10** | 6 | 8 | 9 | 7 | 6 | **10** | 9 | 7 | 7 | 7 | 6 | 5 |
| **ALGORITHM** | 9 | 8 | 7 | 8 | 7 | 7 | 7 | 8 | 8 | 8 | 7 | **10** | 6 |
| **SECURITY** | 9 | 9 | **10** | 8 | 8 | 7 | 8 | 9 | 7 | 7 | 8 | 7 | 5 |
| **QUICK_SYNTAX** | **10** | 8 | 5 | 6 | 7 | 7 | 5 | 7 | 7 | 6 | 5 | 7 | 6 |
| **DATABASE** | 8 | 9 | 7 | 7 | 7 | 7 | 7 | 7 | 8 | 7 | 6 | 8 | 5 |
| **API_DESIGN** | **10** | 9 | 7 | 8 | 8 | 6 | 9 | 8 | 7 | 7 | 7 | 6 | 5 |
| **TESTING** | 7 | **10** | 9 | 7 | 8 | 9 | 7 | 7 | 7 | 7 | 6 | 7 | 5 |
| **GENERAL** | 8 | 8 | 8 | 8 | 8 | 8 | 8 | 9 | 8 | 7 | 8 | 8 | 7 |

**Legend:**
- **10**: Perfect match
- 7-9: Good match
- 5-6: Medium match
- 1-4: Poor match

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
