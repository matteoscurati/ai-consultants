# AI Consultants - Reference Details

Read this file when the user asks about presets, strategies, bash usage, best practices, or known limitations.

## Configuration Presets

| Preset | Consultants | Use Case |
|--------|-------------|----------|
| `minimal` | 2 (Gemini + Codex) | Quick questions |
| `balanced` | 4 (+Mistral +Kilo) | Standard use |
| `thorough` | 5 (+Cursor) | Comprehensive |
| `high-stakes` | All + debate | Critical decisions |
| `local` | Ollama only | Full privacy |
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

# With local model
./scripts/consult_all.sh --preset local "Private question"
```

## Best Practices

### Security

- **Never** include credentials in queries
- Use `--preset local` for sensitive code

### Effective Queries

- Be specific about the question
- Include constraints (performance, etc.)
- Use debate for controversial decisions

## Known Limitations

- Minimum 2 consultants required
- Smart Routing off by default
- Synthesis requires Claude CLI (fallback available)
- Estimated costs (heuristic token counting)
