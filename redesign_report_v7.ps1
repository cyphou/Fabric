####################################################################
# FCA Chargeback Report v7 — Design refresh
#   - Navy (#1E293B) + Orange (#F97316) palette
#   - ◆ FCA text-logo in header
#   - labelPrecision on cards (fixes -9.10E-15 → 0.00)
#   - DistinctCount (fn 6) for Workspace / Capacity cards
#   - categoryLabels hidden (no ugly "TotalCostWorkspace" subtitle)
#   - Orange bars, orange line, themed donuts
#   - SQL ROUND fix for floating-point noise
####################################################################

$token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
$h = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
$ws   = "30da17ec-c32a-4861-bc39-65c5775a87c8"
$rpId = "d8e704d2-09f1-47b9-9ecc-f1b4747b3bba"
$smId = "99bf5b7b-5ad8-4346-9101-df2e069a7a0e"
function ToB64([string]$c) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($c)) }

# ── Design Tokens ─────────────────────────────────────────
$navy     = "#1E293B"
$orange   = "#F97316"
$white    = "#FFFFFF"
$slate300 = "#CBD5E1"
$slate50  = "#F8FAFC"
$dark     = "#334155"
$vsc = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.5.0/schema.json"
$psc = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.0.0/schema.json"

# ── Field helpers ─────────────────────────────────────────
function ColF($e,$p) { @{Column=@{Expression=@{SourceRef=@{Entity=$e}};Property=$p}} }
function AggF($e,$p,[int]$f) { @{Aggregation=@{Expression=@{Column=@{Expression=@{SourceRef=@{Entity=$e}};Property=$p}};Function=$f}} }

# ── VisualContainerObjects helpers ────────────────────────
function VCT([string]$t) {
    @{title=@(@{properties=@{
        text  = @{expr=@{Literal=@{Value="'$t'"}}}
        show  = @{expr=@{Literal=@{Value="true"}}}
        fontColor = @{solid=@{color=@{expr=@{Literal=@{Value="'$dark'"}}}}}
    }})}
}
function VCB([string]$c,[int]$t=0) {
    @{background=@(@{properties=@{
        show  = @{expr=@{Literal=@{Value="true"}}}
        color = @{solid=@{color=@{expr=@{Literal=@{Value="'$c'"}}}}}
        transparency = @{expr=@{Literal=@{Value="${t}D"}}}
    }})}
}

# ── Header with logo ─────────────────────────────────────
function HdrBar([string]$pn,[string]$title) {
    $d = [char]0x25C6  # ◆
    @{
        '$schema' = $vsc; name = "${pn}_hdr"
        position  = @{x=0;y=0;width=1280;height=64}
        visual    = @{
            visualType = "textbox"
            objects = @{general=@(@{properties=@{
                paragraphs = @(
                    @{
                        textRuns = @(
                            @{ value = "$d  "; textStyle = @{ fontFamily = "Segoe UI"; fontSize = "22px"; color = $orange } },
                            @{ value = "FCA"; textStyle = @{ fontFamily = "Segoe UI Semibold"; fontSize = "18px"; color = $white } },
                            @{ value = "  |  $title"; textStyle = @{ fontFamily = "Segoe UI"; fontSize = "14px"; color = $slate300 } }
                        )
                    }
                )
            }})}
            visualContainerObjects = (VCB $navy)
        }
    }
}

# ── Sidebar ───────────────────────────────────────────────
function SideBar([string]$pn) {
    @{
        '$schema' = $vsc; name = "${pn}_sb"
        position  = @{x=0;y=64;width=220;height=656}
        visual    = @{
            visualType = "shape"
            objects = @{
                line = @(@{properties=@{show=@{expr=@{Literal=@{Value="false"}}}}})
                fill = @(@{properties=@{
                    show = @{expr=@{Literal=@{Value="true"}}}
                    fillColor = @{solid=@{color=@{expr=@{Literal=@{Value="'$slate50'"}}}}}
                }})
            }
            visualContainerObjects = (VCB $slate50)
        }
    }
}

