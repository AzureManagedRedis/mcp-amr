# Deploying with Azure Developer CLI (azd)

This guide shows you how to deploy the remote MCP Server for Azure Managed Redis using Azure Developer CLI (`azd`).

## 🚀 Quick Start

### Prerequisites

1. **Install Azure Developer CLI**:
   ```bash
   # macOS/Linux
   curl -fsSL https://aka.ms/install-azd.sh | bash
   
   # Windows (PowerShell)
   powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"
   ```

2. **Install Azure CLI** (if not already installed):
   ```bash
   # macOS
   brew install azure-cli
   
   # Windows
   winget install Microsoft.AzureCLI
   
   # Linux
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
   ```

3. **Install Docker** (for local development):
   - [Docker Desktop](https://www.docker.com/products/docker-desktop)

### Deploy with One Command

```bash
# Login to Azure
azd auth login

# Initialize environment and deploy
azd up
```

That's it! `azd up` will:
1. ✅ Prompt you for environment name, subscription, and location
2. ✅ Create resource group
3. ✅ Deploy all Azure resources (Azure Managed Redis instance, remote MCP server hosted on Container Apps, etc.)
4. ✅ **Auto-generate API keys** (if using API-KEY auth method)
5. ✅ Build and push container image
6. ✅ Deploy the MCP server application
7. ✅ Output all connection details and **display generated API keys**

## 📋 Configuration

### Environment Variables

You can customize the deployment by setting environment variables before running `azd up`:

```bash
# Set Azure location
azd env set AZURE_LOCATION westus2

# Configure Redis SKU
azd env set REDIS_ENTERPRISE_SKU Balanced_B3

# Enable Redis modules
azd env set ENABLE_REDIS_SEARCH true
azd env set ENABLE_REDIS_JSON true
azd env set ENABLE_REDIS_TIMESERIES false
azd env set ENABLE_REDIS_BLOOM false

# Configure scaling
azd env set MIN_REPLICAS 2
azd env set MAX_REPLICAS 10

# Set log level
azd env set LOG_LEVEL DEBUG

# Configure authentication
azd env set MCP_AUTH_METHOD API-KEY
azd env set MCP_API_KEYS "key1,key2,key3"

# Then deploy
azd up
```

### Using .env file

Alternatively, copy the template and edit:

```bash
cp .azure/dev/.env.template .azure/dev/.env
# Edit .azure/dev/.env with your values
azd up
```

## 🔐 Authentication Options

### NO-AUTH (Default)
```bash
azd env set MCP_AUTH_METHOD NO-AUTH
azd up
```

### API Key Authentication (RECOMMENDED)
```bash
# Option 1: Auto-generate API keys (Recommended)
azd env set MCP_AUTH_METHOD API-KEY
azd up
```

**Sample Output with Auto-Generated Keys:**
```
🔐 Generating API keys for MCP authentication...

🎉 API Keys generated successfully!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Your MCP Server API Keys (save these securely):

   🔑 API Key 1: K8vX9nM2pL5wR3yT7uA6sD4fG1hJ9bN0cV
   🔑 API Key 2: P9mQ2xB7vC5nR8yU3wA6sF4lG1kJ0dN7cZ

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

💡 Usage examples:
   • HTTP Header:  X-API-Key: K8vX9nM2pL5wR3yT7uA6sD4fG1hJ9bN0cV
   • Query Parameter: ?api_key=K8vX9nM2pL5wR3yT7uA6sD4fG1hJ9bN0cV

⚠️  Important: Store these keys securely. They will not be shown again.
   You can retrieve them later with: azd env get-value MCP_API_KEYS
```

**Option 2: Provide your own API keys**
```bash
azd env set MCP_AUTH_METHOD API-KEY
azd env set MCP_API_KEYS "$(openssl rand -base64 32),$(openssl rand -base64 32)"
azd up
```

### OAuth Authentication
```bash
azd env set MCP_AUTH_METHOD OAUTH
azd env set OAUTH_TENANT_ID "your-tenant-id"
azd env set OAUTH_CLIENT_ID "your-client-id"
azd env set OAUTH_REQUIRED_SCOPES "MCP.Write,MCP.Read"
azd up
```

### View Generated API Keys
```bash
# View API keys (if using API-KEY authentication)
azd env get-value MCP_API_KEYS

# View authentication method
azd env get-value MCP_AUTH_METHOD

# Or use the helper script
./scripts/api-keys.sh show
```

### Regenerate API Keys
```bash
# Generate new API keys and update deployment
./scripts/api-keys.sh generate
azd provision
```

### Update Infrastructure/Application
```bash
# After making code changes, redeploy
azd provision
```

### View Logs
```bash
# Get container app name
CONTAINER_APP_NAME=$(azd env get-value AZURE_CONTAINER_APP_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)

# Stream logs
az containerapp logs show \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --follow
```

## 🧪 Testing Deployment

```bash
# Get the MCP server URL
MCP_URL=$(azd env get-value MCP_SERVER_URL)
CONTAINER_APP_FQDN=$(azd env get-value AZURE_CONTAINER_APP_FQDN)

# Test health endpoint (NO-AUTH)
curl https://${CONTAINER_APP_FQDN}/health

# Test with API key (if using API-KEY auth)
API_KEY=$(azd env get-value MCP_API_KEYS | cut -d',' -f1)
curl -H "X-API-Key: $API_KEY" https://${CONTAINER_APP_FQDN}/health

# Test with OAuth (if using OAUTH auth)
curl -H "Authorization: Bearer your-jwt-token" https://${CONTAINER_APP_FQDN}/health
```

## 🗑️ Cleanup

```bash
# Delete all resources in the environment
azd down

# Delete with confirmation
azd down --force --purge
```

## 📖 Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [azd Templates](https://azure.github.io/awesome-azd/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure Managed Redis Documentation](https://learn.microsoft.com/azure/azure-cache-for-redis/)
