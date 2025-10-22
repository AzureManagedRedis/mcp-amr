#!/bin/bash

# Create Test Client for App-to-App Authentication
# This script creates a test client and demonstrates true app-to-app authentication
# using federated credentials (no secrets or certificates needed)

set -e

echo "🔧 Creating Test Client for App-to-App Authentication..."
echo "===================================================="

# Set your variables
TENANT_ID=$(az account show --query tenantId -o tsv)
APP_ID="68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e"  # Your Redis MCP Server app ID
CONTAINER_APP_NAME="redis-mcp-oauth"
RESOURCE_GROUP="mcp-redis"

echo "Configuration:"
echo "- Tenant ID: $TENANT_ID"
echo "- App ID: $APP_ID"
echo "- Container App: $CONTAINER_APP_NAME"
echo "- Resource Group: $RESOURCE_GROUP"
echo ""

# Create a test client application
echo "📱 Creating test client application..."
TEST_CLIENT_ID=$(az ad app create \
  --display-name "Redis MCP Test Client $(date +%Y%m%d-%H%M%S)" \
  --query appId -o tsv)

echo "✅ Created test client: $TEST_CLIENT_ID"

# Create a service principal for the test client
echo "🔐 Creating service principal..."
az ad sp create --id $TEST_CLIENT_ID

# Get the service principal object ID
TEST_SP_OBJECT_ID=$(az ad sp show --id $TEST_CLIENT_ID --query id -o tsv)
echo "✅ Service principal created: $TEST_SP_OBJECT_ID"

# Get the app role IDs from the Redis MCP Server app
echo "🎯 Getting app role IDs..."
READ_ROLE_ID=$(az ad app show --id $APP_ID --query "appRoles[?value=='MCP.Read'].id" -o tsv)
WRITE_ROLE_ID=$(az ad app show --id $APP_ID --query "appRoles[?value=='MCP.Write'].id" -o tsv)

if [ -z "$READ_ROLE_ID" ] || [ -z "$WRITE_ROLE_ID" ]; then
    echo "❌ Could not find app roles. Make sure the Redis MCP Server app has MCP.Read and MCP.Write roles configured."
    exit 1
fi

echo "✅ Found app roles:"
echo "   - READ_ROLE_ID: $READ_ROLE_ID"
echo "   - WRITE_ROLE_ID: $WRITE_ROLE_ID"

