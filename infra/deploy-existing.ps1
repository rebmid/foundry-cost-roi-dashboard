# Deploy option B: create the dashboards on an EXISTING APIM + Log Analytics workspace.
# Creates only the workspace-side pieces (PRICING_CL + SUBSCRIPTION_QUOTA_CL tables + DCRs + the
# Cost and ROI workbooks). Does NOT create an APIM. Run this in the resource group that contains
# your Log Analytics workspace.
#
#   ./deploy-existing.ps1 -Subscription <sub-id> -ResourceGroup <workspace-rg> -WorkspaceName <workspace-name>
#
# Your APIM must already log ApiManagementGatewayLlmLog to that workspace: see the README
# "Requirements: what must exist and be turned on" section.
param(
    [Parameter(Mandatory = $true)][string]$Subscription,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$WorkspaceName,
    [switch]$DeployStockWorkbooks,
    [string]$DeploymentName = 'finops-dashboards'
)
$ErrorActionPreference = 'Stop'

az account set --subscription $Subscription

az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroup `
    --subscription $Subscription `
    --template-file "$PSScriptRoot\existing-apim.bicep" `
    --parameters logAnalyticsWorkspaceName=$WorkspaceName deployStockWorkbooks=$($DeployStockWorkbooks.IsPresent) `
    --query "properties.provisioningState" -o tsv

Write-Host ""
Write-Host "Dashboards deployed. Two data steps remain (see README Requirements):"
Write-Host "  1. Populate PRICING_CL (rate card) - deploy pricing-refresh/ against the new dcr-pricing-* DCR, or seed it once."
Write-Host "  2. Populate SUBSCRIPTION_QUOTA_CL with one row per team (APIM subscription) for the budget tile."
Write-Host "  3. Confirm your APIM logs ApiManagementGatewayLlmLog + ApiManagementGatewayLogs to $WorkspaceName."
