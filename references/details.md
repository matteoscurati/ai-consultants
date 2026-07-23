# AI Consultants - Reference Details

Read this file when the user asks about presets, strategies, bash usage, best practices, or known limitations.

## Configuration Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions |
| `balanced` | 4 (+Mistral +Cursor) | Standard use |
| `thorough` | 4 | Comprehensive |
| `high-stakes` | Expanded panel (5 of 11) | Critical decisions |
| `security` | Security-focused (4) | Security reviews |
| `cost-capped` | Budget-friendly | Low cost |
| `max_quality` | 8 of 11, premium models | Critical decisions |
| `medium` | 4, standard models | General questions |
| `fast` | 2, economy models | Quick checks |

A preset only chooses the consultant set + model tier; every run fans out in parallel and returns the coverage union.

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
