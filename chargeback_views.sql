-- =============================================================================
-- FUAM ↔ FCA Bridge: Capacity Cost Chargeback Views
-- =============================================================================
--
-- Allocates Fabric capacity costs (FCA) to workspaces by CU consumption (FUAM).
-- Supports on-demand (PAYG) and reserved capacity (RI) pricing.
--
-- CORE VIEWS (always needed):
--   1. v_CapacityCostPeriod              — Daily cost per capacity (amortized, RI-aware)
--   2. v_WorkspacesCUConsumption         — CU share % per workspace per day
--   3. v_FabricCostSplitByWorkspace      — PRIMARY: daily chargeback per workspace
--   4. v_ReservationSavingsSummary       — RI ROI per capacity per billing period
--
-- EXTENDED VIEWS (attribution & governance):
--   5. v_UnusedReservationHours          — Wasted RI hours (CommitmentDiscountStatus=Unused)
--   6. v_ItemKindCostByWorkspace         — Cost by item kind (Notebook/WH/Lakehouse/Pipeline)
--   7. v_ChargebackByDepartment          — Dept/CostCenter attribution (needs dept_mapping.sql)
--   8. v_WorkspaceCapacityChanges        — Detects mid-period workspace migrations
--
-- ANALYTICS VIEWS (finance & optimization):
--   9. v_ChargebackMonthly               — Monthly rollup for invoicing / finance systems
--  10. v_IdleCapacityWorkspaces          — Workspaces with zero CU on a capacity (waste)
--  11. v_CostEfficiency                  — Cost-per-CU efficiency score per workspace
--  12. v_BudgetTracking                  — Actual vs budget per dept (needs dept_budget table)
--
-- PREREQUISITES:
--   3 OneLake shortcuts in FCA Lakehouse:
--     FUAM_capacities, FUAM_workspaces, FUAM_capacity_metrics_by_item_kind_by_day
--   See README.md for full deployment instructions.
--
-- USAGE:
--   Run this entire script once in the FCA SQL analytics endpoint.
--   For department attribution, also run dept_mapping.sql first.
--   For budget tracking, also run dept_budget.sql first.
--
--   Quick start query:
--     SELECT * FROM [dbo].[v_FabricCostSplitByWorkspace]
--     ORDER BY ChargePeriod DESC, TotalCostWorkspace DESC
--
-- =============================================================================


-- ---------------------------------------------------------------------------
-- VIEW 1: v_CapacityCostPeriod
-- Daily cost per capacity from Azure billing (FCA) joined with FUAM metadata
-- Uses EffectiveCost for proper reservation amortization
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_CapacityCostPeriod] AS
SELECT 
    cap.CapacityId,
    res.ResourceName                        AS CapacityName,
    cost.BillingPeriodStart,
    cost.ChargePeriodStart                  AS ChargePeriod,
    -- EffectiveCost: amortized for reserved, same as BilledCost for on-demand
    SUM(cost.EffectiveCost)                 AS TotalCost,
    -- Keep BilledCost for reference (shows actual invoice amount)
    SUM(cost.BilledCost)                    AS TotalBilledCost,
    -- List cost (on-demand price) to calculate savings from reservations
    SUM(cost.ListCost)                      AS TotalListCost,
    -- Pricing breakdown
    cost.PricingCategory,                   -- 'On-Demand' or 'Commitment-Based'
    ws_count.NbWorkspaces
FROM [dbo].[focus_fabric]          AS cost
JOIN [dbo].[resources]             AS res       ON cost.ResourceKey = res.ResourceKey
JOIN [dbo].[FUAM_capacities]       AS cap       ON res.ResourceName = cap.displayName
JOIN (
    SELECT CapacityId,
           APPROX_COUNT_DISTINCT(WorkspaceId) AS NbWorkspaces
    FROM [dbo].[FUAM_workspaces]
    GROUP BY CapacityId
)                                  AS ws_count  ON cap.CapacityId = ws_count.CapacityId
GROUP BY 
    cap.CapacityId,
    res.ResourceName,
    cost.BillingPeriodStart,
    cost.ChargePeriodStart,
    cost.PricingCategory,
    ws_count.NbWorkspaces;
