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

3. **Run the debate consultation**:
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && INVOKING_AGENT=claude ENABLE_DEBATE=true DEBATE_ROUNDS="${DEBATE_ROUNDS:-2}" ./scripts/consult_all.sh '<query>'
   ```
   Replace `<query>` with the enriched query from step 2 (or $ARGUMENTS if no files were detected). Use single quotes around the query to prevent shell expansion of special characters.
   **Capture the last line of stdout** — it contains the output directory path.

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
     cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/doctor.sh
     ```
   - **Exit code 124** (timeout): Debate is more expensive — suggest reducing `DEBATE_ROUNDS=1` or using `--preset fast`
   - **Partial failures**: Present successful results and note which consultants failed
   - **Empty output**: Suggest running `doctor.sh` to verify CLI installations

## Options

| Variable | Default | Effect |
|----------|---------|--------|
| `DEBATE_ROUNDS` | `2` | Number of debate rounds (1-3). More rounds = deeper analysis but higher cost |
| `ENABLE_SMART_ROUTING` | `false` | Auto-select best consultants for the question type |
