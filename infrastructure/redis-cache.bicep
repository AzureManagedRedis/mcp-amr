@description('The name of the Azure Managed Redis cluster')
param redisEnterpriseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('The SKU of the Azure Managed Redis cluster')
@allowed([
  'Balanced_B0'
  'Balanced_B1'
  'Balanced_B3'
  'Balanced_B5'
  'Balanced_B10'
  'Balanced_B20'
  'Balanced_B50'
])
param redisEnterpriseSku string = 'Balanced_B1'

@description('Enable RedisJSON module')
param enableRedisJson bool = false

@description('Enable RedisTimeSeries module')
param enableRedisTimeSeries bool = false

@description('Enable RedisBloom module')
param enableRedisBloom bool = false

@description('Managed identity object ID for Redis access policy assignment')
param managedIdentityObjectId string = ''

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Development'
  Project: 'Redis-MCP'
  Service: 'AzureManagedRedis'
}

@description('Enable Azure Monitor diagnostics')
param enableDiagnostics bool = true

@description('Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

// Azure Managed Redis Cluster
resource redisEnterpriseCluster 'Microsoft.Cache/redisEnterprise@2025-04-01' = {
  name: redisEnterpriseName
  location: location
  tags: tags
  sku: {
    name: redisEnterpriseSku
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

// Build modules array - RedisSearch is always enabled, others are optional
var modules = concat(
  [{ name: 'RediSearch' }],
  enableRedisJson ? [{ name: 'RedisJSON' }] : [],
  enableRedisTimeSeries ? [{ name: 'RedisTimeSeries' }] : [],
  enableRedisBloom ? [{ name: 'RedisBloom' }] : []
)

// Azure Managed Redis Database
resource redisEnterpriseDatabase 'Microsoft.Cache/redisEnterprise/databases@2025-04-01' = {
  parent: redisEnterpriseCluster
  name: 'default'
  properties: {
    port: 10000
    clusteringPolicy: 'EnterpriseCluster'
    evictionPolicy: 'NoEviction'
    modules: modules
  }
}

// Redis Database Access Policy Assignment for Managed Identity
resource redisAccessPolicyAssignment 'Microsoft.Cache/redisEnterprise/databases/accessPolicyAssignments@2025-04-01' = if (managedIdentityObjectId != '') {
  parent: redisEnterpriseDatabase
  name: 'mcpserveraccess'
  properties: {
    accessPolicyName: 'default'
    user: {
      objectId: managedIdentityObjectId
    }
  }
}

// Diagnostic Settings for Azure Managed Redis
resource redisEnterpriseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && logAnalyticsWorkspaceId != '') {
  name: '${redisEnterpriseName}-diagnostics'
  scope: redisEnterpriseCluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Output important information
@description('The hostname of the Azure Managed Redis cluster')
output redisHostName string = redisEnterpriseCluster.properties.hostName

@description('The Azure Managed Redis cluster resource ID')
output redisEnterpriseId string = redisEnterpriseCluster.id

@description('The Redis database resource ID')
output redisDatabaseId string = redisEnterpriseDatabase.id

@description('The Redis database port')
output databasePort int = redisEnterpriseDatabase.properties.port

@description('Enabled Redis modules')
output enabledModules array = modules

@description('Azure Managed Redis cluster status')
output clusterStatus string = redisEnterpriseCluster.properties.provisioningState
