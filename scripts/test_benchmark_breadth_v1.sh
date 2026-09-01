#!/bin/bash
# Offline-only breadth-v1 harness regression. Its runner is a fail-closed sentinel.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/benchmarks/breadth-v1/scripts/test_breadth_v1.sh"
