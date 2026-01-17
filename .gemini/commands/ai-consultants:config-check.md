---
description: Verify CLI agents are installed and working
allowed-tools: Bash Read
---

# AI Consultants - Configuration Check

Run a preflight check to verify all CLI agents are properly installed and configured.

## Instructions

1. **Run the preflight check script:**

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && ./scripts/preflight_check.sh
```

2. **Analyze the output** and present a clear summary:
   - Which CLIs are installed vs missing
   - Which CLIs have working API connectivity
   - Any warnings or errors
   - Recommendations for fixing issues

## Additional Options

| Option | Command |
|--------|---------|
| JSON output | `./scripts/preflight_check.sh --json` |
| Quick check (CLI only) | `./scripts/preflight_check.sh --quick` |
| Suggest config | `./scripts/preflight_check.sh --suggest-config` |

## Common Issues

- **CLI not found**: Install the missing CLI using the hint provided
- **API connectivity failed**: Check API key/authentication for that service
- **jq not found**: Install jq (`brew install jq` on macOS)
- **Less than 2 agents**: At least 2 consultants needed for comparison

After the check, offer to help fix any issues found.
