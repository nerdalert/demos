# Grid LLM-d Pool Metrics Demo

Proves that simulated inference telemetry drives real EPP aggregation, Grid
scoring, overlay publication, and Praxis routing decisions across two Kind
clusters. Inference simulators emit controlled metric values; every other
component -- llm-d EPP, Grid operator, overlay delivery, Praxis routing -- runs
its production code path.

## Metrics Transport

llm-d EPP normally exposes Prometheus metrics over HTTP on port `9090`. In the
default demo mode, Grid scrapes that endpoint directly. This is the simplest
path for development and matches an llm-d deployment without a separate
metrics security layer.

The optional `--metrics-mtls` mode adds nginx in front of the EPP metrics
endpoint. nginx requires a Grid operator client certificate, terminates TLS on
port `9443`, and forwards the scrape to EPP over local HTTP. nginx is a demo
component, not part of llm-d, and it never handles inference traffic.

```text
Default:  Grid operator ---- HTTP ----> llm-d EPP :9090/metrics

mTLS:     Grid operator -- HTTPS/mTLS -> nginx :9443
                                            |
                                            +-- HTTP -> llm-d EPP :9090/metrics
```

In production, the same protection could be provided by a service mesh,
platform proxy, or an EPP implementation with native TLS. The nginx mode
exists to validate Grid's client-certificate support without requiring one of
those platform-specific integrations.

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
- Optional metrics TLS lifecycle (9 stages): baseline mTLS, handshake rejection,
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
export GRID_XTASK_OVERLAY_SYNC_IMAGE=ghcr.io/praxis-proxy/grid-overlay-sync:v0.1.2
export GRID_XTASK_IMAGE_PULL_POLICY=IfNotPresent
```

Only the optional mTLS mode also needs nginx:

```bash
export GRID_XTASK_NGINX_IMAGE=docker.io/library/nginx:1.27.4-alpine
```

The rollup remains at `v0.1.1` because Grid v0.1.2 did not change the temporary
Praxis AI rollup image. Grid v0.1.2 supplies the updated operator and
overlay-sync images.

The complete image set is:

| Image | Env var | Purpose |
|-------|---------|---------|
| `llm-d-epp` | `GRID_XTASK_EPP_IMAGE` | llm-d Endpoint Picker / metrics aggregator |
| `llm-d-inference-sim` | `GRID_XTASK_SIM_IMAGE` | vLLM-compatible inference simulator |
| `nginx` | `GRID_XTASK_NGINX_IMAGE` | Optional mTLS proxy for EPP metrics; not an llm-d component |
| `grid-overlay-sync` | `GRID_XTASK_OVERLAY_SYNC_IMAGE` | Overlay ConfigMap delivery sidecar |

## Quick Start

```bash
./run.sh --quick --teardown
```

This default path scrapes EPP directly over HTTP and does not deploy nginx or
metrics TLS certificates.

To validate an mTLS-protected metrics endpoint:

```bash
./run.sh --quick --metrics-mtls --teardown
```

The mTLS path adds the nine certificate, failure, rotation, recovery, and
routing proof stages. It fails closed and never falls back to plaintext.

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
