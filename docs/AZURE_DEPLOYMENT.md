# Deploying Redis MCP Server to Azure Container Apps

This guide walks you through deploying the Redis MCP Server to Azure Container Apps using the **automated deployment script** with integrated **authentication configuration**.

## 🚀 Quick Start (Recommended)

The easiest way to deploy is using our **interactive deployment script**:

```bash
./infra/deploy-redis-mcp.sh
```

This script will:
1. **Configure infrastructure** (resource group, location, Redis SKU)  
2. **Configure authentication** (NO-AUTH, API-KEY, or OAUTH)
3. **Deploy complete stack** (Azure Managed Redis, Container Apps, networking)
4. **Build and deploy** your MCP server automatically

## 📋 Prerequisites

Before starting, ensure you have:

1. **Azure CLI** installed and authenticated:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Docker** installed (for building container images)

3. **Project files** - Run the script from the **project root directory**

## 🔐 Authentication Options

The deployment script supports three authentication methods:

### 1. **NO-AUTH** (Development/Testing)
- **Use case**: Development, testing, trusted networks
- **Configuration**: No additional setup required
- **Client usage**: Direct API calls without authentication

### 2. **API-KEY** (Production Ready)  
- **Use case**: Production deployments with API key management
- **Configuration**: Provide comma-separated API keys during deployment
- **Client usage**: Include `X-API-Key` header in requests
- **Generate keys**: `openssl rand -base64 32`

### 3. **OAUTH** (Enterprise)
- **Use case**: Enterprise environments with Azure Entra ID
- **Configuration**: Provide Azure tenant ID, client ID, and scopes
- **Client usage**: Include `Authorization: Bearer <jwt-token>` header
- **Setup**: Requires Azure App Registration

## 🛠️ Deployment Process

### Interactive Deployment

1. **Run the deployment script**:
   ```bash
   ./infra/deploy-redis-mcp.sh
   ```

2. **Configure infrastructure** when prompted:
   - Resource group name
   - Azure region
   - Azure Managed Redis SKU (B0, B1, B3, B5, etc.)

3. **Configure authentication** when prompted:
   ```
   Available authentication methods:
     1) NO-AUTH  - No authentication required
     2) API-KEY  - API key authentication via X-API-Key header  
     3) OAUTH    - OAuth JWT token authentication
   
   Select authentication method (1-3): 2
   Enter API keys: key1,key2,key3
   ```

4. **Confirm and deploy** - The script handles everything automatically!

### Non-Interactive Deployment

For CI/CD pipelines, you can provide parameters directly:

```bash
./infra/deploy-redis-mcp.sh \
  --resource-group "rg-redis-mcp-prod" \
  --location "westus2" \
  --redis-sku "Balanced_B3"
```

*Note: Authentication must still be configured interactively for security*

## 🏗️ What Gets Deployed

The automated deployment creates:

### Azure Resources:
- **Azure Managed Redis** - High-performance Redis with modules
- **Container Apps Environment** - Serverless container hosting  
- **Container Registry** - Private container image storage
- **User-Assigned Managed Identity** - Secure Redis access
- **Log Analytics Workspace** - Centralized logging
- **Networking & Security** - Proper network isolation

### MCP Server Configuration:
- **Redis Connection** - Automatic connection via managed identity
- **Authentication Middleware** - Based on your selected method
- **Health Monitoring** - Built-in health checks  
- **Auto-scaling** - Scales based on HTTP traffic
- **Logging** - Structured logs to Azure Monitor

## 🔧 Manual Configuration (Advanced)

If you prefer manual deployment or need to customize beyond the script options:

### Environment Variables

The deployment configures these environment variables based on your authentication choice:

```bash
# Authentication Configuration
MCP_AUTH_METHOD=API-KEY              # or NO-AUTH, OAUTH
MCP_API_KEYS=key1,key2,key3         # Required for API-KEY
MCP_OAUTH_TENANT_ID=your-tenant     # Required for OAUTH  
MCP_OAUTH_CLIENT_ID=your-client     # Required for OAUTH
MCP_OAUTH_REQUIRED_SCOPES=scope1    # Optional for OAUTH

# Redis Configuration (Auto-configured)
REDIS_HOST=your-redis.redis.cache.windows.net
REDIS_PORT=10000
REDIS_SSL=true
REDIS_ENTRAID_AUTH_METHOD=managed_identity
REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID=your-identity-id
```

