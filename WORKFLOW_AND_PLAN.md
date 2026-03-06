# FUAM ↔ FCA Bridge — Chargeback Workflow & Plan

## Executive Summary

**Goal**: Allocate Microsoft Fabric capacity costs (from **FCA**) to individual workspaces based on actual CU consumption (from **FUAM**).

**Approach**: **Shortcuts + SQL Views only** — no notebook, no Python, no dependencies.

**Supports**: On-demand (PAYG) **and** reserved capacity (RI) pricing.

| Component | Role |
|-----------|------|
| **FUAM** (Fabric Unified Admin Monitoring) | Capacity metrics, workspace metadata, per-workspace CU consumption |
| **FCA** (Fabric Cost Analysis) | Azure billing data in FOCUS format (costs, resources, billing periods) |
| **Bridge** | 3 OneLake shortcuts + 4 SQL views — all created once, no refresh needed |

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
     └───────────────────────┬───────────────────────────┘
                             │ DirectLake / SQL endpoint
                             ▼
     ┌───────────────────────────────────────────────────┐
     │           Power BI Chargeback Report              │
     └───────────────────────────────────────────────────┘
```

---

## Why This Approach?

| Benefit | Detail |
|---------|--------|
| **No code** | No notebook, no Python, no `semantic-link-labs` dependency |
| **No scheduling** | Shortcuts are live pointers — data is always current |
| **No refresh** | SQL views compute on read — always up to date |
| **Reusable** | Same SQL script works on any tenant. Just create shortcuts + run SQL |
| **Portable** | One `.sql` file to version control and share |
| **5-minute setup** | 3 clicks for shortcuts + paste SQL |

---

## Setup Steps

### Step 1: Create OneLake Shortcuts (one-time, in FCA Lakehouse UI)

Open the **FCA Lakehouse** in Fabric → click **Get data** → **New shortcut** → **Microsoft OneLake**.

Create these 3 shortcuts:

| # | Source (FUAM Lakehouse) | Shortcut Name in FCA | Target Path |
|---|------------------------|---------------------|-------------|
| 1 | `capacities` table | `FUAM_capacities` | Tables/dbo |
| 2 | `workspaces` table | `FUAM_workspaces` | Tables/dbo |
| 3 | `capacity_metrics_by_item_kind_by_day` table | `FUAM_capacity_metrics_by_item_kind_by_day` | Tables/dbo |

> **Tip**: When creating each shortcut, browse to the FUAM workspace → FUAM Lakehouse → Tables → select the table. Name it with the `FUAM_` prefix.

### Step 2: Create SQL Views (one-time, in FCA SQL analytics endpoint)

1. Open the **FCA Lakehouse SQL analytics endpoint** 
2. Click **New SQL query**
3. Paste the contents of `chargeback_views.sql`
4. Click **Run**

That's it. The 3 views are created and ready.

### Step 3: Query Your Chargeback Data

```sql
SELECT * FROM [dbo].[v_FabricCostSplitByWorkspace]
ORDER BY ChargePeriod DESC, TotalCostWorkspace DESC
```

---

## SQL Views — What They Do

### `v_CapacityCostPeriod`
Joins FCA billing data with FUAM capacity metadata to get **daily cost per capacity**.

```
focus_fabric (costs) → resources (Azure resource name) → FUAM_capacities (capacity ID)
```

**Reserved capacity handling**: Uses `EffectiveCost` (amortized) instead of `BilledCost`:
- **On-demand**: `EffectiveCost` = `BilledCost` (no difference)
- **Reserved**: `EffectiveCost` = daily amortized portion of the reservation purchase
- Also exposes `ListCost` (on-demand list price) to calculate reservation savings
- Groups by `PricingCategory` (`On-Demand` vs `Commitment-Based`)

### `v_WorkspacesCUConsumption`
Calculates each workspace's **share of CU consumption** within its capacity per day.

```
Formula: WorkspaceCU% = WorkspaceCUs / SUM(AllWorkspaceCUs) per capacity per day
```

- Supports **F SKUs** (paid Fabric) and **P SKUs** (Power BI Premium)
- Excludes Trial SKUs (`FT*`)
- Handles division by zero (0 CU → 0%)

### `v_FabricCostSplitByWorkspace` (FINAL)
Multiplies capacity cost by workspace CU share → **chargeback amount**.

```
Formula: TotalCostWorkspace = TotalCostCapacity × WorkspaceCU%
         ReservationSavings = (ListCost - EffectiveCost) × WorkspaceCU%
