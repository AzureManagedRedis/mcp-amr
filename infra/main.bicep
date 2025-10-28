targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('The SKU of the Azure Managed Redis cluster')
@allowed([
  'Balanced_B0'
  'Balanced_B1'
  'Balanced_B3'
  'Balanced_B5'
])
param redisEnterpriseSku string = 'Balanced_B1'

@description('Enable RediSearch module')
param enableRediSearch bool = true

@description('Enable RedisJSON module')
param enableRedisJson bool = true

@description('Enable RedisTimeSeries module')
param enableRedisTimeSeries bool = false

@description('Enable RedisBloom module')
param enableRedisBloom bool = false

@description('Container app minimum replicas')
@minValue(0)
@maxValue(25)
param minReplicas int = 1

@description('Container app maximum replicas')
@minValue(1)
@maxValue(25)
param maxReplicas int = 5

@description('CPU allocation for container app')
param cpu string = '0.25'

@description('Memory allocation for container app')
param memory string = '0.5Gi'

@description('Log level for MCP server')
@allowed([
  'DEBUG'
  'INFO'
  'WARNING'
  'ERROR'
])
param logLevel string = 'INFO'

@description('MCP Authentication Method')
@allowed([
  'NO-AUTH'
  'API-KEY'
  'OAUTH'
])
param mcpAuthMethod string = 'NO-AUTH'

@description('MCP API keys (comma-separated list) - Required when mcpAuthMethod is API-KEY')
@secure()
param mcpApiKeys string = ''

@description('OAuth Tenant ID - Required when mcpAuthMethod is OAUTH')
param oauthTenantId string = ''

@description('OAuth Client ID - Required when mcpAuthMethod is OAUTH')
param oauthClientId string = ''

@description('OAuth Required Scopes (comma-separated) - Optional for OAUTH method')
param oauthRequiredScopes string = ''

// Tags that should be applied to all resources
var tags = {
  'azd-env-name': environmentName
  Environment: environmentName
  Project: 'Redis-MCP'
  Service: 'AzureManagedRedis'
  CreatedBy: 'azd'
}

// Generate resource group name
var resourceGroupName = 'rg-mcp-${environmentName}'

// Create resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy the main infrastructure
module resources 'resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    baseName: 'redis-mcp'
    location: location
    environment: environmentName
    redisEnterpriseSku: redisEnterpriseSku
    enableRediSearch: enableRediSearch
    enableRedisJson: enableRedisJson
    enableRedisTimeSeries: enableRedisTimeSeries
    enableRedisBloom: enableRedisBloom
    minReplicas: minReplicas
    maxReplicas: maxReplicas
    cpu: cpu
    memory: memory
    logLevel: logLevel
    mcpAuthMethod: mcpAuthMethod
    mcpApiKeys: mcpApiKeys
    oauthTenantId: oauthTenantId
    oauthClientId: oauthClientId
    oauthRequiredScopes: oauthRequiredScopes
    tags: tags
  }
}

// Outputs for azd
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = resourceGroupName
output AZURE_CONTAINER_REGISTRY_NAME string = resources.outputs.containerRegistryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.containerRegistryLoginServer
output AZURE_CONTAINER_APP_NAME string = resources.outputs.containerAppName
output AZURE_CONTAINER_APP_FQDN string = resources.outputs.containerAppFqdn
output REDIS_HOST_NAME string = resources.outputs.redisHostName
output REDIS_PORT int = resources.outputs.redisDatabasePort
output MCP_SERVER_URL string = 'https://${resources.outputs.containerAppFqdn}/message'
