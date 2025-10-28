@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Log retention in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags to apply to all resources')
param tags object = {}

// Create Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: retentionInDays
  }
}

// Outputs
@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace customer ID')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace primary shared key')
@secure()
output logAnalyticsWorkspaceSharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey
