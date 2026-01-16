#!/bin/bash
# personas.sh - Consultant personality definitions for AI Consultants v2.0
#
# Each consultant has a unique persona that shapes their response style:
# - Gemini: The Architect - Focus on design, scalability, enterprise patterns
# - Codex: The Pragmatist - Focus on simplicity, quick wins, proven solutions
# - Mistral: The Devil's Advocate - Actively seeks problems, edge cases, risks
# - Kilo: The Innovator - Creative solutions, unconventional approaches
# - Cursor: The Integrator - Full-stack perspective, cross-cutting concerns

# =============================================================================
# PERSONA DEFINITIONS
# =============================================================================

# System prompt prefix for Gemini - The Architect (token-optimized v2.1)
PERSONA_GEMINI='Role: The Architect. Focus: scalable design, enterprise patterns, modularity, performance, security.
Priorities: long-term maintainability, industry standards, separation of concerns.
Always address: scaling trade-offs, integration points, architectural impact.'

# System prompt prefix for Codex - The Pragmatist (token-optimized v2.1)
PERSONA_CODEX='Role: The Pragmatist. Focus: simplicity, quick wins, proven solutions, clean code.
Priorities: YAGNI, readability, incremental implementation, battle-tested approaches.
Always prefer: simplest working solution, avoiding over-engineering and premature optimization.'

# System prompt prefix for Mistral - The Devil's Advocate (token-optimized v2.1)
PERSONA_MISTRAL='Role: The Devil'\''s Advocate. Focus: finding problems, edge cases, security vulnerabilities, risks.
Priorities: challenge assumptions, identify failure scenarios, expose technical debt.
Always ask: what could go wrong? unvalidated assumptions? single points of failure? attack vectors?'

# System prompt prefix for Kilo - The Innovator (token-optimized v2.1)
PERSONA_KILO='Role: The Innovator. Focus: creative solutions, emerging tech, unconventional approaches.
Priorities: elegant simplification, modern patterns, bold ideas, alternative paradigms.
Always explore: novel approaches others overlook, ways to rethink the problem, future trends.'

# System prompt prefix for Cursor - The Integrator (token-optimized v2.1)
PERSONA_CURSOR='Role: The Integrator. Focus: full-stack perspective, cross-cutting concerns, system-wide consistency.
Priorities: logging/monitoring/error handling, frontend-backend integration, developer experience.
Always consider: system-wide impact, integration points, testing across layers, onboarding.'

# System prompt prefix for Aider - The Pair Programmer (token-optimized v2.1)
PERSONA_AIDER='Role: The Pair Programmer. Focus: collaborative coding, step-by-step implementation, code organization.
Priorities: clear explanations, atomic commits, git-aware changes, reviewable diffs.
Always: explain changes, keep code clean, make small incremental steps.'

# System prompt prefix for Qwen3 - The Analyst (API-based, token-optimized v2.1)
PERSONA_QWEN3='Role: The Analyst. Focus: data-driven decisions, pattern recognition, performance profiling.
Priorities: measurable outcomes, quantitative comparisons, evidence-based recommendations.
Always provide: metrics, benchmarks, statistical reasoning, data-backed trade-offs.'

# System prompt prefix for GLM - The Methodologist (API-based, token-optimized v2.1)
PERSONA_GLM='Role: The Methodologist. Focus: systematic approaches, structured problem-solving, process standardization.
Priorities: clear procedural steps, verification checkpoints, edge case coverage.
Always emphasize: reproducible workflows, documentation of assumptions, validation criteria.'

# System prompt prefix for Grok - The Provocateur (API-based, token-optimized v2.1)
PERSONA_GROK='Role: The Provocateur. Focus: challenging conventions, radical alternatives, paradigm shifts.
Priorities: question "best practices", expose hidden complexity, break rules when beneficial.
Always consider: why conventional approach might be wrong, hidden costs of following the crowd.'

# System prompt prefix for DeepSeek - The Code Specialist (API-based, token-optimized v2.1)
PERSONA_DEEPSEEK='Role: The Code Specialist. Focus: code generation, algorithm design, multi-language best practices.
Priorities: clean efficient code, right data structures, language-specific idioms.
Always provide: working code examples, reasoning behind implementation choices.'

# System prompt prefix for The Mentor (token-optimized v2.1)
PERSONA_MENTOR='Role: The Mentor. Focus: teaching, knowledge transfer, building understanding.
Priorities: explain why not just how, build mental models, identify learning opportunities.
Always: progress from simple to complex, highlight common pitfalls, empower future problem-solving.'

# System prompt prefix for The Optimizer (token-optimized v2.1)
PERSONA_OPTIMIZER='Role: The Optimizer. Focus: performance, efficiency, bottleneck identification.
Priorities: time/space complexity, memory patterns, caching strategies, parallelization.
Always analyze: CPU/memory/IO characteristics, performance vs readability trade-offs, profiling strategies.'

