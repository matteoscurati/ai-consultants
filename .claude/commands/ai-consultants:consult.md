---
description: Consult AI experts (Gemini, Codex, Mistral, Kilo, Cursor, Aider, Amp, Kimi, Qwen, GLM, Grok, DeepSeek, MiniMax, Ollama) for coding questions. Use when weighing trade-offs, comparing approaches, or wanting multiple expert perspectives on non-trivial decisions.
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Expert Panel

Query multiple AI models for expert opinions on a coding question.

**User's Question:** $ARGUMENTS

## Instructions

1. If no question provided in $ARGUMENTS, ask the user what they want to consult about.

2. **File context handling**: Check if $ARGUMENTS contains file paths (tokens containing `/` or extensions like `.ts`, `.js`, `.py`, `.sh`, `.json`, `.yaml`, `.yml`, `.md`, `.go`, `.rs`, `.java`, `.rb`, `.css`, `.html`, `.tsx`, `.jsx`, `.c`, `.cpp`, `.h`).
   If file paths are found:
   - Extract each file path token from $ARGUMENTS
   - Read each file using the **Read** tool
   - Build an enriched query by replacing file path tokens with their inline contents:
     ```
     <original question text without file paths>

     --- File: path/to/file.ts ---
     <file contents>
     --- End File ---
     ```
   - Use this enriched query in step 3 instead of raw $ARGUMENTS

3. **Run the consultation**:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && INVOKING_AGENT=claude ./scripts/consult_all.sh '<query>'
   ```
   Replace `<query>` with the enriched query from step 2 (or $ARGUMENTS if no files were detected). Use single quotes around the query to prevent shell expansion of special characters.
   **Capture the last line of stdout** — it contains the output directory path (e.g., `/tmp/ai_consultations/20260315_143022_12345/`).

4. **Read the results** from the output directory captured in step 3:
   - Read `<output_dir>/report.md` using the **Read** tool
   - Read `<output_dir>/synthesis.json` using the **Read** tool (may not exist if synthesis was skipped or failed)
   - If neither exists, use the **Glob** tool with pattern `<output_dir>/*.json` to discover individual consultant response files, then read each one

5. **Present the results** using this template:

   ### Consensus
   - **Score**: <consensus_percentage>% (<consensus_level: strong/medium/low/none>)
   - **Category**: <question_category>

   ### Consultant Summary
   | Consultant | Confidence | Approach | Key Insight |
   |------------|-----------|----------|-------------|
   | <name> | <score>/10 | <approach> | <one-line from summary> |

   ### Synthesized Recommendation
   - **Recommended approach**: <approach>
   - **Summary**: <synthesized summary>

   ### Key Agreements
   - <points most consultants agree on>

   ### Key Disagreements
   - <points where consultants diverge>

   ### Risk Assessment
   - <caveats and uncertainty factors raised>

   ### Suggested Next Steps
   - <actionable items based on the recommendation>

   If `synthesis.json` is missing, build the summary table and recommendation directly from the individual consultant JSON files in the output directory.

6. **Error recovery**:
   - **Exit code 1** (general failure): Tell the user and suggest running diagnostics:
     ```bash
     cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/doctor.sh
     ```
   - **Exit code 124** (timeout): Suggest `--preset fast` for quicker results or increasing the timeout (e.g., `GEMINI_TIMEOUT=300`)
   - **Partial failures** (some consultants responded, others didn't): Present the successful results normally and note which consultants failed at the end
   - **Empty output directory** (no JSON files produced): Suggest running `doctor.sh` to verify CLI installations and API keys

## Options

| Variable | Effect |
|----------|--------|
| `ENABLE_DEBATE=true` | Enable multi-round debate for deeper analysis |
| `ENABLE_SMART_ROUTING=true` | Auto-select best consultants for the question type |
| `DEBATE_ROUNDS=2` | Number of debate rounds (1-3) |

## Follow-up

For follow-up questions on the same consultation:
```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && INVOKING_AGENT=claude ./scripts/followup.sh '<follow-up question>'
```
