# OAuth Authentication with Microsoft Entra ID

This MCP server supports OAuth 2.0 authentication using Microsoft Entra ID (formerly Azure AD), providing secure, token-based access control for your MCP endpoints.

## Features

- ✅ **JWT Token Validation**: Validates access tokens issued by Microsoft Entra ID
- ✅ **Scope-based Authorization**: Enforce required scopes/roles for API access
- ✅ **Automatic Token Verification**: Built-in JWT signature and expiration validation
- ✅ **Environment Neutral**: Works on Azure, AWS, on-premises, or local development
- ✅ **FastMCP Integration**: Leverages FastMCP's built-in OAuth support

## Quick Start

### 1. Register Your Application in Entra ID

```bash
# Create app registration
az ad app create \
  --display-name "Redis MCP Server" \
  --sign-in-audience AzureADMyOrg

# Get the application ID
APP_ID=$(az ad app list --display-name "Redis MCP Server" --query [0].appId -o tsv)

# Expose an API
az ad app update --id $APP_ID --identifier-uris "api://$APP_ID"
```

### 2. Configure Environment Variables

```bash
export MCP_OAUTH_ENABLED=true
export MCP_OAUTH_TENANT_ID=your-tenant-id
export MCP_OAUTH_CLIENT_ID=your-app-id
export MCP_OAUTH_REQUIRED_SCOPES="MCP.Read,MCP.Write"  # Optional
```

### 3. Start the Server

```bash
# The server will automatically enable OAuth authentication
python -m src.main
```

### 4. Get an Access Token

**Option A: Using Azure CLI (Requires API Permission)**

This option is complex and often encounters Azure CLI limitations. **We strongly recommend Option C instead.**

```bash
# Note: This approach has known issues with Azure CLI's JSON parsing
# If you encounter errors, use Option C (Test Client) which is more reliable

# Step 1: Create OAuth2 scope first
SCOPE_ID=$(uuidgen)
OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"api\":{\"oauth2PermissionScopes\":[{\"adminConsentDescription\":\"Access MCP Server\",\"adminConsentDisplayName\":\"Access MCP Server\",\"id\":\"$SCOPE_ID\",\"isEnabled\":true,\"type\":\"User\",\"userConsentDescription\":\"Access MCP Server\",\"userConsentDisplayName\":\"Access MCP Server\",\"value\":\"user_impersonation\"}]}}"

# Wait for scope creation
sleep 5

# Step 2: Pre-authorize Azure CLI
AZURE_CLI_APP_ID="04b07795-8ddb-461a-bbee-02f9e1bf7b46"

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"api\":{\"preAuthorizedApplications\":[{\"appId\":\"$AZURE_CLI_APP_ID\",\"delegatedPermissionIds\":[\"$SCOPE_ID\"]}]}}"

# Wait for propagation
sleep 10

# Step 3: Get token
TOKEN=$(az account get-access-token --resource api://$APP_ID --query accessToken -o tsv)
```

**⚠️ Warning:** This is the most complex option with the most points of failure. Use Option C for reliable testing.

**Option B: Using Device Code Flow (Easier for Testing)**

```bash
# Get token using device code flow
TOKEN=$(az rest --method POST \
  --url "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  --body "client_id=$APP_ID&scope=api://$APP_ID/.default&grant_type=client_credentials&client_secret=$CLIENT_SECRET" \
  --query access_token -o tsv)
```

**Option C: Create a Test Client Application**

```bash
# Create a test client app
TEST_CLIENT_ID=$(az ad app create \
  --display-name "MCP Test Client" \
  --query appId -o tsv)

# Create a client secret
TEST_CLIENT_SECRET=$(az ad app credential reset \
  --id $TEST_CLIENT_ID \
  --query password -o tsv)

# Add API permission to the test client
API_PERMISSION_ID=$(az ad app show --id $APP_ID --query "api.oauth2PermissionScopes[0].id" -o tsv)
az ad app permission add \
  --id $TEST_CLIENT_ID \
  --api $APP_ID \
  --api-permissions $API_PERMISSION_ID=Scope

# Grant admin consent
az ad app permission admin-consent --id $TEST_CLIENT_ID

# Get token using client credentials
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \
  -d "client_id=$TEST_CLIENT_ID" \
  -d "client_secret=$TEST_CLIENT_SECRET" \
  -d "scope=api://$APP_ID/.default" \
  -d "grant_type=client_credentials" \
  | jq -r .access_token)
```

