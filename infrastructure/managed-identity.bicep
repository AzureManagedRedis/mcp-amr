@description('The name of the managed identity')
param identityName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Tags to apply to all resources')
param tags object = {}

// Create User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// Outputs
@description('The managed identity resource ID')
output managedIdentityId string = managedIdentity.id

@description('The managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('The managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The managed identity name')
output managedIdentityName string = managedIdentity.name
