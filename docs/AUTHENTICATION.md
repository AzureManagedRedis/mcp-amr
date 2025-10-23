# MCP Redis Server - Consolidated Authentication System

The MCP Redis Server now supports **three authentication methods** that can be configured via environment variables:

## 🔧 Configuration

Set the authentication method using the `MCP_AUTH_METHOD` environment variable:

### 1. NO-AUTH (Default)
```bash
MCP_AUTH_METHOD=NO-AUTH
```
- **No authentication required**
- All requests are allowed
- Suitable for development and trusted environments

### 2. API-KEY Authentication  
```bash
MCP_AUTH_METHOD=API-KEY
MCP_API_KEYS=your-api-key-1,your-api-key-2,your-api-key-3
```
- **API key authentication via X-API-Key header**
- Supports multiple API keys (comma-separated)
- Clients must include: `X-API-Key: your-api-key`

### 3. OAUTH Authentication
```bash
MCP_AUTH_METHOD=OAUTH
MCP_OAUTH_TENANT_ID=your-tenant-id
MCP_OAUTH_CLIENT_ID=your-client-id
MCP_OAUTH_REQUIRED_SCOPES=scope1,scope2  # Optional
```
- **OAuth JWT token authentication via Authorization header**
- Azure Entra ID integration
- Clients must include: `Authorization: Bearer your-jwt-token`

## 🚀 Quick Setup

### Using the Configuration Script
Run the interactive configuration helper:
```bash
uv run python configure_auth.py
```

### Manual Configuration Examples

#### Development (No Auth)
```bash
export MCP_AUTH_METHOD=NO-AUTH
uv run python -m src.http_server
```

#### Production with API Keys
```bash
export MCP_AUTH_METHOD=API-KEY
export MCP_API_KEYS=$(openssl rand -base64 32),$(openssl rand -base64 32)
uv run python -m src.http_server
```

#### Enterprise with OAuth
```bash
export MCP_AUTH_METHOD=OAUTH
export MCP_OAUTH_TENANT_ID=your-tenant-id
export MCP_OAUTH_CLIENT_ID=your-client-id
export MCP_OAUTH_REQUIRED_SCOPES=https://redis.com/access
uv run python -m src.http_server
```

## 📋 Client Usage Examples

### NO-AUTH
```bash
curl http://localhost:8000/health
curl http://localhost:8000/sse
```

### API-KEY
```bash
curl -H "X-API-Key: your-api-key" http://localhost:8000/health
curl -H "X-API-Key: your-api-key" http://localhost:8000/sse
```

### OAUTH
```bash
curl -H "Authorization: Bearer your-jwt-token" http://localhost:8000/health
curl -H "Authorization: Bearer your-jwt-token" http://localhost:8000/sse
```

## 🔄 Migration from Previous Versions

If you were using the old configuration format, here's how to migrate:

### Old OAuth Config → New Config
```bash
# Old
MCP_OAUTH_ENABLED=true
MCP_OAUTH_TENANT_ID=...
MCP_OAUTH_CLIENT_ID=...

# New  
MCP_AUTH_METHOD=OAUTH
MCP_OAUTH_TENANT_ID=...
MCP_OAUTH_CLIENT_ID=...
```

### Old API Key Config → New Config
```bash  
# Old
MCP_API_KEY_AUTH_ENABLED=true
MCP_API_KEYS=...

# New
MCP_AUTH_METHOD=API-KEY
MCP_API_KEYS=...
```

## ⚙️ Advanced Configuration

### Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `MCP_AUTH_METHOD` | Authentication method: NO-AUTH, API-KEY, OAUTH | NO-AUTH |
| `MCP_API_KEYS` | Comma-separated list of API keys | (empty) |
| `MCP_OAUTH_TENANT_ID` | Azure tenant ID for OAuth | (empty) |
| `MCP_OAUTH_CLIENT_ID` | Azure client ID for OAuth | (empty) |
| `MCP_OAUTH_REQUIRED_SCOPES` | Required OAuth scopes (comma-separated) | (empty) |

### Health Check Endpoint

The `/health` endpoint is **always accessible without authentication** regardless of the configured method, making it suitable for load balancer health checks.

## 🔍 Troubleshooting

### Authentication Logs
The server logs the selected authentication method at startup:
```
🔓 Authentication: DISABLED
🔒 Authentication: API KEY (2 keys)
🔒 Authentication: OAUTH (tenant: xxx, client: yyy)
```

### Common Issues

1. **API-KEY method but no keys configured**
   - Falls back to NO-AUTH with warning
   - Solution: Set `MCP_API_KEYS` environment variable

2. **OAUTH method but missing tenant/client ID**
   - Falls back to NO-AUTH with warning  
   - Solution: Set `MCP_OAUTH_TENANT_ID` and `MCP_OAUTH_CLIENT_ID`

3. **Import errors after merge**
   - Clean Python cache: `find . -name "__pycache__" -exec rm -rf {} +`
   - Recompile: `uv run python -m compileall src/`