GO


-- ---------------------------------------------------------------------------
-- VIEW 2: v_WorkspacesCUConsumption
-- CU consumption percentage per workspace within each capacity per day
-- Supports F SKUs (paid), P SKUs (Premium), and reserved capacities
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_WorkspacesCUConsumption] AS
SELECT 
    CapacityId,
    CapacityName,
    WorkspaceId,
    WorkspaceName,
    DateCU,
    sku,
    SumCUWorkspace,
    SUM(SumCUWorkspace) OVER (
        PARTITION BY CapacityId, CapacityName, DateCU
    ) AS TotalWorkspaceCUCapacity,
    CASE 
        WHEN SUM(SumCUWorkspace) OVER (PARTITION BY CapacityId, CapacityName, DateCU) = 0 
        THEN 0
        ELSE SumCUWorkspace / SUM(SumCUWorkspace) OVER (
            PARTITION BY CapacityId, CapacityName, DateCU
        )
    END AS TotalCUWorkspacePercCapacity
FROM (
    SELECT 
        cap.CapacityId,
        cap.displayName                     AS CapacityName,
        usage.WorkspaceId,
        ws.WorkspaceName,
        usage.Date                          AS DateCU,
        cap.sku,
        SUM(usage.TotalCUs)                 AS SumCUWorkspace
    FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day] AS usage
    JOIN [dbo].[FUAM_workspaces]       AS ws   ON usage.WorkspaceId = ws.WorkspaceId
    JOIN [dbo].[FUAM_capacities]       AS cap  ON usage.CapacityId  = cap.CapacityId
    WHERE (
        -- Fabric paid SKUs (F2, F4, ... F2048) — excludes Trial (FT*)
        (cap.sku LIKE 'F%' AND cap.sku NOT LIKE 'FT%')
        -- Power BI Premium SKUs (P1-P5)
        OR cap.sku LIKE 'P%'
    )
    GROUP BY 
        cap.CapacityId,
        cap.displayName,
        usage.WorkspaceId,
        ws.WorkspaceName,
        usage.Date,
        cap.sku
) AS TotalCU;
GO


-- ---------------------------------------------------------------------------
-- VIEW 3: v_FabricCostSplitByWorkspace  (FINAL OUTPUT)
-- Chargeback = Capacity daily cost × workspace CU share
-- Supports on-demand AND reserved capacity (uses amortized EffectiveCost)
-- When no CU consumption exists for a day, cost is split evenly across
-- all workspaces attached to that capacity
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_FabricCostSplitByWorkspace] AS

-- Allocated: cost proportioned by workspace CU consumption
SELECT 
    ccp.CapacityId,
    ccp.CapacityName,
    cu.WorkspaceId,
    cu.WorkspaceName,
    ccp.ChargePeriod,
    ccp.PricingCategory,                                    -- 'On-Demand' or 'Commitment-Based'
    ccp.TotalCost                                           AS TotalCostCapacity,
    ccp.TotalCost * cu.TotalCUWorkspacePercCapacity         AS TotalCostWorkspace,
    -- Reservation savings: what it would have cost on-demand minus what it actually costs
    (ccp.TotalListCost - ccp.TotalCost) 
        * cu.TotalCUWorkspacePercCapacity                   AS ReservationSavingsWorkspace,
    cu.TotalCUWorkspacePercCapacity                         AS CUSharePercent,
    'Allocated'                                             AS CostCategory
FROM [dbo].[v_CapacityCostPeriod]       AS ccp
JOIN [dbo].[v_WorkspacesCUConsumption]  AS cu
    ON ccp.CapacityName = cu.CapacityName
   AND ccp.ChargePeriod = cu.DateCU

UNION ALL

-- No consumption: cost split evenly across all workspaces attached to the capacity
SELECT 
    ccp.CapacityId,
    ccp.CapacityName,
    ws.WorkspaceId,
    ws.WorkspaceName,
    ccp.ChargePeriod,
    ccp.PricingCategory,
    ccp.TotalCost                                           AS TotalCostCapacity,
    ccp.TotalCost * 1.0 / ccp.NbWorkspaces                 AS TotalCostWorkspace,
    (ccp.TotalListCost - ccp.TotalCost) 
        * 1.0 / ccp.NbWorkspaces                           AS ReservationSavingsWorkspace,
    1.0 / ccp.NbWorkspaces                                  AS CUSharePercent,
    'Even Split (No Consumption)'                           AS CostCategory
