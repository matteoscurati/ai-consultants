# AI Consultants - Reference Details

Read this file when the user asks about presets, strategies, bash usage, best practices, or known limitations.

## Configuration Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions |
| `balanced` | 4 (+Mistral +Cursor) | Standard use |
| `thorough` | 4 | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `security` | Security-focused | +Debate |
| `cost-capped` | Budget-friendly | Low cost |

## Synthesis Strategies

| Strategy | Description |
|----------|-------------|
| `majority` | Most common answer wins (default) |
| `risk_averse` | Weight conservative responses |
| `security_first` | Prioritize security |
| `cost_capped` | Prefer cheaper solutions |
| `compare_only` | No recommendation |

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
- Use debate for controversial decisions

## Known Limitations

- Minimum 2 consultants required
- Smart Routing off by default
- Synthesis requires Claude CLI (fallback available)
- Estimated costs (heuristic token counting)
