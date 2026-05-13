---
description: Consult AI experts (Claude, Codex, Mistral, Kilo, Cursor, Aider, Amp, Kimi, Qwen, GLM, Grok, DeepSeek, MiniMax, Ollama) for coding questions. Use when weighing trade-offs, comparing approaches, or wanting multiple expert perspectives on non-trivial decisions.
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Expert Panel

Query multiple AI models for expert opinions on a coding question.

**User's Question:** $ARGUMENTS

## Instructions

1. If no question provided in $ARGUMENTS, ask the user what they want to consult about.

2. **File context handling**: Identify which strings in $ARGUMENTS refer to files the user wants the consultants to look at. Use your judgment — verify existence via `Glob` or `Bash ls` when uncertain. This replaces fragile regex detection: a `Makefile`, `Dockerfile`, dotfile, or path without a common extension is still a file; an URL or regex pattern in the question text is not.

   For each file you identify:
   - Strip the file path from the question text.
   - Decide its relevance tag: `PRIMARY` (the focus of the question — what the consultants should critique) or `CONTEXT` (ambient reference — the consultants should read but not necessarily critique). Default to `PRIMARY` if every referenced file is central.
   - Pass each path as a positional argument to `consult_all.sh` with the syntax `path/to/file@TAG` (omit `@TAG` to default to `PRIMARY`).

   **Do not inline file contents into the query string.** `build_context.sh` reads files directly from the filesystem and runs the AST optimization pipeline — passing file paths as arguments is what enables it. Inlining defeats the optimization and inflates the consultants' context.

3. **Run the consultation**:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && INVOKING_AGENT=gemini ./scripts/consult_all.sh '<question>' <file1[@TAG]> <file2[@TAG]> ...
   ```
   - `<question>` is the question text with file paths stripped. Use single quotes to prevent shell expansion.
   - Each `<fileN>` is a file path, optionally suffixed with `@PRIMARY` or `@CONTEXT`.
   - **If the question text exceeds ~8KB or contains awkward quoting**, write it to a tmpfile and use `--query-file <path>` instead:
     ```bash
     cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && INVOKING_AGENT=gemini ./scripts/consult_all.sh --query-file /tmp/question.txt <file1[@TAG]> ...
     ```
   - **Capture the last line of stdout** — it contains the output directory path (e.g., `/tmp/ai_consultations/20260315_143022_12345/`).

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
     cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && ./scripts/doctor.sh
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
| `FORCE_PROJECT_TREE=true` | Include the project tree even for pointed categories (SECURITY, QUICK_SYNTAX, etc.) |

## Follow-up

For follow-up questions on the same consultation:
```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && INVOKING_AGENT=gemini ./scripts/followup.sh '<follow-up question>'
```
