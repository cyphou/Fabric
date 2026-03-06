# FUAM ↔ FCA Bridge — Fabric Capacity Cost Chargeback

## Overview

This solution allocates Microsoft Fabric capacity costs (from **FCA**) to individual workspaces based on actual CU consumption (from **FUAM**). It uses **OneLake shortcuts + SQL views + a Power BI report** — no notebooks, no Python, no scheduled pipelines.

Supports **on-demand (PAYG)** and **reserved capacity (RI)** pricing.

| Component | Role |
|-----------|------|
| **FUAM** (Fabric Unified Admin Monitoring) | Capacity metrics, workspace metadata, per-workspace CU consumption |
| **FCA** (Fabric Cost Analysis) | Azure billing data in FOCUS format (costs, resources, billing periods) |
| **Bridge** | 3 OneLake shortcuts + 4 SQL views + 1 Power BI report (PBIR) |

---

## Architecture

```
┌──────────────────────────┐       ┌──────────────────────────┐
│       FUAM Lakehouse     │       │       FCA Lakehouse      │
│                          │       │                          │
│  Tables:                 │       │  Tables:                 │
│  • capacities            │       │  • focus_fabric          │
│  • workspaces            │       │  • resources             │
│  • capacity_metrics_     │       │                          │
│    by_item_kind_by_day   │       │                          │
└────────────┬─────────────┘       └──────────┬───────────────┘
             │ OneLake Shortcuts              │ Native tables
             │ (created once in UI)           │
             ▼                                ▼
     ┌───────────────────────────────────────────────────┐
     │            FCA Lakehouse                          │
     │                                                   │
     │  Shortcuts (read-only, live):                     │
     │   FUAM_capacities                                 │
     │   FUAM_workspaces                                 │
     │   FUAM_capacity_metrics_by_item_kind_by_day       │
     │                                                   │
     │  SQL Views (created once via SQL endpoint):       │
     │   v_CapacityCostPeriod ──┐                        │
     │   v_WorkspacesCUConsumption ──┤                   │
     │                              ▼                    │
     │   v_FabricCostSplitByWorkspace (FINAL)            │
     │   v_ReservationSavingsSummary (RI analysis)       │
     │                                                   │
     └───────────────────┬──────────────┬────────────────┘
                         │              │
            DirectLake / SQL endpoint   │ XMLA live connection
                         │              │
                         ▼              ▼
     ┌───────────────────────────────────────────────────┐
     │      FCA_Chargeback_Report (Power BI — PBIR)     │
     │                                                   │
     │  Page 1: Cost by Workspace (main chargeback)      │
     │  Page 2: Capacity Overview                        │
     │  Page 3: Reserved vs On-Demand                    │
     │  Page 4: Reservation ROI                          │
     │  Page 5: Cost Trend                               │
     └───────────────────────────────────────────────────┘
```

---

## Prerequisites

Before deploying, confirm the following are in place:

| # | Prerequisite | How to verify |
|---|-------------|---------------|
| 1 | **FUAM Lakehouse** is deployed and populated | Open FUAM workspace → Lakehouse → verify `capacities`, `workspaces`, `capacity_metrics_by_item_kind_by_day` tables have data |
| 2 | **FCA Lakehouse** is deployed and populated | Open FCA workspace → Lakehouse → verify `focus_fabric` and `resources` tables have data |
| 3 | **SQL analytics endpoint** enabled on FCA Lakehouse | In FCA Lakehouse, click the SQL analytics endpoint dropdown — it should be accessible |
| 4 | **Power BI Desktop** (June 2024 or later) | Required for opening the `.pbip` report file; PBIR v4.0 format requires recent builds |
| 5 | **Permissions** | Read access to FUAM Lakehouse tables; Read + Write access to FCA Lakehouse + SQL endpoint |

---

## Deployment Guide

### Step 1: Create OneLake Shortcuts (one-time)

Open the **FCA Lakehouse** in Fabric → **Get data** → **New shortcut** → **Microsoft OneLake**.

