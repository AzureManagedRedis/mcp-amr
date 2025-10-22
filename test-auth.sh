#!/bin/bash

# Simple Redis MCP Server Authentication Test
# This script tests the federated credential authentication setup

set -e

# Configuration
TENANT_ID="72f988bf-86f1-41af-91ab-2d7cd011db47"
APP_ID="68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e"  # Redis MCP Server
CONTAINER_APP_NAME="redis-mcp-oauth"
RESOURCE_GROUP="wjason-mcp-sandbox"

echo "🧪 Testing Redis MCP Server Authentication..."
echo "=================================="

# Check if logged in to Azure CLI
if ! az account show >/dev/null 2>&1; then
    echo "❌ Not logged in to Azure CLI"
    echo "Please run: az login"
    exit 1
fi

echo "✅ Azure CLI authenticated"

# Get container app URL
echo "Getting container app URL..."
CONTAINER_APP_URL=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv 2>/dev/null)

if [ -z "$CONTAINER_APP_URL" ]; then
    echo "❌ Could not get container app URL"
    echo "Make sure container app '$CONTAINER_APP_NAME' exists in resource group '$RESOURCE_GROUP'"
    exit 1
fi

echo "✅ Container App URL: https://$CONTAINER_APP_URL"

# Get access token
echo "Getting access token..."
TOKEN=$(az account get-access-token --resource "api://$APP_ID" --query accessToken -o tsv 2>/dev/null)

if [ -z "$TOKEN" ]; then
    echo "❌ Failed to get access token"
    echo "This could mean:"
    echo "  - You don't have permission to access the Redis MCP app"
    echo "  - The app registration doesn't exist"
    echo "  - Your user account needs to be granted access"
    exit 1
fi

echo "✅ Access token acquired (length: ${#TOKEN} characters)"

# Verify token contents
echo "Checking token contents..."
TOKEN_PAYLOAD=$(echo $TOKEN | cut -d. -f2)
# Add padding if needed for base64 decoding
case $((${#TOKEN_PAYLOAD} % 4)) in
    2) TOKEN_PAYLOAD="${TOKEN_PAYLOAD}==" ;;
    3) TOKEN_PAYLOAD="${TOKEN_PAYLOAD}=" ;;
esac

TOKEN_DATA=$(echo $TOKEN_PAYLOAD | base64 -d 2>/dev/null | jq . 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "✅ Token is valid JSON"
    
    # Check for roles or scopes
    ROLES=$(echo "$TOKEN_DATA" | jq -r '.roles[]? // empty' 2>/dev/null)
    SCOPES=$(echo "$TOKEN_DATA" | jq -r '.scp // empty' 2>/dev/null)
    
    if [ -n "$ROLES" ]; then
        echo "✅ Token roles: $ROLES"
    elif [ -n "$SCOPES" ]; then
        echo "✅ Token scopes: $SCOPES"
    else
        echo "⚠️  No roles or scopes found in token"
    fi
else
    echo "⚠️  Could not parse token payload"
fi

# Test MCP endpoint
echo "Testing MCP server endpoint..."
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
        echo "✅ SUCCESS: MCP server responded correctly!"
        
        # Try to parse and show available tools
        TOOLS=$(echo "$BODY" | jq -r '.result.tools[]?.name // empty' 2>/dev/null)
        if [ -n "$TOOLS" ]; then
            echo "Available tools:"
            echo "$TOOLS" | head -5 | sed 's/^/  - /'
            TOOL_COUNT=$(echo "$TOOLS" | wc -l)
            if [ "$TOOL_COUNT" -gt 5 ]; then
                echo "  ... and $((TOOL_COUNT - 5)) more"
            fi
        else
            echo "Response: $BODY"
        fi
        ;;
    401)
        echo "❌ AUTHENTICATION FAILED (401)"
        echo "This could mean:"
        echo "  - Token is invalid or expired"
        echo "  - App roles are not properly assigned"
        echo "  - OAuth scope validation failed"
        ;;
    403)
        echo "❌ AUTHORIZATION FAILED (403)"
        echo "This could mean:"
        echo "  - User/app doesn't have required permissions"
        echo "  - App roles are missing MCP.Read or MCP.Write"
        ;;
    404)
        echo "❌ ENDPOINT NOT FOUND (404)"
        echo "This could mean:"
        echo "  - Container app URL is incorrect"
        echo "  - MCP server is not running"
        ;;
    *)
        echo "❌ UNEXPECTED ERROR ($HTTP_CODE)"
        echo "Response: $BODY"
        ;;
esac

echo "=================================="
echo "🏁 Test completed"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Authentication setup is working correctly!"
    exit 0
else
    echo "❌ Authentication setup needs attention"
    exit 1
fi