**Using MSAL (Python):**
```python
from msal import ConfidentialClientApplication

app = ConfidentialClientApplication(
    client_id="your-client-id",
    client_credential="your-client-secret",
    authority="https://login.microsoftonline.com/your-tenant-id"
)

result = app.acquire_token_for_client(scopes=["api://your-app-id/.default"])
token = result["access_token"]
```

### 5. Call MCP Endpoints with Token

```bash
curl -X POST http://localhost:8000/message \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }'
```

## Configuration Details

### Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `MCP_OAUTH_ENABLED` | Enable OAuth authentication | Yes | `false` |
| `MCP_OAUTH_TENANT_ID` | Azure AD tenant ID | Yes (if enabled) | - |
| `MCP_OAUTH_CLIENT_ID` | Application (client) ID | Yes (if enabled) | - |
| `MCP_OAUTH_REQUIRED_SCOPES` | Comma-separated list of required scopes | No | `[]` |

### Token Requirements

The access token must:
- Be a valid JWT issued by Microsoft Entra ID
- Have audience (`aud`) claim matching `api://{MCP_OAUTH_CLIENT_ID}`
- Have issuer (`iss`) claim matching `https://login.microsoftonline.com/{tenant-id}/v2.0`
- Not be expired (`exp` claim)
- Contain required scopes if `MCP_OAUTH_REQUIRED_SCOPES` is set

### Scopes vs Roles

- **Scopes** (`scp` claim): Used for delegated permissions (user context)
- **Roles** (`roles` claim): Used for application permissions (app-to-app)

The verifier checks both claims and validates against `MCP_OAUTH_REQUIRED_SCOPES`.

## Advanced Configuration

### Custom Scopes/Roles

Add application roles in Entra ID:

```bash
cat > roles.json << 'EOF'
{
  "appRoles": [
    {
      "allowedMemberTypes": ["User", "Application"],
      "description": "Read access to MCP tools",
      "displayName": "MCP.Read",
      "id": "unique-guid-1",
      "isEnabled": true,
      "value": "MCP.Read"
    },
    {
      "allowedMemberTypes": ["User", "Application"],
      "description": "Full access to MCP tools",
      "displayName": "MCP.Write",
      "id": "unique-guid-2",
      "isEnabled": true,
      "value": "MCP.Write"
    }
  ]
}
EOF

az ad app update --id $APP_ID --app-roles @roles.json
```

Then require them:
```bash
export MCP_OAUTH_REQUIRED_SCOPES="MCP.Read,MCP.Write"
```

### Troubleshooting

**Token validation fails:**
- Verify `MCP_OAUTH_TENANT_ID` and `MCP_OAUTH_CLIENT_ID` are correct
- Check that token audience matches `api://{client-id}`
- Ensure token hasn't expired
- Check server logs for detailed error messages

**Scope validation fails:**
- Verify the token contains the required scopes/roles
- Check that app registration has the roles defined
- Ensure the client has been granted the required permissions

**JWKS errors:**
- The server caches public keys from Microsoft
- If keys rotate, restart the server or wait for cache refresh
- Check network connectivity to `https://login.microsoftonline.com`

## Security Considerations

1. **Always use HTTPS in production** - Tokens should never be transmitted over HTTP
2. **Keep secrets secure** - Never commit `MCP_OAUTH_CLIENT_ID` or tokens to version control
3. **Use short-lived tokens** - Default Entra ID tokens expire after 1 hour
4. **Implement rate limiting** - Consider adding rate limits to prevent abuse
5. **Monitor token usage** - Log authentication attempts and failures
6. **Rotate keys regularly** - Microsoft rotates signing keys automatically

## Testing OAuth Locally

```bash
# 1. Set environment variables
export MCP_OAUTH_ENABLED=true
export MCP_OAUTH_TENANT_ID=your-tenant-id
export MCP_OAUTH_CLIENT_ID=your-app-id

# 2. Start server
python -m src.main

# 3. Get token and test
TOKEN=$(az account get-access-token --resource api://$MCP_OAUTH_CLIENT_ID --query accessToken -o tsv)

curl -X POST http://localhost:8000/message \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## Learn More

- [Microsoft Entra ID Documentation](https://learn.microsoft.com/entra/identity/)
- [OAuth 2.0 and OpenID Connect](https://learn.microsoft.com/entra/identity-platform/v2-protocols)
- [FastMCP Documentation](https://github.com/modelcontextprotocol/python-sdk)