FROM [dbo].[v_CapacityCostPeriod] AS ccp
JOIN (
    -- Deduplicate: one row per workspace per capacity
    SELECT DISTINCT CapacityId, WorkspaceId, WorkspaceName
    FROM [dbo].[FUAM_workspaces]
)                                 AS ws
    ON ccp.CapacityId = ws.CapacityId
WHERE NOT EXISTS (
    SELECT 1 
    FROM [dbo].[v_WorkspacesCUConsumption] AS cu
    WHERE ccp.CapacityName = cu.CapacityName
      AND ccp.ChargePeriod = cu.DateCU
);
GO


-- ---------------------------------------------------------------------------
-- VIEW 4: v_ReservationSavingsSummary  (OPTIONAL)
-- Shows reservation savings vs on-demand pricing per capacity per period
-- Useful for justifying reservation purchases
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_ReservationSavingsSummary] AS
SELECT 
    CapacityId,
    CapacityName,
    BillingPeriodStart,
    PricingCategory,
    SUM(TotalCost)                                          AS TotalEffectiveCost,
    SUM(TotalBilledCost)                                    AS TotalBilledCost,
    SUM(TotalListCost)                                      AS TotalListCost,
    SUM(TotalListCost) - SUM(TotalCost)                     AS TotalSavings,
    CASE 
        WHEN SUM(TotalListCost) = 0 THEN 0
        ELSE (SUM(TotalListCost) - SUM(TotalCost)) / SUM(TotalListCost)
    END                                                     AS SavingsPercent
FROM [dbo].[v_CapacityCostPeriod]
GROUP BY 
    CapacityId,
    CapacityName,
    BillingPeriodStart,
    PricingCategory;
GO


-- ---------------------------------------------------------------------------
-- VIEW 5: v_UnusedReservationHours  (Phase 2.3)
-- Surfaces capacity reservation hours where no workload ran (pure waste).
-- Requires focus_fabric to expose CommitmentDiscountStatus column (FOCUS 1.0+).
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_UnusedReservationHours] AS
SELECT
    cap.CapacityId,
    res.ResourceName                            AS CapacityName,
    cost.ChargePeriodStart                      AS ChargePeriod,
    cost.BillingPeriodStart,
    SUM(cost.EffectiveCost)                     AS UnusedReservationCost,
    SUM(cost.ListCost)                          AS UnusedListCost,
    SUM(cost.ListCost) - SUM(cost.EffectiveCost) AS UnusedOpportunityCost,
    COUNT(*)                                    AS UnusedLineItems
FROM [dbo].[focus_fabric]           AS cost
JOIN [dbo].[resources]              AS res  ON cost.ResourceKey = res.ResourceKey
JOIN [dbo].[FUAM_capacities]        AS cap  ON res.ResourceName = cap.displayName
WHERE cost.CommitmentDiscountStatus = 'Unused'
GROUP BY
    cap.CapacityId,
    res.ResourceName,
    cost.ChargePeriodStart,
    cost.BillingPeriodStart;
GO


-- ---------------------------------------------------------------------------
-- VIEW 6: v_ItemKindCostByWorkspace  (Phase 4.4)
-- Breaks workspace chargeback down by Fabric item kind
-- (Notebook, Warehouse, Lakehouse, Pipeline, etc.).
-- Uses the ItemKind dimension already present in
-- capacity_metrics_by_item_kind_by_day.
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_ItemKindCostByWorkspace] AS