Create these 3 shortcuts:

| # | Source (FUAM Lakehouse) | Shortcut Name in FCA | Target Path |
|---|------------------------|---------------------|-------------|
| 1 | `capacities` table | `FUAM_capacities` | Tables/dbo |
| 2 | `workspaces` table | `FUAM_workspaces` | Tables/dbo |
| 3 | `capacity_metrics_by_item_kind_by_day` table | `FUAM_capacity_metrics_by_item_kind_by_day` | Tables/dbo |

> **Tip**: Browse to FUAM workspace → FUAM Lakehouse → Tables → select the table. Name it with the `FUAM_` prefix.

**Validation**: After creating shortcuts, open the FCA Lakehouse SQL analytics endpoint and run:
```sql
SELECT TOP 5 * FROM [dbo].[FUAM_capacities];
SELECT TOP 5 * FROM [dbo].[FUAM_workspaces];
SELECT TOP 5 * FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day];
```
All three queries must return data.

### Step 2: Create SQL Views (one-time)

1. Open the **FCA Lakehouse SQL analytics endpoint**
2. Click **New SQL query**
3. Paste the full contents of `chargeback_views.sql`
4. Click **Run**

The 4 views are created immediately. No refresh or scheduling needed.

**Validation**: Run the following and verify results:
```sql
SELECT TOP 10 * FROM [dbo].[v_FabricCostSplitByWorkspace]
ORDER BY ChargePeriod DESC, TotalCostWorkspace DESC;
```

### Step 3: Configure the Power BI Report

The report is provided in **PBIR format** (folder-based). Before opening it in Power BI Desktop, you must update the connection settings.

1. Open `FCA_Chargeback_Report.Report/definition.pbir` in a text editor
2. Replace the 3 placeholders with your actual FCA Lakehouse values:

| Placeholder | Replace with | Where to find it |
|-------------|-------------|-------------------|
| `<YOUR_FCA_SQL_ENDPOINT>` | FCA SQL analytics endpoint URL | FCA Lakehouse → Settings → SQL analytics endpoint → copy the connection string |
| `<YOUR_FCA_LAKEHOUSE>` | FCA Lakehouse name | The display name of your FCA Lakehouse (e.g., `FCA_Lakehouse`) |
| `<YOUR_FCA_LAKEHOUSE_GUID>` | FCA Lakehouse GUID | FCA Lakehouse → Settings → About → copy the Lakehouse ID |

Example of a configured `definition.pbir`:
```json
{
  "version": "4.0",
  "datasetReference": {
    "byPath": null,
    "byConnection": {
      "connectionString": "Data Source=x]x]x]x]xxxx.datawarehouse.fabric.microsoft.com;Initial Catalog=FCA_Lakehouse",
      "pbiServiceModelId": null,
      "pbiModelVirtualServerName": "sobe_wowvirtualserver",
      "pbiModelDatabaseName": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "EntityDataSource",
      "connectionType": "pbiServiceXmlaStyleLive"
    }
  }
}
```

3. Open `FCA_Chargeback_Report.pbip` in **Power BI Desktop**
4. When prompted, sign in with your Fabric credentials
5. The report connects live to the FCA SQL analytics endpoint — no import or refresh needed

### Step 4: Publish to Fabric (optional)

1. In Power BI Desktop, click **Publish**
2. Select the target workspace (e.g., the FCA workspace)
3. The report is now available in the Fabric portal for all authorized users

---

## Benefits

| Benefit | Detail |
|---------|--------|
| **No code** | No notebook, no Python, no `semantic-link-labs` dependency |
| **No scheduling** | Shortcuts are live pointers — data is always current |
| **No refresh** | SQL views compute on read — always up to date |
| **Reusable** | Same SQL script works on any tenant — create shortcuts + run SQL |
| **Portable** | One `.sql` file + one `.pbip` project to version control and share |
| **5-minute setup** | 3 shortcuts + paste SQL + update 3 placeholders |

---

## SQL Views Reference

