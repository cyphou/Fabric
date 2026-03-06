-- =============================================================================
-- FUAM ↔ FCA Bridge: Chargeback SQL Views
-- =============================================================================
-- 
-- PURPOSE: Allocate Fabric capacity costs to workspaces based on CU consumption
--          Supports BOTH on-demand (PAYG) and reserved capacity (RI) pricing
-- 
-- RESERVED CAPACITY HANDLING:
--   - Uses EffectiveCost (amortized) instead of BilledCost
--     → Reservation purchase cost is spread evenly across the term
--     → On-demand: EffectiveCost = BilledCost (no difference)
--     → Reserved:  EffectiveCost = daily amortized portion of the reservation
--   - Exposes PricingCategory: 'On-Demand' vs 'Commitment-Based' (reserved)
--   - CommitmentDiscountStatus tracks 'Used' vs 'Unused' reservation hours
--
-- PREREQUISITES:
--   1. Create 3 OneLake shortcuts in FCA Lakehouse (one-time, via UI):
--      - FUAM_capacities       → points to FUAM Lakehouse / capacities
--      - FUAM_workspaces       → points to FUAM Lakehouse / workspaces
--      - FUAM_capacity_metrics_by_item_kind_by_day 
--                              → points to FUAM Lakehouse / capacity_metrics_by_item_kind_by_day
--   2. Run these CREATE VIEW statements in the FCA Lakehouse SQL analytics endpoint
--
-- RESULT: Query v_FabricCostSplitByWorkspace for daily workspace cost breakdown
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
