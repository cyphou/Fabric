# FUAM ↔ FCA Bridge — Fabric Capacity Cost Chargeback

## Overview

This solution allocates Microsoft Fabric capacity costs (from **FCA**) to individual workspaces based on actual CU consumption (from **FUAM**). It uses **OneLake shortcuts + SQL views + a Power BI report** — no orchestration required by default, with an optional Fabric Pipeline for automated exports.

Supports **on-demand (PAYG)** and **reserved capacity (RI/Commitment-Based)** pricing.

| Component | Role |
|-----------|------|
| **FUAM** (Fabric Unified Admin Monitoring) | Capacity metrics, workspace metadata, per-workspace CU consumption |
| **FCA** (Fabric Cost Analysis) | Azure billing data in FOCUS format (costs, resources, billing periods) |
| **Bridge** | 3 OneLake shortcuts + 8 SQL views + 1 Power BI report (PBIR, 7 pages) |
| **Optional** | Notebook (automated deployment), Fabric Pipeline (exports), Semantic Model (TMDL) |

---

## Architecture

```
┌──────────────────────────┐       ┌──────────────────────────┐
│       FUAM Lakehouse     │       │       FCA Lakehouse      │
│  Tables:                 │       │  Tables:                 │
│  • capacities            │       │  • focus_fabric          │
│  • workspaces            │       │  • resources             │
│  • capacity_metrics_     │       │  • dept_workspace_mapping│
│    by_item_kind_by_day   │       │    (reference — manual)  │
└────────────┬─────────────┘       └──────────┬───────────────┘
             │ OneLake Shortcuts (3)          │ Native tables
             ▼                                ▼
     ┌───────────────────────────────────────────────────────────┐
     │            FCA Lakehouse SQL Analytics Endpoint           │
     │                                                           │
     │  Core views (always current — no refresh):                │
     │   v_CapacityCostPeriod          (daily cost per capacity) │
     │   v_WorkspacesCUConsumption     (CU share per workspace)  │
     │   v_FabricCostSplitByWorkspace  ← PRIMARY OUTPUT          │
     │   v_ReservationSavingsSummary   (RI ROI per period)       │
     │                                                           │
     │  Extended views:                                          │
     │   v_UnusedReservationHours      (wasted RI spend)         │
     │   v_ItemKindCostByWorkspace     (Notebook/WH/LH/Pipeline) │
     │   v_ChargebackByDepartment      (Dept + CostCenter)       │
     │   v_WorkspaceCapacityChanges    (migration detection)     │
     └──────────────┬────────────────────────────┬──────────────┘
                    │                            │
          SQL endpoint (DirectQuery)             │ Export (optional)
                    │                            ▼
                    │              ┌─────────────────────────────┐
                    │              │  FCA_Chargeback_Pipeline     │
                    │              │  (Fabric Data Pipeline)      │
                    │              │  → chargeback_export_daily   │
                    │              │  → reservation_roi_export    │
                    │              │  → dept_chargeback_export    │
                    │              └─────────────────────────────┘
                    ▼
     ┌───────────────────────────────────────────────────────────┐
     │      FCA_Chargeback_Report (Power BI — PBIR, 7 pages)    │
     │  OR  FCA_Chargeback_Model  (Semantic Model — TMDL)        │
     └───────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| # | Prerequisite | How to verify |
|---|-------------|---------------|
| 1 | **FUAM Lakehouse** deployed and populated | Workspace → Lakehouse → verify `capacities`, `workspaces`, `capacity_metrics_by_item_kind_by_day` have data |
| 2 | **FCA Lakehouse** deployed and populated | Workspace → Lakehouse → verify `focus_fabric` and `resources` have data |
| 3 | **SQL analytics endpoint** on FCA Lakehouse | FCA Lakehouse → SQL analytics endpoint dropdown is accessible |
| 4 | **Power BI Desktop** (June 2024+) | Required for PBIR v4.0 format |
| 5 | **Permissions** | Read on FUAM; Read+Write on FCA Lakehouse + SQL endpoint |

---

## Deployment Guide

### Option A — Manual (5 minutes, no dependencies)

**Step 1: Create OneLake Shortcuts** (one-time, in FCA Lakehouse UI)

FCA Lakehouse → **Get data** → **New shortcut** → **Microsoft OneLake**

| # | Source (FUAM Lakehouse) | Shortcut Name in FCA |
|---|------------------------|---------------------|
| 1 | `capacities` | `FUAM_capacities` |
| 2 | `workspaces` | `FUAM_workspaces` |
| 3 | `capacity_metrics_by_item_kind_by_day` | `FUAM_capacity_metrics_by_item_kind_by_day` |

**Validation:**
```sql
SELECT TOP 5 * FROM [dbo].[FUAM_capacities];
SELECT TOP 5 * FROM [dbo].[FUAM_workspaces];
SELECT TOP 5 * FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day];
```

**Step 2: Create SQL Views** (one-time, in FCA SQL analytics endpoint)

1. Open FCA Lakehouse → SQL analytics endpoint → **New SQL query**
2. Paste `chargeback_views.sql` → **Run**
3. Optionally paste `dept_mapping.sql` → **Run** (for department attribution)

**Validation:**
```sql
SELECT TOP 10 * FROM [dbo].[v_FabricCostSplitByWorkspace]
ORDER BY ChargePeriod DESC, TotalCostWorkspace DESC;
```

**Step 3: Configure the Power BI Report**

1. Open `FCA_Chargeback_Report.Report/definition.pbir` and replace the 3 placeholders:

| Placeholder | Value to use | Where to find it |
|-------------|-------------|------------------|
| `<YOUR_FCA_SQL_ENDPOINT>` | FCA SQL endpoint URL | FCA Lakehouse → Settings → SQL endpoint → connection string |
| `<YOUR_FCA_LAKEHOUSE>` | FCA Lakehouse display name | e.g. `FCA_Lakehouse` |
| `<YOUR_FCA_LAKEHOUSE_GUID>` | FCA Lakehouse item ID | FCA Lakehouse → Settings → About → Lakehouse ID |

2. Open `FCA_Chargeback_Report.pbip` in Power BI Desktop → sign in → report connects live (no import/refresh)

---

### Option B — Automated Notebook (recommended for first setup)

Run `FCA_Chargeback_Addon_FUAM.ipynb` in Fabric:

1. Edit the **Parameters** cell: set `source_lakehouse`, `source_workspace`, `destination_lakehouse`, `destination_workspace`
2. Optionally set `BUDGET_ALERT_DAILY_USD` for cost threshold alerts
3. Run all cells — shortcuts + all 7 views are created automatically
4. The final **Validation** cell previews results and runs 5 health checks

---

### Option C — Fabric Pipeline (scheduled / automated exports)

Import `FCA_Chargeback_Pipeline.DataPipeline/` into your FCA workspace:

1. In Fabric: **+ New** → **Import** → upload the `.DataPipeline` folder
2. Edit `pipeline-content.json` to replace `<REPLACE_WITH_NOTEBOOK_ITEM_ID>` and `<REPLACE_WITH_FCA_WORKSPACE_ID>`
3. Schedule the pipeline (e.g. daily after FCA billing refresh)

The pipeline runs the notebook, exports 3 views to Delta tables, and validates row counts.

---

### Department Attribution (optional)

1. Run `dept_mapping.sql` in the FCA SQL endpoint to create the `dept_workspace_mapping` table
2. Populate it with your `WorkspaceId → Department / CostCenter / Owner` mappings
3. The `v_ChargebackByDepartment` view will automatically join and expose the enriched data
4. Use the **Cost by Department** report page for cost centre reporting

---

## SQL Views Reference

| View | Phase | Purpose |
|------|-------|---------|
| `v_CapacityCostPeriod` | Core | Daily amortized cost per capacity (EffectiveCost + ListCost, PricingCategory) |
| `v_WorkspacesCUConsumption` | Core | CU share % per workspace per day (F + P SKUs, div-by-zero safe) |
| `v_FabricCostSplitByWorkspace` | Core — **PRIMARY OUTPUT** | Chargeback = cost × CU% per workspace; fallback to even split |
| `v_ReservationSavingsSummary` | Core | RI ROI: EffectiveCost vs ListCost per capacity per billing period |
| `v_UnusedReservationHours` | Extended | Wasted reservation hours where no workload ran (`CommitmentDiscountStatus = 'Unused'`) |
| `v_ItemKindCostByWorkspace` | Extended | Cost split by Fabric item kind (Notebook, Warehouse, Lakehouse, Pipeline…) |
| `v_ChargebackByDepartment` | Extended | Workspace chargeback enriched with Department, CostCenter, Owner |
| `v_WorkspaceCapacityChanges` | Extended | Detects workspaces that moved between capacities within a billing period |
| `v_ChargebackMonthly` | Analytics | Monthly rollup of workspace chargeback — base for MoM trend reports |
| `v_IdleCapacityWorkspaces` | Analytics | Workspaces attached to a capacity with zero CU consumption (idle cost allocation) |
| `v_CostEfficiency` | Analytics | Cost-per-CU-percent per workspace per month (lower = more efficient) |
| `v_BudgetTracking` | Analytics | Actual vs budget variance by department per month (requires `dept_budget.sql`) |

---

## Output Schema — `v_FabricCostSplitByWorkspace`

| Column | Type | Description |
|--------|------|-------------|
| `CapacityId` | string | FUAM capacity identifier |
| `CapacityName` | string | Azure resource name / FUAM display name |
| `WorkspaceId` | string | FUAM workspace identifier |
| `WorkspaceName` | string | Workspace display name |
| `ChargePeriod` | date | Day of the cost charge |
| `PricingCategory` | string | `On-Demand` or `Commitment-Based` |
| `TotalCostCapacity` | decimal | Total amortized cost for that capacity on that day |
| `TotalCostWorkspace` | decimal | **Chargeback amount** for that workspace |
| `ReservationSavingsWorkspace` | decimal | Savings vs on-demand price for that workspace |
| `CUSharePercent` | decimal | Workspace's share of capacity CU (0–1) |
| `CostCategory` | string | `Allocated` or `Even Split (No Consumption)` |

---

## Power BI Report — 8 Pages

| Page | View | Key Visuals |
|------|------|-------------|
| **Cost by Workspace** | `v_FabricCostSplitByWorkspace` | KPI cards, bar by workspace, detail table, capacity/date/pricing slicers |
| **Capacity Overview** | `v_FabricCostSplitByWorkspace` | Stacked bar by capacity, donut (Allocated vs Even Split), capacity table |
| **Reserved vs On-Demand** | `v_FabricCostSplitByWorkspace` | On-demand / reserved / savings KPIs, donut by pricing, savings bar |
| **Reservation ROI** | `v_ReservationSavingsSummary` | EffectiveCost / ListCost / Savings / Savings% KPIs, clustered bar, summary table |
| **Cost Trend** | `v_FabricCostSplitByWorkspace` | Daily line by workspace, by pricing category, by capacity |
| **Cost by Item Kind** | `v_ItemKindCostByWorkspace` | Cost bar by item kind, donut share, detail table, workspace/date slicers |
| **Cost by Department** | `v_ChargebackByDepartment` | Cost bar by department (with pricing series), donut share, detail table with Owner |
| **Month-over-Month** | `v_ChargebackMonthly` | Monthly trend line by workspace, MoM clustered bar, total cost/savings KPI cards |

---

## File Structure

```
FUAM_FCA_Bridge/
│
├── README.md                                     ← This document
├── WORKFLOW_AND_PLAN.md                          ← Detailed workflow, architecture, roadmap
│
├── chargeback_views.sql                          ← 12 SQL views (run once in FCA SQL endpoint)
├── dept_mapping.sql                              ← dept_workspace_mapping DDL + sample data
├── dept_budget.sql                               ← dept_budget DDL + sample data (budget tracking)
├── FCA_Chargeback_Addon_FUAM.ipynb               ← Automated deployment notebook (sempy-labs)
│
├── FCA_Chargeback_Report.pbip                    ← Power BI project entry point
└── FCA_Chargeback_Report.Report/                 ← PBIR report folder (8 pages)
│   ├── definition.pbir                           ← Data source connection (update 3 placeholders)
│   └── definition/
│       └── pages/
│           ├── CostByWorkspace/                  ← Page 1 (10 visuals)
│           ├── CapacityOverview/                  ← Page 2 (4 visuals)
│           ├── ReservedVsOnDemand/                ← Page 3 (7 visuals)
│           ├── ReservationROI/                    ← Page 4 (8 visuals)
│           ├── CostTrend/                         ← Page 5 (4 visuals)
│           ├── ItemKindBreakdown/                 ← Page 6 (7 visuals)
            ├── DepartmentChargeback/              ← Page 7 (7 visuals)
            └── MonthOverMonth/                    ← Page 8 (6 visuals)