### `v_CapacityCostPeriod`
Joins FCA billing data with FUAM capacity metadata to get **daily cost per capacity**.

```
focus_fabric (costs) → resources (Azure resource name) → FUAM_capacities (capacity ID)
```

**Reserved capacity handling** — uses `EffectiveCost` (amortized) instead of `BilledCost`:
- **On-demand**: `EffectiveCost` = `BilledCost` (no difference)
- **Reserved**: `EffectiveCost` = daily amortized portion of the reservation purchase
- Exposes `ListCost` (on-demand list price) to calculate reservation savings
- Groups by `PricingCategory` (`On-Demand` vs `Commitment-Based`)

### `v_WorkspacesCUConsumption`
Calculates each workspace's **share of CU consumption** within its capacity per day.

```
WorkspaceCU% = WorkspaceCUs / SUM(AllWorkspaceCUs) per capacity per day
```

- Supports **F SKUs** (paid Fabric) and **P SKUs** (Power BI Premium)
- Excludes Trial SKUs (`FT*`)
- Handles division by zero (0 CU → 0%)

### `v_FabricCostSplitByWorkspace` *(primary output)*
Multiplies capacity cost by workspace CU share → **chargeback amount**.

```
TotalCostWorkspace      = TotalCostCapacity × WorkspaceCU%
ReservationSavings      = (ListCost - EffectiveCost) × WorkspaceCU%
```

- **Allocated** rows: cost proportioned by actual workspace consumption
- **Even Split** rows: when no CU consumption exists for a day, cost is divided evenly across all workspaces on that capacity
- `PricingCategory`: distinguishes `On-Demand` vs `Commitment-Based` (reserved)
- `ReservationSavingsWorkspace`: per-workspace savings from reservations

### `v_ReservationSavingsSummary`
Aggregated view for **reservation ROI analysis** per capacity per billing period.

