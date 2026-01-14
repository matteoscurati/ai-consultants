#!/bin/bash
# query_grok.sh - Query Grok (xAI) via HTTP API (v2.0 with Persona and Confidence)
#
# Usage: ./query_grok.sh "question" [context_file] [output_file]
#
# Environment variables:
#   GROK_API_KEY    - API key for xAI (required)
#   GROK_MODEL      - Model to use (default: grok-beta)
#   GROK_TIMEOUT    - Timeout in seconds (default: 180)
#   ENABLE_PERSONA  - Enable "The Provocateur" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/api_query.sh"

run_api_consultant "Grok" "$@"
