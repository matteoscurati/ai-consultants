---
description: Manage consultant persona assignments
argument-hint: [consultant] [persona-id]
allowed-tools: Bash Read Edit
---

# AI Consultants - Persona Configuration

Manage persona assignments for AI consultants. Each consultant can have a unique personality that shapes their response style.

**Arguments:** $ARGUMENTS

## Instructions

### Step 1: Show Available Personas

```bash
cd /Users/matteoscurati/work/ai-consultants
source scripts/lib/personas.sh
list_personas
```

This shows the 15 available personas:
1. The Architect - Design patterns, scalability
2. The Pragmatist - Simplicity, quick wins
3. The Devil's Advocate - Edge cases, risks
4. The Innovator - Creative solutions
5. The Integrator - Full-stack perspective
6. The Analyst - Data-driven decisions
7. The Methodologist - Structured approaches
8. The Provocateur - Challenge conventions
9. The Mentor - Teaching focus
10. The Optimizer - Performance
11. The Security Expert - Security-first
12. The Minimalist - Less is more
13. The DX Advocate - Developer experience
14. The Debugger - Root cause analysis
15. The Reviewer - Code quality

### Step 2: Show Current Assignments

```bash
source scripts/config.sh
source scripts/lib/personas.sh
echo "Current Persona Assignments:"
for agent in Gemini Codex Mistral Kilo Cursor Qwen3 GLM Grok; do
  persona=$(get_persona_name "$agent" 2>/dev/null)
  [[ -n "$persona" ]] && echo "  $agent: $persona"
done
```

### Step 3: If User Wants to Change a Persona

If the user specifies a consultant and persona in $ARGUMENTS, or interactively:

1. Ask which consultant to change (Gemini, Codex, Mistral, Kilo, Cursor, etc.)
2. Ask which persona ID (1-15) to assign
3. Update the .env file:

```bash
# Example: Set Gemini to persona 9 (The Mentor)
# Add or update in .env:
GEMINI_PERSONA_ID=9
```

To update .env, use the Edit tool to add/modify the line:
- If `{AGENT}_PERSONA_ID=` exists, update it
- Otherwise, add it to the "PERSONA ASSIGNMENTS" section

### Step 4: Verify the Change

```bash
source .env
source scripts/config.sh
source scripts/lib/personas.sh
echo "Updated: $(get_persona_name "AGENT_NAME")"
```

## Default Persona Assignments

| Consultant | Default Persona |
|------------|-----------------|
| Gemini | The Architect (1) |
| Codex | The Pragmatist (2) |
| Mistral | The Devil's Advocate (3) |
| Kilo | The Innovator (4) |
| Cursor | The Integrator (5) |
| Qwen3 | The Analyst (6) |
| GLM | The Methodologist (7) |
| Grok | The Provocateur (8) |
