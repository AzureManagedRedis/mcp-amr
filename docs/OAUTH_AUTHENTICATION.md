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

**Option A: Using Azure CLI (Add Custom Scopes)**

To get tokens with custom scopes like `MCP.Read,MCP.Write` in the `scp` claim:

```bash
# Step 1: Add OAuth2 permission scopes to your app registration
OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)

# Generate UUIDs for the scopes
READ_SCOPE_ID=$(uuidgen)
WRITE_SCOPE_ID=$(uuidgen)

# Add the OAuth2 permission scopes
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{
    \"api\": {
      \"oauth2PermissionScopes\": [
        {
          \"adminConsentDescription\": \"Read access to MCP tools\",
          \"adminConsentDisplayName\": \"MCP.Read\",
          \"id\": \"$READ_SCOPE_ID\",
          \"isEnabled\": true,
          \"type\": \"User\",
          \"userConsentDescription\": \"Read access to MCP tools\",
          \"userConsentDisplayName\": \"MCP.Read\",
          \"value\": \"MCP.Read\"
        },
        {
          \"adminConsentDescription\": \"Write access to MCP tools\",
          \"adminConsentDisplayName\": \"MCP.Write\",
          \"id\": \"$WRITE_SCOPE_ID\",
          \"isEnabled\": true,
          \"type\": \"User\",
          \"userConsentDescription\": \"Write access to MCP tools\",
          \"userConsentDisplayName\": \"MCP.Write\",
          \"value\": \"MCP.Write\"
        }
      ]
    }
  }"

# Step 2: Pre-authorize Azure CLI to access these scopes
AZURE_CLI_APP_ID="04b07795-8ddb-461a-bbee-02f9e1bf7b46"

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{
    \"api\": {
      \"preAuthorizedApplications\": [
        {
          \"appId\": \"$AZURE_CLI_APP_ID\",
          \"delegatedPermissionIds\": [\"$READ_SCOPE_ID\", \"$WRITE_SCOPE_ID\"]
        }
      ]
    }
  }"

# Wait for propagation
sleep 30

# Step 3: Get token with custom scopes
TOKEN=$(az account get-access-token --resource api://$APP_ID --query accessToken -o tsv)

# Verify the token contains the expected scopes
echo "Token scopes:"
# Handle base64 padding issues
TOKEN_PAYLOAD=$(echo $TOKEN | cut -d'.' -f2)
# Add padding if needed
while [ $((${#TOKEN_PAYLOAD} % 4)) -ne 0 ]; do
  TOKEN_PAYLOAD="${TOKEN_PAYLOAD}="
done
echo $TOKEN_PAYLOAD | base64 -d 2>/dev/null | jq -r .scp

# Alternative: Use Python to decode (more reliable)
# python3 -c "
# import json, base64, sys
# payload = sys.argv[1]
# payload += '=' * (4 - len(payload) % 4)
# decoded = json.loads(base64.b64decode(payload))
# print('Scopes:', decoded.get('scp', 'No scopes found'))
# print('Expires:', decoded.get('exp'))
# " $(echo $TOKEN | cut -d'.' -f2)
```

**Note:** This creates delegated permissions (appears in `scp` claim) rather than application roles.

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

**Option 1: OAuth2 Permission Scopes (Delegated Permissions - appears in `scp` claim)**

For user-context tokens (Azure CLI, interactive login):

```bash
# Add OAuth2 permission scopes
OBJECT_ID=$(az ad app show --id $APP_ID --query id -o tsv)
READ_SCOPE_ID=$(uuidgen)
WRITE_SCOPE_ID=$(uuidgen)

az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{
    \"api\": {
      \"oauth2PermissionScopes\": [
        {
          \"adminConsentDescription\": \"Read access to MCP tools\",
          \"adminConsentDisplayName\": \"MCP.Read\",
          \"id\": \"$READ_SCOPE_ID\",
          \"isEnabled\": true,
          \"type\": \"User\",
          \"userConsentDescription\": \"Read access to MCP tools\",
          \"userConsentDisplayName\": \"MCP.Read\",
          \"value\": \"MCP.Read\"
        },
        {
          \"adminConsentDescription\": \"Write access to MCP tools\",
          \"adminConsentDisplayName\": \"MCP.Write\",
          \"id\": \"$WRITE_SCOPE_ID\",
          \"isEnabled\": true,
          \"type\": \"User\",
          \"userConsentDescription\": \"Write access to MCP tools\",
          \"userConsentDisplayName\": \"MCP.Write\",
          \"value\": \"MCP.Write\"
        }
      ]
    }
  }"
```

**Option 2: Application Roles (App Permissions - appears in `roles` claim)**

For app-to-app authentication:

```bash
# Generate UUIDs for the roles
READ_ROLE_ID=$(uuidgen)
WRITE_ROLE_ID=$(uuidgen)

cat > roles.json << EOF
{
  "appRoles": [
    {
      "allowedMemberTypes": ["User", "Application"],
      "description": "Read access to MCP tools",
      "displayName": "MCP.Read",
      "id": "$READ_ROLE_ID",
      "isEnabled": true,
      "value": "MCP.Read"
    },
    {
      "allowedMemberTypes": ["User", "Application"],
      "description": "Full access to MCP tools",
      "displayName": "MCP.Write",
      "id": "$WRITE_ROLE_ID",
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

**Key Differences:**
- **OAuth2 Scopes**: User-delegated permissions, appear in `scp` claim
- **App Roles**: Application permissions, appear in `roles` claim

### Troubleshooting

**Token validation fails:**
- Verify `MCP_OAUTH_TENANT_ID` and `MCP_OAUTH_CLIENT_ID` are correct
- Check that token audience matches `api://{client-id}`
- Ensure token hasn't expired
- Check server logs for detailed error messages

**Scope validation fails:**
- Verify the token contains the required scopes/roles in `scp` or `roles` claims
- For `scp` claim: Check OAuth2 permission scopes are defined and granted
- For `roles` claim: Check app roles are defined and assigned
- Ensure the client has been granted the required permissions
- Use `echo $TOKEN | cut -d'.' -f2 | base64 -d | jq` to inspect token claims

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