# Assign app roles to the test client service principal
echo "🔗 Assigning app roles to test client..."
RESOURCE_SP_ID=$(az ad sp show --id $APP_ID --query id -o tsv)

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$TEST_SP_OBJECT_ID/appRoleAssignments" \
  --body "{\"principalId\": \"$TEST_SP_OBJECT_ID\", \"resourceId\": \"$RESOURCE_SP_ID\", \"appRoleId\": \"$READ_ROLE_ID\"}" \
  --headers Content-Type=application/json

az rest --method POST \
  --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$TEST_SP_OBJECT_ID/appRoleAssignments" \
  --body "{\"principalId\": \"$TEST_SP_OBJECT_ID\", \"resourceId\": \"$RESOURCE_SP_ID\", \"appRoleId\": \"$WRITE_ROLE_ID\"}" \
  --headers Content-Type=application/json

echo "✅ App roles assigned to test client"

# Assign subscription-level Reader role to the test client (required for Azure CLI login)
echo "🔑 Assigning subscription Reader role to test client..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
az role assignment create \
  --assignee $TEST_CLIENT_ID \
  --role "Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

echo "✅ Reader role assigned to test client for subscription access"

# Set up federated credentials for GitHub Actions (most common OIDC provider)
echo "🔐 Setting up federated credentials for app-to-app auth..."
echo ""
echo "Since your tenant doesn't allow client secrets or certificates,"
echo "we need to use federated credentials with an OIDC provider."
echo ""

# Option 1: GitHub Actions (most common)
read -p "Do you have a GitHub repository to use for testing? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter your GitHub username: " GITHUB_USER
    read -p "Enter your GitHub repository name: " GITHUB_REPO
    read -p "Enter branch name (default: main): " GITHUB_BRANCH
    GITHUB_BRANCH=${GITHUB_BRANCH:-main}
    
    echo "Setting up GitHub Actions federated credential..."
    
    cat > github-federated-cred.json << EOF
{
  "name": "github-actions-$(date +%s)",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_USER}/${GITHUB_REPO}:ref:refs/heads/${GITHUB_BRANCH}",
  "description": "GitHub Actions for app-to-app testing",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

    az ad app federated-credential create --id $TEST_CLIENT_ID --parameters @github-federated-cred.json
    echo "✅ GitHub Actions federated credential created"
    
    # Create a sample GitHub Actions workflow
    cat > github-workflow-sample.yml << EOF
# Sample GitHub Actions workflow for testing app-to-app auth
# Save this as .github/workflows/test-mcp-auth.yml in your repository

name: Test MCP Authentication

on:
  workflow_dispatch:  # Manual trigger
  push:
    branches: [ ${GITHUB_BRANCH} ]

permissions:
  id-token: write
  contents: read

jobs:
  test-auth:
    runs-on: ubuntu-latest
    steps:
    - name: Azure Login with OIDC
      uses: azure/login@v1
      with:
        client-id: $TEST_CLIENT_ID
        tenant-id: $TENANT_ID
        subscription-id: \${{ secrets.AZURE_SUBSCRIPTION_ID }}
        
    - name: Get Access Token for MCP
      id: get-token
      run: |
        TOKEN=\$(az account get-access-token --resource "api://$APP_ID" --query accessToken -o tsv)
        echo "TOKEN=\$TOKEN" >> \$GITHUB_OUTPUT
        echo "Token acquired successfully (length: \${#TOKEN} characters)"
        
        # Verify token contains expected app roles (without logging the token)
        TOKEN_PAYLOAD=\$(echo \$TOKEN | cut -d. -f2)
        case \$((\\${#TOKEN_PAYLOAD} % 4)) in
            2) TOKEN_PAYLOAD="\\${TOKEN_PAYLOAD}==" ;;
            3) TOKEN_PAYLOAD="\\${TOKEN_PAYLOAD}=" ;;
        esac
        ROLES=\$(echo \$TOKEN_PAYLOAD | base64 -d 2>/dev/null | jq -r '.roles[]? // empty' 2>/dev/null || echo "")
        if [ -n "\$ROLES" ]; then
            echo "Token contains app roles: \$ROLES"
        else
            echo "Warning: No app roles found in token"
        fi
        
    - name: Test MCP Server
      env:
        TOKEN: \${{ steps.get-token.outputs.TOKEN }}
      run: |
        curl -X POST "https://$CONTAINER_APP_NAME.blacktree-376d2ec0.westus2.azurecontainerapps.io/message" \\
          -H "Authorization: Bearer \$TOKEN" \\
          -H "Content-Type: application/json" \\
          -d '{
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {}
          }'
EOF

    echo "📄 Sample GitHub workflow saved to: github-workflow-sample.yml"
    echo ""
    echo "🔧 To use this workflow:"
    echo "1. Copy github-workflow-sample.yml to .github/workflows/test-mcp-auth.yml in your repo"
    echo "2. Add AZURE_SUBSCRIPTION_ID as a repository secret"
    echo "3. Run the workflow manually or push to trigger it"
    echo ""
    
    # Clean up temp files
    rm -f github-federated-cred.json
    
else
    echo "📝 Alternative: Workload Identity Federation with Azure Container Instances"
    echo ""
    echo "Since you don't have a GitHub repo, here's how to test with Azure Container Instances:"
    echo ""
    
    # Create a simple federated credential for testing (using a generic OIDC issuer)
    cat > aci-federated-cred.json << EOF
{
  "name": "aci-testing-$(date +%s)",
  "issuer": "https://login.microsoftonline.com/$TENANT_ID/v2.0",
  "subject": "system:serviceaccount:default:workload-identity-sa",
  "description": "Azure Container Instance testing",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

    az ad app federated-credential create --id $TEST_CLIENT_ID --parameters @aci-federated-cred.json
    echo "✅ Azure Container Instance federated credential created"
    
    # Clean up temp file
    rm -f aci-federated-cred.json
    
    echo ""
    echo "⚠️  Note: This federated credential is for demonstration."
    echo "For real app-to-app auth, you'll need a proper OIDC provider like:"
    echo "- GitHub Actions"
    echo "- Azure DevOps"
    echo "- Other Azure services with managed identity"
    echo ""
fi

# Demonstrate the limitation and provide workarounds
echo ""
echo "🔍 Testing App-to-App Authentication..."
echo "======================================"
echo ""
echo "❗ IMPORTANT: True app-to-app authentication with federated credentials"
echo "requires running from the configured OIDC provider context."
echo ""
echo "What we've set up:"
echo "✅ Test client app: $TEST_CLIENT_ID"
echo "✅ App role assignments: MCP.Read, MCP.Write"
echo "✅ Federated credential configured"
echo ""
echo "To get a token in the configured environment:"

if [[ $REPLY =~ ^[Yy]$ ]]; then
    cat << EOF

# In GitHub Actions (or similar OIDC environment):
TOKEN=\$(curl -s -X POST \\
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \\
  -H "Content-Type: application/x-www-form-urlencoded" \\
  -d "client_id=$TEST_CLIENT_ID" \\
  -d "scope=api://$APP_ID/.default" \\
  -d "grant_type=client_credentials" \\
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \\
  -d "client_assertion=\$ACTIONS_ID_TOKEN_REQUEST_TOKEN" \\
  | jq -r .access_token)

EOF
else
    cat << EOF

# In Azure Container Instance with managed identity:
TOKEN=\$(curl -s -H "Metadata: true" \\
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=api://$APP_ID&client_id=$TEST_CLIENT_ID" \\
  | jq -r .access_token)

EOF
fi

echo ""
echo "🧪 For local testing, we'll demonstrate with your user context:"
echo "(This simulates what the app would do, but uses your identity)"

# Get container app URL first
CONTAINER_APP_URL=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv)

if [ -z "$CONTAINER_APP_URL" ]; then
    echo "❌ Could not get container app URL"
    echo "Make sure container app '$CONTAINER_APP_NAME' exists in resource group '$RESOURCE_GROUP'"
    exit 1
fi

echo "📡 Container App URL: https://$CONTAINER_APP_URL"

# For demonstration, use Azure CLI to get token (but explain it's not true app-to-app)
echo "🎫 Getting demonstration token (using Azure CLI context)..."
TOKEN=$(az account get-access-token --resource "api://$APP_ID" --query accessToken -o tsv 2>/dev/null)

if [ -n "$TOKEN" ]; then
    echo "✅ Demonstration token acquired"
    echo "   ⚠️  Note: This uses YOUR user identity for demonstration"
    echo "   ⚠️  True app-to-app auth requires running from OIDC provider context"
    
    # Test the endpoint
    echo "🧪 Testing MCP endpoint with demonstration token..."
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "https://$CONTAINER_APP_URL/message" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/list",
        "params": {}
      }' 2>/dev/null)

    # Extract HTTP code and body (macOS compatible)
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    echo "HTTP Status: $HTTP_CODE"

    case $HTTP_CODE in
        200)
            echo "🎉 SUCCESS: MCP server authentication working!"
            
            # Try to parse and show available tools
            TOOLS=$(echo "$BODY" | jq -r '.result.tools[]?.name // empty' 2>/dev/null)
            if [ -n "$TOOLS" ]; then
                echo "Available tools:"
                echo "$TOOLS" | head -5 | sed 's/^/  - /'
                TOOL_COUNT=$(echo "$TOOLS" | wc -l)
                if [ "$TOOL_COUNT" -gt 5 ]; then
                    echo "  ... and $((TOOL_COUNT - 5)) more"
                fi
            fi
            ;;
        *)
            echo "❌ Error response"
            echo "Response: $BODY"
            ;;
    esac
