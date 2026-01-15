#!/bin/bash
# query_deepseek.sh - Query DeepSeek via HTTP API (v2.0 with Persona and Confidence)
#
# Usage: ./query_deepseek.sh "question" [context_file] [output_file]
#
# Environment variables:
#   DEEPSEEK_API_KEY   - API key for DeepSeek (required)
#   DEEPSEEK_MODEL     - Model to use (default: deepseek-coder)
#   DEEPSEEK_TIMEOUT   - Timeout in seconds (default: 180)
#   ENABLE_PERSONA     - Enable "The Code Specialist" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/api_query.sh"

run_api_consultant "DeepSeek" "$@"
