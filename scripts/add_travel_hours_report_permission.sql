-- Seed module Báo cáo đi đường (TravelHoursReport)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
SELECT '11111111-1111-1111-1111-111111111101',
       'TravelHoursReport',
       'Báo cáo đi đường',
       'Chi tiết giờ đi đường mobile, bổ sung thủ công',
       49,
       NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM "Permissions" WHERE "Id" = '11111111-1111-1111-1111-111111111101'
);

INSERT INTO "RolePermissions" (
  "Id", "RoleName", "RoleDisplayName", "PermissionId", "StoreId",
  "CanView", "CanCreate", "CanEdit", "CanDelete", "CanApprove", "CanExport",
  "IsActive", "CreatedAt"
)
SELECT gen_random_uuid(),
       src."RoleName",
       MAX(src."RoleDisplayName"),
       '11111111-1111-1111-1111-111111111101'::uuid,
       src."StoreId",
       true,
       bool_or(COALESCE(src."CanCreate", false)),
       bool_or(COALESCE(src."CanEdit", false)),
       false,
       false,
       bool_or(COALESCE(src."CanExport", false)),
       true,
       NOW()
FROM "RolePermissions" src
WHERE src."PermissionId" IN (
  '11111111-1111-1111-1111-111111111046'::uuid,
  '11111111-1111-1111-1111-111111111096'::uuid
)
AND NOT EXISTS (
  SELECT 1 FROM "RolePermissions" x
  WHERE x."RoleName" = src."RoleName"
    AND x."StoreId" IS NOT DISTINCT FROM src."StoreId"
    AND x."PermissionId" = '11111111-1111-1111-1111-111111111101'::uuid
)
GROUP BY src."RoleName", src."StoreId";
