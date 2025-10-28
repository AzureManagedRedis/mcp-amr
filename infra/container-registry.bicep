@description('The name of the Azure Container Registry')
param acrName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('The managed identity principal ID that needs ACR access')
param managedIdentityPrincipalId string

@description('Tags to apply to all resources')
param tags object = {}

// Create Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
  }
}

// Grant AcrPull role to managed identity
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentityPrincipalId, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry resource ID')
output containerRegistryId string = containerRegistry.id

@description('Instructions for building and pushing the container image')
output buildInstructions string = 'Run: az acr build --registry ${containerRegistry.name} --image redis-mcp-server:latest --platform linux/amd64 .'
