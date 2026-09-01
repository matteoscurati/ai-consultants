# AI Consultants - Reference Details

Read this file when the user asks about presets, strategies, bash usage, best practices, or known limitations.

## Configuration Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions |
| `balanced` | 3 (+Mistral) | Standard use |
| `thorough` | 3 | Comprehensive |
| `high-stakes` | Expanded panel (4 of 10) | Critical decisions |
| `security` | Security-focused (3) | Security reviews |
| `cost-capped` | Budget-friendly | Low cost |
| `max_quality` | All 10, maximum tier and max effort | Critical decisions |
| `medium` | 3, standard models | General questions |
| `fast` | 2, economy models | Quick checks |

A preset chooses the consultant set + model tier, then uses only statically configured transports (a CLI on `PATH`, or selected API mode with its key). After host self-exclusion it fills canonical slots from `ALL_CONSULTANTS` in canonical order. If the effective target cannot be met, including after an enabled health gate prunes the panel, it stops with promised/selected/missing-capacity guidance rather than silently running fewer consultants. Configured custom API agents are appended and can satisfy capacity; a full canonical preset may therefore exceed its advertised count. `max_quality` remains advertised as 10, but has an effective target of 9 under a canonical invoking host because self-exclusion is fail-closed.

## Synthesis Strategies

| Strategy | Description |
|----------|-------------|
| `coverage` | Union of every distinct point across the panel (default) |
| `compare_only` | Present each consultant side-by-side, no synthesized union |
| `majority` | A single blended recommendation, weighting all equally |
| `risk_averse` | Weight conservative responses |
| `security_first` | Prioritize security |
| `cost_capped` | Prefer cheaper solutions |

## Bash Usage

```bash
cd ~/.claude/skills/ai-consultants

# With preset
./scripts/consult_all.sh --preset balanced "Best approach for caching?"

# With strategy
./scripts/consult_all.sh --strategy risk_averse "Security question"

# With file context — paths trigger AST optimization (v2.14+)
./scripts/consult_all.sh "Review the auth flow" src/auth.ts src/session.ts

# With relevance tags — PRIMARY = focus, CONTEXT = ambient reference
./scripts/consult_all.sh "Why does auth fail under load?" \
    src/auth.ts@PRIMARY src/cache.ts@CONTEXT

# With query loaded from file (for long/awkwardly-quoted questions)
echo "Long multi-paragraph question..." > /tmp/q.txt
./scripts/consult_all.sh --query-file /tmp/q.txt src/big.py
```

See `references/configuration.md` § "Context Handoff (v2.14+)" for `QUESTION_CATEGORY` and `FORCE_PROJECT_TREE` env vars.

## Best Practices

### Security

- **Never** include credentials in queries
- Review and redact sensitive code before sending it to any external consultant

### Effective Queries

- Be specific about the question
- Include constraints (performance, etc.)
- The panel pays off most on breadth questions ("what could go wrong?", "enumerate the risks"); for a single-answer factual question, one strong model is usually enough

## Known Limitations

- Minimum 2 consultants required
- Smart Routing off by default
- Synthesis requires Claude CLI (fallback available)
- Estimated costs (heuristic token counting)
