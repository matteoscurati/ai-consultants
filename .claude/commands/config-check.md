---
description: Verify CLI agents are installed and working
allowed-tools: Bash Read
---

# AI Consultants - Configuration Check

Run a preflight check to verify all CLI agents are properly installed and configured.

## Instructions

1. **Run the preflight check script:**

```bash
cd /Users/matteoscurati/work/ai-consultants
./scripts/preflight_check.sh
```

2. **Analyze the output** and present a clear summary to the user:
   - Which CLIs are installed vs missing
   - Which CLIs have working API connectivity
   - Any warnings or errors
   - Recommendations for fixing issues

3. **If the user wants JSON output for debugging:**

```bash
./scripts/preflight_check.sh --json
```

4. **If the user wants quick check (CLI only, no API test):**

```bash
./scripts/preflight_check.sh --quick
```

5. **To get suggested configuration based on detected CLIs:**

```bash
./scripts/preflight_check.sh --suggest-config
```

## Common Issues and Solutions

- **CLI not found**: Install the missing CLI using the hint provided
- **API connectivity failed**: Check API key/authentication for that service
- **jq not found**: Install jq (`brew install jq` on macOS)
- **Less than 2 agents**: At least 2 consultants needed for comparison

After the check, offer to help fix any issues found.
