// Deploy option B: bring your own APIM + Log Analytics workspace.
//
// Creates only the workspace-side pieces the dashboards read (PRICING_CL + SUBSCRIPTION_QUOTA_CL
// tables and their data collection rules, plus the Cost and ROI workbooks). It does NOT create an
// APIM or a Foundry resource. Deploy this into the SAME resource group as your Log Analytics
// workspace.
//
// Your existing APIM must already log to this workspace (APIM resource diagnostic with AllLogs, and
// per-API LLM logging). See the README "Requirements: what must exist and be turned on" section.

@description('Name of your existing Log Analytics workspace. Deploy this template into that workspace\'s resource group.')
param logAnalyticsWorkspaceName string

@description('Also deploy the Alerts workbook.')
param deployStockWorkbooks bool = false

param location string = resourceGroup().location

var resourceSuffix = uniqueString(subscription().id, resourceGroup().id)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ---- Rate card table + ingestion ----
resource pricingTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: logAnalytics
  name: 'PRICING_CL'
  properties: {
    totalRetentionInDays: 4383
    plan: 'Analytics'
    schema: {
      name: 'PRICING_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'Model', type: 'string' }
        { name: 'InputTokensPrice', type: 'real' }
        { name: 'OutputTokensPrice', type: 'real' }
      ]
    }
    retentionInDays: 730
  }
}

resource pricingDCR 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-pricing-${resourceSuffix}'
  location: location
  kind: 'Direct'
  properties: {
    streamDeclarations: {
      'Custom-Json-${pricingTable.name}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'Model', type: 'string' }
          { name: 'InputTokensPrice', type: 'real' }
          { name: 'OutputTokensPrice', type: 'real' }
        ]
      }
    }
    destinations: {
      logAnalytics: [ { workspaceResourceId: logAnalytics.id, name: logAnalytics.name } ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-Json-${pricingTable.name}' ]
        destinations: [ logAnalytics.name ]
        transformKql: 'source'
        outputStream: 'Custom-${pricingTable.name}'
      }
    ]
  }
}

var monitoringMetricsPublisherRoleDefinitionID = resourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
resource pricingDCRRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: pricingDCR
  name: guid(subscription().id, resourceGroup().id, pricingDCR.name, monitoringMetricsPublisherRoleDefinitionID)
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleDefinitionID
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// ---- Per-team budget table + ingestion ----
resource subscriptionQuotaTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  parent: logAnalytics
  name: 'SUBSCRIPTION_QUOTA_CL'
  properties: {
    totalRetentionInDays: 4383
    plan: 'Analytics'
    schema: {
      name: 'SUBSCRIPTION_QUOTA_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'Subscription', type: 'string' }
        { name: 'CostQuota', type: 'real' }
      ]
    }
    retentionInDays: 730
  }
}

resource subscriptionQuotaDCR 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-quota-${resourceSuffix}'
  location: location
  kind: 'Direct'
  properties: {
    streamDeclarations: {
      'Custom-Json-${subscriptionQuotaTable.name}': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'Subscription', type: 'string' }
          { name: 'CostQuota', type: 'real' }
        ]
      }
    }
    destinations: {
      logAnalytics: [ { workspaceResourceId: logAnalytics.id, name: logAnalytics.name } ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-Json-${subscriptionQuotaTable.name}' ]
        destinations: [ logAnalytics.name ]
        transformKql: 'source'
        outputStream: 'Custom-${subscriptionQuotaTable.name}'
      }
    ]
  }
}

resource subscriptionQuotaDCRRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: subscriptionQuotaDCR
  name: guid(subscription().id, resourceGroup().id, subscriptionQuotaDCR.name, monitoringMetricsPublisherRoleDefinitionID)
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleDefinitionID
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// ---- Workbooks ----
resource costWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, resourceSuffix, 'costAnalysis')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Cost Analysis'
    serializedData: replace(loadTextContent('../workbook/FoundryCostAnalysis-LogAnalytics.workbook'), '{workspace-id}', logAnalytics.id)
    sourceId: logAnalytics.id
    category: 'workbook'
  }
}

resource roiWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, resourceSuffix, 'costRoi')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Foundry Cost & ROI'
    serializedData: replace(loadTextContent('../workbook/FoundryCostRoi-LogAnalytics.workbook'), '{workspace-id}', logAnalytics.id)
    sourceId: logAnalytics.id
    category: 'workbook'
  }
}

resource alertsWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = if (deployStockWorkbooks) {
  name: guid(resourceGroup().id, resourceSuffix, 'alertsWorkbook')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Alerts Workbook'
    serializedData: loadTextContent('workbooks/alerts.json')
    sourceId: logAnalytics.id
    category: 'workbook'
  }
}

output pricingDCREndpoint string = pricingDCR.properties.endpoints.logsIngestion
output pricingDCRImmutableId string = pricingDCR.properties.immutableId
output pricingDCRStream string = pricingDCR.properties.dataFlows[0].streams[0]
output subscriptionQuotaDCREndpoint string = subscriptionQuotaDCR.properties.endpoints.logsIngestion
output subscriptionQuotaDCRImmutableId string = subscriptionQuotaDCR.properties.immutableId
output subscriptionQuotaDCRStream string = subscriptionQuotaDCR.properties.dataFlows[0].streams[0]
output logAnalyticsWorkspaceCustomerId string = logAnalytics.properties.customerId
