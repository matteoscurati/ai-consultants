---
description: Run AI consultation with multi-round debate where consultants critique each other's positions. Use for architecture decisions, security reviews, controversial trade-offs, or when a standard consultation produced low consensus.
argument-hint: <question> [file1] [file2] ...
allowed-tools: Bash Read Glob Grep
---

# AI Consultants - Debate Mode

Run a multi-round debate where AI consultants critique each other's responses and refine their positions.

**Question:** $ARGUMENTS

## When to Use Debate

- **Architecture decisions**: Microservices vs monolith, database choices, system design
- **Security reviews**: Threat modeling, authentication strategies, data protection approaches
- **Low-consensus results**: A previous `/ai-consultants:consult` returned low consensus — debate forces deeper analysis
- **Controversial trade-offs**: Performance vs maintainability, speed vs correctness, build vs buy

## Instructions

1. If no question provided in $ARGUMENTS, ask the user what they want to debate.

2. **File context handling**: Identify which strings in $ARGUMENTS refer to files the user wants the consultants to debate over. Use your judgment — verify existence via `Glob` or `Bash ls` when uncertain. A `Makefile`, `Dockerfile`, dotfile, or path without a common extension is still a file; an URL or regex pattern in the question text is not.

   For each file you identify:
   - Strip the file path from the question text.
   - Decide its relevance tag: `PRIMARY` (the focus of the debate — what the consultants should critique) or `CONTEXT` (ambient reference — read but not necessarily critiqued). Default to `PRIMARY` if every referenced file is central.
   - Pass each path as a positional argument to `consult_all.sh` with the syntax `path/to/file@TAG` (omit `@TAG` to default to `PRIMARY`).

   **Do not inline file contents into the query string.** `build_context.sh` reads files directly from the filesystem and runs the AST optimization pipeline.

3. **Run the debate consultation**:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && INVOKING_AGENT=gemini ENABLE_DEBATE=true DEBATE_ROUNDS="${DEBATE_ROUNDS:-2}" ./scripts/consult_all.sh '<question>' <file1[@TAG]> <file2[@TAG]> ...
   ```
   - `<question>` is the question text with file paths stripped. Use single quotes to prevent shell expansion.
   - Each `<fileN>` is a file path, optionally suffixed with `@PRIMARY` or `@CONTEXT`.
   - **If the question text exceeds ~8KB or contains awkward quoting**, write it to a tmpfile and pass `--query-file <path>` instead of the inline question.
   - **Capture the last line of stdout** — it contains the output directory path.

4. **Read the results** from the output directory captured in step 3:
   - Read `<output_dir>/report.md` using the **Read** tool
   - Read `<output_dir>/synthesis.json` using the **Read** tool (may not exist)
   - Use the **Glob** tool with pattern `<output_dir>/round_*/round_summary.json` to find debate round summaries, then read each one
   - Use the **Glob** tool with pattern `<output_dir>/round_*/*.json` to find debate round responses (exclude `round_summary.json` — these individual files contain position changes, critiques, and confidence deltas)
   - Round 1 (initial responses) are stored directly in `<output_dir>/*.json`; subsequent rounds are in `<output_dir>/round_N/` subdirectories

5. **Present the results** using this debate-specific template:

   ### Consensus
   - **Score**: <consensus_percentage>% (<consensus_level>)
   - **Category**: <question_category>

   ### Position Evolution
   | Consultant | Initial Approach | Changed? | Final Approach | Confidence Delta |
   |------------|-----------------|----------|---------------|-----------------|
   | <name> | <round 1 approach> | Yes/No | <final approach> | <+N/-N> |

   ### Key Critiques
   - **<consultant>** on **<target>**: <critique summary> (severity: <minor/moderate/major>)

   ### Debate Stability
   - **Assessment**: <stable/mostly_stable/volatile> — <N> of <total> consultants changed position
   - If stable: "Strong agreement — consultants held their positions after cross-critique"
   - If volatile: "Significant disagreement — positions shifted substantially during debate"

   ### Synthesized Recommendation
   - **Recommended approach**: <approach>
   - **Summary**: <synthesized summary>

   ### Key Agreements
   - <points reinforced through debate>

   ### Key Disagreements
   - <unresolved points of contention>

   ### Risk Assessment
   - <caveats and uncertainty factors>

   ### Suggested Next Steps
   - <actionable items>

   If `synthesis.json` is missing, build the summary from individual consultant JSON files.

6. **Error recovery**:
   - **Exit code 1** (general failure): Tell the user and suggest running diagnostics:
     ```bash
     cd "${AI_CONSULTANTS_DIR:-$HOME/.gemini/skills/ai-consultants}" && ./scripts/doctor.sh
     ```
   - **Exit code 124** (timeout): Debate is more expensive — suggest reducing `DEBATE_ROUNDS=1` or using `--preset fast`
   - **Partial failures**: Present successful results and note which consultants failed
   - **Empty output**: Suggest running `doctor.sh` to verify CLI installations

## Options

| Variable | Default | Effect |
|----------|---------|--------|
| `DEBATE_ROUNDS` | `2` | Number of debate rounds (1-3). More rounds = deeper analysis but higher cost |
| `ENABLE_SMART_ROUTING` | `false` | Auto-select best consultants for the question type |
