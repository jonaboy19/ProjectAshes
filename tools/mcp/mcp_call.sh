#!/bin/bash
# Call a DCC-MCP gateway tool from any shell (for Codex or scripts that have no MCP client).
# usage: mcp_call.sh <tool> '<json arguments>'     tool is one of: search | describe | load_skill | call
# e.g.   mcp_call.sh call '{"tool_slug":"godot.<instance8>.godot_analysis__get_project_statistics","arguments":{}}'
curl -s -m "${T:-120}" -X POST "${GATEWAY:-http://127.0.0.1:9765/mcp}" -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
 -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":${2:-{\}}}}"
