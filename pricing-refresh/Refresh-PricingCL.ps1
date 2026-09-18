<#
    Refresh-PricingCL.ps1  (Azure Automation runbook, PowerShell 7.2)

    Pulls current Azure list prices from the public Retail Prices API and writes them to the
    PRICING_CL custom table via the deployed data collection rule (DCR). Run on a schedule so
    the finops-framework rate card stays current with zero manual editing.

    Auth: the Automation account's system-assigned managed identity, granted
    "Monitoring Metrics Publisher" on the DCR.
#>
param(
    [Parameter(Mandatory)][string] $DcrEndpoint,      # e.g. https://dcr-pricing-xxxx.<region>.ingest.monitor.azure.com
    [Parameter(Mandatory)][string] $DcrImmutableId,   # e.g. dcr-xxxxxxxxxxxx
    [string] $StreamName  = 'Custom-Json-PRICING_CL',
    [string] $Region      = 'swedencentral',
    [string] $ServiceName = 'Foundry Models',
    [Parameter(Mandatory)][string] $MeterMapJson      # {"gpt-4.1":["gpt 4.1 Inp glbl","gpt 4.1 Outp glbl"], ...}
)
$ErrorActionPreference = 'Stop'

# 1) managed-identity token for the Monitor ingestion endpoint (handle SecureString on newer Az.Accounts)
Connect-AzAccount -Identity | Out-Null
$raw = Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com'
$token = if ($raw.Token -is [System.Security.SecureString]) {
    [System.Net.NetworkCredential]::new('', $raw.Token).Password
} else { $raw.Token }

# 2) pull current retail prices (follow pagination)
$filter = "serviceName eq '$ServiceName' and armRegionName eq '$Region' and unitOfMeasure eq '1K'"
$url = "https://prices.azure.com/api/retail/prices?currencyCode='USD'&`$filter=$([uri]::EscapeDataString($filter))"
$price = @{}
do {
    $r = Invoke-RestMethod -Uri $url -Method GET
    foreach ($it in $r.Items) { $price[$it.skuName] = $it.retailPrice }
    $url = $r.NextPageLink
} while ($url)

# 3) build PRICING_CL rows from the model -> [inputMeter, outputMeter] map
$map = $MeterMapJson | ConvertFrom-Json
$now = (Get-Date).ToUniversalTime().ToString('o')
$rows = foreach ($m in $map.PSObject.Properties.Name) {
    $meters = $map.$m
    [pscustomobject]@{
        TimeGenerated     = $now
        Model             = $m
        InputTokensPrice  = $price[$meters[0]]
        OutputTokensPrice = $price[$meters[1]]
    }
}
$body = ConvertTo-Json @($rows) -Depth 5

# 4) ingest into PRICING_CL via the data collection rule
$uri = "$DcrEndpoint/dataCollectionRules/$DcrImmutableId/streams/$StreamName" + "?api-version=2023-01-01"
Invoke-RestMethod -Uri $uri -Method POST -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $body

Write-Output "Refreshed PRICING_CL with $($rows.Count) rows at $now"
$rows | ForEach-Object { Write-Output ("  {0}: in={1} out={2}" -f $_.Model, $_.InputTokensPrice, $_.OutputTokensPrice) }
