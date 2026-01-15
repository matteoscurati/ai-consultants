---
description: Run AI consultation with multi-round debate enabled
argument-hint: <question> [rounds=2]
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Debate Mode

Run a multi-round debate consultation where AI consultants critique each other's responses.

**Question:** $ARGUMENTS

```bash
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "$ARGUMENTS"
```

After completion:
1. Read the final report from the output directory
2. Summarize how positions evolved during the debate
3. Highlight the final consensus and key critiques
