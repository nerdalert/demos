# Grid Combined-Site Demo

Three Kubernetes clusters (west, central, east) where every cluster runs both
the consumer and provider sides of the inference path as separate workloads.
There is no public entry point, GTM emulator, or separate edge cluster. The
topology matches the compact combined-site installation while remaining a
disposable Kind demo.

## Topology

```text
+-------------------------+ +-------------------------+ +-------------------------+
| west cluster            | | central cluster         | | east cluster            |
|                         | |                         | |                         |
| workload                | | workload                | | workload                |
|    |                    | |    |                    | |    |                    |
|    v                    | |    v                    | |    v                    |
| consumer gateway        | | consumer gateway        | | consumer gateway        |
|    | Grid selection     | |    | Grid selection     | |    | Grid selection     |
|    v                    | |    v                    | |    v                    |
| provider gateway        | | provider gateway        | | provider gateway        |
|    |                    | |    |                    | |    |                    |
|    v                    | |    v                    | |    v                    |
| private inference       | | private inference       | | private inference       |
+-------------------------+ +-------------------------+ +-------------------------+
              ^                     ^                     ^
              |                     |                     |
              +----- eligible remote provider paths -----+

3 Kind clusters, model=mock-model, colocated consumer/provider roles
```

## What It Proves

- Consumer and secured provider roles colocated at each site
- Three Kind clusters become healthy with three-site SWIM membership
- Each site receives a versioned routing overlay
- Each workload reaches its local consumer gateway
- All three local simulated providers serve successful requests
- Provider-gateway mTLS, peer authorization, credential replacement,
  and backend NetworkPolicy enforced
- Remote provider fallback after local provider drain
- Routing returns to restored local provider after overlay hot reload

## Prerequisites

- A local [praxis-proxy/grid](https://github.com/praxis-proxy/grid) checkout (or set `GRID_REPO`)
- Docker
- kind, kubectl on `PATH`
- Rust stable 1.96+
- Capacity for three single-node Kind clusters

## Registry Images

```bash
export GRID_XTASK_GATEWAY_IMAGE=ghcr.io/praxis-proxy/grid-ai-rollup:v0.1.1
export GRID_XTASK_OPERATOR_IMAGE=ghcr.io/praxis-proxy/grid-operator:v0.1.1
export GRID_XTASK_MOCK_PROVIDER_IMAGE=ghcr.io/praxis-proxy/grid-mock-providers:v0.1.1
export GRID_XTASK_IMAGE_PULL_POLICY=IfNotPresent
```

## Quick Start

```bash
./run.sh --quick --teardown
```

## Full Mode

```bash
./run.sh --full --teardown
```

Full mode adds local-provider preference, remote-provider fallback after drain,
existing-session behavior during drain, sequential Grid operator restart
recovery, and sustained inference after recovery.

## Teardown and Keep-on-Failure

`--teardown` deletes all Kind clusters after the run, including on failure.
Add `--keep-on-failure` to retain clusters when a proof fails:

```bash
./run.sh --quick --teardown --keep-on-failure
```

## Evidence

Each run writes human-readable narration and machine-readable `results.json`
to the evidence directory.

See [e2e-demo-output.txt](e2e-demo-output.txt) for checked-in example output
from a quick cold run.

## Known Limitations

- No public traffic entry, GTM emulation, or DNS failover.
- No regional affinity or enforced region locking.
- Consumer and provider gateways are separate Deployments; they are not
  collapsed into one process.
- Kind networking does not represent production latency or failure modes.
- Simulated inference providers return canned responses.

## Implementation Documentation

See the [Grid repository](https://github.com/praxis-proxy/grid) for full
architecture, design documentation, and implementation details.
