# Grid LLM-d Pool Metrics Demo

Proves that simulated inference telemetry drives real EPP aggregation, Grid
scoring, overlay publication, and Praxis routing decisions across two Kind
clusters. Inference simulators emit controlled metric values; every other
component -- llm-d EPP, Grid operator, overlay delivery, Praxis routing -- runs
its production code path.

## Topology

```text
+-------------------------------+  +-------------------------------+
|         Kind: pool-a          |  |         Kind: pool-b          |
|                               |  |                               |
|  sim-1 --+                    |  |  sim-1 --+                    |
|           +-> llm-d EPP <-+  |  |           +-> llm-d EPP <-+  |
|  sim-2 --+    :9090    Grid|  |  |  sim-2 --+    :9090    Grid|  |
|                     Operator|  |  |                     Operator|  |
|  provider-gateway (mTLS)    |  |  |  provider-gateway (mTLS)    |  |
|  consumer-gateway <- overlay|  |  |  consumer-gateway <- overlay|  |
+---------------+-------------+  +---------------+-------------+
                |       SWIM mesh (UDP)           |
                +---------------------------------+

2 Kind clusters, model=llmd-sim-model, scoreFirst routing
```

## What It Proves

- llm-d EPP aggregates per-simulator metrics into pool-level summaries
- Grid operator scrapes EPP and scores backends with production scoring engine
- Metrics-driven preference flip: Pool A pressure causes B to outrank A
- A-to-B-to-A capacity failover as Pool A ramp resets
- Content-addressed overlay published and hot-reloaded without pod restart
- Scorecard shows raw metrics, weighted scores, and ranks from the same overlay
  revision
- Metrics TLS lifecycle (9 stages): baseline mTLS, handshake rejection,
  missing client identity, wrong CA, valid restore, stale-cache TTL expiry
  and recovery, client cert rotation, server cert rotation with nginx
  restart, and end-to-end routing verification after the full TLS cycle

## Prerequisites

- A local [praxis-proxy/grid](https://github.com/praxis-proxy/grid) checkout (or set `GRID_REPO`)
- Docker or Podman
- kind
- Rust stable 1.96+
- Approximately 4 GB RAM for two Kind clusters

## Registry Images (Grid v0.1.2+)

This demo requires Grid v0.1.2 or later. The v0.1.1 operator image does not
contain the mTLS metrics scraping pipeline needed for the TLS proof stages.

```bash
export GRID_XTASK_GATEWAY_IMAGE=ghcr.io/praxis-proxy/grid-ai-rollup:v0.1.1
export GRID_XTASK_OPERATOR_IMAGE=ghcr.io/praxis-proxy/grid-operator:v0.1.2
export GRID_XTASK_EPP_IMAGE=ghcr.io/llm-d/llm-d-inference-scheduler:v0.8.0
export GRID_XTASK_SIM_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:v0.10.2
export GRID_XTASK_NGINX_IMAGE=docker.io/library/nginx:1.27.4-alpine
export GRID_XTASK_OVERLAY_SYNC_IMAGE=ghcr.io/praxis-proxy/grid-overlay-sync:v0.1.2
export GRID_XTASK_IMAGE_PULL_POLICY=IfNotPresent
```

The rollup remains at `v0.1.1` because Grid v0.1.2 did not change the temporary
Praxis AI rollup image. Grid v0.1.2 supplies the updated operator and
overlay-sync images.

The complete image set is:

| Image | Env var | Purpose |
|-------|---------|---------|
| `llm-d-epp` | `GRID_XTASK_EPP_IMAGE` | llm-d Endpoint Picker / metrics aggregator |
| `llm-d-inference-sim` | `GRID_XTASK_SIM_IMAGE` | vLLM-compatible inference simulator |
| `nginx` | `GRID_XTASK_NGINX_IMAGE` | TLS proxy for EPP metrics scraping (official image, no custom build) |
| `grid-overlay-sync` | `GRID_XTASK_OVERLAY_SYNC_IMAGE` | Overlay ConfigMap delivery sidecar |

## Quick Start

```bash
./run.sh --quick --teardown
```

## Full Mode

```bash
./run.sh --full --teardown
```

Full mode adds the pressure-flip and recovery proofs (approximately 4 minutes
additional for the 120-second simulator ramp cycle).

## Teardown and Keep-on-Failure

`--teardown` deletes both Kind clusters after the run, including on failure.
Add `--keep-on-failure` to retain clusters when a proof fails:

```bash
./run.sh --quick --teardown --keep-on-failure
```

## Evidence

Each run writes evidence to the evidence directory (default: `evidence/`).
See [e2e-demo-output.txt](e2e-demo-output.txt) for checked-in example output
from a full cold run.

## Known Limitations

- Simulated telemetry only; `--fake-metrics` generators produce controlled ramp
  patterns, not measurements from real GPU inference workloads.
- No P99 latency or prefix-cache derivation; both signals default to 0.5
  (neutral).
- Two-pool topology; each cluster's own provider scores with full locality
  (1.0) while the remote peer scores at 0.5.
- No cost signal; defaults to 0.5.
- No hysteresis or minimum switch margin; a 0.01-point score difference
  triggers a rank change.
- Missing telemetry scores neutrally, which can cause an unobservable provider
  to outrank one with known high pressure.

## Implementation Documentation

See the [Grid repository](https://github.com/praxis-proxy/grid) for full
architecture, scoring model, and implementation details.