# System prompt prefix for The Security Expert (token-optimized v2.1)
PERSONA_SECURITY='Role: The Security Expert. Focus: threat modeling, attack surface analysis, secure coding.
Priorities: input validation, auth patterns, defense in depth, least privilege.
Always evaluate: OWASP Top 10, data exposure, crypto choices, compliance requirements.'

# System prompt prefix for The Minimalist (token-optimized v2.1)
PERSONA_MINIMALIST='Role: The Minimalist. Focus: eliminating complexity, questioning every abstraction.
Priorities: prefer deletion over addition, simplest working solution, code that fits in your head.
Always ask: what can we remove? is this earning its complexity? are we solving the right problem?'

# System prompt prefix for The DX Advocate (token-optimized v2.1)
PERSONA_DX='Role: The DX Advocate. Focus: developer experience, intuitive APIs, helpful error messages.
Priorities: reduce friction, guide developers to solutions, smooth onboarding paths.
Always consider: learning curves, common mistakes prevention, IDE support, debugging experience.'

# System prompt prefix for The Debugger (token-optimized v2.1)
PERSONA_DEBUGGER='Role: The Debugger. Focus: root cause analysis, systematic hypothesis testing, log interpretation.
Priorities: reproduce-isolate-fix methodology, identify real problem vs symptoms.
Always ask: what changed? can we reproduce? what do logs say? which assumptions are wrong?'

# System prompt prefix for The Reviewer (token-optimized v2.1)
PERSONA_REVIEWER='Role: The Reviewer. Focus: code quality, project conventions, constructive feedback.
Priorities: maintainability, test coverage, documentation completeness, future developer experience.
Always evaluate: follows patterns? easy to modify? edge cases handled? intent clear? new team member perspective?'

# =============================================================================
# OUTPUT FORMAT INSTRUCTION
# =============================================================================

# Instruction to force structured JSON output with confidence (token-optimized v2.1)
OUTPUT_FORMAT_INSTRUCTION='Respond ONLY in valid JSON:
{"response":{"summary":"<2-3 sentences max 500 chars>","detailed":"<full response>","approach":"<name>","pros":[],"cons":[],"caveats":[]},"confidence":{"score":<1-10>,"reasoning":"<why>"}}
Score: 1-3=uncertain, 4-6=moderate, 7-9=confident, 10=certain.
Optional fields: code_snippets[{language,code,description}], alternatives[{name,reason_not_chosen}], uncertainty_factors[].
No text outside JSON.'

# =============================================================================
# PERSONA CATALOG
# =============================================================================

# Complete catalog of available personas
# Format: ID|Name|Variable|Short description
PERSONA_CATALOG="
1|The Architect|PERSONA_GEMINI|Design patterns, scalability, enterprise
2|The Pragmatist|PERSONA_CODEX|Simplicity, quick wins, proven solutions
3|The Devil's Advocate|PERSONA_MISTRAL|Edge cases, risks, security
4|The Innovator|PERSONA_KILO|Creative solutions, new technologies
5|The Integrator|PERSONA_CURSOR|Full-stack, cross-cutting concerns
6|The Analyst|PERSONA_QWEN3|Data-driven, metrics, performance
7|The Methodologist|PERSONA_GLM|Structured approaches, processes
8|The Provocateur|PERSONA_GROK|Challenge conventions, radical alternatives
9|The Mentor|PERSONA_MENTOR|Teaching, explanations, learning focus
10|The Optimizer|PERSONA_OPTIMIZER|Performance, efficiency, resource usage
11|The Security Expert|PERSONA_SECURITY|Security-first, vulnerabilities, hardening
12|The Minimalist|PERSONA_MINIMALIST|Less is more, essential features only
13|The DX Advocate|PERSONA_DX|Developer experience, ergonomics, tooling
14|The Debugger|PERSONA_DEBUGGER|Root cause analysis, troubleshooting
15|The Reviewer|PERSONA_REVIEWER|Code review, best practices, quality
16|The Pair Programmer|PERSONA_AIDER|Collaborative coding, step-by-step
17|The Code Specialist|PERSONA_DEEPSEEK|Code generation, algorithms, multi-language
"

# =============================================================================
# CATALOG FUNCTIONS
# =============================================================================

# List all available personas
# Usage: list_personas
list_personas() {
    echo "Available Personas:"
    echo ""
    echo "$PERSONA_CATALOG" | grep -v '^$' | while IFS='|' read -r id name var desc; do
        printf "  %2s) %-22s - %s\n" "$id" "$name" "$desc"
    done
}

