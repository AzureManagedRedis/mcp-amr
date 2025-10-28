# Deploying with Azure Developer CLI (azd)

This guide shows you how to deploy the Redis MCP Server using Azure Developer CLI (`azd`).

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
3. ✅ Deploy all Azure resources (Redis, Container Apps, etc.)
4. ✅ Build and push container image
5. ✅ Deploy the MCP server application
6. ✅ Output all connection details

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

### API Key Authentication
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
azd env set OAUTH_REQUIRED_SCOPES "api://your-app/.default"
azd up
```

## 🔄 Common Operations

### View Deployed Resources
```bash
# List all resources in your environment
azd env get-values

# Show resource group in Azure Portal
az group show --name rg-$(azd env get-value AZURE_ENV_NAME)
```

### Update Application Code
```bash
# After making code changes, redeploy
azd deploy
```

### Re-provision Infrastructure
```bash
# Update infrastructure only
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

### Scale Application
```bash
CONTAINER_APP_NAME=$(azd env get-value AZURE_CONTAINER_APP_NAME)
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)

az containerapp update \
  --name "$CONTAINER_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --min-replicas 3 \
  --max-replicas 10
```

## 🌍 Multiple Environments

Deploy to multiple environments (dev, staging, prod):

```bash
# Create and deploy to dev
azd env new dev
azd env set AZURE_LOCATION eastus
azd up

# Create and deploy to staging
azd env new staging
azd env set AZURE_LOCATION westus2
azd up

# Create and deploy to prod
azd env new prod
azd env set AZURE_LOCATION westus2
azd env set REDIS_ENTERPRISE_SKU Balanced_B5
azd env set MIN_REPLICAS 3
azd env set MAX_REPLICAS 20
azd up

# Switch between environments
azd env select dev
azd env select staging
azd env select prod
```

## 🧪 Testing Deployment

```bash
# Get the MCP server URL
MCP_URL=$(azd env get-value MCP_SERVER_URL)
CONTAINER_APP_FQDN=$(azd env get-value AZURE_CONTAINER_APP_FQDN)

# Test health endpoint
curl https://${CONTAINER_APP_FQDN}/health

# Test with API key (if using API-KEY auth)
curl -H "X-API-Key: your-api-key" https://${CONTAINER_APP_FQDN}/health

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

## 🔧 Troubleshooting

### View Environment Variables
```bash
azd env get-values
```

### Check Deployment Status
```bash
azd show
```

### View Resource Group
```bash
RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
az group show --name "$RESOURCE_GROUP"
```

### Redeploy from Scratch
```bash
azd down --force --purge
azd up
```

## 📚 CI/CD Integration

### GitHub Actions

The repository includes a GitHub Actions workflow (`.github/workflows/azure-dev.yml`).

**Setup**:
1. Fork the repository
2. Set repository secrets/variables:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`
   - `AZURE_ENV_NAME`
   - `AZURE_LOCATION`
3. Push to `main` branch to trigger deployment

### Azure DevOps

The repository includes an Azure DevOps pipeline (`.azdo/pipeline.yml`).

**Setup**:
1. Create service connection in Azure DevOps
2. Set pipeline variables
3. Run pipeline

## 🆚 azd vs Shell Script

| Feature | `azd up` | Shell Script |
|---------|----------|--------------|
| Setup | Single command | Multiple commands |
| Environment Management | Built-in multi-env | Manual |
| CI/CD Integration | Native GitHub/ADO | Custom setup |
| Updates | `azd deploy` | Manual rebuild |
| Cleanup | `azd down` | Manual deletion |
| Learning Curve | Moderate | Low |
| Flexibility | Structured | Very flexible |

**Choose `azd` if you want**:
- ✅ Quick, standardized deployments
- ✅ Multiple environments (dev/staging/prod)
- ✅ Built-in CI/CD integration
- ✅ Azure best practices out of the box

**Choose shell script if you want**:
- ✅ Maximum control and customization
- ✅ No additional tools to learn
- ✅ Custom deployment workflows

## 📖 Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [azd Templates](https://azure.github.io/awesome-azd/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure Managed Redis Documentation](https://learn.microsoft.com/azure/azure-cache-for-redis/)
