#!/bin/bash
# classify_question.sh - Question classifier for smart routing
#
# Classifies questions by type to optimize consultant selection.
#
# Usage: ./classify_question.sh "question"   (or - to read it from stdin)
# Output: category (CODE_REVIEW, ARCHITECTURE, BUG_DEBUG, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

QUESTION="${1:-}"
# "-" reads the question from stdin so callers never need to put a large
# question in argv.
if [[ "$QUESTION" == "-" ]]; then
    QUESTION=$(cat)
fi

if [[ -z "$QUESTION" ]]; then
    log_error "Usage: $0 \"question\""
    exit 1
fi

# =============================================================================
# PATTERN-BASED CLASSIFICATION (fast, no API call)
# =============================================================================

classify_by_patterns() {
    local question="$1"
    local q_lower=$(echo "$question" | tr '[:upper:]' '[:lower:]')

    # SECURITY first: security questions routinely also say "fix", "check",
    # "design", "review" or "performance", and matching those broader
    # categories first meant SECURITY almost never won. The patterns avoid
    # bare "auth"/"token" substrings ("author", "tokens per second"), and
    # design-pattern or testing injections (dependency, constructor, field,
    # fault injection) are removed first: they are not injection attacks.
    local q_security
    q_security=$(printf '%s\n' "$q_lower" | sed -E 's/(dependency|constructor|setter|field|property|method|interface|fault)[ -]injection//g')
    if echo "$q_security" | grep -qE '(^|[^a-z])(security|secure|vulnerab[a-z]*|exploit[a-z]*|cve-[0-9]|xss|csrf|ssrf|sqli|jwt|oauth[0-9]*|auth|authn|authz|authenticat[a-z]*|authoriz[a-z]*|password[s]?|encrypt[a-z]*|decrypt[a-z]*|secret[s]?|sanitiz[a-z]*)([^a-z]|$)|injection|access token|api key'; then
        echo "SECURITY"
        return 0
    fi

    # CODE_REVIEW patterns
    if echo "$q_lower" | grep -qE 'review|check|code review|analyze.*code|quality|qualit'; then
        echo "CODE_REVIEW"
        return 0
    fi

    # BUG_DEBUG patterns
    if echo "$q_lower" | grep -qE 'bug|error|crash|fix|debug|problem|issue|not working|fails|exception|traceback'; then
        echo "BUG_DEBUG"
        return 0
    fi

    # ARCHITECTURE patterns
    if echo "$q_lower" | grep -qE 'architect|design|pattern|structure|microservic|monolit|scalabil|refactor|organiz|system design'; then
        echo "ARCHITECTURE"
        return 0
    fi

    # ALGORITHM patterns
    if echo "$q_lower" | grep -qE 'algorithm|optimi|performance|complexit|O\(|big-o|efficien|sort|search|data structure'; then
        echo "ALGORITHM"
        return 0
    fi

    # QUICK_SYNTAX patterns
    if echo "$q_lower" | grep -qE 'syntax|how to write|example of|snippet|one-liner'; then
        echo "QUICK_SYNTAX"
        return 0
    fi

    # DATABASE patterns
    if echo "$q_lower" | grep -qE 'database|sql|query|mongodb|postgres|mysql|redis|index|migration|schema'; then
        echo "DATABASE"
        return 0
    fi

    # API patterns
    if echo "$q_lower" | grep -qE 'api|rest|graphql|endpoint|request|response|http|webhook'; then
        echo "API_DESIGN"
        return 0
    fi

    # TESTING patterns
    if echo "$q_lower" | grep -qE 'test|testing|unit test|integration|mock|stub|coverage|tdd|bdd'; then
        echo "TESTING"
        return 0
    fi

    # Default
    echo "GENERAL"
    return 0
}

# =============================================================================
# LLM-BASED CLASSIFICATION (more accurate, requires API)
# =============================================================================

classify_with_llm() {
    local question="$1"

    local prompt="Classify this programming question into ONE category only:

CATEGORIES:
- CODE_REVIEW: Code review, quality analysis, best practices
- BUG_DEBUG: Debugging, error fixing, troubleshooting
- ARCHITECTURE: System design, patterns, project structure
- ALGORITHM: Algorithms, data structures, complexity, optimization
- SECURITY: Security, vulnerabilities, authentication
- QUICK_SYNTAX: Quick syntax questions, snippets, one-liners
- DATABASE: SQL queries, schema design, database operations
- API_DESIGN: API design, REST, GraphQL, endpoints
- TESTING: Unit testing, integration testing, TDD
- GENERAL: Other

QUESTION: $question

Reply ONLY with the category name (e.g.: ARCHITECTURE), nothing else."

    # Same boundary as synthesis: never ask the invoking host to classify for
    # itself, bound the call, and run it stateless, tool-free and on the
    # economy model (classification needs one word, not the premium tier).
    local claude_cmd="${CLAUDE_CMD:-claude}"
    if [[ "$(get_self_consultant_name)" != "CLAUDE" ]] && command -v "$claude_cmd" &> /dev/null; then
        local result
        result=$(printf '%s' "$prompt" | run_with_timeout "${CLASSIFICATION_TIMEOUT:-30}" \
            "$claude_cmd" --print --no-session-persistence --setting-sources "" --tools "" \
            --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
            --model "$(get_model_for_tier claude economy)" 2>/dev/null \
            | tr -d '\n' | tr '[:lower:]' '[:upper:]' || true)
        # Validate that it's a valid category
        case "$result" in
            CODE_REVIEW|BUG_DEBUG|ARCHITECTURE|ALGORITHM|SECURITY|QUICK_SYNTAX|DATABASE|API_DESIGN|TESTING|GENERAL)
                echo "$result"
                return 0
                ;;
            *)
                # Fallback to pattern matching
                classify_by_patterns "$question"
                return 0
                ;;
        esac
    else
        # No LLM available, use pattern matching
        classify_by_patterns "$question"
        return 0
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# Use classification mode from config or default to pattern
CLASSIFICATION_MODE="${CLASSIFICATION_MODE:-pattern}"

case "$CLASSIFICATION_MODE" in
    llm)
        classify_with_llm "$QUESTION"
        ;;
    pattern|*)
        classify_by_patterns "$QUESTION"
        ;;
esac
