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
  "version": "1.1",
  "default_score": 5,
  "general_score": 8,
  "capability_default": 5,
  "known_consultants": ["Gemini", "Codex", "..."],
  "categories": {
    "CODE_REVIEW": { "Gemini": 7, "Codex": 10, "..." },
    "BUG_DEBUG":   { "..." }
  },
  "capabilities": {
    "Gemini": { "intelligence": 8, "taste": 8, "cost": 6 },
    "Codex":  { "intelligence": 8, "taste": 5, "cost": 4 }
  },
  "category_axis": {
    "API_DESIGN": "taste", "CODE_REVIEW": "taste", "ALGORITHM": "intelligence"
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

## Capability-Aware Routing & Voting (v2.20+)

Beyond category *fit* (the affinity matrix), v1.1 of `affinity.json` adds a
per-consultant **capability** score on three axes (1-10): `intelligence`,
`taste`, and `cost`. A `category_axis` map names the quality axis each category
stresses — **taste** for design-shaped work (API_DESIGN, ARCHITECTURE,
CODE_REVIEW, GENERAL), **intelligence** otherwise.

Two opt-in features consume this:

- **`ENABLE_CAPABILITY_WEIGHTING`** — a consultant's vote weight becomes
  `confidence × (S + capability) / S` (`S = CAPABILITY_WEIGHT_STRENGTH`, default
  10), so on a taste-shaped question a high-taste model's opinion counts for more.
- **`ENABLE_CAPABILITY_ROUTING`** — panel *eligibility* still uses raw affinity,
  but the *sort rank* becomes `affinity + (capability − CAPABILITY_DEFAULT)`, so
  under a size limit the quality axis reorders which eligible consultants make
  the cut.

`cost` is an efficiency axis for budget-aware composition only — **never** a
vote weight (tie-break order: intelligence > taste > cost). Scores are
subjective, point-in-time seeds — re-derive them for your own panel. Helpers:
`get_capability <consultant> <axis>` and `get_category_axis <category>` in
`lib/routing.sh`.

## Roster Audit — Uncorrelated Value (v2.20+)

Adding a consultant only helps if it says something the others don't. The
`scripts/roster_audit.sh` tool measures this across past consultations: a
consultant's approach is *distinct* in a round when its keyword set has low
Jaccard overlap (`< --threshold`, default 20%) with **every** other consultant
that round. A consultant that is rarely distinct is correlated with the panel —
a candidate to drop or down-weight; one that is often distinct earns its seat on
diversity.

```bash
# audit specific consultation output dirs
./scripts/roster_audit.sh /path/to/consultation_dir ...

# or the N most recent under the consultations base
./scripts/roster_audit.sh --recent 30

# machine-readable
./scripts/roster_audit.sh --json --recent 30
```

Read-only; reuses the `voting.sh` keyword/Jaccard machinery. Consultations with
fewer than two responders are skipped (correlation is undefined). This is the
model-routing "before a new model earns a row" bar (contribute >=1 thing the
incumbents miss) applied to the consultation panel instead of a review lane.

## Measured Calibration — Replacing the Heuristic Seeds (v2.20+)

The `capabilities` scores in `affinity.json` ship as subjective seeds. To
**measure** them instead of guessing, three tools derive each axis from data the
tool already produces — sliced by the same `category_axis` that consumes them:

| Tool | Derives | From |
|---|---|---|
| `scripts/roster_calibrate.sh` | intelligence, taste, cost (**Tier A**) | blind peer-review scores (sliced by axis) + observed `tokens_used` × catalog rate |
| `scripts/taste_elo.sh` | taste (**Tier B**) | pairwise LLM-as-judge Elo over taste-axis answers (removes peer self-bias) |
| `references/calibration_benchmark.json` | the question set | 50 questions, 5 per category, balanced across the two axes |
| `scripts/run_calibration.sh` | the data | runs the benchmark through the panel with `ENABLE_PEER_REVIEW=true`, then calibrates |

### Workflow

```bash
# 1. Collect data: run the benchmark through the full panel (real calls — costs money).
./scripts/run_calibration.sh --limit 10 --dry-run   # preview
./scripts/run_calibration.sh                         # full 50-question run

# 2. Tier A: measured intelligence/taste/cost -> capabilities block
./scripts/roster_calibrate.sh --recent 50            # print measured block
./scripts/roster_calibrate.sh --recent 50 --write    # merge into affinity.json (keeps unmeasured cells)

# 3. Tier B (optional): refine taste via pairwise-judge Elo
./scripts/taste_elo.sh --recent 50 --write
```

Both `roster_calibrate.sh` and `taste_elo.sh` also accept explicit consultation
dirs and `--json`, and back up `affinity.json` to `.bak` before `--write`.

### How each axis is measured

- **cost** — mean *observed* `$/response` (`tokens_used` × catalog rate, 60/40
  input/output split), rank-normalized so the cheapest = 10. This is cost per
  *task* (verbosity + completion), not per-token sticker price — a terse pricey
  model can still rank cheap.
- **intelligence / taste** — mean **blind peer-review** `quality_score` (already
  1-10), sliced by `category_axis`: intelligence = performance on
  intelligence-axis categories, taste = on taste-axis categories.
- **taste (Tier B)** — taste has no ground truth, so `taste_elo.sh` measures it
  *relative to a chosen judge*. Each pair of answers on a taste-axis question is
  shown to the judge, which picks the better one on design taste only; wins feed
  an Elo ranking. The judge is pluggable:
  - `JUDGE_CLI` — CLI for the built-in judge (default `claude`).
  - `TASTE_JUDGE_CMD` — external judge `cmd <ctx> <A.json> <B.json>` printing
    `A`/`B` (used by tests and custom judges).

### Companion: which consultants earn a seat

`roster_audit.sh` (above) answers *who to keep*; calibration answers *how much
each is worth per axis*. Together they make the roster data-driven: audit to
prune redundant consultants, calibrate to score the survivors, then enable
`ENABLE_CAPABILITY_WEIGHTING` / `ENABLE_CAPABILITY_ROUTING` to act on the
measured scores.

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
