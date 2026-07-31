#!/usr/bin/env bash
# Record the agentic loop demo with asciinema inside a tmux session.
#
# Layout:
#   ┌─────────────────────┬────────────────────┐
#   │  MCP server         │  vLLM logs         │
#   ├─────────────────────┴────────────────────┤
#   │  Praxis logs                             │
#   ├──────────────────────────────────────────┤
#   │  curl commands (demo runner)             │
#   └──────────────────────────────────────────┘
#
# Prerequisites:
#   - vLLM running: podman run --name vllm ...
#   - praxis-ai on $PATH (or set PRAXIS_BIN)
#
# Usage:
#   ./record.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAST_FILE="$SCRIPT_DIR/demo.cast"
SESSION="praxis-agentic-loop-demo"
PRAXIS_BIN="${PRAXIS_BIN:-$(command -v praxis-ai 2>/dev/null || echo "")}"
CONFIG="$SCRIPT_DIR/agentic-loop.yaml"

# Resolve to absolute path (relative paths break after cd)
if [ -n "$PRAXIS_BIN" ] && [ -f "$PRAXIS_BIN" ]; then
    PRAXIS_BIN="$(cd "$(dirname "$PRAXIS_BIN")" && pwd)/$(basename "$PRAXIS_BIN")"
else
    echo "error: praxis-ai not found. Either:"
    echo "  - add it to PATH"
    echo "  - set PRAXIS_BIN=/path/to/praxis-ai"
    exit 1
fi

# Kill any leftover session
tmux kill-session -t "$SESSION" &>/dev/null || true

# Kill any praxis already on :8080 or MCP server on :9100
lsof -ti :8080 | xargs kill &>/dev/null || true
lsof -ti :9100 | xargs kill &>/dev/null || true
sleep 0.5

# Clean up any leftover SQLite DB from previous runs
rm -f "$SCRIPT_DIR/responses.db"*

# ── Build the 4-pane layout ──────────────────────────────────────────
#
# Build top-down with stable pane targeting:
#   1. new-session → pane 0 (MCP server, top-left)
#   2. split 0 vertically → 0=MCP top, 1=Praxis bottom-half
#   3. split 1 vertically → 1=Praxis middle, 2=curl bottom
#   4. split 0 horizontally → 0=MCP left, 3=vLLM right
#
# Each pane ends with `read` so it stays open even if the
# command exits early (prevents pane index shifts).

# Pane 0: MCP mock server (top-left)
tmux new-session -d -s "$SESSION" -x 200 -y 50 \
    "printf '\033[1;34m── MCP Server ──\033[0m\n'; \
     python3 $SCRIPT_DIR/mcp_server.py 2>&1; \
     echo 'MCP server exited'; read"

# Wait for MCP server to be ready
printf "Waiting for MCP server on :9100..."
for i in $(seq 1 30); do
    if curl -s -o /dev/null -X POST http://127.0.0.1:9100/mcp \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' 2>/dev/null; then
        printf " ready.\n"
        break
    fi
    printf "."
    sleep 1
done

# Pane 1: Praxis (middle row, full width)
tmux split-window -v -t "${SESSION}:0.0" -p 70 \
    "printf '\033[1;33m── Praxis Logs ──\033[0m\n'; \
     cd $SCRIPT_DIR && \
     RUST_LOG=praxis_filter=debug $PRAXIS_BIN -c $CONFIG 2>&1 \
     | grep --line-buffered -E 'classified|mcp|tool_resolve|tool_parse|dispatch|agentic|loop|iteration|transition|function_call|tool_call|route matched|upstream selected|listening|ready|error|ERROR|panic|WARN|warn|unknown|invalid|failed'; \
     echo 'Praxis exited'; read"

# Pane 2: curl demo (bottom row, full width)
tmux split-window -v -t "${SESSION}:0.1" -p 50 \
    "$SCRIPT_DIR/run-demo.sh; tmux wait-for -S demo-done"

# Pane 3: vLLM logs (top-right, split from MCP server)
tmux split-window -h -t "${SESSION}:0.0" -p 50 \
    "printf '\033[1;35m── vLLM Logs ──\033[0m\n'; \
     podman logs -f vllm 2>&1 | grep --line-buffered -vE '^\$'; \
     echo 'vLLM logs ended — is the container running?'; read"

# Focus the curl pane
tmux select-pane -t "${SESSION}:0.2"

sleep 2

# Record the full tmux session
asciinema rec \
    --overwrite \
    --title "Praxis — Agentic Loop with MCP Tool Calling" \
    --idle-time-limit 3 \
    --command "tmux attach -t $SESSION" \
    "$CAST_FILE"

# Cleanup
tmux kill-session -t "$SESSION" &>/dev/null || true
lsof -ti :8080 | xargs kill &>/dev/null || true
lsof -ti :9100 | xargs kill &>/dev/null || true

printf "\nRecording saved to %s\n" "$CAST_FILE"
