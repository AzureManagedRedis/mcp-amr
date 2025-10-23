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
IMAGE_NAME="redis-mcp-server"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Basic --admin-enabled true
```

#### Step 2: Build and Push Container Image

```bash
# Build and push to ACR
<<<<<<< HEAD
az acr build --registry $ACR_NAME --image $IMAGE_NAME:latest --platform linux/amd64 .

# Or build locally and push
docker build -t $IMAGE_NAME .
az acr login --name $ACR_NAME
docker tag $IMAGE_NAME $ACR_NAME.azurecr.io/$IMAGE_NAME:latest
docker push $ACR_NAME.azurecr.io/$IMAGE_NAME:latest
=======
# Build the image name to avoid zsh colon interpretation issues
IMAGE_WITH_TAG="${IMAGE_NAME}:latest"
az acr build --registry $ACR_NAME --image "$IMAGE_WITH_TAG" .

# Or build locally and push
docker build -t $IMAGE_NAME --platform linux/amd64 .
az acr login --name $ACR_NAME
FULL_IMAGE_PATH="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest"
docker tag $IMAGE_NAME "$FULL_IMAGE_PATH"
docker push "$FULL_IMAGE_PATH"
>>>>>>> wjason/server-auth
```

#### Step 3: Create Container Apps Environment

```bash
CONTAINER_APP_ENV="env-redis-mcp"

az containerapp env create \
  --name $CONTAINER_APP_ENV \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

#### Step 4: Create User-Assigned Managed Identity

```bash
CONTAINER_APP_NAME="redis-mcp-server"
IDENTITY_NAME="identity-redis-mcp"

# Create the managed identity
az identity create \
  --name $IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION

# Get identity details
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

echo "Identity Client ID: $IDENTITY_CLIENT_ID"
echo "Identity Principal ID: $IDENTITY_PRINCIPAL_ID"
```

#### Step 5: Deploy Container App with Managed Identity

```bash
# Get ACR credentials
ACR_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username --output tsv)
ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query 'passwords[0].value' --output tsv)

<<<<<<< HEAD
=======
# Build the full image path to avoid zsh colon interpretation issues
FULL_IMAGE_PATH="${ACR_SERVER}/${IMAGE_NAME}:latest"

>>>>>>> wjason/server-auth
# Create container app with user-assigned managed identity
az containerapp create \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $CONTAINER_APP_ENV \
<<<<<<< HEAD
  --image $ACR_SERVER/$IMAGE_NAME:latest \
=======
  --image "$FULL_IMAGE_PATH" \
>>>>>>> wjason/server-auth
  --registry-server $ACR_SERVER \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --user-assigned $IDENTITY_ID \
  --target-port 8000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 5 \
  --cpu 0.25 \
  --memory 0.5Gi \
  --env-vars \
    REDIS_HOST=$REDIS_HOST \
    REDIS_PORT=10000 \
    REDIS_SSL=true \
    REDIS_ENTRAID_AUTH_METHOD=managed_identity \
    REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID=$IDENTITY_CLIENT_ID \
    MCP_REDIS_LOG_LEVEL=INFO
```

#### Step 6: Grant Redis Access to Managed Identity

```bash
# For Azure Cache for Redis Enterprise with Entra ID support
REDIS_NAME="your-redis-cache-name"

az redis access-policy-assignment create \
  --resource-group $RESOURCE_GROUP \
  --redis-cache-name $REDIS_NAME \
  --access-policy-assignment-name "mcp-server-access" \
  --access-policy-name "Data Contributor" \
  --object-id $IDENTITY_PRINCIPAL_ID \
  --object-id-alias "ServicePrincipal"

echo "Deployment complete! Your container app is now using managed identity for Redis authentication."
```

> **Note**: If you're using Azure Cache for Redis Basic/Standard (non-Enterprise) that doesn't support Entra ID authentication, you'll need to use password-based authentication instead. Add `REDIS_PWD=your-redis-password` to the environment variables and remove the `REDIS_ENTRAID_*` variables.

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

<<<<<<< HEAD
=======
### MCP Server OAuth Authentication (Protect MCP Endpoints)

Protect your MCP server endpoints with Microsoft Entra ID OAuth authentication. Clients must present valid access tokens to use the MCP tools.

