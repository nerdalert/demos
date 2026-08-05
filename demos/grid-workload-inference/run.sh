#!/usr/bin/env bash
set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLB_DIR="$(cd "${DEMO_DIR}/../grid-glb-demo" && pwd)"
export GRID_DEMO_ENTRYPOINT="grid-workload-inference"
exec "$(dirname "${DEMO_DIR}")/../scripts/run-grid-demo.sh" "${GLB_DIR}" --no-ingress "$@"
