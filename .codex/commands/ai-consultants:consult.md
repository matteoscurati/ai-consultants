---
description: Consult AI experts (Gemini, Claude, Mistral, Kimi, Qwen, GLM, Grok, DeepSeek, MiniMax) for coding questions. Use when weighing trade-offs, comparing approaches, or wanting multiple expert perspectives on non-trivial decisions.
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Expert Panel

Query multiple AI models for expert opinions on a coding question.

**User's Question:** $ARGUMENTS

## Instructions

1. If no question provided in $ARGUMENTS, ask the user what they want to consult about.

   Separate supported consultation options from the question. Preserve
   `--preset <name>` and `--strategy <name>` as CLI arguments before the
   question; reject an incomplete option instead of guessing its value.

2. **File context handling**: Identify which strings in $ARGUMENTS refer to files the user wants the consultants to look at. Use your judgment — verify existence via `Glob` or `Bash ls` when uncertain. This replaces fragile regex detection: a `Makefile`, `Dockerfile`, dotfile, or path without a common extension is still a file; an URL or regex pattern in the question text is not.

   For each file you identify:
   - Strip the file path from the question text.
   - Decide its relevance tag: `PRIMARY` (the focus of the question — what the consultants should critique) or `CONTEXT` (ambient reference — the consultants should read but not necessarily critique). Default to `PRIMARY` if every referenced file is central.
   - Pass each path as a positional argument to `consult_all.sh` with the syntax `path/to/file@TAG` (omit `@TAG` to default to `PRIMARY`).

   **Do not inline file contents into the query string.** `build_context.sh` reads files directly from the filesystem and runs the AST optimization pipeline — passing file paths as arguments is what enables it. Inlining defeats the optimization and inflates the consultants' context.

3. **Write the question safely and run the consultation**:
   - With Bash, create a query file using `mktemp`, set mode 600, and write the
     exact question text (with file paths and consultation options removed)
     through a **single-quoted heredoc delimiter that does not occur as its own
     line in the question**. Never pass raw user text as a shell argument or
     through an unquoted heredoc.
   - Shell-quote every context-file path as one argument.
   - Install a shell trap that removes only the exact query file when the Bash
     invocation exits; question text must not persist in the temp directory.
   - Capture `caller_root="$PWD"` before changing directories. Pass it through
     `--context-root` so regular files from the user's project are staged under
     a private temp directory without widening the runtime filesystem allowlist.

   ```bash
   caller_root="$PWD"; cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ./scripts/consult_all.sh [--preset <name>] [--strategy <name>] --context-root "$caller_root" --query-file "<private-question-file>" "<file1[@TAG]>" "<file2[@TAG]>" ...
   ```
   - Each `<fileN>` is a file path, optionally suffixed with `@PRIMARY` or `@CONTEXT`.
   - **Capture the last line of stdout** — it contains the output directory path (e.g., `/tmp/ai_consultations/20260315_143022_12345/`).
   - Keep `INVOKING_AGENT=codex` exactly as shown. Never invoke
     `query_codex.sh` directly or remove self-exclusion.

4. **Read the results** from the output directory captured in step 3:
   - Read `<output_dir>/report.md` using the **Read** tool
   - Read `<output_dir>/synthesis.json` using the **Read** tool (may not exist if synthesis was skipped or failed)
   - If neither exists, use the **Glob** tool with pattern `<output_dir>/*.json` to discover individual consultant response files, then read each one
   - `codex.json` must not exist and `.synthesis_provider` must not be `codex`.
     Treat either condition as a self-exclusion failure.

5. **Present the results** using this template. Preserve the union of distinct
   considerations, including points raised by only one consultant:

   ### Category
   - <question_category>

   ### Consultant Summary
   | Consultant | Confidence | Approach | Key Insight |
   |------------|-----------|----------|-------------|
   | <name> | <score>/10 | <approach> | <one-line from summary> |

   ### Coverage (the union of distinct considerations)
   - <every distinct point, recommendation, risk, and edge case raised by any consultant, deduplicated and attributed>

   ### Risks & Caveats
   - <distinct caveats and uncertainty factors>

   ### Suggested Next Steps
   - <actionable items based on the recommendation>

   If `synthesis.json` is missing, build the summary table and coverage union directly from the individual consultant JSON files.

6. **Error recovery**:
   - **Exit code 1** (general failure): Tell the user and suggest running diagnostics:
     ```bash
     cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && ./scripts/doctor.sh
     ```
   - **Exit code 124** (timeout): Suggest `--preset fast` for quicker results or increasing the timeout (e.g., `GEMINI_TIMEOUT=300`)
   - **Partial failures** (some consultants responded, others didn't): Present the successful results normally and note which consultants failed at the end
   - **Empty output directory** (no JSON files produced): Suggest running `doctor.sh` to verify CLI installations and API keys

## Options

| Variable | Effect |
|----------|--------|
| `ENABLE_SMART_ROUTING=true` | Auto-select best consultants for the question type |
| `SYNTHESIS_STRATEGY=compare_only` | Present consultants side-by-side without a recommendation |
| `FORCE_PROJECT_TREE=true` | Include the project tree even for pointed categories (SECURITY, QUICK_SYNTAX, etc.) |

## Follow-up

For follow-up questions on the same consultation:
```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}" && INVOKING_AGENT=codex ./scripts/followup.sh --query-file "<private-follow-up-file>"
```
Create and clean the follow-up file with the same private heredoc/trap contract.
Never target Codex from a Codex-hosted follow-up.