### Custom Bicep Deployment

```bash
# Deploy with Bicep templates
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/resources.bicep \
  --parameters @infra/resources.parameters.json \
  --parameters location=$LOCATION \
  --parameters mcpAuthMethod="API-KEY" \
  --parameters mcpApiKeys="key1,key2,key3"
```

## 📊 Testing Your Deployment

After deployment completes, test your MCP server:

### Health Check (No Authentication Required)
```bash
curl https://your-app-url.azurecontainerapps.io/health
```

### Authentication Testing

#### NO-AUTH Method:
```bash
curl -X POST https://your-app-url.azurecontainerapps.io/message \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

#### API-KEY Method:
```bash
curl -X POST https://your-app-url.azurecontainerapps.io/message \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

#### OAUTH Method:
```bash
# Get token (example using Azure CLI)
TOKEN=$(az account get-access-token --resource "api://your-client-id" --query accessToken -o tsv)

curl -X POST https://your-app-url.azurecontainerapps.io/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

## 🔧 Configuration Reference

### Authentication Environment Variables

| Variable | Description | Required For | Example |
|----------|-------------|--------------|---------|
| `MCP_AUTH_METHOD` | Authentication method | All | `NO-AUTH`, `API-KEY`, `OAUTH` |
| `MCP_API_KEYS` | API keys (comma-separated) | API-KEY | `key1,key2,key3` |
| `MCP_OAUTH_TENANT_ID` | Azure tenant ID | OAUTH | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `MCP_OAUTH_CLIENT_ID` | Azure client ID | OAUTH | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `MCP_OAUTH_REQUIRED_SCOPES` | Required OAuth scopes | OAUTH (optional) | `scope1,scope2` |

### Redis Environment Variables (Auto-configured)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `REDIS_HOST` | Redis hostname | - | `your-redis.redis.cache.windows.net` |
| `REDIS_PORT` | Redis port | `6379` | `10000` |
| `REDIS_SSL` | Enable SSL | `false` | `true` |
| `REDIS_ENTRAID_AUTH_METHOD` | Redis auth method | - | `managed_identity` |
| `REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID` | Managed identity client ID | - | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

## 🔍 Monitoring & Troubleshooting

### View Application Logs
```bash
# Get deployment outputs first
DEPLOYMENT_NAME=$(az deployment group list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'redis-mcp-deployment')].name" -o tsv | head -1)
CONTAINER_APP_NAME=$(az deployment group show --resource-group $RESOURCE_GROUP --name $DEPLOYMENT_NAME --query "properties.outputs.containerAppName.value" -o tsv)

# View logs
az containerapp logs show --name $CONTAINER_APP_NAME --resource-group $RESOURCE_GROUP --follow
```

### Check Authentication Status
The deployment script shows authentication configuration in the summary. Look for:
```
🔐 Authentication:
  Authentication: API KEY
  API Keys: 3 configured
  Test with: curl -H "X-API-Key: your-api-key" https://your-app.azurecontainerapps.io/health
```

### Common Issues

1. **Authentication Errors**:
   - Verify `MCP_AUTH_METHOD` is set correctly
   - Check API keys are properly configured
   - For OAuth, ensure tenant/client IDs are valid

2. **Redis Connection Issues**:
   - Verify managed identity has Redis access policies
   - Check Redis firewall settings
   - Ensure SSL settings match Redis configuration

3. **Container Issues**:
   - Review container logs for startup errors
   - Check resource limits (CPU/memory)
   - Verify image was built and pushed correctly

---

## 🔑 Using Service Principal for Redis Authentication

For production deployments where managed identity is not feasible, you can use service principal authentication to connect to Azure Managed Redis.

### Prerequisites

1. **Create a Service Principal with Certificate**:
```bash
# Create service principal with certificate authentication
SP_NAME="redis-mcp-sp"
CERT_NAME="redis-mcp-cert"

