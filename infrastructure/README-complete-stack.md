# Complete Redis MCP Server Stack - Bicep Infrastructure

This directory contains the complete Infrastructure as Code (IaC) solution for deploying the Redis MCP Server stack to Azure using Bicep templates.

## 🏗️ Architecture Overview

The complete stack includes:

1. **User-Assigned Managed Identity** - For secure authentication between services
2. **Azure Managed Redis** - Azure Managed Redis with RedisSearch and RedisJSON modules
3. **Azure Container Registry** - For storing the MCP server container image
4. **Container Apps Environment** - Serverless container hosting platform
5. **Container App** - The MCP server application
6. **Log Analytics Workspace** - Centralized logging and monitoring

## 📁 Files Structure

```
infrastructure/
├── main.bicep                     # Main orchestration template
├── main.parameters.json          # Parameters for main template
├── redis-cache.bicep             # Azure Managed Redis module
├── redis-cache.parameters.json   # Redis-specific parameters
├── deploy-complete-stack.sh       # Complete deployment script
├── deploy-redis.sh               # Redis-only deployment script
└── README.md                     # This file
```

## 🚀 Quick Deployment

### Prerequisites

1. **Azure CLI** installed and logged in:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Docker** installed (for container builds)

3. **Bicep CLI** (installed with Azure CLI):
   ```bash
   az bicep version
   ```

### One-Command Complete Deployment

```bash
# Deploy the entire stack
./deploy-complete-stack.sh
```

This single command will:
- ✅ Create all Azure resources (Redis, ACR, Container Apps, etc.)
- ✅ Build and push the MCP server container image
- ✅ Configure authentication and access policies
- ✅ Deploy and start the container application
- ✅ Test the deployment

## ⚙️ Configuration

### Main Parameters (`main.parameters.json`)

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `baseName` | Base name for all resources | `redis-mcp` | Any valid name |
| `location` | Azure region | `East US` | Any Azure region |
| `environment` | Environment name | `dev` | dev, test, prod |
| `redisEnterpriseSku` | Redis SKU | `Balanced_B1` | B0, B1, B3, B5 |
| `enableRedisSearch` | Enable RedisSearch | `true` | true/false |
| `enableRedisJson` | Enable RedisJSON | `true` | true/false |
| `publicNetworkAccess` | Redis public access | `Enabled` | Enabled/Disabled |
| `minReplicas` | Min container replicas | `1` | 0-25 |
| `maxReplicas` | Max container replicas | `5` | 1-25 |
| `cpu` | Container CPU | `0.25` | 0.25, 0.5, 0.75, 1.0, etc. |
| `memory` | Container memory | `0.5Gi` | 0.5Gi, 1Gi, 1.5Gi, etc. |
| `logLevel` | MCP server log level | `INFO` | DEBUG, INFO, WARNING, ERROR |

### Resource Naming Convention

Resources are automatically named with this pattern:
- **Redis**: `{baseName}-redis-{environment}-{uniqueSuffix}`
- **ACR**: `{baseName}acr{environment}{uniqueSuffix}`
- **Identity**: `{baseName}-identity-{environment}`
- **Container App**: `{baseName}-app-{environment}`
- **Environment**: `{baseName}-env-{environment}`

## 🏢 Component Details

### 1. User-Assigned Managed Identity

```bicep
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31'
```

**Purpose**: 
- Provides secure authentication for Container App to access Redis
- Eliminates need for password management
- Enables Azure RBAC for Redis access

### 2. Azure Managed Redis

```bicep
module redisModule 'redis-cache.bicep'
```

**Features**:
- Azure Managed Redis with RedisSearch and RedisJSON modules
- NoEviction policy (required for RedisSearch)
- TLS 1.2 encryption
- Integrated with Log Analytics for monitoring

### 3. Azure Container Registry

```bicep
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01'
```

**Features**:
- Basic SKU (cost-effective for development)
- Admin user enabled for initial setup
- Managed identity has AcrPull permissions

### 4. Container Apps Environment

```bicep
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01'
```

**Features**:
- Serverless container hosting
- Integrated with Log Analytics
- Auto-scaling capabilities

### 5. Container App

```bicep
resource containerApp 'Microsoft.App/containerApps@2023-05-01'
```

**Features**:
- Uses managed identity for Redis authentication
- Auto-scaling based on HTTP requests
- Health probes and monitoring
- Environment variables pre-configured

## 🔒 Security Features

### Authentication Flow

1. **Container App** uses **User-Assigned Managed Identity**
2. **Managed Identity** has **Data Contributor** role on Redis
3. **No passwords or keys** in application configuration
4. **Automatic token rotation** by Azure

### Network Security

- **TLS encryption** for all Redis connections
- **HTTPS-only** for Container App ingress
- **Private networking** available (set `publicNetworkAccess: 'Disabled'`)

### Access Control

