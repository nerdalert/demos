#!/usr/bin/env bash
# Demo runner — agentic loop with MCP tool calling.
set -uo pipefail

PRAXIS="http://127.0.0.1:8080"
MCP_URL="http://127.0.0.1:9100/mcp"
MODEL="Qwen/Qwen3-0.6B"
TYPE_DELAY=0.04

type_cmd() {
    local cmd="$1"
    printf "\n"
    printf '\033[1;32m$ \033[0m'
    for (( i=0; i<${#cmd}; i++ )); do
        printf '%s' "${cmd:$i:1}"
        sleep "$TYPE_DELAY"
    done
    printf "\n"
    sleep 0.3
}

banner() {
    printf "\n\033[1;36m## %s\033[0m\n" "$1"
    sleep 1.5
}

sleep 2

# ── Step 1: Simple request (no tools) ─────────────────────────────────

banner "1. Simple request — no MCP tools"
printf "Send a plain request with no tools. The model answers\n"
printf "directly — no agentic loop, no MCP calls.\n"
sleep 1

CMD='curl -s '"$PRAXIS"'/v1/responses -H "Content-Type: application/json" -d '\''{"model":"'"$MODEL"'","input":"What is 2+2? Answer in one word."}'\'' | jq .'
type_cmd "$CMD"
RESPONSE=$(curl -s "$PRAXIS"/v1/responses \
    -H "Content-Type: application/json" \
    -d '{"model":"'"$MODEL"'","input":"What is 2+2? Answer in one word."}')
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
ANSWER=$(echo "$RESPONSE" | jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' 2>/dev/null || echo "")

if [ -n "$ANSWER" ]; then
    printf "\n\033[1;32m↳ No tool calls — straight answer.\033[0m\n"
fi
sleep 3

# ── Step 2: MCP tool call — weather in San Francisco ──────────────────

banner "2. MCP tool call — weather in San Francisco"
printf "Send a request with an MCP tool definition pointing at\n"
printf "the mock weather server. The model calls get_weather,\n"
printf "Praxis dispatches to MCP, loops back with the result.\n"
sleep 1

CMD='curl -s '"$PRAXIS"'/v1/responses -H "Content-Type: application/json" -d '\''{"model":"'"$MODEL"'","input":"What is the weather in San Francisco?","tools":[{"type":"mcp","server_label":"weather","server_url":"'"$MCP_URL"'","allowed_tools":["get_weather"],"require_approval":"never"}]}'\'' | jq .'
type_cmd "$CMD"
RESPONSE2=$(curl -s "$PRAXIS"/v1/responses \
    -H "Content-Type: application/json" \
    -d '{"model":"'"$MODEL"'","input":"What is the weather in San Francisco?","tools":[{"type":"mcp","server_label":"weather","server_url":"'"$MCP_URL"'","allowed_tools":["get_weather"],"require_approval":"never"}]}')
echo "$RESPONSE2" | jq . 2>/dev/null || echo "$RESPONSE2"

TOOL_CALLS=$(echo "$RESPONSE2" | jq '[.output[] | select(.type == "mcp_call")]' 2>/dev/null || echo "[]")
TOOL_COUNT=$(echo "$TOOL_CALLS" | jq 'length' 2>/dev/null || echo "0")
ANSWER2=$(echo "$RESPONSE2" | jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' 2>/dev/null || echo "")

if [ "$TOOL_COUNT" -gt 0 ]; then
    printf "\n\033[1;33m↳ %s MCP tool call(s) dispatched by Praxis.\033[0m\n" "$TOOL_COUNT"
fi
if [ -n "$ANSWER2" ]; then
    printf "\033[1;32m↳ Model answered:\033[0m %s\n" "$ANSWER2"
fi
sleep 3

# ── Step 3: MCP tool call — weather in Paris ──────────────────────────

banner "3. MCP tool call — weather in Paris"
printf "Same flow, different city. Shows the loop is repeatable.\n"
sleep 1

CMD='curl -s '"$PRAXIS"'/v1/responses -H "Content-Type: application/json" -d '\''{"model":"'"$MODEL"'","input":"What is the weather in Paris?","tools":[{"type":"mcp","server_label":"weather","server_url":"'"$MCP_URL"'","allowed_tools":["get_weather"],"require_approval":"never"}]}'\'' | jq .'
type_cmd "$CMD"
RESPONSE3=$(curl -s "$PRAXIS"/v1/responses \
    -H "Content-Type: application/json" \
    -d '{"model":"'"$MODEL"'","input":"What is the weather in Paris?","tools":[{"type":"mcp","server_label":"weather","server_url":"'"$MCP_URL"'","allowed_tools":["get_weather"],"require_approval":"never"}]}')
echo "$RESPONSE3" | jq . 2>/dev/null || echo "$RESPONSE3"

ANSWER3=$(echo "$RESPONSE3" | jq -r '.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text' 2>/dev/null || echo "")

if [ -n "$ANSWER3" ]; then
    printf "\n\033[1;32m↳ Model answered:\033[0m %s\n" "$ANSWER3"
fi
sleep 3

printf "\n\033[1;32mDone.\033[0m The agentic loop dispatched MCP tool calls,\n"
printf "fed results back to the model, and produced final answers.\n"
printf "No client-side orchestration needed.\n"
sleep 3
