-- =============================================================================
-- FUAM ↔ FCA Bridge: Department / Cost Center Mapping
-- =============================================================================
--
-- Reference table that maps each workspace to a Department, CostCenter,
-- and Owner for chargeback attribution (Phase 2.1).
--
-- USAGE:
--   1. Run this script once in the FCA Lakehouse SQL analytics endpoint.
--   2. Populate the table with your workspace-to-department mappings.
--   3. The view v_ChargebackByDepartment (in chargeback_views.sql) will
--      automatically join against this table.
--
-- MAINTENANCE:
--   - Add / update rows as workspaces are created or re-assigned.
--   - WorkspaceId must match the FUAM_workspaces.WorkspaceId value exactly.
--   - Workspaces with no mapping row will appear as 'Unassigned'.
--
-- =============================================================================


-- ---------------------------------------------------------------------------
-- TABLE: dept_workspace_mapping
-- One row per workspace. Workspaces not present default to 'Unassigned'.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS [dbo].[dept_workspace_mapping] (
    WorkspaceId     VARCHAR(255)    NOT NULL,   -- FUAM workspace GUID
    WorkspaceName   VARCHAR(512)    NULL,        -- Optional: for readability
    Department      VARCHAR(255)    NOT NULL,    -- e.g. 'Finance', 'Engineering'
    CostCenter      VARCHAR(100)    NOT NULL,    -- e.g. 'CC-1042'
    Owner           VARCHAR(255)    NULL,        -- e.g. 'alice@contoso.com'
    Notes           VARCHAR(1000)   NULL,
    UpdatedAt       DATE            NULL,
    CONSTRAINT pk_dept_mapping PRIMARY KEY (WorkspaceId)
);
GO


-- ---------------------------------------------------------------------------
-- SAMPLE DATA — replace with your actual mappings
-- ---------------------------------------------------------------------------
--
-- Example: find WorkspaceId from FUAM_workspaces:
--   SELECT WorkspaceId, WorkspaceName FROM [dbo].[FUAM_workspaces]
--

INSERT INTO [dbo].[dept_workspace_mapping]
    (WorkspaceId, WorkspaceName, Department, CostCenter, Owner, UpdatedAt)
VALUES
    -- Replace these GUIDs with real workspace IDs from FUAM_workspaces
    ('00000000-0000-0000-0000-000000000001', 'Finance Analytics', 'Finance',       'CC-1001', 'finance-lead@contoso.com', GETDATE()),
    ('00000000-0000-0000-0000-000000000002', 'HR Reporting',      'Human Resources','CC-1002', 'hr-lead@contoso.com',      GETDATE()),
    ('00000000-0000-0000-0000-000000000003', 'Sales Dashboard',   'Sales',          'CC-1003', 'sales-lead@contoso.com',   GETDATE()),
    ('00000000-0000-0000-0000-000000000004', 'Data Engineering',  'IT',             'CC-2001', 'de-lead@contoso.com',      GETDATE()),
    ('00000000-0000-0000-0000-000000000005', 'Platform Dev',      'IT',             'CC-2001', 'platform@contoso.com',     GETDATE());
GO


-- ---------------------------------------------------------------------------
-- VALIDATION: verify mapping coverage
-- Run after populating to see which workspaces lack a department mapping.
-- ---------------------------------------------------------------------------
SELECT
    ws.WorkspaceId,
    ws.WorkspaceName,
    dm.Department,
    dm.CostCenter,
    dm.Owner,
    CASE WHEN dm.WorkspaceId IS NULL THEN 'Missing mapping' ELSE 'OK' END AS MappingStatus
FROM [dbo].[FUAM_workspaces]            AS ws
LEFT JOIN [dbo].[dept_workspace_mapping] AS dm ON ws.WorkspaceId = dm.WorkspaceId
ORDER BY MappingStatus DESC, ws.WorkspaceName;
GO
