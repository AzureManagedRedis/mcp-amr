# Deploying Redis MCP Server to Azure Container Apps

This guide walks you through deploying the Redis MCP Server to Azure Container Apps, a fully managed serverless container platform.

## Prerequisites

1. **Azure CLI** installed and logged in:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Docker** installed (for local testing)

3. **Azure Cache for Redis** instance (recommended) or external Redis

## Quick Deployment

### Option 1: Automated Deployment (Recommended)

1. **Configure your settings** in the deployment script:
   ```bash
   # For Linux/macOS
   chmod +x deploy-to-azure.sh
   
   # For Windows
   # Use deploy-to-azure.ps1
   ```

2. **Update variables** in the script:
   - Change `ACR_NAME` to something globally unique
   - Update Redis connection details
   - Modify resource group name and location if needed

3. **Run the deployment**:
   ```bash
   # Linux/macOS
   ./deploy-to-azure.sh
   
   # Windows PowerShell
   .\deploy-to-azure.ps1
   ```

### Option 2: Manual Step-by-Step Deployment

#### Step 1: Create Azure Resources

```bash
# Set variables
RESOURCE_GROUP="rg-redis-mcp"
LOCATION="eastus"
ACR_NAME="your-unique-acr-name"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
```

#### Step 2: Build and Push Container Image

```bash
# Build and push to ACR
az acr build --registry $ACR_NAME --image redis-mcp-server:latest .

# Or build locally and push
docker build -t redis-mcp-server .
az acr login --name $ACR_NAME
docker tag redis-mcp-server $ACR_NAME.azurecr.io/redis-mcp-server:latest
docker push $ACR_NAME.azurecr.io/redis-mcp-server:latest
```

#### Step 3: Create Container Apps Environment

```bash
CONTAINER_APP_ENV="env-redis-mcp"

az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

#### Step 4: Deploy Container App

```bash
# Get ACR credentials
ACR_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value --output tsv)

# Create container app
az containerapp create \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APP_ENV \
  --image $ACR_SERVER/redis-mcp-server:latest \
  --registry-server $ACR_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 5 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    REDIS_HOST=your-redis-host \
    REDIS_PORT=6380 \
    REDIS_PWD=your-redis-password \
    REDIS_SSL=true \
    MCP_REDIS_LOG_LEVEL=INFO
```

## Setting up Azure Cache for Redis

### Create Redis Cache

```bash
REDIS_NAME="redis-mcp-cache"

az redis create \
  --location $LOCATION \
  --name $REDIS_NAME \
  --resource-group $RESOURCE_GROUP \
  --sku Basic \
  --vm-size c0
```

### Get Redis Connection Details

```bash
# Get hostname
REDIS_HOST=$(az redis show --name $REDIS_NAME --resource-group $RESOURCE_GROUP --query hostName --output tsv)

# Get access keys
REDIS_KEY=$(az redis list-keys --name $REDIS_NAME --resource-group $RESOURCE_GROUP --query primaryKey --output tsv)

echo "Redis Host: $REDIS_HOST"
echo "Redis Port: 6380 (SSL)"
echo "Redis Key: $REDIS_KEY"
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `REDIS_HOST` | Redis hostname | `127.0.0.1` | `mycache.redis.cache.windows.net` |
| `REDIS_PORT` | Redis port | `6379` | `6380` (SSL) |
| `REDIS_PWD` | Redis password | `""` | Your Redis access key |
| `REDIS_SSL` | Enable SSL | `false` | `true` |
| `REDIS_DB` | Database number | `0` | `0` |
| `MCP_REDIS_LOG_LEVEL` | Log level | `WARNING` | `INFO` |

### Entra ID Authentication (Recommended for Azure Cache for Redis Enterprise)

Azure Cache for Redis Enterprise supports Microsoft Entra ID (formerly Azure AD) authentication, providing better security without managing passwords.

#### Environment Variables for Entra ID

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `REDIS_ENTRAID_AUTH_METHOD` | Authentication method | Yes | `managed_identity`, `service_principal`, or `default_azure_credential` |
| `REDIS_ENTRAID_TENANT_ID` | Tenant ID | For service_principal | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `REDIS_ENTRAID_CLIENT_ID` | Application (client) ID | For service_principal | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `REDIS_ENTRAID_CERT_PATH` | Path to certificate file | For service_principal | `/app/cert.pem` |
| `REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID` | Managed identity client ID | For user-assigned MI | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

#### Authentication Methods

**1. Managed Identity (Recommended for Container Apps):**

**Option A: System-Assigned Managed Identity**

```bash
# Enable system-assigned managed identity
az containerapp identity assign \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --system-assigned

# Get the principal ID
PRINCIPAL_ID=$(az containerapp identity show \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --query principalId \
  --output tsv)

# Grant Redis access to the managed identity
az redis access-policy-assignment create \
  --resource-group $RESOURCE_GROUP \
  --redis-cache-name $REDIS_NAME \
  --access-policy-assignment-name "mcp-server-access" \
  --access-policy-name "Data Contributor" \
  --object-id $PRINCIPAL_ID \
  --object-id-alias "ServicePrincipal"

# Deploy with managed identity authentication
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_HOST=your-redis-host \
    REDIS_PORT=6380 \
    REDIS_SSL=true \
    REDIS_ENTRAID_AUTH_METHOD=managed_identity
```

**Option B: User-Assigned Managed Identity**