-- Allocated: cost pro-rated by CU%, then split by ItemKind share within workspace/day
SELECT
    ccp.CapacityId,
    ccp.CapacityName,
    ik.WorkspaceId,
    ik.WorkspaceName,
    ik.ItemKind,
    ccp.ChargePeriod,
    ccp.PricingCategory,
    ccp.TotalCost                                                   AS TotalCostCapacity,
    -- Workspace cost × ItemKind share within the workspace that day
    ccp.TotalCost
        * CASE
            WHEN cap_total.TotalCapacityCU = 0 THEN 0
            ELSE ik.ItemKindCU / cap_total.TotalCapacityCU
          END                                                       AS TotalCostItemKind,
    CASE
        WHEN cap_total.TotalCapacityCU = 0 THEN 0
        ELSE ik.ItemKindCU / cap_total.TotalCapacityCU
    END                                                             AS ItemKindCUSharePercent
FROM [dbo].[v_CapacityCostPeriod]    AS ccp

-- Per-workspace-per-itemkind CU for that day
JOIN (
    SELECT
        cap.CapacityId,
        cap.displayName                 AS CapacityName,
        usage.WorkspaceId,
        ws.WorkspaceName,
        usage.ItemKind,
        usage.Date                      AS ChargePeriod,
        SUM(usage.TotalCUs)             AS ItemKindCU
    FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day] AS usage
    JOIN [dbo].[FUAM_workspaces]   AS ws  ON usage.WorkspaceId = ws.WorkspaceId
    JOIN [dbo].[FUAM_capacities]   AS cap ON usage.CapacityId  = cap.CapacityId
    WHERE (cap.sku LIKE 'F%' AND cap.sku NOT LIKE 'FT%')
       OR cap.sku LIKE 'P%'
    GROUP BY
        cap.CapacityId, cap.displayName,
        usage.WorkspaceId, ws.WorkspaceName,
        usage.ItemKind, usage.Date
)                                    AS ik
    ON ccp.CapacityName = ik.CapacityName
   AND ccp.ChargePeriod = ik.ChargePeriod

-- Total CU for the whole capacity that day (denominator)
JOIN (
    SELECT
        cap.CapacityId,
        usage.Date                      AS ChargePeriod,
        SUM(usage.TotalCUs)             AS TotalCapacityCU
    FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day] AS usage
    JOIN [dbo].[FUAM_capacities]   AS cap ON usage.CapacityId = cap.CapacityId
    WHERE (cap.sku LIKE 'F%' AND cap.sku NOT LIKE 'FT%')
       OR cap.sku LIKE 'P%'
    GROUP BY cap.CapacityId, usage.Date
)                                    AS cap_total
    ON ccp.CapacityId = cap_total.CapacityId
   AND ccp.ChargePeriod = cap_total.ChargePeriod;
GO


-- ---------------------------------------------------------------------------
-- VIEW 7: v_ChargebackByDepartment  (Phase 2.1)
-- Joins chargeback output with the dept_workspace_mapping reference table
-- to aggregate cost by Department and CostCenter.
-- Create the reference table first: see dept_mapping.sql
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_ChargebackByDepartment] AS
SELECT
    cb.CapacityId,
    cb.CapacityName,
    cb.WorkspaceId,
    cb.WorkspaceName,
    COALESCE(dm.Department, 'Unassigned')       AS Department,
    COALESCE(dm.CostCenter, 'Unassigned')       AS CostCenter,
    COALESCE(dm.Owner, 'Unassigned')            AS Owner,
    cb.ChargePeriod,
    cb.PricingCategory,
    cb.CostCategory,
    cb.TotalCostCapacity,
    cb.TotalCostWorkspace,
    cb.ReservationSavingsWorkspace,
    cb.CUSharePercent
FROM [dbo].[v_FabricCostSplitByWorkspace]   AS cb
LEFT JOIN [dbo].[dept_workspace_mapping]    AS dm
    ON cb.WorkspaceId = dm.WorkspaceId;
GO