- **Azure RBAC** for Redis access policies
- **Container Registry** access via managed identity
- **Least privilege** principle applied

## 📊 Monitoring and Logging

### Log Analytics Integration

All services send logs to a centralized Log Analytics workspace:
- **Redis diagnostics** and metrics
- **Container App** application logs
- **Container Apps Environment** platform logs

### Useful Log Queries

```kql
// Container App logs
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "redis-mcp-app-dev"
| order by TimeGenerated desc

// Redis connection logs
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.CACHE"
| where Category == "ConnectedClientList"
```

## 🎯 Deployment Scenarios

### Development Environment

```bash
# Quick dev deployment with minimal resources
az deployment group create \
  --resource-group rg-redis-mcp-dev \
  --template-file main.bicep \
  --parameters environment=dev redisEnterpriseSku=Balanced_B0 minReplicas=1
```

### Production Environment

```bash
# Production deployment with high availability
az deployment group create \
  --resource-group rg-redis-mcp-prod \
  --template-file main.bicep \
  --parameters environment=prod redisEnterpriseSku=Balanced_B3 minReplicas=2 maxReplicas=10
```

## 🔄 CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Deploy Redis MCP Stack
on:
  push:
    branches: [main]
    
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Infrastructure
      run: |
        cd infrastructure
        az deployment group create \
          --resource-group rg-redis-mcp-prod \
          --template-file main.bicep \
          --parameters @main.parameters.json \
          --parameters environment=prod imageTag=${{ github.sha }}
    
    - name: Build and Push Image
      run: |
        REGISTRY=$(az deployment group show --resource-group rg-redis-mcp-prod --name main --query 'properties.outputs.containerRegistryName.value' -o tsv)
        az acr build --registry $REGISTRY --image redis-mcp-server:${{ github.sha }} .
```

## 🛠️ Troubleshooting

### Common Issues

1. **Redis Authentication Failed**
   ```bash
   # Check managed identity assignment
   az redis access-policy-assignment list --resource-group rg-redis-mcp --redis-cache-name redis-mcp-redis-dev-abc123
   ```

2. **Container App Won't Start**
   ```bash
   # Check container logs
   az containerapp logs show --name redis-mcp-app-dev --resource-group rg-redis-mcp --follow
   ```

3. **Image Build Failed**
   ```bash
   # Build locally and push
   docker build -t redis-mcp-server .
   az acr login --name redismcpacrdevabc123
   docker tag redis-mcp-server redismcpacrdevabc123.azurecr.io/redis-mcp-server:latest
   docker push redismcpacrdevabc123.azurecr.io/redis-mcp-server:latest
   ```

### Deployment Validation

```bash
# Check all resources
az resource list --resource-group rg-redis-mcp --output table

# Test Redis connectivity
az redis ping --name redis-mcp-redis-dev-abc123 --resource-group rg-redis-mcp

# Check container app status
az containerapp show --name redis-mcp-app-dev --resource-group rg-redis-mcp --query properties.provisioningState
```

## 🧹 Cleanup

### Delete Entire Stack

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-redis-mcp --yes --no-wait
```

### Selective Cleanup

```bash
# Delete only the container app
az containerapp delete --name redis-mcp-app-dev --resource-group rg-redis-mcp

# Delete only Redis
az redis delete --name redis-mcp-redis-dev-abc123 --resource-group rg-redis-mcp
```

## 📈 Scaling and Performance

### Manual Scaling

```bash
# Scale container app
az containerapp update \
  --name redis-mcp-app-dev \
  --resource-group rg-redis-mcp \
  --min-replicas 2 \
  --max-replicas 20

# Scale Redis (requires downtime)
az deployment group create \
  --resource-group rg-redis-mcp \
  --template-file main.bicep \
  --parameters @main.parameters.json redisEnterpriseSku=Balanced_B5
```

### Auto-scaling Configuration

The template includes HTTP-based auto-scaling:
- **Scale out**: When concurrent requests > 30
- **Scale in**: When requests drop below threshold
- **Min replicas**: Configurable (default: 1)
- **Max replicas**: Configurable (default: 5)

## 💰 Cost Optimization

### Development

- Use `Balanced_B0` Redis SKU
- Set `minReplicas: 0` (scale to zero when idle)
- Use `Basic` Container Registry SKU

### Production

- Choose appropriate Redis SKU based on usage
- Monitor and adjust replica counts
- Consider `Premium` Container Registry for geo-replication

## 📚 Additional Resources

- [Azure Managed Redis Documentation](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Redis MCP Server Documentation](../README.md)

## 🤝 Contributing

When modifying the templates:

1. **Validate templates** before committing:
   ```bash
   az deployment group validate --template-file main.bicep --parameters @main.parameters.json --resource-group test-rg
   ```

2. **Test deployments** in a development environment

3. **Update documentation** for any new parameters or features

4. **Follow naming conventions** and tagging standards