else
    echo "❌ Could not get demonstration token"
    echo "Make sure you're logged in to Azure CLI: az login"
fi

echo ""
echo "======================================"
echo "🏁 App-to-App Test Client Setup Complete"
echo ""
echo "📋 Summary:"
echo "- Test Client ID: $TEST_CLIENT_ID"
echo "- Service Principal ID: $TEST_SP_OBJECT_ID" 
echo "- App roles assigned: MCP.Read, MCP.Write"
echo "- Federated credentials: Configured"
echo "- Authentication method: Federated credentials (no secrets/certificates)"
echo ""
echo "🚀 Next Steps for True App-to-App Auth:"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "1. Set up the GitHub Actions workflow in your repository"
    echo "2. Add AZURE_SUBSCRIPTION_ID as a repository secret"  
    echo "3. Run the workflow to test true app-to-app authentication"
    echo "4. The workflow will use the test client identity, not your user identity"
else
    echo "1. Deploy your application in Azure with managed identity"
    echo "2. Configure the managed identity to use federated credentials"
    echo "3. Your application can then get tokens as the test client app"
fi

# Save important IDs for future reference
cat > test-client-app-info.txt << EOF
Test Client App-to-App Authentication Setup
==========================================
Date: $(date)
Test Client ID: $TEST_CLIENT_ID
Service Principal Object ID: $TEST_SP_OBJECT_ID
Resource App ID: $APP_ID
Tenant ID: $TENANT_ID
Container App URL: https://$CONTAINER_APP_URL

Authentication Method: Federated Credentials (no secrets/certificates)

App Roles Assigned:
- MCP.Read: $READ_ROLE_ID
- MCP.Write: $WRITE_ROLE_ID

For App-to-App Token (in OIDC provider context):
curl -s -X POST \\
  "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token" \\
  -H "Content-Type: application/x-www-form-urlencoded" \\
  -d "client_id=$TEST_CLIENT_ID" \\
  -d "scope=api://$APP_ID/.default" \\
  -d "grant_type=client_credentials" \\
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \\
  -d "client_assertion=\$OIDC_TOKEN" \\
  | jq -r .access_token

For local demonstration (uses your identity):
TOKEN=\$(az account get-access-token --resource "api://$APP_ID" --query accessToken -o tsv)

To test the endpoint:
curl -X POST "https://$CONTAINER_APP_URL/message" \\
  -H "Authorization: Bearer \$TOKEN" \\
  -H "Content-Type: application/json" \\
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}'
EOF

echo ""
echo "📄 Complete setup information saved to: test-client-app-info.txt"