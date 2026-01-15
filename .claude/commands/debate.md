---
description: Run AI consultation with multi-round debate enabled
argument-hint: <question> [rounds=2]
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Debate Mode

Run a multi-round debate where AI consultants critique each other's responses.

**Question:** $ARGUMENTS

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "$ARGUMENTS"
```

After completion, summarize:
- How positions evolved during the debate
- Final consensus and key critiques
