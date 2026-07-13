#!/bin/bash
# stub_cli.sh - Offline stand-in for a consultant CLI (claude/codex/agy/vibe).
#
# Ignores all arguments and any stdin, and prints a single valid consultant
# response envelope (matching lib/schema.json) to stdout. Used by test_e2e.sh
# to drive consult_all.sh's full pipeline without hitting real network CLIs.
#
# Environment variables:
#   STUB_APPROACH - value for response.approach (default: "approach-alpha"),
#                   lets a test give different consultants different
#                   approaches to exercise voting/consensus.
#
# Usage: stub_cli.sh [any args...] (stdin, if any, is drained and ignored)
set -uo pipefail

# Drain stdin if any is piped in, without blocking on a terminal.
if [[ ! -t 0 ]]; then
    cat >/dev/null
fi

APPROACH="${STUB_APPROACH:-approach-alpha}"

jq -n --arg approach "$APPROACH" '{
    consultant: "Claude",
    model: "stub-model",
    persona: "The Architect",
    response: {
        summary: "Stubbed offline summary for integration testing.",
        detailed: "This is a canned detailed response used to drive the pipeline end-to-end without a real CLI.",
        approach: $approach,
        pros: ["fast", "deterministic"],
        cons: ["not a real answer"],
        caveats: ["stubbed response for testing only"]
    },
    confidence: {
        score: 7,
        reasoning: "Stubbed confidence for offline testing.",
        uncertainty_factors: ["no real model was queried"]
    },
    metadata: {
        tokens_used: 42,
        latency_ms: 1,
        timestamp: "2026-01-01T00:00:00Z"
    }
}'