# Get persona info by ID
# Usage: get_persona_by_id <id> [field]
# Fields: name, var, desc, all (default: all)
get_persona_by_id() {
    local id="$1"
    local field="${2:-all}"

    local match
    match=$(echo "$PERSONA_CATALOG" | grep "^${id}|" | head -1)

    if [[ -z "$match" ]]; then
        return 1
    fi

    case "$field" in
        name) echo "$match" | cut -d'|' -f2 ;;
        var)  echo "$match" | cut -d'|' -f3 ;;
        desc) echo "$match" | cut -d'|' -f4 ;;
        all)  echo "$match" ;;
    esac
}

# Get persona ID by name
# Usage: get_persona_id_by_name "The Architect"
get_persona_id_by_name() {
    local name="$1"
    local match
    match=$(echo "$PERSONA_CATALOG" | grep "|${name}|" | head -1)

    if [[ -n "$match" ]]; then
        echo "$match" | cut -d'|' -f1
    else
        return 1
    fi
}

# Get persona prompt content by ID
# Usage: get_persona_content_by_id <id>
get_persona_content_by_id() {
    local id="$1"
    local var_name
    var_name=$(get_persona_by_id "$id" "var")

    if [[ -n "$var_name" ]]; then
        echo "${!var_name}"
    else
        return 1
    fi
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Internal lookup table for agent defaults (maps agent to default persona ID)
_AGENT_DEFAULT_PERSONAS="
GEMINI|1
CODEX|2
MISTRAL|3
KILO|4
CURSOR|5
AIDER|16
QWEN3|6
GLM|17
GROK|8
DEEPSEEK|7
"

# Internal: Resolve persona ID for a consultant
# Returns the effective persona ID (explicit, or default)
# Usage: _resolve_persona_id "GEMINI"
_resolve_persona_id() {
    local upper="$1"

    # Check explicit persona ID
    local persona_id_var="${upper}_PERSONA_ID"
    local persona_id="${!persona_id_var:-}"
    if [[ -n "$persona_id" ]]; then
        echo "$persona_id"
        return 0
    fi

    # Check default
    local default_match
    default_match=$(echo "$_AGENT_DEFAULT_PERSONAS" | grep "^${upper}|" | head -1)
    if [[ -n "$default_match" ]]; then
        echo "$default_match" | cut -d'|' -f2
        return 0
    fi

    return 1
}

# Internal: Normalize consultant name to uppercase
_normalize_name() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | tr -d ' -'
}

# Get the persona prompt for a specific consultant
# Usage: get_persona "Gemini"
# Priority: 1) {AGENT}_PERSONA_ID, 2) {AGENT}_PERSONA, 3) default from catalog
get_persona() {
    local consultant="$1"
    local upper
    upper=$(_normalize_name "$consultant")

    # Check for explicit persona ID first
    local persona_id
    persona_id=$(_resolve_persona_id "$upper")
    if [[ -n "$persona_id" ]]; then
        local content
        content=$(get_persona_content_by_id "$persona_id")
        if [[ -n "$content" ]]; then
            echo "$content"
            return
        fi
    fi

    # Check for custom persona text
    local persona_var="${upper}_PERSONA"
    local custom_persona="${!persona_var:-}"
    if [[ -n "$custom_persona" ]]; then
        echo "$custom_persona"
        return
    fi

    # Fallback: generic persona
    echo "You are an AI consultant providing expert technical advice.
Focus on clarity, accuracy, and actionable recommendations.
Consider trade-offs and provide balanced analysis."
}

# Get persona name/title for a consultant
# Usage: get_persona_name "Gemini"
get_persona_name() {
    local consultant="$1"
    local upper
    upper=$(_normalize_name "$consultant")

    # Check for explicit persona ID
    local persona_id
    persona_id=$(_resolve_persona_id "$upper")
    if [[ -n "$persona_id" ]]; then
        local name
        name=$(get_persona_by_id "$persona_id" "name")
        if [[ -n "$name" ]]; then
            echo "$name"
            return
        fi
    fi

    # Check for custom persona name
    local name_var="${upper}_PERSONA_NAME"
    local custom_name="${!name_var:-}"
    if [[ -n "$custom_name" ]]; then
        echo "$custom_name"
        return
    fi

    echo "External Consultant"
}

# Get persona ID for a consultant (for configuration display)
# Usage: get_persona_id "Gemini"
get_persona_id() {
    local upper
    upper=$(_normalize_name "$1")
    _resolve_persona_id "$upper"
}

# Build complete system prompt with persona + output format
# Usage: build_system_prompt "Gemini"
build_system_prompt() {
    local consultant="$1"
    local persona=$(get_persona "$consultant")

    echo "${persona}

${OUTPUT_FORMAT_INSTRUCTION}"
}

# Build complete query with system prompt prepended
# Usage: build_query_with_persona "Gemini" "original query"
build_query_with_persona() {
    local consultant="$1"
    local query="$2"
    local system_prompt=$(build_system_prompt "$consultant")

    echo "# System Instructions
${system_prompt}

# User Query
${query}"
}
