#!/bin/bash
# Show what the gateway can see. Usage: tools/mcp/dcc_mcp_status.sh
curl -s -m 10 -X POST http://127.0.0.1:9765/mcp -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' \
 -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","arguments":{"kind":"skill","query":"scene","limit":1}}}' | head -c 600; echo