#### Environment Variables for MCP OAuth

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `MCP_OAUTH_ENABLED` | Enable OAuth authentication | Yes | `true` |
| `MCP_OAUTH_TENANT_ID` | Entra ID tenant ID | Yes | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `MCP_OAUTH_CLIENT_ID` | Application (client) ID | Yes | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `MCP_OAUTH_REQUIRED_SCOPES` | Required OAuth scopes (comma-separated) | No | `api://your-app-id/.default` or `MCP.Read,MCP.Write` |

#### Setup Instructions

**1. Register Application in Entra ID:**

```bash
# Create app registration
az ad app create \
  --display-name "Redis MCP Server" \
  --sign-in-audience AzureADMyOrg

# Get the app ID
APP_ID=$(az ad app list --display-name "Redis MCP Server" --query '[0].appId' -o tsv)

# Expose an API and add scopes
az ad app update --id $APP_ID \
  --identifier-uris "api://$APP_ID"

# Add application roles (optional)
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

**2. Deploy with OAuth Enabled:**

```bash
# Get your tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

# Deploy container app with OAuth
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    MCP_OAUTH_ENABLED=true \
    MCP_OAUTH_TENANT_ID=$TENANT_ID \
    MCP_OAUTH_CLIENT_ID=$APP_ID \
    MCP_OAUTH_REQUIRED_SCOPES="MCP.Read,MCP.Write"
```

**3. Create a Test Client and Get Token:**

We provide two ready-to-use scripts for testing authentication:

#### Option A: Quick Testing with Azure CLI (Recommended)

Use your existing Azure CLI login to quickly test the MCP server:

```bash
# Run the simple authentication test
./test-auth.sh
```

This script will:
- ✅ Use your Azure CLI context (no app registration needed)
- ✅ Get an access token for the MCP server
- ✅ Test the MCP endpoints and show available tools
- ✅ Provide clear success/error messages

#### Option B: App-to-App Authentication Setup

For true app-to-app authentication using federated credentials (no secrets or certificates):

```bash
# Run the app-to-app setup script  
./create-app-to-app-client.sh
```

This script will:
- ✅ Create a dedicated test client app registration
- ✅ Assign proper app roles (MCP.Read, MCP.Write)
- ✅ Set up federated credentials for GitHub Actions or Azure services
- ✅ Generate sample GitHub Actions workflow for CI/CD testing
- ✅ Demonstrate true client app identity (not user identity)

#### Manual Testing

If you prefer manual testing:

```bash
# Get token using Azure CLI context
TOKEN=$(az account get-access-token --resource "api://68dd3060-50d2-4ee0-bb8e-0aa54fff6b1e" --query accessToken -o tsv)

# Test MCP server
curl -X POST "https://redis-mcp-oauth.blacktree-376d2ec0.westus2.azurecontainerapps.io/message" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}'
```

**Expected Results:**
- ✅ HTTP 200 response with list of available Redis tools
- ✅ Token contains app roles (`MCP.Read`, `MCP.Write`) or appropriate scopes
- ✅ MCP server returns tools like `redis_get`, `redis_set`, `redis_list_keys`, etc.

**Benefits of Federated Credentials:**
- ✅ No client secrets to manage or rotate
- ✅ More secure - uses OIDC token exchange
- ✅ Better for CI/CD pipelines and cloud-native apps
- ✅ Supports workload identity patterns

>>>>>>> wjason/server-auth
### Entra ID Authentication (Recommended for Azure Cache for Redis Enterprise)

Azure Cache for Redis Enterprise supports Microsoft Entra ID (formerly Azure AD) authentication, providing better security without managing passwords.

<<<<<<< HEAD
#### Environment Variables for Entra ID
=======
#### Environment Variables for Redis Entra ID
>>>>>>> wjason/server-auth

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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
  --resource-group $RESOURCE_GROUP \
  --system-assigned

# Get the principal ID
PRINCIPAL_ID=$(az containerapp identity show \
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
  --resource-group $RESOURCE_GROUP \
  --secrets cert-file="$(cat cert.pem | base64)"

# Deploy with service principal authentication
az containerapp update \
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
   az containerapp identity assign --name redis-mcp-server --resource-group $RESOURCE_GROUP --system-assigned
=======
   az containerapp identity assign --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --system-assigned
>>>>>>> wjason/server-auth
   ```

