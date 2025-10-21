# API Key Authentication

The Redis MCP Server HTTP/SSE transport supports API key authentication to secure access to your MCP endpoints.

## Features

- ✅ **Simple API Key validation**: Secure your endpoints with predefined API keys
- ✅ **Multiple API Keys**: Support for multiple valid API keys (useful for key rotation)
- ✅ **Constant-time comparison**: Prevents timing attacks
- ✅ **Health check bypass**: Health endpoint always accessible for monitoring
- ✅ **Standard header**: Uses `X-API-Key` header

## Quick Start

### 1. Configure API Keys

```bash
# Enable API key authentication
export MCP_API_KEY_AUTH_ENABLED=true

# Set one or more API keys (comma-separated)
export MCP_API_KEYS="your-secret-key-1,your-secret-key-2"
```

### 2. Start the Server

```bash
uv run python src/http_server.py
```

You should see:
```
🔒 API Key Authentication: ENABLED
   Configured API Keys: 2
   All requests must include valid X-API-Key header
```

### 3. Make Authenticated Requests

```bash
# Valid request with API key
curl -X POST http://localhost:8000/message \
  -H "X-API-Key: your-secret-key-1" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Without API key (will fail)
curl -X POST http://localhost:8000/message \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
# Returns: {"jsonrpc":"2.0","id":null,"error":{"code":-32001,"message":"Missing X-API-Key header"}}

# With invalid API key (will fail)
curl -X POST http://localhost:8000/message \
  -H "X-API-Key: wrong-key" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
# Returns: {"jsonrpc":"2.0","id":null,"error":{"code":-32001,"message":"Invalid API key"}}
```

## Configuration

### Environment Variables

| Variable | Description | Required | Default | Example |
|----------|-------------|----------|---------|---------|
| `MCP_API_KEY_AUTH_ENABLED` | Enable API key authentication | No | `false` | `true` |
| `MCP_API_KEYS` | Comma-separated list of valid API keys | Yes (if enabled) | - | `key1,key2,key3` |

### Generating Secure API Keys

Use strong random keys for production:

```bash
# Generate a secure random API key (32 bytes, base64 encoded)
openssl rand -base64 32

# Or using Python
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Example output:
# Kj8Hn2pQ9xR5mW7tY3vZ1aB4cD6eF8gH0iJ2kL4mN6oP8qR0sT2uV4w
```

### Multiple API Keys

You can configure multiple valid API keys for:
- **Key rotation**: Add new key, update clients, remove old key
- **Different clients**: Give each client their own key
- **Environment separation**: Different keys for dev/staging/prod

```bash
export MCP_API_KEYS="prod-key-v1,prod-key-v2,backup-key"
```

## Security Best Practices

1. **Use Strong Keys**: Generate cryptographically secure random keys (at least 32 bytes)
2. **Keep Keys Secret**: Never commit API keys to version control
3. **Use HTTPS**: Always use HTTPS in production to encrypt API keys in transit
4. **Rotate Keys Regularly**: Change API keys periodically
5. **One Key Per Client**: Give each client their own unique API key for better access control
6. **Monitor Access**: Review logs for authentication failures

## Azure Container Apps Deployment

### Setting API Keys as Secrets

```bash
# Store API key as a secret
az containerapp secret set \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --secrets mcp-api-keys="my-key1,my-key2,my-key3"

# Update container with API key authentication (adds to existing env vars)
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    MCP_API_KEY_AUTH_ENABLED=true \
    MCP_API_KEYS=secretref:mcp-api-keys
```

> **Important**: Using `--set-env-vars` adds or updates the specified variables while keeping existing ones. Don't use `--replace-env-vars` unless you want to replace ALL environment variables.

## Troubleshooting

### Authentication Always Fails

**Check:**
1. Ensure `MCP_API_KEY_AUTH_ENABLED=true`
2. Verify `MCP_API_KEYS` is set correctly
3. Check for whitespace in API keys (no spaces around commas)
4. Ensure header is `X-API-Key` (case-sensitive)

**Enable debug logging:**
```bash
export MCP_REDIS_LOG_LEVEL=DEBUG
```

### Health Check Fails

The `/health` endpoint always bypasses authentication for container orchestration. If it's failing, the issue is not authentication-related.

### Key Rotation

To rotate keys without downtime:

```bash
# Step 1: Add new key alongside old key
export MCP_API_KEYS="old-key,new-key"

# Step 2: Update clients to use new key

# Step 3: Remove old key once all clients updated
export MCP_API_KEYS="new-key"
```

## Example: Testing Script

```bash
#!/bin/bash

# Configure API keys
export MCP_API_KEY_AUTH_ENABLED=true
export MCP_API_KEYS="test-key-123"

# Start server in background
uv run python src/http_server.py &
SERVER_PID=$!

# Wait for server to start
sleep 3

# Test with valid key
echo "Testing with valid API key..."
curl -X POST http://localhost:8000/message \
  -H "X-API-Key: test-key-123" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Test without key
echo -e "\n\nTesting without API key (should fail)..."
curl -X POST http://localhost:8000/message \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'

# Cleanup
kill $SERVER_PID
```

## Comparison with OAuth

| Feature | API Key | OAuth (Entra ID) |
|---------|---------|------------------|
| **Complexity** | Simple | Complex |
| **Setup Time** | Immediate | Requires Azure AD setup |
| **Use Case** | Service-to-service, simple auth | Enterprise SSO, user delegation |
| **Token Format** | Static string | JWT with expiration |
| **Revocation** | Update environment variable | Instant via Azure AD |
| **Audit Trail** | Basic logging | Full Azure AD audit logs |
| **Multi-tenant** | Manual per-tenant keys | Native multi-tenant support |

**Recommendation:**
- Use **API Keys** for simple deployments, internal services, or quick prototyping
- Use **OAuth/Entra ID** for enterprise deployments with SSO requirements