# Generate self-signed certificate
openssl req -x509 -newkey rsa:4096 -keyout ${CERT_NAME}-key.pem \
  -out ${CERT_NAME}-cert.pem -days 365 -nodes \
  -subj "/CN=${SP_NAME}"

# Combine private key and certificate into single PEM file (required by MCP server)
cat ${CERT_NAME}-key.pem ${CERT_NAME}-cert.pem > ${CERT_NAME}-combined.pem

# Create service principal with certificate
SP_OUTPUT=$(az ad sp create-for-rbac --name "$SP_NAME" \
  --cert @${CERT_NAME}-cert.pem \
  --create-cert \
  --output json)

CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.appId')
TENANT_ID=$(echo $SP_OUTPUT | jq -r '.tenant')

echo "Client ID: $CLIENT_ID"
echo "Tenant ID: $TENANT_ID"
echo "Certificate: ${CERT_NAME}-combined.pem"
```

2. **Assign Azure Managed Redis Permissions**:
```bash
# Set your Azure Managed Redis cluster name
REDIS_CLUSTER_NAME="your-redis-cluster-name"
DATABASE_NAME="default"

# Assign Azure Managed Redis Data Contributor access policy
# Note: Azure Managed Redis uses access policies, not traditional RBAC roles
az redisenterprise database access-policy-assignment create \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $REDIS_CLUSTER_NAME \
  --database-name $DATABASE_NAME \
  --access-policy-assignment-name "redis-mcp-policy" \
  --object-id $CLIENT_ID \
  --object-id-alias "$SP_NAME" \
  --access-policy-name "default"

# Verify the access policy assignment
az redisenterprise database access-policy-assignment show \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $REDIS_CLUSTER_NAME \
  --database-name $DATABASE_NAME \
  --access-policy-assignment-name "redis-mcp-policy"

# Or list all access policy assignments
az redisenterprise database access-policy-assignment list \
  --resource-group $RESOURCE_GROUP \
  --cluster-name $REDIS_CLUSTER_NAME \
  --database-name $DATABASE_NAME
```

### Configuration

#### Option 1: Mount Certificate as File in Container App

```bash
# Create a secret with the certificate content (base64 encoded)
CERT_CONTENT=$(cat ${CERT_NAME}-combined.pem | base64)

# Update container app with certificate mounted as volume
# Note: The secret name 'redis-mcp-cert' becomes the filename in the mounted volume
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_ENTRAID_AUTH_METHOD="service_principal" \
    REDIS_ENTRAID_TENANT_ID="$TENANT_ID" \
    REDIS_ENTRAID_CLIENT_ID="$CLIENT_ID" \
    REDIS_ENTRAID_CERT_PATH="/mnt/certs/redis-mcp-cert" \
  --secrets redis-mcp-cert="$CERT_CONTENT" \
  --secret-volume-mount "/mnt/certs"

# The certificate will be available at: /mnt/certs/redis-mcp-cert
# The filename matches the secret name (redis-mcp-cert)
```

#### Option 2: Use Azure Key Vault for Certificate Storage (Recommended)

```bash
# Store certificate in Azure Key Vault
az keyvault certificate import \
  --vault-name $KEY_VAULT_NAME \
  --name redis-mcp-cert \
  --file ${CERT_NAME}-combined.pem

