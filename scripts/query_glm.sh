#!/bin/bash
# query_glm.sh - Query GLM (Zhipu AI) via HTTP API (v2.0 with Persona and Confidence)
#
# Usage: ./query_glm.sh "question" [context_file] [output_file]
#
# Environment variables:
#   GLM_API_KEY     - API key for Zhipu AI (required)
#   GLM_MODEL       - Model to use (default: glm-4)
#   GLM_TIMEOUT     - Timeout in seconds (default: 180)
#   ENABLE_PERSONA  - Enable "The Methodologist" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/api_query.sh"

run_api_consultant "GLM" "$@"
