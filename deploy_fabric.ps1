# deploy_fabric.ps1 - Deploy FCA Chargeback artifacts to Fabric workspace
param(
    [string]$WorkspaceId = "30da17ec-c32a-4861-bc39-65c5775a87c8",
    [string]$SqlEndpoint = "xhlpuk7wrauudjqpiv52x4auta-5ql5umbkynqurpbzmxcxowuhza.datawarehouse.fabric.microsoft.com",
    [string]$SqlEndpointId = "fe90a9f8-8443-4264-a608-82fc8455581a",
    [string]$LakehouseName = "FCA"
)

$ErrorActionPreference = "Stop"
$baseDir = $PSScriptRoot
$apiBase = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId"

# --- Auth ---
Write-Host "=== Getting Fabric API token ===" -ForegroundColor Cyan
$token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
if (-not $token) { throw "Failed to get access token" }
$headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }

# --- Helpers ---
function ToB64([string]$c) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($c)) }
function FileB64([string]$p) { ToB64 (Get-Content $p -Raw -Encoding UTF8) }

function CleanTmdl([string]$path) {
    $lines = Get-Content $path -Encoding UTF8
    $cleaned = @()
    $inContent = $false
    foreach ($line in $lines) {
        if (-not $inContent -and $line -match '^\s*///') { continue }
        if (-not $inContent -and $line.Trim() -eq '') { continue }
        $inContent = $true
        $cleaned += $line
    }
    return ($cleaned -join "`n")
}

function Wait-Operation([string]$opId) {
    $maxAttempts = 30
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        Start-Sleep -Seconds 3
        $op = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/operations/$opId" -Headers @{ Authorization = "Bearer $token" }
        if ($op.status -eq "Succeeded") {
            Write-Host "  Operation succeeded." -ForegroundColor Green
            return $op
        }
        if ($op.status -eq "Failed") {
            Write-Host "  Operation FAILED: $($op.error.message)" -ForegroundColor Red
            throw $op.error.message
        }
        Write-Host "  Status: $($op.status)... waiting" -ForegroundColor Gray
    }
    throw "Operation timed out"
}

function Deploy-Item([string]$Name, [string]$Type, [object]$Def, [string]$Desc) {
    $existingItems = Invoke-RestMethod -Uri "$apiBase/items" -Headers $headers
    $existing = $existingItems.value | Where-Object { $_.displayName -eq $Name -and $_.type -eq $Type }

    if ($existing) {
        $itemId = $existing.id
        Write-Host "  Updating existing $Type '$Name' ($itemId)..." -ForegroundColor Yellow
        $body = @{ definition = $Def } | ConvertTo-Json -Depth 30 -Compress
        $r = Invoke-WebRequest -Uri "$apiBase/items/$itemId/updateDefinition" -Headers $headers -Method Post -Body $body -UseBasicParsing
        if ($r.Headers['x-ms-operation-id']) {
            Wait-Operation $r.Headers['x-ms-operation-id']
        }
        return $itemId
    }
    else {
        Write-Host "  Creating $Type '$Name'..." -ForegroundColor Yellow
        $body = @{ displayName = $Name; type = $Type; definition = $Def }
        if ($Desc) { $body.description = $Desc }
        $json = $body | ConvertTo-Json -Depth 30 -Compress
        $r = Invoke-WebRequest -Uri "$apiBase/items" -Headers $headers -Method Post -Body $json -UseBasicParsing
        if ($r.StatusCode -eq 201) {
            $item = $r.Content | ConvertFrom-Json
            Write-Host "  Created: $($item.id)" -ForegroundColor Green
            return $item.id
        }
        if ($r.Headers['x-ms-operation-id']) {
            $op = Wait-Operation $r.Headers['x-ms-operation-id']
            # Get the created item ID
            $items = Invoke-RestMethod -Uri "$apiBase/items" -Headers $headers
            $created = $items.value | Where-Object { $_.displayName -eq $Name -and $_.type -eq $Type }
            if ($created) {
                Write-Host "  Created: $($created.id)" -ForegroundColor Green
                return $created.id
            }
        }
        return $null
    }
}

