$token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
$h = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
$ws = "30da17ec-c32a-4861-bc39-65c5775a87c8"
$sm = "1bb5bdb2-9318-497f-8ebe-39947fd12a79"

function ToB64([string]$c) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($c)) }

$platform = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json","metadata":{"type":"SemanticModel","displayName":"FCA_Chargeback_Model"},"config":{"version":"2.0","logicalId":"00000000-0000-0000-0000-000000000000"}}'
$pbism = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json","version":"4.2","settings":{}}'
$dbTmdl = "database`n`tcompatibilityLevel: 1604"

$sqlEp = "XHLPUK7WRAUUDJQPIV52X4AUTA-5QL5UMBKYNQURPBZMXCXOWUHZA.datawarehouse.fabric.microsoft.com"
$sqlId = "fe90a9f8-8443-4264-a608-82fc8455581a"

$exprTmdl = @"
expression FCA_SQL_Endpoint =
`tlet
`t`tSource = Sql.Database("$sqlEp", "$sqlId")
`tin
`t`tSource
`tlineageTag: f0a00000-cafe-cafe-cafe-000000000001
`tannotation PBI_NavigationStepName = Navigation
"@

$modelTmdl = @"
model Model
`tculture: en-US
`tdefaultPowerBIDataSourceVersion: powerBI_V3
`tannotation PBI_QueryOrder = ["FCA_SQL_Endpoint"]
ref table v_FabricCostSplitByWorkspace
ref table v_ReservationSavingsSummary
ref table v_ItemKindCostByWorkspace
ref table v_ChargebackMonthly
ref cultureInfo en-US
"@

$cultureTmdl = @"
cultureInfo en-US
`tlinguisticMetadata =
`t`t`t{
`t`t`t  "Version": "1.0.0",
`t`t`t  "Language": "en-US"
`t`t`t}
`t`tcontentType: json
"@

$relTmdl = ""

# Table 1: v_FabricCostSplitByWorkspace
$t1 = @"
table v_FabricCostSplitByWorkspace
`tlineageTag: a1b2c3d4-0001-0001-0001-000000000001
`tcolumn CapacityId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000002
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn CapacityName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000003
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000004
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000005
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn ChargePeriod
`t`tdataType: dateTime
`t`tformatString: Short Date
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000006
`t`tsummarizeBy: none
`t`tsourceColumn: ChargePeriod
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation UnderlyingDateTimeDataType = Date
`tcolumn PricingCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000007
`t`tsummarizeBy: none
`t`tsourceColumn: PricingCategory
`t`tannotation SummarizationSetBy = Automatic
`tcolumn TotalCostCapacity
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0001-0001-0001-000000000009
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostCapacity
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalCostWorkspace
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0001-0001-0001-00000000000a
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostWorkspace
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn ReservationSavingsWorkspace
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0001-0001-0001-00000000000b
`t`tsummarizeBy: sum
`t`tsourceColumn: ReservationSavingsWorkspace
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn CUSharePercent
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0001-0001-0001-00000000000c
`t`tsummarizeBy: average
`t`tsourceColumn: CUSharePercent
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn CostCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0001-0001-0001-00000000000d
`t`tsummarizeBy: none
`t`tsourceColumn: CostCategory
`t`tannotation SummarizationSetBy = Automatic
`tmeasure 'Total Chargeback' = SUM([TotalCostWorkspace])
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0001-meas-0001-000000000001
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tmeasure 'Total Reservation Savings' = SUM([ReservationSavingsWorkspace])
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0001-meas-0001-000000000002
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tmeasure '# Workspaces' = DISTINCTCOUNT([WorkspaceId])
`t`tformatString: #,0
`t`tlineageTag: a1b2c3d4-0001-meas-0001-000000000003
`tmeasure '# Capacities' = DISTINCTCOUNT([CapacityId])
`t`tformatString: #,0
`t`tlineageTag: a1b2c3d4-0001-meas-0001-000000000004
`tpartition v_FabricCostSplitByWorkspace = m
`t`tmode: directQuery
`t`tsource =
`t`t`tlet
`t`t`t`tSource = FCA_SQL_Endpoint,
`t`t`t`tv = Source{[Schema="dbo", Item="v_FabricCostSplitByWorkspace"]}[Data]
`t`t`tin
`t`t`t`tv
`tannotation PBI_ResultType = Table
"@

