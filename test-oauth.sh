#!/bin/bash

# Enable DEBUG logging
export MCP_REDIS_LOG_LEVEL=DEBUG

# OAuth configuration from your token
export MCP_OAUTH_ENABLED=true
export MCP_OAUTH_TENANT_ID=72f988bf-86f1-41af-91ab-2d7cd011db47
export MCP_OAUTH_CLIENT_ID=68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e

echo "Starting HTTP server with OAuth enabled..."
echo "Log Level: DEBUG"
echo "Tenant ID: $MCP_OAUTH_TENANT_ID"
echo "Client ID: $MCP_OAUTH_CLIENT_ID"
echo ""

uv run python src/http_server.py
