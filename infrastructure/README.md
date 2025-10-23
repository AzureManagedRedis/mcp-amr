# Redis Infrastructure with Bicep

This directory contains Bicep templates for deploying Azure Managed Redis cache for the MCP Redis server.

## 📁 Files

- `redis-cache.bicep` - Main Bicep template for Redis cache
- `redis-cache.parameters.json` - Parameters file with default values
- `deploy-redis.sh` - Automated deployment script
- `README.md` - This documentation

## 🚀 Quick Deployment

### Prerequisites

1. **Azure CLI** installed and logged in:
   ```bash
   az login
   az account set --subscription "your-subscription-id"
   ```

2. **Bicep CLI** (usually installed with Azure CLI):
   ```bash
   az bicep version
   ```

### One-Command Deployment

```bash
# Make the script executable and run it
chmod +x deploy-redis.sh
./deploy-redis.sh
```

This will:
- ✅ Create resource group if it doesn't exist
- ✅ Validate the Bicep template
- ✅ Deploy Redis cache with Log Analytics
- ✅ Output connection details
- ✅ Save deployment information to a file

### Manual Deployment

If you prefer manual deployment:

```bash
# Create resource group
az group create --name rg-redis-mcp --location eastus

# Deploy Redis cache
az deployment group create \
  --resource-group rg-redis-mcp \
  --template-file redis-cache.bicep \
  --parameters @redis-cache.parameters.json
```

## ⚙️ Configuration

### Parameters

Edit `redis-cache.parameters.json` to customize your deployment:

| Parameter | Description | Default | Options |
|-----------|-------------|---------|---------|
| `redisCacheName` | Name of Redis cache | `redis-mcp-cache` | Must be globally unique |
| `location` | Azure region | `East US` | Any Azure region |
| `redisCacheSize` | Cache size | `C0` | C0, C1, C2, C3, C4, C5, C6 |
| `redisCacheSKU` | Pricing tier | `Basic` | Basic, Standard, Premium |
| `enableNonSslPort` | Allow non-SSL | `false` | true/false |
| `enableDiagnostics` | Enable monitoring | `true` | true/false |

### Redis Cache Sizes

| Size | Memory | Price Tier |
|------|--------|------------|
| C0 | 250 MB | Basic/Standard |
| C1 | 1 GB | Basic/Standard |
| C2 | 2.5 GB | Basic/Standard |
| C3 | 6 GB | Basic/Standard |
| C4 | 13 GB | Basic/Standard |
| C5 | 26 GB | Basic/Standard |
| C6 | 53 GB | Basic/Standard |

## 📊 Outputs

After deployment, you'll get:

```bash
# Connection details
REDIS_HOST=your-cache.redis.cache.windows.net
REDIS_PORT=6380
REDIS_SSL=true

# Access keys (managed securely by Azure)
PRIMARY_KEY=<automatically-generated>
SECONDARY_KEY=<automatically-generated>
```

## 🔗 Integration with MCP Server

Use the deployment outputs to configure your MCP server:

### Environment Variables

```bash
# From deployment outputs
REDIS_HOST=your-redis-hostname
REDIS_PORT=6380
REDIS_SSL=true
REDIS_PWD=your-primary-key
```

### Container App Configuration

```bash
az containerapp update \
  --name redis-mcp-server \
  --resource-group rg-redis-mcp \
  --set-env-vars \
    REDIS_HOST=$REDIS_HOST \
    REDIS_PORT=6380 \
    REDIS_SSL=true \
    REDIS_PWD=$PRIMARY_KEY
```

## 🔒 Security Features

The template includes:

- ✅ **TLS 1.2 minimum** - Enforced encryption
- ✅ **SSL-only ports** - Non-SSL port disabled by default  
- ✅ **Access key rotation** - Managed by Azure
- ✅ **Diagnostics logging** - Connected to Log Analytics
- ✅ **Network security** - Can be extended with VNet integration

## 📈 Monitoring

The template automatically sets up:

- **Log Analytics workspace** for centralized logging
- **Diagnostic settings** for Redis metrics and logs
- **Connected client monitoring**
- **Performance metrics** collection

Access monitoring through:
- Azure Portal → Redis Cache → Monitoring
- Log Analytics queries
- Azure Monitor dashboards

## 🛠️ Troubleshooting

### Common Issues

1. **Name already exists**
   ```
   Error: Redis cache name must be globally unique
   ```
   **Solution**: Change `redisCacheName` in parameters file

2. **Insufficient permissions**
   ```
   Error: Authorization failed
   ```
   **Solution**: Ensure you have Contributor role on subscription/resource group

3. **Region not available**
   ```
   Error: Redis cache not available in region
   ```
   **Solution**: Change `location` parameter to supported region

### Useful Commands

```bash
# Check deployment status
az deployment group show --resource-group rg-redis-mcp --name <deployment-name>

# Get Redis connection details
az redis show --name redis-mcp-cache --resource-group rg-redis-mcp

# List access keys
az redis list-keys --name redis-mcp-cache --resource-group rg-redis-mcp

# Test Redis connection
redis-cli -h <hostname> -p 6380 -a <access-key> --tls ping
```

## 🔄 Updates and Maintenance

### Scaling Up

Update the parameters file and redeploy:

```json
{
  "redisCacheSize": {
    "value": "C1"  // Changed from C0 to C1
  }
}
```

### Key Rotation

```bash
# Regenerate primary key
az redis regenerate-key --name redis-mcp-cache --resource-group rg-redis-mcp --key-type Primary

# Update application configuration with new key
```

## 🧹 Cleanup

To remove all resources:

```bash
# Delete entire resource group (careful!)
az group delete --name rg-redis-mcp --yes --no-wait

# Or delete just the Redis cache
az redis delete --name redis-mcp-cache --resource-group rg-redis-mcp
```

## 📚 Additional Resources

- [Azure Cache for Redis Documentation](https://docs.microsoft.com/en-us/azure/azure-cache-for-redis/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Redis MCP Server Configuration](../docs/AZURE_DEPLOYMENT.md)