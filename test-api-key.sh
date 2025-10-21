#!/bin/bash

# Enable API key authentication
export MCP_API_KEY_AUTH_ENABLED=true

# Set API keys (comma-separated for multiple keys)
export MCP_API_KEYS="my-secret-key-1,my-secret-key-2"

# Optional: Enable debug logging
export MCP_REDIS_LOG_LEVEL=DEBUG

echo "Starting HTTP server with API Key authentication..."
echo "Authentication: ENABLED"
echo "API Keys configured: 2"
echo ""
echo "Test with:"
echo '  curl -H "X-API-Key: my-secret-key-1" http://localhost:8000/message -X POST -H "Content-Type: application/json" -d '"'"'{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'"'"
echo ""

uv run python src/http_server.py
