-- =============================================================================
-- dept_budget.sql
-- Department Monthly Budget Reference Table
-- FCA Chargeback Addon for FUAM — Budget Tracking Support
--
-- PURPOSE:
--   This table stores monthly budget allocations by Department / CostCenter.
--   It feeds the v_BudgetTracking view, which computes actual-vs-budget
--   variance and utilization per department per month.
--
-- PREREQUISITES:
--   Run dept_mapping.sql first to ensure Department and CostCenter values
--   are consistent with the dept_workspace_mapping table.
--
-- USAGE:
--   1. Run this script once in the FCA SQL analytics endpoint.
--   2. Insert or update rows to reflect your actual budget allocations.
--   3. Query v_BudgetTracking to see actuals vs. budgets.
--
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Step 1: Create the reference table (idempotent via IF NOT EXISTS pattern)
-- ---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1
    FROM   sys.tables
    WHERE  name = 'dept_budget'
      AND  SCHEMA_NAME(schema_id) = 'dbo'
)
BEGIN
    CREATE TABLE [dbo].[dept_budget] (
        -- Which department / cost centre this budget row covers
        Department          NVARCHAR(200)   NOT NULL,
        CostCenter          NVARCHAR(100)   NOT NULL,
        -- First day of the month this budget applies to (e.g. 2025-01-01)
        BudgetMonth         DATE            NOT NULL,
        -- Monthly budget in USD
        MonthlyBudgetUSD    DECIMAL(18, 2)  NOT NULL,
        -- Optional free-text annotation (e.g. "Q1 approved budget")
        Notes               NVARCHAR(500)   NULL,
        CONSTRAINT PK_dept_budget PRIMARY KEY (Department, CostCenter, BudgetMonth)
    );
END;
GO


-- ---------------------------------------------------------------------------
-- Step 2: Sample budget rows — edit to match your actual departments
--         These mirror the sample rows in dept_mapping.sql
-- ---------------------------------------------------------------------------
-- Remove existing samples before re-inserting (safe for re-runs)
DELETE FROM [dbo].[dept_budget]
WHERE Department IN ('Engineering', 'Finance', 'Marketing', 'Data Platform');
GO

INSERT INTO [dbo].[dept_budget] (Department, CostCenter, BudgetMonth, MonthlyBudgetUSD, Notes)
VALUES
    -- Engineering has a $5 000 / month Fabric capacity budget
    ('Engineering',    'CC-001', '2025-01-01', 5000.00, 'FY2025 Q1 approved'),
    ('Engineering',    'CC-001', '2025-02-01', 5000.00, 'FY2025 Q1 approved'),
    ('Engineering',    'CC-001', '2025-03-01', 5000.00, 'FY2025 Q1 approved'),
    ('Engineering',    'CC-001', '2025-04-01', 5500.00, 'FY2025 Q2 uplift'),

    -- Finance allocated $2 000 / month
    ('Finance',        'CC-002', '2025-01-01', 2000.00, 'FY2025 Q1 approved'),
    ('Finance',        'CC-002', '2025-02-01', 2000.00, 'FY2025 Q1 approved'),
    ('Finance',        'CC-002', '2025-03-01', 2000.00, 'FY2025 Q1 approved'),
    ('Finance',        'CC-002', '2025-04-01', 2000.00, 'FY2025 Q2 same'),

    -- Marketing smaller allocation
    ('Marketing',      'CC-003', '2025-01-01', 1500.00, 'FY2025 Q1 approved'),
    ('Marketing',      'CC-003', '2025-02-01', 1500.00, 'FY2025 Q1 approved'),
    ('Marketing',      'CC-003', '2025-03-01', 1500.00, 'FY2025 Q1 approved'),
    ('Marketing',      'CC-003', '2025-04-01', 1800.00, 'FY2025 Q2 campaign uplift'),

    -- Data Platform team (shared platform cost)
    ('Data Platform',  'CC-004', '2025-01-01', 8000.00, 'FY2025 Q1 approved'),
    ('Data Platform',  'CC-004', '2025-02-01', 8000.00, 'FY2025 Q1 approved'),
    ('Data Platform',  'CC-004', '2025-03-01', 8000.00, 'FY2025 Q1 approved'),
    ('Data Platform',  'CC-004', '2025-04-01', 8500.00, 'FY2025 Q2 expansion');
GO


-- ---------------------------------------------------------------------------
-- Step 3: Validation — preview budget tracking results
-- ---------------------------------------------------------------------------
SELECT
    Department,
    CostCenter,
    BillingMonth,
    ActualCost,
    BudgetAmount,
    BudgetVariance,
    CAST(BudgetUtilization * 100 AS DECIMAL(5,1))   AS BudgetUtilizationPct
FROM [dbo].[v_BudgetTracking]
ORDER BY Department, CostCenter, BillingMonth;
GO

-- Quick summary: departments currently over budget
SELECT Department, CostCenter, BillingMonth, BudgetVariance
FROM   [dbo].[v_BudgetTracking]
WHERE  BudgetVariance > 0
ORDER  BY BudgetVariance DESC;
GO
