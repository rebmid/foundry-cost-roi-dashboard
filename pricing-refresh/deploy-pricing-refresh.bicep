@description('Location for the Automation account.')
param location string = resourceGroup().location
param automationAccountName string = 'aa-finops-pricing'

@description('Public raw URL of Refresh-PricingCL.ps1.')
param runbookRawUrl string

@description('Existing pricing DCR name (role-assignment scope).')
param dcrName string
param dcrEndpoint string
param dcrImmutableId string
param streamName string = 'Custom-Json-PRICING_CL'
param region string = 'swedencentral'
param serviceName string = 'Foundry Models'
param meterMapJson string
param scheduleStart string = dateTimeAdd(utcNow(), 'PT1H')

resource aa 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    sku: { name: 'Basic' }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: aa
  name: 'Refresh-PricingCL'
  location: location
  properties: {
    runbookType: 'PowerShell72'
    logVerbose: false
    logProgress: false
    publishContentLink: {
      uri: runbookRawUrl
    }
  }
}

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: aa
  name: 'weekly-pricing-refresh'
  properties: {
    frequency: 'Week'
    interval: 1
    startTime: scheduleStart
    timeZone: 'UTC'
  }
}

resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: aa
  name: guid(aa.id, 'Refresh-PricingCL', 'weekly')
  properties: {
    runbook: {
      name: 'Refresh-PricingCL'
    }
    schedule: {
      name: 'weekly-pricing-refresh'
    }
    parameters: {
      DcrEndpoint: dcrEndpoint
      DcrImmutableId: dcrImmutableId
      StreamName: streamName
      Region: region
      ServiceName: serviceName
      MeterMapJson: meterMapJson
    }
  }
  dependsOn: [
    runbook
    schedule
  ]
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' existing = {
  name: dcrName
}

// Monitoring Metrics Publisher on the DCR for the Automation managed identity
resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dcr
  name: guid(dcr.id, aa.id, 'MonitoringMetricsPublisher')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalId: aa.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output automationAccount string = aa.name
output runbookName string = runbook.name
output principalId string = aa.identity.principalId
