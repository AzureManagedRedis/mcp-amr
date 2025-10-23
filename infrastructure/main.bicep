@description('Base name for all resources')
param baseName string = 'redis-mcp'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
param environment string = 'dev'

@description('The SKU of the Azure Managed Redis cluster')
@allowed([
  'Balanced_B0'
  'Balanced_B1'
  'Balanced_B3'
  'Balanced_B5'
])
param redisEnterpriseSku string = 'Balanced_B1'

@description('Enable RedisJSON module')
param enableRedisJson bool = false

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

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'Redis-MCP'
  Service: 'AzureManagedRedis'
  CreatedBy: 'Bicep'
}

// Generate unique names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var redisName = '${baseName}-amr-${environment}-${uniqueSuffix}'
var acrName = replace('${baseName}acr${environment}${uniqueSuffix}', '-', '')
var identityName = '${baseName}-identity-${environment}'
var containerAppEnvName = '${baseName}-env-${environment}'
var containerAppName = '${baseName}-app-${environment}'
var logAnalyticsName = '${baseName}-logs-${environment}'

// 1. Create User-Assigned Managed Identity
module managedIdentityModule 'managed-identity.bicep' = {
  name: 'managed-identity-deployment'
  params: {
    identityName: identityName
    location: location
    tags: tags
  }
}

// 2. Create Log Analytics Workspace
module logAnalyticsModule 'log-analytics.bicep' = {
  name: 'log-analytics-deployment'
  params: {
    logAnalyticsWorkspaceName: logAnalyticsName
    location: location
    tags: tags
  }
}

// 3. Create Azure Managed Redis
module redisModule 'redis-cache.bicep' = {
  name: 'redis-deployment'
  params: {
    redisEnterpriseName: redisName
    location: location
    redisEnterpriseSku: redisEnterpriseSku
    enableRedisJson: enableRedisJson
    enableRedisTimeSeries: enableRedisTimeSeries
    enableRedisBloom: enableRedisBloom
    managedIdentityObjectId: managedIdentityModule.outputs.managedIdentityPrincipalId
    enableDiagnostics: true
    logAnalyticsWorkspaceId: logAnalyticsModule.outputs.logAnalyticsWorkspaceId
    tags: tags
  }
}

// 4. Create Azure Container Registry
module acrModule 'container-registry.bicep' = {
  name: 'acr-deployment'
  params: {
    acrName: acrName
    location: location
    managedIdentityPrincipalId: managedIdentityModule.outputs.managedIdentityPrincipalId
    tags: tags
  }
}

// 5. Create Container Apps and Environment
module containerAppsModule 'container-apps.bicep' = {
  name: 'container-apps-deployment'
  params: {
    containerAppName: containerAppName
    containerAppEnvName: containerAppEnvName
    location: location
    managedIdentityId: managedIdentityModule.outputs.managedIdentityId
    managedIdentityClientId: managedIdentityModule.outputs.managedIdentityClientId
    logAnalyticsWorkspaceCustomerId: logAnalyticsModule.outputs.logAnalyticsWorkspaceCustomerId
    logAnalyticsWorkspaceSharedKey: logAnalyticsModule.outputs.logAnalyticsWorkspaceSharedKey
    containerRegistryLoginServer: acrModule.outputs.containerRegistryLoginServer
    usePlaceholderImage: true  // Use placeholder during initial deployment
    redisHostName: redisModule.outputs.redisHostName
    redisPort: redisModule.outputs.databasePort
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

// Redis Access Policy Assignment (requires Azure CLI or REST API call after deployment)
// This will be handled in the deployment script

// Outputs
@description('The managed identity resource ID')
output managedIdentityId string = managedIdentityModule.outputs.managedIdentityId

@description('The managed identity client ID')
output managedIdentityClientId string = managedIdentityModule.outputs.managedIdentityClientId

@description('The managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentityModule.outputs.managedIdentityPrincipalId

@description('The Redis hostname')
output redisHostName string = redisModule.outputs.redisHostName

@description('The Redis cluster resource ID')
output redisClusterId string = redisModule.outputs.redisEnterpriseId

@description('The Redis database port')
output redisDatabasePort int = redisModule.outputs.databasePort

@description('Container Registry login server')
output containerRegistryLoginServer string = acrModule.outputs.containerRegistryLoginServer

@description('Container Registry name')
output containerRegistryName string = acrModule.outputs.containerRegistryName

@description('Container App name')
output containerAppName string = containerAppsModule.outputs.containerAppName

@description('Container App FQDN')
output containerAppFqdn string = containerAppsModule.outputs.containerAppFqdn

@description('Instructions for building and pushing the container image')
output buildInstructions string = acrModule.outputs.buildInstructions
