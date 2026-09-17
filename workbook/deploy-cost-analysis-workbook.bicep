param workspaceResourceId string
param location string = resourceGroup().location

resource wb 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'foundry-cost-analysis-improved-v1')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Cost Analysis - Improved'
    serializedData: replace(loadTextContent('FoundryCostAnalysis-LogAnalytics.workbook'), '{workspace-id}', workspaceResourceId)
    sourceId: workspaceResourceId
    category: 'workbook'
    version: '1.0'
  }
}

output workbookId string = wb.id
