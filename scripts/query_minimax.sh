#!/bin/bash
# query_minimax.sh - Query MiniMax via HTTP API
#
# Usage: ./query_minimax.sh "question" [context_file] [output_file]
#
# Environment variables:
#   MINIMAX_API_KEY    - API key for MiniMax (required)
#   MINIMAX_MODEL      - Model to use (default: MiniMax-M2.5)
#   MINIMAX_TIMEOUT    - Timeout in seconds (default: 180)
#   ENABLE_PERSONA     - Enable "The Pragmatic Optimizer" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/api_query.sh"

run_api_consultant "MiniMax" "$@"
