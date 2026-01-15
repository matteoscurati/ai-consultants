---
description: Quick alias for /consult - ask AI experts for coding advice
argument-hint: <question>
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Quick Query

Run AI consultation for: $ARGUMENTS

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/consult_all.sh "$ARGUMENTS"
```

Summarize the key findings and recommendations from all consultants.