# ============================================================
# 1. SEMANTIC MODEL
# ============================================================
Write-Host "`n=== Deploying Semantic Model ===" -ForegroundColor Cyan
$smDir = Join-Path $baseDir "FCA_Chargeback_Model.SemanticModel"

# .platform
$platform = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": {
    "type": "SemanticModel",
    "displayName": "FCA_Chargeback_Model"
  },
  "config": {
    "version": "2.0",
    "logicalId": "00000000-0000-0000-0000-000000000000"
  }
}
'@

# definition.pbism
$pbism = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
  "version": "4.2",
  "settings": {}
}
'@

# database.tmdl
$databaseTmdl = "database`n`tcompatibilityLevel: 1604"

# model.tmdl - with ref entries for all tables
$modelTmdl = @"
model Model
`tculture: en-US
`tdefaultPowerBIDataSourceVersion: powerBI_V3
`tannotation PBI_QueryOrder = ["v_FabricCostSplitByWorkspace", "v_ReservationSavingsSummary", "v_ItemKindCostByWorkspace", "v_ChargebackByDepartment", "dept_workspace_mapping"]
ref table v_FabricCostSplitByWorkspace
ref table v_ReservationSavingsSummary
ref table v_ItemKindCostByWorkspace
ref table v_ChargebackByDepartment
ref table dept_workspace_mapping
ref cultureInfo en-US
"@

# expressions.tmdl - with actual endpoint
$exprTmdl = @"
expression FCA_SQL_Endpoint =
`t`tlet
`t`t`tdatabase = Sql.Database("$SqlEndpoint", "$SqlEndpointId")
`t`tin
`t`t`tdatabase
`tlineageTag: f0a00000-cafe-cafe-cafe-000000000001
`tannotation PBI_NavigationStepName = Navigation
`tannotation PBI_ResultType = {"type":"table"}
"@

# cultures/en-US.tmdl
$cultureTmdl = @"
cultureInfo en-US
`tlinguisticMetadata =
`t`t`t{
`t`t`t  "Version": "1.0.0",
`t`t`t  "Language": "en-US"
`t`t`t}
`t`tcontentType: json
"@

# Build parts
$smParts = @()
$smParts += @{ path = ".platform"; payload = (ToB64 $platform); payloadType = "InlineBase64" }
$smParts += @{ path = "definition.pbism"; payload = (ToB64 $pbism); payloadType = "InlineBase64" }
$smParts += @{ path = "definition/database.tmdl"; payload = (ToB64 $databaseTmdl); payloadType = "InlineBase64" }
$smParts += @{ path = "definition/model.tmdl"; payload = (ToB64 $modelTmdl); payloadType = "InlineBase64" }
$smParts += @{ path = "definition/expressions.tmdl"; payload = (ToB64 $exprTmdl); payloadType = "InlineBase64" }
$smParts += @{ path = "definition/cultures/en-US.tmdl"; payload = (ToB64 $cultureTmdl); payloadType = "InlineBase64" }

# Table files (cleaned)
$tableFiles = Get-ChildItem (Join-Path $smDir "definition\tables") -Filter "*.tmdl"
foreach ($tf in $tableFiles) {
    $cleaned = CleanTmdl $tf.FullName
    $smParts += @{ path = "definition/tables/$($tf.Name)"; payload = (ToB64 $cleaned); payloadType = "InlineBase64" }
}

$smDef = @{ format = "TMDL"; parts = $smParts }
$smId = Deploy-Item -Name "FCA_Chargeback_Model" -Type "SemanticModel" -Def $smDef -Desc "DirectQuery semantic model for FUAM-FCA Chargeback"

# ============================================================
# 2. REPORT
# ============================================================
Write-Host "`n=== Deploying Report ===" -ForegroundColor Cyan
$rptDir = Join-Path $baseDir "FCA_Chargeback_Report.Report"

# definition.pbir using byConnection (required by Fabric REST API)
# Get workspace name for connection string
$wsInfo = Invoke-RestMethod -Uri "$apiBase" -Headers $headers
$wsName = $wsInfo.displayName
$connStr = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$wsName;initial catalog=FCA_Chargeback_Model;integrated security=ClaimsToken;semanticmodelid=$smId"
$pbir = @"
{
  "`$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json",
  "version": "4.0",
  "datasetReference": {
    "byConnection": {
      "connectionString": "$connStr"
    }
  }
}
"@

# .platform for report
$rptPlatform = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": {
    "type": "Report",
    "displayName": "FCA_Chargeback_Report"
  },
  "config": {
    "version": "2.0",
    "logicalId": "00000000-0000-0000-0000-000000000000"
  }
}
'@

