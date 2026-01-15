---
description: Quick alias for /consult - ask AI experts for coding advice
argument-hint: <question>
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Quick Query

Run AI consultation for: $ARGUMENTS

```bash
./scripts/consult_all.sh "$ARGUMENTS"
```

After completion, summarize the key findings and recommendations from all consultants.