```

- **Allocated** rows: cost proportioned by actual workspace consumption
- **Even Split** rows: when no CU consumption exists for a day, cost is divided evenly across all workspaces attached to that capacity
- `PricingCategory` column: distinguishes `On-Demand` vs `Commitment-Based` (reserved)
- `ReservationSavingsWorkspace`: shows how much each workspace saves thanks to reservations

### `v_ReservationSavingsSummary` (OPTIONAL)
Aggregated view for **reservation ROI analysis** per capacity per billing period.

- Compares `EffectiveCost` (what you pay) vs `ListCost` (what you'd pay on-demand)
- Shows `SavingsPercent` to justify reservation purchases
- Useful for FinOps reporting and capacity planning

---

## Output Schema (`v_FabricCostSplitByWorkspace`)

| Column | Type | Description |
|--------|------|-------------|
| `CapacityId` | string | FUAM capacity identifier |
| `CapacityName` | string | Azure resource name / FUAM display name |
| `WorkspaceId` | string | FUAM workspace identifier (NULL for unallocated) |
| `WorkspaceName` | string | Workspace name (or `** Unallocated (Idle Capacity)`) |
| `ChargePeriod` | date | Day of the cost charge |
| `PricingCategory` | string | `On-Demand` or `Commitment-Based` (reserved) |
| `TotalCostCapacity` | decimal | Total amortized cost for that capacity on that day |
| `TotalCostWorkspace` | decimal | **Chargeback amount** for that workspace |
| `ReservationSavingsWorkspace` | decimal | Savings vs. on-demand price for that workspace |
| `CUSharePercent` | decimal | Workspace's share of capacity CU (0–1) |
| `CostCategory` | string | `Allocated` or `Even Split (No Consumption)` |

---

## File Structure

```
FUAM_FCA_Bridge/
├── WORKFLOW_AND_PLAN.md       ← This document
└── chargeback_views.sql       ← SQL views to run once in FCA SQL endpoint
```

---

## Known Limitations & Future Improvements

| # | Gap | Workaround / Future Enhancement |
|---|-----|--------------------------------|
| 1 | **No user-level split** | Join with FUAM user activity tables for per-user cost |
| 2 | **No department mapping** | Add a reference table `WorkspaceId → Department / CostCenter` |
| 3 | **Workspace capacity migration** | A workspace moving between capacities mid-period may double-count |
| 4 | **Unused reservation hours** | FCA tracks `CommitmentDiscountStatus` = `Unused` — could add a dedicated view for waste analysis |

---

## Power BI Report (Recommended)

Connect a Power BI report to the **FCA SQL analytics endpoint** using DirectLake mode:

- **Page 1 — Cost by Workspace**: Table/bar chart of `TotalCostWorkspace` by workspace, filterable by capacity, date, and `PricingCategory`
- **Page 2 — Capacity Overview**: Total cost vs. allocated vs. unallocated per capacity
- **Page 3 — Reserved vs On-Demand**: Breakdown by `PricingCategory`, show `ReservationSavingsWorkspace` to highlight RI value
- **Page 4 — Reservation ROI**: Use `v_ReservationSavingsSummary` to show savings % and justify reservation purchases
- **Page 5 — Trend**: Line chart of workspace costs over time, sliced by pricing category

---

## References

- [Fabric Unified Admin Monitoring (FUAM)](https://learn.microsoft.com/fabric/admin/monitoring/)
- [Fabric Cost Analysis (FCA)](https://learn.microsoft.com/fabric/governance/)
- [FOCUS Cost Standard](https://focus.finops.org/)
- [Original notebook](https://github.com/cyphou/Fabric)