│
├── FCA_Chargeback_Pipeline.DataPipeline/         ← Fabric Data Pipeline (optional)
│   ├── .platform                                 ← Fabric item metadata
│   └── pipeline-content.json                     ← ADF-style pipeline: notebook → export → validate
│
└── FCA_Chargeback_Model.SemanticModel/           ← DirectQuery semantic model (optional)
    ├── .platform                                 ← Fabric item metadata
    └── definition/
        ├── model.tmdl                            ← Model-level settings
        ├── relationships.tmdl                    ← Cross-table relationship definitions
        ├── expressions.tmdl                      ← Shared FCA_SQL_Endpoint data source (single placeholder)
        ├── cultures/en-US.tmdl
        └── tables/
            ├── v_FabricCostSplitByWorkspace.tmdl ← Fact + 6 measures
            ├── v_ReservationSavingsSummary.tmdl  ← RI ROI + 4 measures
            ├── v_ItemKindCostByWorkspace.tmdl    ← Item kind + 3 measures
            ├── v_ChargebackByDepartment.tmdl     ← Dept chargeback + 4 measures
            └── dept_workspace_mapping.tmdl       ← Dimension table
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| SQL views fail to create | Shortcuts not created or named differently | Verify names are exactly `FUAM_capacities`, `FUAM_workspaces`, `FUAM_capacity_metrics_by_item_kind_by_day` |
| `v_FabricCostSplitByWorkspace` returns 0 rows | No overlapping date range between FCA billing and FUAM metrics | `SELECT DISTINCT ChargePeriodStart FROM focus_fabric` vs `SELECT DISTINCT Date FROM FUAM_capacity_metrics_by_item_kind_by_day` — must overlap |
| `v_CapacityCostPeriod` returns 0 rows | `ResourceName` in FCA ≠ `displayName` in FUAM | `SELECT DISTINCT ResourceName FROM resources` vs `SELECT DISTINCT displayName FROM FUAM_capacities` — must match |
| `v_UnusedReservationHours` returns 0 rows | `CommitmentDiscountStatus` column missing | FOCUS 1.0+ required; check with `SELECT TOP 1 CommitmentDiscountStatus FROM focus_fabric` |
| Report shows "Unable to connect" | Placeholders not replaced in `definition.pbir` | Replace all 3 placeholders with actual FCA values (see Step 3) |
| Even Split rows dominate | Workspaces have no CU consumption for those days | Expected for idle days; filter `CostCategory = 'Allocated'` for consumption-based rows only |
| `v_ChargebackByDepartment` shows only 'Unassigned' | `dept_workspace_mapping` table is empty or not created | Run `dept_mapping.sql` and populate with actual WorkspaceId values from `FUAM_workspaces` |
| Trial capacity not shown | By design | `FT*` SKUs are excluded in `v_WorkspacesCUConsumption` |
| P SKU workspaces missing | SKU filter issue | `v_WorkspacesCUConsumption` supports `P1–P5` via `LIKE 'P%'` — verify SKU column in `FUAM_capacities` |

---

## References

- [Fabric Unified Admin Monitoring (FUAM)](https://learn.microsoft.com/fabric/admin/monitoring/)
- [Fabric Cost Analysis (FCA)](https://learn.microsoft.com/fabric/governance/)
- [FOCUS Cost Standard](https://focus.finops.org/)
- [Power BI PBIR format](https://learn.microsoft.com/power-bi/developer/projects/projects-report)
- [TMDL semantic model format](https://learn.microsoft.com/analysis-services/tmdl/tmdl-overview)
- [Fabric Data Pipeline](https://learn.microsoft.com/fabric/data-factory/data-factory-overview)
- [Original notebook inspiration](https://github.com/cyphou/Fabric)


