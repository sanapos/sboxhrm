-- Seed RolePermissions for BusinessTripExpense / BusinessTripReport on all stores
-- that already have AdvanceRequests (same finance family).
WITH perm AS (
  SELECT "Id" FROM "Permissions" WHERE "Module" = 'BusinessTripExpense' LIMIT 1
),
report_perm AS (
  SELECT "Id" FROM "Permissions" WHERE "Module" = 'BusinessTripReport' LIMIT 1
),
stores AS (
  SELECT DISTINCT rp."StoreId"
  FROM "RolePermissions" rp
  JOIN "Permissions" p ON p."Id" = rp."PermissionId"
  WHERE p."Module" = 'AdvanceRequests' AND rp."StoreId" IS NOT NULL
  UNION
  SELECT DISTINCT "StoreId" FROM "BusinessTripCases" WHERE "StoreId" IS NOT NULL
  UNION
  SELECT DISTINCT "StoreId" FROM "BusinessTripExpenseCategories" WHERE "StoreId" IS NOT NULL
),
role_defs(role_name, role_display, can_view, can_create, can_edit, can_delete, can_export, can_approve) AS (
  VALUES
    ('Admin', 'Quản trị viên', true, true, true, true, true, true),
    ('Director', 'Giám đốc', true, true, true, true, true, true),
    ('Manager', 'Quản lý', true, true, true, true, true, true),
    ('Accountant', 'Kế toán', true, true, true, true, true, true),
    ('DepartmentHead', 'Trưởng phòng', true, true, true, false, false, true),
    ('Employee', 'Nhân viên', true, true, false, false, false, false)
)
INSERT INTO "RolePermissions" (
  "Id", "RoleName", "RoleDisplayName", "PermissionId", "StoreId",
  "CanView", "CanCreate", "CanEdit", "CanDelete", "CanExport", "CanApprove",
  "IsActive", "CreatedAt"
)
SELECT gen_random_uuid(), d.role_name, d.role_display, perm."Id", s."StoreId",
       d.can_view, d.can_create, d.can_edit, d.can_delete, d.can_export, d.can_approve,
       true, NOW()
FROM stores s
CROSS JOIN perm
CROSS JOIN role_defs d
WHERE NOT EXISTS (
  SELECT 1 FROM "RolePermissions" rp
  WHERE rp."StoreId" = s."StoreId"
    AND rp."PermissionId" = perm."Id"
    AND rp."RoleName" = d.role_name
);

-- Report module: view/export for manager+ roles
WITH report_perm AS (
  SELECT "Id" FROM "Permissions" WHERE "Module" = 'BusinessTripReport' LIMIT 1
),
stores AS (
  SELECT DISTINCT rp."StoreId"
  FROM "RolePermissions" rp
  JOIN "Permissions" p ON p."Id" = rp."PermissionId"
  WHERE p."Module" = 'BusinessTripExpense' AND rp."StoreId" IS NOT NULL
),
role_defs(role_name, role_display, can_view, can_export) AS (
  VALUES
    ('Admin', 'Quản trị viên', true, true),
    ('Director', 'Giám đốc', true, true),
    ('Manager', 'Quản lý', true, true),
    ('Accountant', 'Kế toán', true, true),
    ('DepartmentHead', 'Trưởng phòng', true, false),
    ('Employee', 'Nhân viên', true, false)
)
INSERT INTO "RolePermissions" (
  "Id", "RoleName", "RoleDisplayName", "PermissionId", "StoreId",
  "CanView", "CanCreate", "CanEdit", "CanDelete", "CanExport", "CanApprove",
  "IsActive", "CreatedAt"
)
SELECT gen_random_uuid(), d.role_name, d.role_display, report_perm."Id", s."StoreId",
       d.can_view, false, false, false, d.can_export, false,
       true, NOW()
FROM stores s
CROSS JOIN report_perm
CROSS JOIN role_defs d
WHERE NOT EXISTS (
  SELECT 1 FROM "RolePermissions" rp
  WHERE rp."StoreId" = s."StoreId"
    AND rp."PermissionId" = report_perm."Id"
    AND rp."RoleName" = d.role_name
);

-- Ensure Employee/DepartmentHead can Create on existing rows
UPDATE "RolePermissions" rp
SET "CanCreate" = true,
    "CanView" = true
FROM "Permissions" p
WHERE p."Id" = rp."PermissionId"
  AND p."Module" = 'BusinessTripExpense'
  AND rp."RoleName" IN ('Employee', 'DepartmentHead', 'Accountant', 'Manager', 'Admin', 'Director');
