@description('The name of the Container App')
param containerAppName string

@description('The name of the Container Apps Environment')
param containerAppEnvName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('The managed identity resource ID')
param managedIdentityId string

@description('The managed identity client ID')
param managedIdentityClientId string

@description('Log Analytics workspace customer ID')
param logAnalyticsWorkspaceCustomerId string

@description('Log Analytics workspace shared key')
@secure()
param logAnalyticsWorkspaceSharedKey string

@description('Container Registry login server')
param containerRegistryLoginServer string

@description('Container image tag to deploy')
param imageTag string = 'latest'

@description('Use placeholder image for initial deployment')
param usePlaceholderImage bool = false

@description('Placeholder image to use when container image is not ready')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Redis hostname')
param redisHostName string

@description('Redis port')
param redisPort int

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

@description('Enable MCP API key authentication')
param mcpApiKeyAuthEnabled bool = true

@description('MCP API keys (comma-separated list)')
@secure()
param mcpApiKeys string

@description('Tags to apply to all resources')
param tags object = {}

// Create Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceCustomerId
        sharedKey: logAnalyticsWorkspaceSharedKey
      }
    }
  }
}

// Create Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8000
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistryLoginServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          image: usePlaceholderImage ? placeholderImage : '${containerRegistryLoginServer}/redis-mcp-server:${imageTag}'
          name: 'redis-mcp-server'
          env: [
            {
              name: 'REDIS_HOST'
              value: redisHostName
            }
            {
              name: 'REDIS_PORT'
              value: string(redisPort)
            }
            {
              name: 'REDIS_SSL'
              value: 'true'
            }
            {
              name: 'REDIS_ENTRAID_AUTH_METHOD'
              value: 'managed_identity'
            }
            {
              name: 'REDIS_ENTRAID_MANAGED_IDENTITY_CLIENT_ID'
              value: managedIdentityClientId
            }
            {
              name: 'MCP_REDIS_LOG_LEVEL'
              value: logLevel
            }
            {
              name: 'MCP_API_KEY_AUTH_ENABLED'
              value: string(mcpApiKeyAuthEnabled)
            }
            {
              name: 'MCP_API_KEYS'
              value: mcpApiKeys
            }
          ]
          resources: {
            cpu: json(cpu)
            memory: memory
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
        ]
      }
    }
  }
}

// Outputs
@description('Container App name')
output containerAppName string = containerApp.name

@description('Container App resource ID')
output containerAppId string = containerApp.id

@description('Container App FQDN')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container Apps Environment name')
output containerAppEnvironmentName string = containerAppEnvironment.name

@description('Container Apps Environment resource ID')
output containerAppEnvironmentId string = containerAppEnvironment.id
