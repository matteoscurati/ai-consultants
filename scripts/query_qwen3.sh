#!/bin/bash
# query_qwen3.sh - Query Qwen3 via HTTP API (v2.0 with Persona and Confidence)
#
# Usage: ./query_qwen3.sh "question" [context_file] [output_file]
#
# Environment variables:
#   QWEN3_API_KEY   - API key for Alibaba DashScope (required)
#   QWEN3_MODEL     - Model to use (default: qwen-max)
#   QWEN3_TIMEOUT   - Timeout in seconds (default: 180)
#   ENABLE_PERSONA  - Enable "The Analyst" persona (default: true)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/api_query.sh"

run_api_consultant "Qwen3" "$@"
