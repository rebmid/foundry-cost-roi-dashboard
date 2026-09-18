// Deploys the Log Analytics variant of the Foundry Cost & ROI workbook.
// Pass the Log Analytics workspace resource id that receives ApiManagementGatewayLlmLog + PRICING_CL.
param workspaceResourceId string
param location string = resourceGroup().location

resource wb 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'foundry-cost-roi-la-v1')
  location: location
  kind: 'shared'
  properties: {
    displayName: 'Foundry Cost & ROI'
    serializedData: replace(loadTextContent('FoundryCostRoi-LogAnalytics.workbook'), '{workspace-id}', workspaceResourceId)
    sourceId: workspaceResourceId
    category: 'workbook'
    version: '1.0'
  }
}

output workbookId string = wb.id
