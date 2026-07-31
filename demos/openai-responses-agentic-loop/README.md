# Agentic Loop — MCP Tool Calling

[![asciicast](https://asciinema.org/a/UsStPVPQaQXkrnyQ.svg)](https://asciinema.org/a/UsStPVPQaQXkrnyQ)

A demo of **Praxis** running a full agentic loop: the model calls an MCP
tool, Praxis dispatches the call to the MCP server, feeds the result back
to the model, and the model produces a final answer. No client-side
orchestration needed — the proxy handles the entire tool-call loop
server-side via the `iterative_request_router`.

## What it shows

| Step | What happens |
|------|--------------|
| 1 | Simple request with no tools — model answers directly, no loop |
| 2 | MCP tool call (weather in SF) — model calls `get_weather`, Praxis dispatches to MCP, loops back with result |
| 3 | MCP tool call (weather in Paris) — same flow, different city |

### Key behaviors

- **Server-side agentic loop**: the `iterative_request_router` (IRR)
  drives the model-tool-model cycle entirely within the proxy
- **MCP tool resolution**: `openai_mcp_tool_resolve` discovers available
  tools from the MCP server at request time via `tools/list`
- **MCP tool dispatch**: `openai_mcp_dispatch` executes `tools/call`
  when the model emits a function call, then triggers a loop transition
  back to inference with the result
- **Agentic loop control**: `agentic_loop` extracts completed function
  calls from the model response and coordinates with MCP dispatch
- **No streaming in loop**: IRR buffers responses within the loop —
  only the final answer is returned to the client
- **Client function calls pass through**: non-MCP function calls are
  returned to the client without looping

## Architecture

```text
┌────────┐       ┌──────────────────────────────────────────────┐
│ client │──────▸│            Praxis (127.0.0.1:8080)           │
│ (curl) │       │                                              │
└────────┘       │  format → validate → tool_parse              │
                 │    → store → rehydrate → mcp_tool_resolve    │
                 │                                              │
                 │  ┌─ iterative_request_router ─────────────┐  │
                 │  │                                        │  │
                 │  │  mcp_dispatch → agentic_loop           │  │
                 │  │    → responses_proxy → router ─────────│──│──▸ vLLM (:8000)
                 │  │                                        │  │
                 │  │  model emits tool_call?                │  │
                 │  │    yes → mcp_dispatch ─────────────────│──│──▸ MCP (:9100)
                 │  │          loop back to inference        │  │
                 │  │    no  → done, return to client        │  │
                 │  └────────────────────────────────────────┘  │
                 └──────────────────────────────────────────────┘
```

## Prerequisites

- **Praxis AI** built from source (`cargo build -p praxis-ai-proxy --release`)
- **vLLM** running with a tool-calling model (e.g. `Qwen/Qwen3-0.6B`)
- **Python 3** (for the mock MCP server)
- **tmux** and **asciinema** (for recording only)

## Quick start

```bash
# Terminal 1: start vLLM
podman run --name vllm -p 8000:8000 \
  vllm/vllm-openai:latest --model Qwen/Qwen3-0.6B

# Terminal 2: start the mock MCP server
cd demos/openai-responses-agentic-loop
python3 mcp_server.py

# Terminal 3: start Praxis AI
cd demos/openai-responses-agentic-loop
RUST_LOG=praxis_filter=debug praxis-ai -c agentic-loop.yaml

# Terminal 4: send a request with an MCP tool
curl -s http://127.0.0.1:8080/v1/responses \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "input": "What is the weather in San Francisco?",
    "tools": [{
      "type": "mcp",
      "server_label": "weather",
      "server_url": "http://127.0.0.1:9100/mcp",
      "allowed_tools": ["get_weather"],
      "require_approval": "never"
    }]
  }' | jq .
```

## Recording the demo

```bash
./record.sh
```

Play back:

```bash
asciinema play demo.cast
```

## What to look for

### MCP server logs

```
[MCP] POST /mcp 200    # tools/list (resolve phase)
[MCP] POST /mcp 200    # tools/call (dispatch phase)
```

### Praxis logs

```
classified format=openai_responses          # request classified
mcp_tool_resolve discovered tools           # tools/list from MCP server
iteration 1: inference                      # first inference call
agentic_loop detected function_call         # model wants to call a tool
mcp_dispatch executing tools/call           # Praxis calls MCP server
transition action=loop next=inference       # loop back with result
iteration 2: inference                      # second inference call
done                                        # final answer returned
```

### What vLLM sees

Two inference calls per MCP request:

1. **Initial**: user message + tool definitions (model emits a `function_call`)
2. **Post-tool**: user message + tool definitions + function call + tool result (model produces the final answer)

## Files

| File | Description |
|------|-------------|
| `agentic-loop.yaml` | Praxis config: IRR + MCP resolve/dispatch + agentic loop |
| `mcp_server.py` | Mock MCP server with `get_weather` tool (port 9100) |
| `record.sh` | Set up tmux + asciinema recording (4-pane layout) |
| `run-demo.sh` | Demo runner: no-tool request, SF weather, Paris weather |
| `demo.cast` | Recorded asciinema session |
