---
description: Manage consultant persona assignments
argument-hint: [consultant] [persona-id]
allowed-tools: Bash Read Edit
---

# AI Consultants - Persona Configuration

Manage persona assignments for AI consultants. Each consultant can have a unique personality that shapes their response style.

**Arguments:** $ARGUMENTS

## Available Personas

| ID | Persona | Focus |
|----|---------|-------|
| 1 | The Architect | Design patterns, scalability |
| 2 | The Pragmatist | Simplicity, quick wins |
| 3 | The Devil's Advocate | Edge cases, risks |
| 4 | The Innovator | Creative solutions |
| 5 | The Integrator | Full-stack perspective |
| 6 | The Analyst | Data-driven decisions |
| 7 | The Methodologist | Structured approaches |
| 8 | The Provocateur | Challenge conventions |
| 9 | The Mentor | Teaching focus |
| 10 | The Optimizer | Performance |
| 11 | The Security Expert | Security-first |
| 12 | The Minimalist | Less is more |
| 13 | The DX Advocate | Developer experience |
| 14 | The Debugger | Root cause analysis |
| 15 | The Reviewer | Code quality |

## Default Assignments

Gemini (1), Codex (2), Mistral (3), Kilo (4), Cursor (5), Qwen3 (6), GLM (7), Grok (8)

## Instructions

### Step 1: Show Current Assignments

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}"
source scripts/config.sh && source scripts/lib/personas.sh
echo "Current Persona Assignments:"
for agent in Gemini Codex Mistral Kilo Cursor Qwen3 GLM Grok; do
  persona=$(get_persona_name "$agent" 2>/dev/null)
  [[ -n "$persona" ]] && echo "  $agent: $persona"
done
```

### Step 2: Change a Persona

To change a persona, update the .env file with:

```bash
# Example: Set Gemini to persona 9 (The Mentor)
GEMINI_PERSONA_ID=9
```

Use the Edit tool to add or update the `{AGENT}_PERSONA_ID=` line in .env.

### Step 3: Verify the Change

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}"
source .env && source scripts/config.sh && source scripts/lib/personas.sh
get_persona_name "AGENT_NAME"
```
