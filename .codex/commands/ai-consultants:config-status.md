---
description: Show current AI Consultants configuration status
allowed-tools: Bash Read
---

# AI Consultants - Configuration Status

Show the current configuration status for AI Consultants.

## Instructions

Run the following script to gather configuration status:

```bash
cd "${AI_CONSULTANTS_DIR:-$HOME/.codex/skills/ai-consultants}"
[[ -f .env ]] && source .env
source scripts/config.sh
source scripts/lib/personas.sh

echo "=== CLI Consultants ==="
echo "Gemini:  ${ENABLE_GEMINI:-true} ($(command -v gemini &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Claude:  ${ENABLE_CLAUDE:-false} ($(command -v claude &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Mistral: ${ENABLE_MISTRAL:-true} ($(command -v vibe &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Kilo:    ${ENABLE_KILO:-true} ($(command -v kilocode &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Cursor:  ${ENABLE_CURSOR:-true} ($(command -v agent &>/dev/null && echo 'installed' || echo 'not found'))"

echo ""
echo "=== API Consultants ==="
echo "Qwen3: ${ENABLE_QWEN3:-false} (API key: $([ -n \"$QWEN3_API_KEY\" ] && echo 'set' || echo 'not set'))"
echo "GLM:   ${ENABLE_GLM:-false} (API key: $([ -n \"$GLM_API_KEY\" ] && echo 'set' || echo 'not set'))"
echo "Grok:  ${ENABLE_GROK:-false} (API key: $([ -n \"$GROK_API_KEY\" ] && echo 'set' || echo 'not set'))"

echo ""
echo "=== Persona Assignments ==="
for agent in Gemini Claude Mistral Kilo Cursor; do
  persona_name=$(get_persona_name "$agent" 2>/dev/null || echo "Default")
  echo "$agent: $persona_name"
done

echo ""
echo "=== Features ==="
echo "Personas:      ${ENABLE_PERSONA:-true}"
echo "Synthesis:     ${ENABLE_SYNTHESIS:-true}"
echo "Debate:        ${ENABLE_DEBATE:-false}"
echo "Smart Routing: ${ENABLE_SMART_ROUTING:-false}"
echo "Cost Tracking: ${ENABLE_COST_TRACKING:-true}"
```

Present the output as a clear summary to the user.
