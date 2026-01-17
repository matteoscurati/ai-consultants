---
description: Consult AI experts (Gemini, Claude, Mistral, Kilo, Cursor) for coding questions
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Expert Panel

Query multiple AI models for expert opinions on a coding question.

**User's Question:** $ARGUMENTS

## Instructions

1. If no question provided in $ARGUMENTS, ask the user what they want to consult about.

2. Run the consultation:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ./scripts/consult_all.sh "$ARGUMENTS"
   ```

3. Present a summary of the results:
   - Each consultant's recommendation and confidence score
   - Consensus level and weighted vote
   - Key agreements and disagreements
   - Synthesized recommendation

4. For follow-up questions:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ./scripts/followup.sh "<follow-up question>"
   ```

## Options

| Variable | Effect |
|----------|--------|
| `ENABLE_DEBATE=true` | Enable multi-round debate |
| `ENABLE_SMART_ROUTING=true` | Auto-select best consultants |
| `DEBATE_ROUNDS=2` | Number of debate rounds (1-3) |

Example with debate:
```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ENABLE_DEBATE=true ./scripts/consult_all.sh "$ARGUMENTS"
```
