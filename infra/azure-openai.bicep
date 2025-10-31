@description('Name of the Azure OpenAI service')
param openAIServiceName string

@description('Location for the Azure OpenAI service')
param location string = resourceGroup().location

@description('Azure OpenAI service SKU')
@allowed([
  'S0'
])
param openAISku string = 'S0'

@description('Managed identity principal ID that needs access to Azure OpenAI')
param managedIdentityPrincipalId string

@description('Tags to apply to all resources')
param tags object = {}

// Create Azure OpenAI service
resource openAIService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAIServiceName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAISku
  }
  properties: {
    customSubDomainName: openAIServiceName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true  // Disable API key authentication, force Azure AD
  }
}

// Create text-embedding-ada-002 deployment
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAIService
  name: 'text-embedding-ada-002'
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
  }
}

// Assign "Cognitive Services OpenAI User" role to the managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAIService.id, managedIdentityPrincipalId, 'Cognitive Services OpenAI User')
  scope: openAIService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Azure OpenAI service name')
output openAIServiceName string = openAIService.name

@description('Azure OpenAI service resource ID')
output openAIServiceId string = openAIService.id

@description('Azure OpenAI service endpoint')
output openAIEndpoint string = openAIService.properties.endpoint

@description('Azure OpenAI deployment name for embeddings')
output embeddingDeploymentName string = embeddingDeployment.name
