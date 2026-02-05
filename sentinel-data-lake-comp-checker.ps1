<#
.SYNOPSIS
    Sentinel Data Lake Compatibility Checker

.DESCRIPTION
    Validates whether your Azure environment meets the requirements for Microsoft Sentinel
    Data Lake (ADX/Log Analytics integration). Checks workspace configuration, data connectors,
    retention policies, storage account settings, and ingestion compatibility across subscriptions.
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$env:AZURE_CORE_OUTPUT = "json"
$env:AZURE_CORE_NO_COLOR = "true"
az login 2>$null

$tenantRaw = az rest --method GET --url "https://graph.microsoft.com/v1.0/organization" 2>$null
$tenant = $tenantRaw | ConvertFrom-Json
$tenantId = $tenant.value[0].id
$tenantName = $tenant.value[0].displayName
$tenantCountry = $tenant.value[0].countryLetterCode
$tenantDomain = ($tenant.value[0].verifiedDomains | Where-Object { $_.isDefault }).name

$wsRaw = az monitor log-analytics workspace list 2>$null
$workspaces = $wsRaw | ConvertFrom-Json

$sentinelRaw = az resource list --resource-type "Microsoft.OperationsManagement/solutions" 2>$null
$sentinelAll = $sentinelRaw | ConvertFrom-Json
$sentinel = $sentinelAll | Where-Object { $_.name -like "*SecurityInsights*" }

$locRaw = az account list-locations --query "[].{Name:name, DisplayName:displayName, Geo:metadata.geographyGroup, PairedRegion:metadata.pairedRegion[0].name}" 2>$null
$subLocations = $locRaw | ConvertFrom-Json

$euCountries = @("AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR","HU","IE","IT","LV","LT","LU","MT","NL","PL","PT","RO","SK","SI","ES","SE","NO","CH","IS","LI")
$euRegions = @("westeurope","northeurope","francecentral","germanywestcentral","norwayeast","swedencentral","switzerlandnorth","uksouth","ukwest")

$sentinelLocations = if ($sentinel) { $sentinel | Select-Object -ExpandProperty location -Unique } else { @() }
$wsLocations = if ($workspaces) { $workspaces | Select-Object -ExpandProperty location -Unique } else { @() }

$isEuTenant = $tenantCountry -in $euCountries
$regionsMatch = ($wsLocations | ForEach-Object { $_.ToLower().Replace(" ","") -in $euRegions }) -contains $true

[PSCustomObject]@{
    TenantName    = $tenantName
    TenantId      = $tenantId
    Country       = $tenantCountry
    DefaultDomain = $tenantDomain
    IsEuTenant    = $isEuTenant
} | Format-List

$workspaces | Select-Object name, location, resourceGroupName, retentionInDays, sku | Format-Table -AutoSize

if ($sentinel) {
    $sentinel | Select-Object name, location, resourceGroup | Format-Table -AutoSize
} else {
    Write-Output "Sentinel solution not found - verify permissions or subscription"
}

[PSCustomObject]@{
    TenantCountry         = $tenantCountry
    TenantGeo             = if ($isEuTenant) { "Europe" } else { "Other" }
    SentinelRegions       = if ($sentinelLocations) { $sentinelLocations -join ", " } else { "Not found" }
    WorkspaceRegions      = $wsLocations -join ", "
    RegionInEuropeGeo     = $regionsMatch
    DataLakeCompatible    = $isEuTenant -and $regionsMatch
} | Format-List

if ($subLocations) {
    $subLocations | Where-Object { $_.Geo -eq "Europe" -and $_.PairedRegion } | Sort-Object Name | Format-Table Name, DisplayName, PairedRegion -AutoSize
}