# Table 2: v_ReservationSavingsSummary
$t2 = @"
table v_ReservationSavingsSummary
`tlineageTag: a1b2c3d4-0002-0002-0002-000000000001
`tcolumn CapacityId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000002
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn CapacityName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000003
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn BillingPeriodStart
`t`tdataType: dateTime
`t`tformatString: Short Date
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000004
`t`tsummarizeBy: none
`t`tsourceColumn: BillingPeriodStart
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation UnderlyingDateTimeDataType = Date
`tcolumn PricingCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000005
`t`tsummarizeBy: none
`t`tsourceColumn: PricingCategory
`t`tannotation SummarizationSetBy = Automatic
`tcolumn TotalEffectiveCost
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000006
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalEffectiveCost
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalBilledCost
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000007
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalBilledCost
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalListCost
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000008
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalListCost
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalSavings
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0002-0002-0002-000000000009
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalSavings
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn SavingsPercent
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0002-0002-0002-00000000000a
`t`tsummarizeBy: average
`t`tsourceColumn: SavingsPercent
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tmeasure 'Effective Cost (RI)' = CALCULATE(SUM([TotalEffectiveCost]), [PricingCategory] = "Commitment-Based")
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0002-meas-0002-000000000001
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tmeasure 'On-Demand Equivalent' = SUM([TotalListCost])
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0002-meas-0002-000000000002
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tmeasure 'Total RI Savings' = SUM([TotalSavings])
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0002-meas-0002-000000000003
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tpartition v_ReservationSavingsSummary = m
`t`tmode: directQuery
`t`tsource =
`t`t`tlet
`t`t`t`tSource = FCA_SQL_Endpoint,
`t`t`t`tv = Source{[Schema="dbo", Item="v_ReservationSavingsSummary"]}[Data]
`t`t`tin
`t`t`t`tv
`tannotation PBI_ResultType = Table
"@

# Table 3: v_ItemKindCostByWorkspace
$t3 = @"
table v_ItemKindCostByWorkspace
`tlineageTag: a1b2c3d4-0003-0003-0003-000000000001
`tcolumn CapacityId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000002
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn CapacityName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000003
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000004
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000005
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn ItemKind
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000006
`t`tsummarizeBy: none
`t`tsourceColumn: ItemKind
`t`tannotation SummarizationSetBy = Automatic
`tcolumn ChargePeriod
`t`tdataType: dateTime
`t`tformatString: Short Date
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000007
`t`tsummarizeBy: none
`t`tsourceColumn: ChargePeriod
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation UnderlyingDateTimeDataType = Date
`tcolumn PricingCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000008
`t`tsummarizeBy: none
`t`tsourceColumn: PricingCategory
`t`tannotation SummarizationSetBy = Automatic
`tcolumn TotalCostCapacity
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0003-0003-0003-000000000009
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostCapacity
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalCostItemKind
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0003-0003-0003-00000000000a
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostItemKind
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn ItemKindCUSharePercent
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0003-0003-0003-00000000000b
`t`tsummarizeBy: average
`t`tsourceColumn: ItemKindCUSharePercent
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tmeasure 'Cost by Item Kind' = SUM([TotalCostItemKind])
`t`tformatString: `$#,0.00;(`$#,0.00);`$#,0.00
`t`tlineageTag: a1b2c3d4-0003-meas-0003-000000000001
`t`tannotation PBI_FormatHint = {"currencyCulture":"en-US"}
`tmeasure '# Item Kinds' = DISTINCTCOUNT([ItemKind])
`t`tformatString: #,0
`t`tlineageTag: a1b2c3d4-0003-meas-0003-000000000002
`tpartition v_ItemKindCostByWorkspace = m
`t`tmode: directQuery
`t`tsource =
`t`t`tlet
`t`t`t`tSource = FCA_SQL_Endpoint,
`t`t`t`tv = Source{[Schema="dbo", Item="v_ItemKindCostByWorkspace"]}[Data]
`t`t`tin
`t`t`t`tv
`tannotation PBI_ResultType = Table
"@

# Table 4: v_ChargebackMonthly
$t4 = @"
table v_ChargebackMonthly
`tlineageTag: a1b2c3d4-0009-0009-0009-000000000001
`tcolumn CapacityId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000002
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn CapacityName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000003
`t`tsummarizeBy: none
`t`tsourceColumn: CapacityName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceId
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000004
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceId
`t`tannotation SummarizationSetBy = Automatic
`tcolumn WorkspaceName
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000005
`t`tsummarizeBy: none
`t`tsourceColumn: WorkspaceName
`t`tannotation SummarizationSetBy = Automatic
`tcolumn BillingMonth
`t`tdataType: dateTime
`t`tformatString: Short Date
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000006
`t`tsummarizeBy: none
`t`tsourceColumn: BillingMonth
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation UnderlyingDateTimeDataType = Date
`tcolumn PricingCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000007
`t`tsummarizeBy: none
`t`tsourceColumn: PricingCategory
`t`tannotation SummarizationSetBy = Automatic
`tcolumn CostCategory
`t`tdataType: string
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000008
`t`tsummarizeBy: none
`t`tsourceColumn: CostCategory
`t`tannotation SummarizationSetBy = Automatic
`tcolumn TotalCostCapacity
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0009-0009-0009-000000000009
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostCapacity
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn TotalCostWorkspace
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0009-0009-0009-00000000000a
`t`tsummarizeBy: sum
`t`tsourceColumn: TotalCostWorkspace
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn ReservationSavingsWorkspace
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0009-0009-0009-00000000000b
`t`tsummarizeBy: sum
`t`tsourceColumn: ReservationSavingsWorkspace
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn AvgCUSharePercent
`t`tdataType: double
`t`tlineageTag: a1b2c3d4-0009-0009-0009-00000000000c
`t`tsummarizeBy: average
`t`tsourceColumn: AvgCUSharePercent
`t`tannotation SummarizationSetBy = Automatic
`t`tannotation PBI_FormatHint = {"isGeneralNumber":true}
`tcolumn DaysWithData
`t`tdataType: int64
`t`tlineageTag: a1b2c3d4-0009-0009-0009-00000000000d
`t`tsummarizeBy: sum
`t`tsourceColumn: DaysWithData
`t`tannotation SummarizationSetBy = Automatic
`tpartition v_ChargebackMonthly = m
`t`tmode: directQuery
`t`tsource =
`t`t`tlet
`t`t`t`tSource = FCA_SQL_Endpoint,
`t`t`t`tv = Source{[Schema="dbo", Item="v_ChargebackMonthly"]}[Data]
`t`t`tin
`t`t`t`tv
`tannotation PBI_ResultType = Table
"@

$parts = @()
$parts += @{path=".platform";payload=(ToB64 $platform);payloadType="InlineBase64"}
$parts += @{path="definition.pbism";payload=(ToB64 $pbism);payloadType="InlineBase64"}
$parts += @{path="definition/database.tmdl";payload=(ToB64 $dbTmdl);payloadType="InlineBase64"}
$parts += @{path="definition/model.tmdl";payload=(ToB64 $modelTmdl);payloadType="InlineBase64"}
$parts += @{path="definition/expressions.tmdl";payload=(ToB64 $exprTmdl);payloadType="InlineBase64"}
$parts += @{path="definition/relationships.tmdl";payload=(ToB64 $relTmdl);payloadType="InlineBase64"}
$parts += @{path="definition/cultures/en-US.tmdl";payload=(ToB64 $cultureTmdl);payloadType="InlineBase64"}
$parts += @{path="definition/tables/v_FabricCostSplitByWorkspace.tmdl";payload=(ToB64 $t1);payloadType="InlineBase64"}
$parts += @{path="definition/tables/v_ReservationSavingsSummary.tmdl";payload=(ToB64 $t2);payloadType="InlineBase64"}
$parts += @{path="definition/tables/v_ItemKindCostByWorkspace.tmdl";payload=(ToB64 $t3);payloadType="InlineBase64"}
$parts += @{path="definition/tables/v_ChargebackMonthly.tmdl";payload=(ToB64 $t4);payloadType="InlineBase64"}

$apiBase = "https://api.fabric.microsoft.com/v1/workspaces/$ws"
$body = @{definition=@{format="TMDL";parts=$parts}} | ConvertTo-Json -Depth 30 -Compress

Write-Host "Updating semantic model with DirectQuery partitions ($($parts.Count) parts)..."
try {
    $r = Invoke-WebRequest -Uri "$apiBase/items/$sm/updateDefinition" -Headers $h -Method Post -Body $body -UseBasicParsing
    Write-Host "Status: $($r.StatusCode)"
    $opId = $r.Headers['x-ms-operation-id']
    Write-Host "OpId: $opId"
    
    # Poll for completion
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 5 /nobreak >nul" -Wait
    $h2 = @{ Authorization = "Bearer $token" }
    $op = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/operations/$opId" -Headers $h2
    Write-Host "OpStatus: $($op.status)"
    if ($op.status -ne "Succeeded") {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 5 /nobreak >nul" -Wait
        $op = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/operations/$opId" -Headers $h2
        Write-Host "OpStatus (retry): $($op.status)"
    }
    if ($op.status -eq "Failed") {
        Write-Host "FAILED: $($op | ConvertTo-Json -Depth 10)"
    }
} catch {
    $e = $_.Exception
    Write-Host "Error: $($e.Message)"
    if ($e.Response) {
        $sr = [System.IO.StreamReader]::new($e.Response.GetResponseStream())
        Write-Host "Body: $($sr.ReadToEnd())"
    }
}