-- ---------------------------------------------------------------------------
-- VIEW 8: v_WorkspaceCapacityChanges  (Phase 2.4)
-- Detects workspaces that appeared on more than one capacity within the same
-- billing period. Useful for identifying mid-period migrations and auditing
-- potential double-counting in chargeback rows.
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_WorkspaceCapacityChanges] AS
WITH WorkspaceCapacityPerDay AS (
    SELECT
        usage.WorkspaceId,
        ws.WorkspaceName,
        usage.CapacityId,
        cap.displayName                         AS CapacityName,
        cap.sku,
        usage.Date                              AS DateCU,
        -- Derive billing period from the date (first day of month)
        DATEFROMPARTS(YEAR(usage.Date), MONTH(usage.Date), 1) AS BillingPeriodStart
    FROM [dbo].[FUAM_capacity_metrics_by_item_kind_by_day] AS usage
    JOIN [dbo].[FUAM_workspaces]       AS ws  ON usage.WorkspaceId = ws.WorkspaceId
    JOIN [dbo].[FUAM_capacities]       AS cap ON usage.CapacityId  = cap.CapacityId
    WHERE (cap.sku LIKE 'F%' AND cap.sku NOT LIKE 'FT%')
       OR cap.sku LIKE 'P%'
),
WorkspaceCapacityCount AS (
    SELECT
        WorkspaceId,
        WorkspaceName,
        BillingPeriodStart,
        COUNT(DISTINCT CapacityId)              AS DistinctCapacityCount,
        MIN(DateCU)                             AS FirstDay,
        MAX(DateCU)                             AS LastDay
    FROM WorkspaceCapacityPerDay
    GROUP BY WorkspaceId, WorkspaceName, BillingPeriodStart
)
SELECT
    wcc.WorkspaceId,
    wcc.WorkspaceName,
    wcc.BillingPeriodStart,
    wcc.DistinctCapacityCount,
    wcc.FirstDay,
    wcc.LastDay,
    -- Pivot: list all capacity names the workspace appeared on that period
    STRING_AGG(DISTINCT wcd.CapacityName, ' → ')
        WITHIN GROUP (ORDER BY wcd.CapacityName)    AS CapacitiesInPeriod,
    CASE
        WHEN wcc.DistinctCapacityCount > 1
        THEN 'Migration detected'
        ELSE 'Stable'
    END                                             AS MigrationStatus
FROM WorkspaceCapacityCount AS wcc
JOIN WorkspaceCapacityPerDay AS wcd
    ON wcc.WorkspaceId      = wcd.WorkspaceId
   AND wcc.BillingPeriodStart = wcd.BillingPeriodStart
GROUP BY
    wcc.WorkspaceId,
    wcc.WorkspaceName,
    wcc.BillingPeriodStart,
    wcc.DistinctCapacityCount,
    wcc.FirstDay,
    wcc.LastDay;
GO


-- ---------------------------------------------------------------------------
-- VIEW 9: v_ChargebackMonthly  (Analytics A)
-- Monthly rollup of workspace chargeback — one row per workspace per month.
-- Use as the base for Month-over-Month trend reports.
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_ChargebackMonthly] AS
SELECT
    CapacityId,
    CapacityName,
    WorkspaceId,
    WorkspaceName,
    DATEFROMPARTS(YEAR(ChargePeriod), MONTH(ChargePeriod), 1)   AS BillingMonth,
    PricingCategory,
    CostCategory,
    SUM(TotalCostCapacity)                                      AS TotalCostCapacity,
    SUM(TotalCostWorkspace)                                     AS TotalCostWorkspace,
    SUM(ReservationSavingsWorkspace)                            AS ReservationSavingsWorkspace,
    AVG(CUSharePercent)                                         AS AvgCUSharePercent,
    COUNT(DISTINCT ChargePeriod)                                AS DaysWithData
FROM [dbo].[v_FabricCostSplitByWorkspace]
GROUP BY
    CapacityId,
    CapacityName,
    WorkspaceId,
    WorkspaceName,
    DATEFROMPARTS(YEAR(ChargePeriod), MONTH(ChargePeriod), 1),
    PricingCategory,
    CostCategory;
GO


-- ---------------------------------------------------------------------------
-- VIEW 10: v_IdleCapacityWorkspaces  (Analytics B)
-- Identifies workspaces attached to a capacity on a given day but with zero
-- CU consumption — those days are "idle" but still incur a cost share via
-- the even-split fallback in v_FabricCostSplitByWorkspace.
-- Useful for rightsizing and Fabric governance reports.
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_IdleCapacityWorkspaces] AS
SELECT
    ccp.CapacityId,
    ccp.CapacityName,
    ws.WorkspaceId,
    ws.WorkspaceName,
    ccp.ChargePeriod,
    ccp.PricingCategory,
    -- Each idle workspace absorbs an equal share of the capacity daily cost
    ccp.TotalCost * 1.0 / ccp.NbWorkspaces         AS IdleCostAllocation,
    ccp.NbWorkspaces