- Compares `EffectiveCost` (what you pay) vs `ListCost` (what you'd pay on-demand)
- Shows `SavingsPercent` to justify reservation purchases
- Used by the **Reservation ROI** report page

---

## Output Schema — `v_FabricCostSplitByWorkspace`

| Column | Type | Description |
|--------|------|-------------|
| `CapacityId` | string | FUAM capacity identifier |
| `CapacityName` | string | Azure resource name / FUAM display name |
| `WorkspaceId` | string | FUAM workspace identifier (NULL for even-split rows) |
| `WorkspaceName` | string | Workspace display name |
| `ChargePeriod` | date | Day of the cost charge |
| `PricingCategory` | string | `On-Demand` or `Commitment-Based` |
| `TotalCostCapacity` | decimal | Total amortized cost for that capacity on that day |
| `TotalCostWorkspace` | decimal | **Chargeback amount** for that workspace |
| `ReservationSavingsWorkspace` | decimal | Savings vs on-demand price for that workspace |
| `CUSharePercent` | decimal | Workspace's share of capacity CU (0–1) |
| `CostCategory` | string | `Allocated` or `Even Split (No Consumption)` |

---

## Power BI Report — Pages & Visuals

The `FCA_Chargeback_Report` is a 5-page PBIR report connected live to the FCA SQL analytics endpoint.

| Page | Data Source View | Key Visuals |
|------|-----------------|-------------|
| **Cost by Workspace** | `v_FabricCostSplitByWorkspace` | KPI cards (total cost, savings, workspace count, capacity count), bar chart by workspace, detail table, slicers (capacity, date range, pricing category) |
| **Capacity Overview** | `v_CapacityCostPeriod` | Stacked bar chart (cost by capacity with cost category), donut chart (allocated vs even split), capacity detail table |
| **Reserved vs On-Demand** | `v_FabricCostSplitByWorkspace` | On-demand / reserved / savings KPI cards, donut by pricing category, savings by workspace bar chart, pricing detail table |
| **Reservation ROI** | `v_ReservationSavingsSummary` | Effective cost / list cost / savings / savings % KPI cards, clustered column chart (effective vs list by capacity), summary table, capacity slicer |
| **Cost Trend** | `v_FabricCostSplitByWorkspace` | Daily cost line chart by workspace, line chart by pricing category, line chart by capacity |

---

## File Structure

```
FUAM_FCA_Bridge/
├── README.md                                          ← This document
├── chargeback_views.sql                               ← SQL views (run once in FCA SQL endpoint)
├── FCA_Chargeback_Report.pbip                         ← Power BI project entry point
└── FCA_Chargeback_Report.Report/                      ← PBIR report folder
    ├── .platform                                      ← Fabric metadata (type, display name)
    ├── definition.pbir                                ← Data source connection (update placeholders!)
    └── definition/
        ├── report.json                                ← Report-level settings & theme
        ├── version.json                               ← PBIR schema version
        └── pages/
            ├── pages.json                             ← Page ordering
            ├── CostByWorkspace/                       ← Page 1 (10 visuals)
            │   ├── page.json
            │   └── visuals/
            ├── CapacityOverview/                       ← Page 2 (4 visuals)
            │   ├── page.json
            │   └── visuals/
            ├── ReservedVsOnDemand/                     ← Page 3 (7 visuals)
            │   ├── page.json
            │   └── visuals/
            ├── ReservationROI/                         ← Page 4 (8 visuals)
            │   ├── page.json
            │   └── visuals/
            └── CostTrend/                              ← Page 5 (4 visuals)
                ├── page.json
                └── visuals/
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| SQL views fail to create | Shortcuts not yet created, or named differently | Verify shortcut names are exactly `FUAM_capacities`, `FUAM_workspaces`, `FUAM_capacity_metrics_by_item_kind_by_day` |
| `v_FabricCostSplitByWorkspace` returns 0 rows | No overlapping date range between FCA billing data and FUAM metrics | Check `SELECT DISTINCT ChargePeriodStart FROM focus_fabric` vs `SELECT DISTINCT Date FROM FUAM_capacity_metrics_by_item_kind_by_day` — they must overlap |
| `v_CapacityCostPeriod` returns 0 rows | `ResourceName` in FCA doesn't match `displayName` in FUAM | Run `SELECT DISTINCT ResourceName FROM resources` and `SELECT DISTINCT displayName FROM FUAM_capacities` — values must match |
| Report shows "Unable to connect" in PBI Desktop | Placeholders not replaced in `definition.pbir` | Open `definition.pbir` and verify all 3 placeholders are replaced with actual values (see Step 3) |
| Report shows no data but connection works | SQL views exist but return empty results | Run the validation query from Step 2; troubleshoot the SQL layer first |
| Even Split rows dominate | Workspaces have no CU consumption for those days | Expected for idle days; filter on `CostCategory = 'Allocated'` to see only consumption-based rows |
| Trial capacity (FT SKU) not shown | By design — trial SKUs are excluded | The `v_WorkspacesCUConsumption` view explicitly filters out `FT*` SKUs |

---

## Known Limitations

| # | Limitation | Mitigation |
|---|-----------|------------|
| 1 | **No user-level cost split** | Join with FUAM user activity tables for per-user allocation |
| 2 | **No department / cost center mapping** | Add a reference table mapping `WorkspaceId → Department / CostCenter` and join in a new view |
| 3 | **Workspace capacity migration** | A workspace moving between capacities mid-period may double-count on the migration day |
| 4 | **Unused reservation hours** | FCA exposes `CommitmentDiscountStatus = 'Unused'` — a dedicated waste-analysis view could be added |

---

## References

- [Fabric Unified Admin Monitoring (FUAM)](https://learn.microsoft.com/fabric/admin/monitoring/)
- [Fabric Cost Analysis (FCA)](https://learn.microsoft.com/fabric/governance/)
- [FOCUS Cost Standard](https://focus.finops.org/)
- [Power BI PBIR format](https://learn.microsoft.com/power-bi/developer/projects/projects-report)
- [Original notebook](https://github.com/cyphou/Fabric)