# ── Slicer (title hidden to avoid double name) ───────────
function Sli([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,[string]$ent,[string]$prop,[string]$qr) {
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "slicer"
            query   = @{queryState=@{Values=@{projections=@(@{field=(ColF $ent $prop);queryRef=$qr;active=$true})}}}
            objects = @{data=@(@{properties=@{mode=@{expr=@{Literal=@{Value="'Dropdown'"}}}}})}
            visualContainerObjects = @{title=@(@{properties=@{
                show = @{expr=@{Literal=@{Value="false"}}}
            }})}
            drillFilterOtherVisuals = $true
        }
    }
}

# ── KPI Card ──────────────────────────────────────────────
function Crd([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ent,[string]$prop,[int]$fn,[string]$qr,
             [string]$tt,[int]$prec=2) {
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "card"
            query   = @{queryState=@{Values=@{projections=@(@{
                field=(AggF $ent $prop $fn);queryRef=$qr;active=$true
            })}}}
            objects = @{
                labels = @(@{properties=@{
                    color = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
                    fontSize = @{expr=@{Literal=@{Value="24D"}}}
                    labelPrecision = @{expr=@{Literal=@{Value="${prec}L"}}}
                }})
                categoryLabels = @(@{properties=@{
                    show = @{expr=@{Literal=@{Value="false"}}}
                }})
            }
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ── Measure Card (references a DAX measure) ──────────────
function MsrCrd([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ent,[string]$measure,[string]$qr,
             [string]$tt,[int]$prec=0) {
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "card"
            query   = @{queryState=@{Values=@{projections=@(@{
                field=@{Measure=@{Expression=@{SourceRef=@{Entity=$ent}};Property=$measure}}
                queryRef=$qr;active=$true
            })}}}
            objects = @{
                labels = @(@{properties=@{
                    color = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
                    fontSize = @{expr=@{Literal=@{Value="24D"}}}
                    labelPrecision = @{expr=@{Literal=@{Value="${prec}L"}}}
                }})
                categoryLabels = @(@{properties=@{
                    show = @{expr=@{Literal=@{Value="false"}}}
                }})
            }
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ── Bar Chart (orange) ────────────────────────────────────
function Bar([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ce,[string]$cp,[string]$cr,
             [string]$ve,[string]$vp,[string]$vr,
             [string]$tt,[int]$fn=0) {
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "barChart"
            query = @{
                queryState = @{
                    Category = @{projections=@(@{field=(ColF $ce $cp);queryRef=$cr;active=$true})}
                    Y        = @{projections=@(@{field=(AggF $ve $vp $fn);queryRef=$vr;active=$true})}
                }
                sortDefinition = @{sort=@(@{field=(AggF $ve $vp $fn);direction="Descending"})}
            }
            objects = @{dataPoint=@(@{properties=@{
                fill = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
            }})}
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ── Donut Chart (theme colors for multi-segment) ─────────
function Dnt([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ce,[string]$cp,[string]$cr,
             [string]$ve,[string]$vp,[string]$vr,
             [string]$tt,[int]$fn=0) {
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "donutChart"
            query = @{queryState=@{
                Category = @{projections=@(@{field=(ColF $ce $cp);queryRef=$cr;active=$true})}
                Y        = @{projections=@(@{field=(AggF $ve $vp $fn);queryRef=$vr;active=$true})}
            }}
            objects = @{dataPoint=@(@{properties=@{
                fill = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
            }})}
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ── Column Chart ──────────────────────────────────────────
function ColChart([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ce,[string]$cp,[string]$cr,
             [string]$ve,[string]$vp,[string]$vr,
             [string]$tt,[int]$fn=0,
             [string]$se,[string]$sp,[string]$sr) {
    $qs = @{
        Category = @{projections=@(@{field=(ColF $ce $cp);queryRef=$cr;active=$true})}
        Y        = @{projections=@(@{field=(AggF $ve $vp $fn);queryRef=$vr;active=$true})}
    }
    if($se){ $qs['Series'] = @{projections=@(@{field=(ColF $se $sp);queryRef=$sr;active=$true})} }

    $vis = @{
        visualType = "clusteredColumnChart"
        query = @{queryState=$qs}
        visualContainerObjects = (VCT $tt)
        drillFilterOtherVisuals = $true
    }
    if(-not $se){
        $vis['objects'] = @{dataPoint=@(@{properties=@{
            fill = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
        }})}
    }
    @{ '$schema'=$vsc; name=$n; position=@{x=$x;y=$y;width=$w;height=$h}; visual=$vis }
}

# ── Line Chart ────────────────────────────────────────────
function Lin([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [string]$ce,[string]$cp,[string]$cr,
             [string]$ve,[string]$vp,[string]$vr,
             [string]$tt,[int]$fn=0,
             [string]$se,[string]$sp,[string]$sr) {
    $qs = @{
        Category = @{projections=@(@{field=(ColF $ce $cp);queryRef=$cr;active=$true})}
        Y        = @{projections=@(@{field=(AggF $ve $vp $fn);queryRef=$vr;active=$true})}
    }
    if($se){ $qs['Series'] = @{projections=@(@{field=(ColF $se $sp);queryRef=$sr;active=$true})} }

    $vis = @{
        visualType = "lineChart"
        query = @{queryState=$qs}
        visualContainerObjects = (VCT $tt)
        drillFilterOtherVisuals = $true
    }
    if(-not $se){
        $vis['objects'] = @{dataPoint=@(@{properties=@{
            fill = @{solid=@{color=@{expr=@{Literal=@{Value="'$orange'"}}}}}
        }})}
    }
    @{ '$schema'=$vsc; name=$n; position=@{x=$x;y=$y;width=$w;height=$h}; visual=$vis }
}

# ── Clustered Bar (multi-Y) ──────────────────────────────
function CBar([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
              [string]$ce,[string]$cp,[string]$cr,
              [array]$yf,[string]$tt) {
    $yp = @()
    foreach($f in $yf){ $yp += @{field=(AggF $f.entity $f.prop $f.fn);queryRef=$f.ref;active=$true} }
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "clusteredBarChart"
            query = @{queryState=@{
                Category = @{projections=@(@{field=(ColF $ce $cp);queryRef=$cr;active=$true})}
                Y        = @{projections=$yp}
            }}
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ── Table ─────────────────────────────────────────────────
function Tbl([string]$n,[int]$x,[int]$y,[int]$w,[int]$h,
             [array]$flds,[string]$tt,
             [string]$se,[string]$sp,[int]$sf=0) {
    $pr = @()
    foreach($f in $flds){
        if($null -ne $f.agg){ $pr += @{field=(AggF $f.entity $f.prop $f.agg);queryRef=$f.ref;active=$true} }
        else                { $pr += @{field=(ColF $f.entity $f.prop);queryRef=$f.ref;active=$true} }
    }
    $q = @{queryState=@{Values=@{projections=$pr}}}
    if($se){ $q['sortDefinition'] = @{sort=@(@{field=(AggF $se $sp $sf);direction="Descending"})} }
    @{
        '$schema' = $vsc; name = $n
        position  = @{x=$x;y=$y;width=$w;height=$h}
        visual    = @{
            visualType = "tableEx"
            query = $q
            visualContainerObjects = (VCT $tt)
            drillFilterOtherVisuals = $true
        }
    }
}

# ══════════════════════════════════════════════════════════
# Entity shortcuts
# ══════════════════════════════════════════════════════════
$e  = "v_FabricCostSplitByWorkspace"
$r  = "v_ReservationSavingsSummary"
$ik = "v_ItemKindCostByWorkspace"
$cm = "v_ChargebackMonthly"

# ── PAGE 1: Cost by Workspace ────────────────────────────
$p1 = @()
$p1 += HdrBar "cb" "Cost by Workspace"
$p1 += SideBar "cb"
# Cards
$p1 += Crd "cb_c1" 232 76 250 90 $e "TotalCostWorkspace" 0 "Sum($e.TotalCostWorkspace)" "Total Workspace Cost" 2
$p1 += Crd "cb_c2" 494 76 250 90 $e "ReservationSavingsWorkspace" 0 "Sum($e.ReservationSavingsWorkspace)" "Reservation Savings" 2
$p1 += MsrCrd "cb_c3" 756 76 250 90 $e "# Workspaces" "$e.# Workspaces" "Workspaces" 0
$p1 += MsrCrd "cb_c4" 1018 76 250 90 $e "# Capacities" "$e.# Capacities" "Capacities" 0
# Slicers
$p1 += Sli "cb_s1" 12 80 196 80 $e "ChargePeriod" "$e.ChargePeriod"
$p1 += Sli "cb_s2" 12 170 196 80 $e "CapacityName" "$e.CapacityName"
$p1 += Sli "cb_s3" 12 260 196 80 $e "PricingCategory" "$e.PricingCategory"
# Charts
$p1 += Bar "cb_bar" 232 178 520 270 $e "WorkspaceName" "$e.WorkspaceName" $e "TotalCostWorkspace" "Sum($e.TotalCostWorkspace)" "Cost by Workspace"
$p1 += Dnt "cb_dnt" 764 178 504 270 $ik "ItemKind" "$ik.ItemKind" $ik "TotalCostItemKind" "Sum($ik.TotalCostItemKind)" "Cost by Item Kind"
# Table
$p1 += Tbl "cb_tbl" 232 460 1036 250 @(
    @{entity=$e;prop="CapacityName";ref="$e.CapacityName"},
    @{entity=$e;prop="WorkspaceName";ref="$e.WorkspaceName"},
    @{entity=$e;prop="ChargePeriod";ref="$e.ChargePeriod"},
    @{entity=$e;prop="PricingCategory";ref="$e.PricingCategory"},
    @{entity=$e;prop="TotalCostWorkspace";ref="Sum($e.TotalCostWorkspace)";agg=0},
    @{entity=$e;prop="CUSharePercent";ref="Sum($e.CUSharePercent)";agg=0},
    @{entity=$e;prop="CostCategory";ref="$e.CostCategory"}
) "Workspace Chargeback Detail" $e "TotalCostWorkspace"

# ── PAGE 2: Capacity Overview ────────────────────────────
$p2 = @()
$p2 += HdrBar "co" "Capacity Overview"
$p2 += Dnt "co_dnt" 20 76 500 340 $e "CapacityName" "$e.CapacityName" $e "TotalCostWorkspace" "Sum($e.TotalCostWorkspace)" "Cost Allocation by Capacity"
$p2 += ColChart "co_col" 540 76 720 340 $e "CapacityName" "$e.CapacityName" $e "TotalCostWorkspace" "Sum($e.TotalCostWorkspace)" "Cost by Capacity and Pricing" 0 $e "PricingCategory" "$e.PricingCategory"
$p2 += Tbl "co_tbl" 20 428 1240 282 @(
    @{entity=$e;prop="CapacityName";ref="$e.CapacityName"},
    @{entity=$e;prop="TotalCostCapacity";ref="Sum($e.TotalCostCapacity)";agg=0},
    @{entity=$e;prop="TotalCostWorkspace";ref="Sum($e.TotalCostWorkspace)";agg=0},
    @{entity=$e;prop="ReservationSavingsWorkspace";ref="Sum($e.ReservationSavingsWorkspace)";agg=0},
    @{entity=$e;prop="CUSharePercent";ref="Average($e.CUSharePercent)";agg=1}
) "Capacity vs Workspace Cost" $e "TotalCostWorkspace"

# ── PAGE 3: Reserved vs On-Demand ────────────────────────
$p3 = @()
$p3 += HdrBar "rv" "Reserved vs On-Demand"
$p3 += SideBar "rv"
$p3 += Sli "rv_s1" 12 80 196 80 $e "CapacityName" "$e.CapacityName"
$p3 += Crd "rv_c1" 232 76 340 90 $e "TotalCostWorkspace" 0 "Sum($e.TotalCostWorkspace)" "Total Cost" 2
$p3 += Crd "rv_c2" 584 76 340 90 $e "ReservationSavingsWorkspace" 0 "Sum($e.ReservationSavingsWorkspace)" "Reservation Savings" 2
$p3 += Dnt "rv_dnt" 232 178 400 270 $e "PricingCategory" "$e.PricingCategory" $e "TotalCostWorkspace" "Sum($e.TotalCostWorkspace)" "Cost Split by Pricing"
$p3 += Bar "rv_bar" 644 178 624 270 $e "WorkspaceName" "$e.WorkspaceName" $e "ReservationSavingsWorkspace" "Sum($e.ReservationSavingsWorkspace)" "Savings by Workspace"
$p3 += Tbl "rv_tbl" 232 460 1036 250 @(
    @{entity=$e;prop="WorkspaceName";ref="$e.WorkspaceName"},
    @{entity=$e;prop="PricingCategory";ref="$e.PricingCategory"},
    @{entity=$e;prop="TotalCostWorkspace";ref="Sum($e.TotalCostWorkspace)";agg=0},
    @{entity=$e;prop="ReservationSavingsWorkspace";ref="Sum($e.ReservationSavingsWorkspace)";agg=0}
) "Pricing Detail" $e "TotalCostWorkspace"

# ── PAGE 4: Reservation ROI ──────────────────────────────
$p4 = @()
$p4 += HdrBar "roi" "Reservation ROI"
$p4 += SideBar "roi"
$p4 += Sli "roi_s1" 12 80 196 80 $r "CapacityName" "$r.CapacityName"
$p4 += Crd "roi_c1" 232 76 250 90 $r "TotalEffectiveCost" 0 "Sum($r.TotalEffectiveCost)" "Effective Cost" 2
$p4 += Crd "roi_c2" 494 76 250 90 $r "TotalListCost" 0 "Sum($r.TotalListCost)" "List Price (On-Demand)" 2
$p4 += Crd "roi_c3" 756 76 250 90 $r "TotalSavings" 0 "Sum($r.TotalSavings)" "Savings" 2
$p4 += Crd "roi_c4" 1018 76 250 90 $r "SavingsPercent" 1 "Average($r.SavingsPercent)" "Savings %" 1
$p4 += CBar "roi_cb" 232 178 1036 270 $r "BillingPeriodStart" "$r.BillingPeriodStart" @(
    @{entity=$r;prop="TotalEffectiveCost";fn=0;ref="Sum($r.TotalEffectiveCost)"},
    @{entity=$r;prop="TotalListCost";fn=0;ref="Sum($r.TotalListCost)"}
) "Effective Cost vs List Price"
$p4 += Tbl "roi_tbl" 232 460 1036 250 @(
    @{entity=$r;prop="CapacityName";ref="$r.CapacityName"},
    @{entity=$r;prop="BillingPeriodStart";ref="$r.BillingPeriodStart"},
    @{entity=$r;prop="TotalEffectiveCost";ref="Sum($r.TotalEffectiveCost)";agg=0},
    @{entity=$r;prop="TotalListCost";ref="Sum($r.TotalListCost)";agg=0},
    @{entity=$r;prop="TotalSavings";ref="Sum($r.TotalSavings)";agg=0},
    @{entity=$r;prop="SavingsPercent";ref="Average($r.SavingsPercent)";agg=1}
) "Savings Detail" $r "TotalSavings"

# ── PAGE 5: Cost Trend ───────────────────────────────────
$p5 = @()
$p5 += HdrBar "ct" "Cost Trend"
$p5 += SideBar "ct"
$p5 += Sli "ct_s1" 12 80 196 80 $e "CapacityName" "$e.CapacityName"
$p5 += ColChart "ct_mo" 232 76 1036 280 $cm "BillingMonth" "$cm.BillingMonth" $cm "TotalCostWorkspace" "Sum($cm.TotalCostWorkspace)" "Monthly Cost"
$p5 += Lin "ct_daily" 232 368 520 342 $e "ChargePeriod" "$e.ChargePeriod" $e "TotalCostWorkspace" "Sum($e.TotalCostWorkspace)" "Daily Cost Trend"
$p5 += ColChart "ct_pr" 764 368 504 342 $cm "BillingMonth" "$cm.BillingMonth" $cm "TotalCostWorkspace" "Sum($cm.TotalCostWorkspace)" "Monthly by Pricing" 0 $cm "PricingCategory" "$cm.PricingCategory"

# ── PAGE 6: Item Kind Breakdown ──────────────────────────
$p6 = @()
$p6 += HdrBar "ik" "Cost by Item Kind"
$p6 += SideBar "ik"
$p6 += Sli "ik_s1" 12 80 196 80 $ik "ChargePeriod" "$ik.ChargePeriod"
$p6 += Sli "ik_s2" 12 170 196 80 $ik "WorkspaceName" "$ik.WorkspaceName"
$p6 += Crd "ik_c1" 232 76 340 90 $ik "TotalCostItemKind" 0 "Sum($ik.TotalCostItemKind)" "Total Item Kind Cost" 2
$p6 += Crd "ik_c2" 584 76 340 90 $ik "ItemKind" 5 "CountNonNull($ik.ItemKind)" "Item Kinds" 0
$p6 += Bar "ik_bar" 232 178 520 270 $ik "ItemKind" "$ik.ItemKind" $ik "TotalCostItemKind" "Sum($ik.TotalCostItemKind)" "Cost by Item Kind"
$p6 += Dnt "ik_dnt" 764 178 504 270 $ik "ItemKind" "$ik.ItemKind" $ik "TotalCostItemKind" "Sum($ik.TotalCostItemKind)" "Item Kind Share"
$p6 += Tbl "ik_tbl" 232 460 1036 250 @(
    @{entity=$ik;prop="WorkspaceName";ref="$ik.WorkspaceName"},
    @{entity=$ik;prop="ItemKind";ref="$ik.ItemKind"},
    @{entity=$ik;prop="ChargePeriod";ref="$ik.ChargePeriod"},
    @{entity=$ik;prop="TotalCostItemKind";ref="Sum($ik.TotalCostItemKind)";agg=0}
) "Item Kind Detail" $ik "TotalCostItemKind"

# ── PAGE 7: Month over Month ────────────────────────────
$p7 = @()
$p7 += HdrBar "mom" "Month-over-Month"
$p7 += SideBar "mom"
$p7 += Sli "mom_s1" 12 80 196 80 $cm "CapacityName" "$cm.CapacityName"
$p7 += Crd "mom_c1" 232 76 340 90 $cm "TotalCostWorkspace" 0 "Sum($cm.TotalCostWorkspace)" "Total Monthly Cost" 2
$p7 += Crd "mom_c2" 584 76 340 90 $cm "ReservationSavingsWorkspace" 0 "Sum($cm.ReservationSavingsWorkspace)" "Monthly Savings" 2
$p7 += Lin "mom_ln" 232 178 1036 270 $cm "BillingMonth" "$cm.BillingMonth" $cm "TotalCostWorkspace" "Sum($cm.TotalCostWorkspace)" "Monthly Cost Trend"
$p7 += CBar "mom_cb" 232 460 1036 250 $cm "BillingMonth" "$cm.BillingMonth" @(
    @{entity=$cm;prop="TotalCostWorkspace";fn=0;ref="Sum($cm.TotalCostWorkspace)"},
    @{entity=$cm;prop="ReservationSavingsWorkspace";fn=0;ref="Sum($cm.ReservationSavingsWorkspace)"}
) "Cost vs Savings by Month"

# ── PAGE 8: Monthly Cost by Workspace ────────────────────
$p8 = @()
$p8 += HdrBar "mw" "Monthly Cost by Workspace"
$p8 += SideBar "mw"
$p8 += Sli "mw_s1" 12 80 196 80 $cm "CapacityName" "$cm.CapacityName"
$p8 += Sli "mw_s2" 12 170 196 80 $cm "WorkspaceName" "$cm.WorkspaceName"

$p8 += ColChart "mw_stack" 232 76 1036 320 $cm "BillingMonth" "$cm.BillingMonth" $cm "TotalCostWorkspace" "Sum($cm.TotalCostWorkspace)" "Monthly Cost by Workspace" 0 $cm "WorkspaceName" "$cm.WorkspaceName"

$p8 += Tbl "mw_tbl" 232 408 1036 302 @(
    @{entity=$cm;prop="BillingMonth";ref="$cm.BillingMonth"},
    @{entity=$cm;prop="WorkspaceName";ref="$cm.WorkspaceName"},
    @{entity=$cm;prop="CapacityName";ref="$cm.CapacityName"},
    @{entity=$cm;prop="TotalCostWorkspace";ref="Sum($cm.TotalCostWorkspace)";agg=0},
    @{entity=$cm;prop="ReservationSavingsWorkspace";ref="Sum($cm.ReservationSavingsWorkspace)";agg=0},
    @{entity=$cm;prop="DaysWithData";ref="Sum($cm.DaysWithData)";agg=0}
) "Monthly Workspace Detail" $cm "TotalCostWorkspace"

# ══════════════════════════════════════════════════════════
# ASSEMBLE REPORT DEFINITION
# ══════════════════════════════════════════════════════════
$pbir = @{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definitionProperties/2.0.0/schema.json'
    version = '4.0'
    datasetReference = @{byConnection=@{
        connectionString = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/FCA;initial catalog=FCA_Chargeback_Model;semanticmodelid=$smId"
    }}
} | ConvertTo-Json -Depth 5

$reportJson = @{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.1.0/schema.json'
    themeCollection = @{
        baseTheme = @{
            name = "CY24SU06"
            reportVersionAtImport = @{visual="1.8.50";report="2.0.50";page="1.3.50"}
            type = "SharedResources"
        }
    }
    resourcePackages = @(@{
        name = "SharedResources"; type = "SharedResources"
        items = @(@{name="CY24SU06";path="BaseThemes/CY24SU06.json";type="BaseTheme"})
    })
    settings = @{
        hideVisualContainerHeader      = $true
        useStylableVisualContainerHeader = $true
        defaultDrillFilterOtherVisuals = $true
        allowChangeFilterTypes         = $true
        useEnhancedTooltips            = $true
    }
} | ConvertTo-Json -Depth 5

$versionJson = '{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json","version":"2.0.0"}'
$pagesJson   = @{
    '$schema'      = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.0.0/schema.json'
    pageOrder      = @("CostByWorkspace","CapacityOverview","ReservedVsOnDemand","ReservationROI","CostTrend","ItemKindBreakdown","MonthOverMonth","MonthlyByWorkspace")
    activePageName = "CostByWorkspace"
} | ConvertTo-Json -Depth 3

$pageDef = @{'$schema'=$psc; displayOption="FitToPage"; height=720; width=1280}

$pages = [ordered]@{
    CostByWorkspace    = @{dn="Cost by Workspace";     v=$p1}
    CapacityOverview   = @{dn="Capacity Overview";     v=$p2}
    ReservedVsOnDemand = @{dn="Reserved vs On-Demand"; v=$p3}
    ReservationROI     = @{dn="Reservation ROI";       v=$p4}
    CostTrend          = @{dn="Cost Trend";            v=$p5}
    ItemKindBreakdown  = @{dn="Cost by Item Kind";     v=$p6}
    MonthOverMonth     = @{dn="Month-over-Month";          v=$p7}
    MonthlyByWorkspace = @{dn="Monthly Cost by Workspace"; v=$p8}
}

$parts = @()
$parts += @{path="definition.pbir";            payload=(ToB64 $pbir);       payloadType="InlineBase64"}
$parts += @{path="definition/report.json";     payload=(ToB64 $reportJson); payloadType="InlineBase64"}
$parts += @{path="definition/version.json";    payload=(ToB64 $versionJson);payloadType="InlineBase64"}
$parts += @{path="definition/pages/pages.json";payload=(ToB64 $pagesJson); payloadType="InlineBase64"}

foreach($pgName in $pages.Keys) {
    $pg = $pages[$pgName]
    $po = $pageDef.Clone()
    $po['name']        = $pgName
    $po['displayName'] = $pg.dn
    $parts += @{path="definition/pages/$pgName/page.json"; payload=(ToB64 ($po|ConvertTo-Json -Depth 3)); payloadType="InlineBase64"}
    foreach($vis in $pg.v) {
        $vj = $vis | ConvertTo-Json -Depth 30 -Compress
        $parts += @{path="definition/pages/$pgName/visuals/$($vis.name)/visual.json"; payload=(ToB64 $vj); payloadType="InlineBase64"}
    }
}

Write-Host "Total parts: $($parts.Count)"
$body = @{definition=@{parts=$parts}} | ConvertTo-Json -Depth 30 -Compress
Write-Host "Deploying v7..."

try {
    $resp = Invoke-WebRequest -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/items/$rpId/updateDefinition" -Headers $h -Method Post -Body $body -UseBasicParsing
    Write-Host "Status: $($resp.StatusCode)"
    $opId = $resp.Headers['x-ms-operation-id']
    Write-Host "OpId: $opId"
    for($i=0; $i -lt 15; $i++){
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 5 /nobreak >nul" -Wait
        $op = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/operations/$opId" -Headers @{Authorization="Bearer $token"}
        Write-Host "Poll $i : $($op.status)"
        if($op.status -eq "Succeeded"){ Write-Host "=== V7 DEPLOYED OK ==="; break }
        if($op.status -eq "Failed"){
            Write-Host "FAILED: $($op | ConvertTo-Json -Depth 10)"
            break
        }
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    if($_.Exception.Response){
        $sr = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        Write-Host "Body: $($sr.ReadToEnd())"
    }
}

# ── SQL FIX: add ROUND() to the main view ────────────────
Write-Host "`n--- Fixing SQL view with ROUND() ---"
try {
    $sqlToken = az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv
    $sqlEndpoint = "xhlpuk7wrauudjqpiv52x4auta-5ql5umbkynqurpbzmxcxowuhza.datawarehouse.fabric.microsoft.com"
    $sqlDb = "fe90a9f8-8443-4264-a608-82fc8455581a"

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=$sqlEndpoint;Database=$sqlDb;Encrypt=True;TrustServerCertificate=False"
    $conn.AccessToken = $sqlToken
    $conn.Open()
    Write-Host "SQL connected"

    $sql = @"
CREATE OR ALTER VIEW [dbo].[v_FabricCostSplitByWorkspace] AS
SELECT
    ccp.CapacityId, ccp.CapacityName, cu.WorkspaceId, cu.WorkspaceName,
    ccp.ChargePeriod, ccp.PricingCategory,
    ccp.TotalCost AS TotalCostCapacity,
    ROUND(ccp.TotalCost * cu.TotalCUWorkspacePercCapacity, 4) AS TotalCostWorkspace,
    ROUND((ccp.TotalListCost - ccp.TotalCost) * cu.TotalCUWorkspacePercCapacity, 4) AS ReservationSavingsWorkspace,
    cu.TotalCUWorkspacePercCapacity AS CUSharePercent,
    'Allocated' AS CostCategory
FROM [dbo].[v_CapacityCostPeriod] AS ccp
JOIN [dbo].[v_WorkspacesCUConsumption] AS cu
    ON ccp.CapacityName = cu.CapacityName AND ccp.ChargePeriod = cu.DateCU
UNION ALL
SELECT
    ccp.CapacityId, ccp.CapacityName, ws.WorkspaceId, ws.WorkspaceName,
    ccp.ChargePeriod, ccp.PricingCategory,
    ccp.TotalCost AS TotalCostCapacity,
    ROUND(ccp.TotalCost * 1.0 / ccp.NbWorkspaces, 4) AS TotalCostWorkspace,
    ROUND((ccp.TotalListCost - ccp.TotalCost) * 1.0 / ccp.NbWorkspaces, 4) AS ReservationSavingsWorkspace,
    1.0 / ccp.NbWorkspaces AS CUSharePercent,
    'Even Split (No Consumption)' AS CostCategory
FROM [dbo].[v_CapacityCostPeriod] AS ccp
JOIN (SELECT DISTINCT CapacityId, WorkspaceId, WorkspaceName FROM [dbo].[FUAM_workspaces]) AS ws
    ON ccp.CapacityId = ws.CapacityId
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[v_WorkspacesCUConsumption] AS cu
    WHERE ccp.CapacityName = cu.CapacityName AND ccp.ChargePeriod = cu.DateCU
);
"@
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 120
    $cmd.ExecuteNonQuery() | Out-Null
    Write-Host "SQL view updated with ROUND()"
    $conn.Close()
} catch {
    Write-Host "SQL fix skipped: $($_.Exception.Message)"
}

Write-Host "`nDone."