FROM [dbo].[v_CapacityCostPeriod] AS ccp
JOIN (
    -- Deduplicate: one row per workspace per capacity
    SELECT DISTINCT CapacityId, WorkspaceId, WorkspaceName
    FROM [dbo].[FUAM_workspaces]
)                                 AS ws
    ON ccp.CapacityId = ws.CapacityId
WHERE NOT EXISTS (
    -- Workspace had no CU consumption on this day → it is "idle"
    SELECT 1
    FROM [dbo].[v_WorkspacesCUConsumption] AS cu
    WHERE ccp.CapacityName  = cu.CapacityName
      AND ccp.ChargePeriod  = cu.DateCU
      AND cu.WorkspaceId    = ws.WorkspaceId
);
GO


-- ---------------------------------------------------------------------------
-- VIEW 11: v_CostEfficiency  (Analytics C)
-- Cost-per-CU-percentage per workspace per month.
-- Lower values = more efficient use of reserved / on-demand capacity.
-- Excludes even-split rows (CostCategory = 'Even Split (No Consumption)').
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_CostEfficiency] AS
SELECT
    CapacityId,
    CapacityName,
    WorkspaceId,
    WorkspaceName,
    DATEFROMPARTS(YEAR(ChargePeriod), MONTH(ChargePeriod), 1)   AS BillingMonth,
    SUM(TotalCostWorkspace)                                     AS TotalCost,
    AVG(CUSharePercent)                                         AS AvgCUShare,
    -- Cost per 1% of CU capacity → lower = more efficient
    CASE
        WHEN AVG(CUSharePercent) = 0 THEN NULL
        ELSE SUM(TotalCostWorkspace) / AVG(CUSharePercent)
    END                                                         AS CostPerCUPercent
FROM [dbo].[v_FabricCostSplitByWorkspace]
WHERE CostCategory = 'Allocated'
GROUP BY
    CapacityId,
    CapacityName,
    WorkspaceId,
    WorkspaceName,
    DATEFROMPARTS(YEAR(ChargePeriod), MONTH(ChargePeriod), 1);
GO


-- ---------------------------------------------------------------------------
-- VIEW 12: v_BudgetTracking  (Analytics E)
-- Compares actual monthly department chargeback against a budget table.
-- Requires dept_budget table (see dept_budget.sql).
-- BudgetVariance > 0 means over-budget; < 0 means under-budget.
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW [dbo].[v_BudgetTracking] AS
SELECT
    cb.Department,
    cb.CostCenter,
    DATEFROMPARTS(YEAR(cb.ChargePeriod), MONTH(cb.ChargePeriod), 1)  AS BillingMonth,
    SUM(cb.TotalCostWorkspace)                                        AS ActualCost,
    MAX(b.MonthlyBudgetUSD)                                           AS BudgetAmount,
    SUM(cb.TotalCostWorkspace) - MAX(b.MonthlyBudgetUSD)              AS BudgetVariance,
    CASE
        WHEN MAX(b.MonthlyBudgetUSD) = 0 OR MAX(b.MonthlyBudgetUSD) IS NULL THEN NULL
        ELSE SUM(cb.TotalCostWorkspace) / MAX(b.MonthlyBudgetUSD)
    END                                                               AS BudgetUtilization
FROM [dbo].[v_ChargebackByDepartment]   AS cb
LEFT JOIN [dbo].[dept_budget]           AS b
    ON  cb.Department   = b.Department
    AND cb.CostCenter   = b.CostCenter
    AND DATEFROMPARTS(YEAR(cb.ChargePeriod), MONTH(cb.ChargePeriod), 1) = b.BudgetMonth
GROUP BY
    cb.Department,
    cb.CostCenter,
    DATEFROMPARTS(YEAR(cb.ChargePeriod), MONTH(cb.ChargePeriod), 1);
GO
