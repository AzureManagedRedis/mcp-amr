# MCP Redis Server API Authentication

The Redis MCP Server is now configured with API Key authentication enabled by default.

## Configuration

### API Key Parameters

- **`mcpApiKeyAuthEnabled`**: Boolean parameter to enable/disable API key authentication (default: `true`)
- **`mcpApiKeys`**: Secure parameter containing comma-separated list of valid API keys

### Environment Variables Set in Container

- `MCP_API_KEY_AUTH_ENABLED=true`: Enables API key authentication
- `MCP_API_KEYS=api-key-1,api-key-2,api-key-3`: List of valid API keys

## Usage

### Making Authenticated Requests

All requests to the MCP server must include the `X-API-Key` header:

```bash
curl -X POST https://your-container-app-url/message \
  -H "X-API-Key: api-key-1" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }'
```

### Available API Keys

The default configuration includes three API keys:
- `api-key-1`
- `api-key-2` 
- `api-key-3`

## Customizing API Keys

### Option 1: Update Parameters File

Edit `resources.parameters.json`:

```json
{
  "parameters": {
    "mcpApiKeys": {
      "value": "your-api-key-1,your-api-key-2"
    }
  }
}
```

### Option 2: Override During Deployment

Pass custom API keys during deployment:

```bash
az deployment group create \
  --resource-group "your-rg" \
  --template-file "resources.bicep" \
  --parameters @"resources.parameters.json" \
  --parameters mcpApiKeys="custom-key-1,custom-key-2"
```

### Option 3: Update Existing Deployment

Update the Container App environment variables:

```bash
az containerapp update \
  --name "your-container-app" \
  --resource-group "your-rg" \
  --set-env-vars MCP_API_KEYS="new-key-1,new-key-2,new-key-3"
```

## Security Best Practices

1. **Use Strong Keys**: Generate cryptographically strong API keys
2. **Rotate Keys**: Regularly rotate API keys for security
3. **Limit Access**: Only provide keys to authorized users/applications
4. **Monitor Usage**: Review Container App logs for authentication attempts

## Testing Authentication

### Valid Request (should succeed)
```bash
curl -X POST https://your-app.azurecontainerapps.io/message \
  -H "X-API-Key: api-key-1" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

### Invalid Request (should fail)
```bash
curl -X POST https://your-app.azurecontainerapps.io/message \
  -H "X-API-Key: invalid-key" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

### No Authentication (should fail)
```bash
curl -X POST https://your-app.azurecontainerapps.io/message \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Disabling Authentication

To disable API key authentication, set `mcpApiKeyAuthEnabled` to `false`:

```json
{
  "mcpApiKeyAuthEnabled": {
    "value": false
  }
}
```

When disabled, all requests will be accepted without authentication.