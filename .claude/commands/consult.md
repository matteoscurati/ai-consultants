---
description: Consult AI experts (Gemini, Codex, Mistral, Kilo, Cursor) for coding questions
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Expert Panel

You are invoking the AI Consultants skill to get multiple expert opinions on a coding question.

## Task

Run the AI consultants script to query multiple AI models for their expert opinions on the user's question.

**User's Question:** $ARGUMENTS

## Instructions

1. If no question was provided in $ARGUMENTS, ask the user what they want to consult the experts about.

2. Run the consultation using:
   ```bash
   ./scripts/consult_all.sh "$ARGUMENTS"
   ```

3. Wait for the script to complete and read the generated report.

4. Present a summary of the consultation results:
   - Each consultant's recommendation and confidence score
   - The consensus level and weighted vote
   - Key agreements and disagreements
   - The synthesized recommendation

5. If the user wants to follow up, use:
   ```bash
   ./scripts/followup.sh "<follow-up question>"
   ```

## Options

The user can customize the consultation with environment variables:
- `ENABLE_DEBATE=true` - Enable multi-round debate between consultants
- `ENABLE_SMART_ROUTING=true` - Auto-select best consultants for the question
- `DEBATE_ROUNDS=2` - Number of debate rounds (1-3)

Example with debate:
```bash
ENABLE_DEBATE=true DEBATE_ROUNDS=2 ./scripts/consult_all.sh "$ARGUMENTS"
```
