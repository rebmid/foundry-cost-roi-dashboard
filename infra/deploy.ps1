# Deploy the full standalone FinOps-for-AI platform (APIM gateway, throttling, budget
# auto-disable, Foundry models, sample teams, tables, and the cost + ROI workbooks).
#
#   ./deploy.ps1 -Subscription <sub-id>
#
# Then populate prices/quotas and generate sample traffic:
#   python postdeploy.py --subscription <sub-id> --resource-group finops-standalone --deployment finops-standalone
param(
    [Parameter(Mandatory = $true)][string]$Subscription,
    [string]$ResourceGroup = 'finops-standalone',
    [string]$Location = 'swedencentral',
    [string]$DeploymentName = 'finops-standalone'
)
$ErrorActionPreference = 'Stop'

az account set --subscription $Subscription
az group create -n $ResourceGroup -l $Location --subscription $Subscription | Out-Null

az deployment group create `
    --name $DeploymentName `
    --resource-group $ResourceGroup `
    --subscription $Subscription `
    --template-file "$PSScriptRoot\main.bicep" `
    --parameters "$PSScriptRoot\params.json" `
    --query "properties.provisioningState" -o tsv

Write-Host ""
Write-Host "Deployed. Next, populate prices/quotas and generate sample traffic:"
Write-Host "  python `"$PSScriptRoot\postdeploy.py`" --subscription $Subscription --resource-group $ResourceGroup --deployment $DeploymentName"
