---
description: Show current AI Consultants configuration status
allowed-tools: Bash Read
---

# AI Consultants - Configuration Status

Show the current configuration status for AI Consultants.

## Instructions

1. **Check if .env exists and source configuration:**

```bash
cd /Users/matteoscurati/work/ai-consultants
if [[ -f .env ]]; then
  source .env
fi
source scripts/config.sh
source scripts/lib/personas.sh
```

2. **Show CLI Consultant Status:**

```bash
echo "=== CLI Consultants ==="
echo "Gemini:  ${ENABLE_GEMINI:-true} ($(command -v gemini &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Codex:   ${ENABLE_CODEX:-true} ($(command -v codex &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Mistral: ${ENABLE_MISTRAL:-true} ($(command -v vibe &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Kilo:    ${ENABLE_KILO:-true} ($(command -v kilocode &>/dev/null && echo 'installed' || echo 'not found'))"
echo "Cursor:  ${ENABLE_CURSOR:-true} ($(command -v agent &>/dev/null && echo 'installed' || echo 'not found'))"
```

3. **Show API Consultant Status:**

```bash
echo ""
echo "=== API Consultants ==="
echo "Qwen3: ${ENABLE_QWEN3:-false} (API key: $([ -n \"$QWEN3_API_KEY\" ] && echo 'set' || echo 'not set'))"
echo "GLM:   ${ENABLE_GLM:-false} (API key: $([ -n \"$GLM_API_KEY\" ] && echo 'set' || echo 'not set'))"
echo "Grok:  ${ENABLE_GROK:-false} (API key: $([ -n \"$GROK_API_KEY\" ] && echo 'set' || echo 'not set'))"
```

4. **Show Persona Assignments:**

```bash
echo ""
echo "=== Persona Assignments ==="
for agent in Gemini Codex Mistral Kilo Cursor; do
  persona_name=$(get_persona_name "$agent" 2>/dev/null || echo "Default")
  echo "$agent: $persona_name"
done
```

5. **Show Feature Status:**

```bash
echo ""
echo "=== Features ==="
echo "Personas:      ${ENABLE_PERSONA:-true}"
echo "Synthesis:     ${ENABLE_SYNTHESIS:-true}"
echo "Debate:        ${ENABLE_DEBATE:-false}"
echo "Smart Routing: ${ENABLE_SMART_ROUTING:-false}"
echo "Cost Tracking: ${ENABLE_COST_TRACKING:-true}"
```

6. **Present the information in a clear summary to the user.**