```bash
# Create a user-assigned managed identity
IDENTITY_NAME="identity-redis-mcp"
az identity create \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Get the identity details
IDENTITY_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query id \
  --output tsv)

IDENTITY_CLIENT_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query clientId \
  --output tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId \
  --output tsv)

# Assign the user-assigned identity to the container app
az containerapp identity assign \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --user-assigned $IDENTITY_ID

# Grant Redis access to the user-assigned managed identity
az redis access-policy-assignment create \
  --resource-group $RESOURCE_GROUP \
  --redis-cache-name $REDIS_NAME \
  --access-policy-assignment-name "mcp-server-access" \
  --access-policy-name "Data Contributor" \
  --object-id $IDENTITY_PRINCIPAL_ID \
  --object-id-alias "ServicePrincipal"

# Deploy with user-assigned managed identity authentication
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_HOST=your-redis-host \
    REDIS_PORT=6380 \
    REDIS_SSL=true \
    REDIS_ENTRAID_AUTH_METHOD=managed_identity \
    REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID=$IDENTITY_CLIENT_ID
```

**2. Service Principal (Certificate-based):**

```bash
# Create service principal
az ad sp create-for-rbac --name "redis-mcp-sp" --create-cert

# Upload certificate as secret (assuming cert is in cert.pem)
az containerapp secret set \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --secrets cert-file="$(cat cert.pem | base64)"

# Deploy with service principal authentication
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_HOST=your-redis-host \
    REDIS_PORT=6380 \
    REDIS_SSL=true \
    REDIS_ENTRAID_AUTH_METHOD=service_principal \
    REDIS_ENTRAID_TENANT_ID=your-tenant-id \
    REDIS_ENTRAID_CLIENT_ID=your-client-id \
    REDIS_ENTRAID_CERT_PATH=/mnt/secrets/cert-file
```

**3. DefaultAzureCredential (Tries multiple methods):**

```bash
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_HOST=your-redis-host \
    REDIS_PORT=6380 \
    REDIS_SSL=true \
    REDIS_ENTRAID_AUTH_METHOD=default_azure_credential
```

### Security Best Practices

1. **Use Entra ID Authentication** (Recommended for Azure Cache for Redis Enterprise):
   - ✅ No password management needed
   - ✅ Automatic token rotation
   - ✅ Better audit trail
   - ✅ Works with Azure RBAC

2. **Use Azure Key Vault** for storing Redis passwords (if not using Entra ID):
   ```bash
   # Create Key Vault
   az keyvault create --name "kv-redis-mcp" --resource-group $RESOURCE_GROUP --location $LOCATION
   
   # Store Redis password
   az keyvault secret set --vault-name "kv-redis-mcp" --name "redis-password" --value $REDIS_KEY
   ```

2. **Enable Managed Identity** for the Container App:
   ```bash
   az containerapp identity assign --name redis-mcp-server --resource-group $RESOURCE_GROUP --system-assigned
   ```

3. **Use Virtual Network** for private communication:
   ```bash
   # Create VNet
   az network vnet create --resource-group $RESOURCE_GROUP --name vnet-redis-mcp --address-prefix 10.0.0.0/16 --subnet-name subnet-containers --subnet-prefix 10.0.1.0/24
   ```

## Monitoring and Troubleshooting

### View Logs

```bash
# Container Apps logs
az containerapp logs show --name redis-mcp-server --resource-group $RESOURCE_GROUP --follow

# Or use Azure Portal > Container Apps > Monitoring > Log stream
```

### Health Checks

The application includes a health check endpoint. Monitor it in Azure:

```bash
# Check app status
az containerapp show --name redis-mcp-server --resource-group $RESOURCE_GROUP --query properties.runningStatus
```

### Common Issues

1. **Redis Connection Failed**
   - Verify Redis host, port, and password
   - Check if SSL is required (Azure Cache for Redis uses SSL by default)
   - Ensure firewall rules allow Container Apps IP ranges

2. **Container Won't Start**
   - Check environment variables
   - Review container logs
   - Verify image build was successful

3. **Performance Issues**
   - Increase CPU/memory allocation
   - Scale up replicas
   - Check Redis performance metrics

## Scaling and Performance

### Auto-scaling Rules

```bash
# Update scaling rules
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --min-replicas 2 \
  --max-replicas 10 \
  --scale-rule-name "http-requests" \
  --scale-rule-type "http" \
  --scale-rule-http-concurrency 30
```

### Resource Allocation

```bash
# Increase resources
az containerapp update \
  --name redis-mcp-server \
  --resource-group $RESOURCE_GROUP \
  --cpu 0.5 \
  --memory 1Gi
```

## Cost Optimization

1. **Use appropriate pricing tier**:
   - Basic: Development/testing
   - Standard: Production workloads
   - Premium: High-performance needs

2. **Right-size resources**:
   - Start with minimal CPU/memory
   - Monitor and scale based on usage

3. **Implement auto-shutdown** for development environments

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure Container Apps

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Build and push
      run: |
        az acr build --registry ${{ secrets.ACR_NAME }} --image redis-mcp-server:${{ github.sha }} .
    
    - name: Deploy to Container Apps
      run: |
        az containerapp update \
          --name redis-mcp-server \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --image ${{ secrets.ACR_NAME }}.azurecr.io/redis-mcp-server:${{ github.sha }}
```

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Cache for Redis Documentation](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Redis MCP Server GitHub Repository](https://github.com/redis/mcp-redis)