# Grant Container App managed identity access to Key Vault
CONTAINER_APP_IDENTITY=$(az containerapp show \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

az keyvault set-policy \
  --name $KEY_VAULT_NAME \
  --object-id $CONTAINER_APP_IDENTITY \
  --certificate-permissions get list \
  --secret-permissions get list

# Update container app to reference Key Vault certificate
# Note: When using Key Vault references, the secret name becomes the filename
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars \
    REDIS_ENTRAID_AUTH_METHOD="service_principal" \
    REDIS_ENTRAID_TENANT_ID="$TENANT_ID" \
    REDIS_ENTRAID_CLIENT_ID="$CLIENT_ID" \
    REDIS_ENTRAID_CERT_PATH="/mnt/certs/redis-kv-cert" \
  --secrets "redis-kv-cert=keyvaultref:https://${KEY_VAULT_NAME}.vault.azure.net/certificates/redis-mcp-cert,identityref:system" \
  --secret-volume-mount "/mnt/certs"

# The certificate will be available at: /mnt/certs/redis-kv-cert
# The filename matches the secret name (redis-kv-cert) defined in the --secrets parameter
```

### Environment Variables for Service Principal

| Variable | Description | Example |
|----------|-------------|---------|
| `REDIS_ENTRAID_AUTH_METHOD` | Set to `service_principal` | `service_principal` |
| `REDIS_ENTRAID_TENANT_ID` | Azure tenant ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `REDIS_ENTRAID_CLIENT_ID` | Service principal client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `REDIS_ENTRAID_CERT_PATH` | Path to combined certificate file (private key + cert) | `/mnt/certs/redis-mcp-cert` |

**Important Notes**: 
- The certificate file must contain both the private key and certificate in PEM format, concatenated in a single file.
- When mounting secrets as volumes in Azure Container Apps, the **secret name** becomes the **filename** in the mounted path.
- For Option 1: Secret name `redis-mcp-cert` → File path `/mnt/certs/redis-mcp-cert` (no extension)
- For Option 2 (Key Vault): Secret name `redis-kv-cert` → File path `/mnt/certs/redis-kv-cert` (no extension)

### Security Considerations

- **Use Azure Key Vault**: Store certificates in Azure Key Vault and reference them via managed identity
- **Protect private keys**: Never commit certificate files to source control
- **Certificate expiration**: Monitor certificate expiration dates and set up renewal procedures
- **Rotate certificates regularly**: Implement a certificate rotation strategy (recommended: 90-365 days)
- **Principle of least privilege**: Only assign necessary Azure Managed Redis access policies
- **Monitor access**: Enable Azure Monitor for Redis to track authentication and access patterns
- **Use strong keys**: Use at least RSA 4096-bit keys for production certificates

## 🐳 Container Image Updates

For production deployments, it's crucial to use unique image tags and follow proper deployment practices.

### Building Images with Unique Tags

#### Using Git Commit SHA (Recommended)
```bash
# Get current git commit SHA
GIT_SHA=$(git rev-parse --short HEAD)
IMAGE_TAG="$GIT_SHA"

# Build and push image using Azure Container Registry
# This builds in Azure, no local Docker required
az acr build \
  --registry $CONTAINER_REGISTRY_NAME \
  --image redis-mcp:$IMAGE_TAG \
  --image redis-mcp:latest \
  --file Dockerfile \
  .

# The image is automatically pushed to ACR after build
echo "Image built and pushed: $CONTAINER_REGISTRY_NAME.azurecr.io/redis-mcp:$IMAGE_TAG"
```

#### Using Semantic Versioning
```bash
# For versioned releases
VERSION="1.2.3"
IMAGE_TAG="v$VERSION"

# Build and push with version tag
az acr build \
  --registry $CONTAINER_REGISTRY_NAME \
  --image redis-mcp:$IMAGE_TAG \
  --file Dockerfile \
  .
```

#### Using Timestamp for CI/CD
```bash
# For automated builds
GIT_SHA=$(git rev-parse --short HEAD)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
IMAGE_TAG="build-$TIMESTAMP-$GIT_SHA"

# Build and push with timestamp tag
az acr build \
  --registry $CONTAINER_REGISTRY_NAME \
  --image redis-mcp:$IMAGE_TAG \
  --file Dockerfile \
  .
```

### Updating Container Apps with New Images

#### Method 1: Update Container App Directly
```bash
# Update container app with new image
az containerapp update \
  --name $CONTAINER_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image $CONTAINER_REGISTRY_NAME.azurecr.io/redis-mcp:$IMAGE_TAG
```

#### Method 2: Update Bicep Template (Recommended)
```bash
# Update the image tag in parameters file
jq --arg tag "$IMAGE_TAG" '.parameters.containerImageTag.value = $tag' \
   infra/container-apps.parameters.json > tmp.json && \
   mv tmp.json infra/container-apps.parameters.json

# Redeploy with updated image
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/container-apps.bicep \
  --parameters @infra/container-apps.parameters.json
```