$rptParts = @()
$rptParts += @{ path = ".platform"; payload = (ToB64 $rptPlatform); payloadType = "InlineBase64" }
$rptParts += @{ path = "definition.pbir"; payload = (ToB64 $pbir); payloadType = "InlineBase64" }

# All files under definition/
$defDir = Join-Path $rptDir "definition"
$rptFiles = Get-ChildItem -Recurse $defDir -File
foreach ($rf in $rptFiles) {
    $relPath = "definition/" + $rf.FullName.Substring($defDir.Length + 1).Replace('\', '/')
    $rptParts += @{ path = $relPath; payload = (FileB64 $rf.FullName); payloadType = "InlineBase64" }
}

$rptDef = @{ parts = $rptParts }
$rptId = Deploy-Item -Name "FCA_Chargeback_Report" -Type "Report" -Def $rptDef -Desc "FUAM-FCA Chargeback Report"

# ============================================================
# 3. DATA PIPELINE
# ============================================================
Write-Host "`n=== Deploying Data Pipeline ===" -ForegroundColor Cyan
$pipeDir = Join-Path $baseDir "FCA_Chargeback_Pipeline.DataPipeline"

$pipeContent = Get-Content (Join-Path $pipeDir "pipeline-content.json") -Raw -Encoding UTF8
$pipeContent = $pipeContent.Replace("<REPLACE_WITH_FCA_WORKSPACE_ID>", $WorkspaceId)
# Replace notebook ID placeholder with the existing addon notebook
$pipeContent = $pipeContent.Replace("<REPLACE_WITH_NOTEBOOK_ITEM_ID>", "c4b5e795-d05b-4bca-80e9-10d4d9a5fd9e")
# Extract just the properties object (pipeline API expects only {properties:{...}})
$pipeObj = $pipeContent | ConvertFrom-Json
$pipeClean = @{ properties = $pipeObj.properties } | ConvertTo-Json -Depth 30 -Compress
# Remove description and annotations if they exist (not part of pipeline schema)
$pipeCleanObj = $pipeClean | ConvertFrom-Json
if ($pipeCleanObj.properties.PSObject.Properties['description']) {
    $pipeCleanObj.properties.PSObject.Properties.Remove('description')
}
if ($pipeCleanObj.properties.PSObject.Properties['annotations']) {
    $pipeCleanObj.properties.PSObject.Properties.Remove('annotations')
}
$pipeClean = $pipeCleanObj | ConvertTo-Json -Depth 30 -Compress

$pipePlatform = @'
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": {
    "type": "DataPipeline",
    "displayName": "FCA_Chargeback_Pipeline"
  },
  "config": {
    "version": "2.0",
    "logicalId": "00000000-0000-0000-0000-000000000000"
  }
}
'@

$pipeParts = @()
$pipeParts += @{ path = ".platform"; payload = (ToB64 $pipePlatform); payloadType = "InlineBase64" }
$pipeParts += @{ path = "pipeline-content.json"; payload = (ToB64 $pipeClean); payloadType = "InlineBase64" }

$pipeDef = @{ parts = $pipeParts }
$pipeId = Deploy-Item -Name "FCA_Chargeback_Pipeline" -Type "DataPipeline" -Def $pipeDef -Desc "FUAM-FCA Chargeback Pipeline"

# ============================================================
# SUMMARY
# ============================================================
Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "  Semantic Model : $smId"
Write-Host "  Report         : $rptId"
Write-Host "  Pipeline       : $pipeId"
$wsUrl = "https://app.powerbi.com/groups/$WorkspaceId/list"
Write-Host "  Workspace URL  : $wsUrl" -ForegroundColor Cyan