3. **Use Virtual Network** for private communication:
   ```bash
   # Create VNet
   az network vnet create --resource-group $RESOURCE_GROUP --name vnet-redis-mcp --address-prefix 10.0.0.0/16 --subnet-name subnet-containers --subnet-prefix 10.0.1.0/24
   ```

<<<<<<< HEAD
=======
## Updating Container App with Latest Image

### Issue: Latest Tag Not Pulling New Image

When using the `:latest` tag, Container Apps may cache the image and not pull the newest version. Here are several solutions:

#### Solution 1: Force Update with Revision Restart

```bash
# First, build and push your latest image
IMAGE_WITH_TAG="${IMAGE_NAME}:latest"
az acr build --registry $ACR_NAME --image "$IMAGE_WITH_TAG" .

# Update container app
ACR_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
FULL_IMAGE_PATH="${ACR_SERVER}/${IMAGE_NAME}:latest"

az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image "$FULL_IMAGE_PATH"

# Force restart to pull latest image
az containerapp revision restart \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP
```

#### Solution 2: Use Unique Tags

```bash
# Use timestamp-based tags to force new image pulls
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IMAGE_WITH_TAG="${IMAGE_NAME}:${TIMESTAMP}"

# Build with unique tag
az acr build --registry $ACR_NAME --image "$IMAGE_WITH_TAG" .

# Update with specific tag
ACR_SERVER=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query loginServer --output tsv)
FULL_IMAGE_PATH="${ACR_SERVER}/${IMAGE_NAME}:${TIMESTAMP}"

az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image "$FULL_IMAGE_PATH"
```

### Verify Image Update

After updating, verify that the new image is being used:

```bash
# Check current image
az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "properties.template.containers[0].image" \
  --output tsv

# List recent revisions to see deployment history
az containerapp revision list \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name,Active:properties.active,CreatedTime:properties.createdTime,Image:properties.template.containers[0].image}" \
  --output table

# Check if new revision is running
az containerapp revision show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --revision-name "$(az containerapp revision list --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query '[0].name' -o tsv)" \
  --query "properties.runningState" \
  --output tsv
```

### Why This Happens

1. **Image Caching**: Container platforms cache images to improve performance
2. **Latest Tag Ambiguity**: The `:latest` tag is just a pointer, not a version
3. **No Change Detection**: If the tag hasn't changed, the platform assumes no update is needed

### Best Practices

- **Use unique tags** for production deployments (timestamps, git SHA, semantic versions)
- **Reserve `:latest`** for development/testing only
- **Implement proper CI/CD** with versioned releases
- **Monitor deployments** to ensure updates are successful

>>>>>>> wjason/server-auth
## Monitoring and Troubleshooting

### View Logs

```bash
# Container Apps logs
<<<<<<< HEAD
az containerapp logs show --name redis-mcp-server --resource-group $RESOURCE_GROUP --follow
=======
az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow
>>>>>>> wjason/server-auth

# Or use Azure Portal > Container Apps > Monitoring > Log stream
```

### Health Checks

The application includes a health check endpoint. Monitor it in Azure:

```bash
# Check app status
<<<<<<< HEAD
az containerapp show --name redis-mcp-server --resource-group $RESOURCE_GROUP --query properties.runningStatus
=======
az containerapp show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --query properties.runningStatus
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
  --name redis-mcp-server \
=======
  --name $CONTAINER_APP_NAME \
>>>>>>> wjason/server-auth
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
<<<<<<< HEAD
        az acr build --registry ${{ secrets.ACR_NAME }} --image redis-mcp-server:${{ github.sha }} .
=======
        az acr build --registry ${{ secrets.ACR_NAME }} --image "${{ secrets.IMAGE_NAME }}:${{ github.sha }}" .
>>>>>>> wjason/server-auth
    
    - name: Deploy to Container Apps
      run: |
        az containerapp update \
<<<<<<< HEAD
          --name redis-mcp-server \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --image ${{ secrets.ACR_NAME }}.azurecr.io/redis-mcp-server:${{ github.sha }}
=======
          --name ${{ secrets.CONTAINER_APP_NAME }} \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --image "${{ secrets.ACR_NAME }}.azurecr.io/${{ secrets.IMAGE_NAME }}:${{ github.sha }}"
>>>>>>> wjason/server-auth
```

## Additional Resources

- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Cache for Redis Documentation](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Redis MCP Server GitHub Repository](https://github.com/redis/mcp-redis)