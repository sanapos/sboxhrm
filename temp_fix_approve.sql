UPDATE "RolePermissions" rp
SET "CanApprove" = true
FROM "Permissions" p
WHERE p."Id" = rp."PermissionId"
  AND rp."RoleName" = 'Manager'
  AND p."Module" = 'Leave'
  AND rp."StoreId" = '985262f9-7166-47c9-9edd-1847f620a3a2';

-- Verify the fix
SELECT rp."RoleName", rp."StoreId", p."Module",
       rp."CanView", rp."CanApprove", rp."CanEdit", rp."CanDelete"
FROM "RolePermissions" rp
JOIN "Permissions" p ON p."Id" = rp."PermissionId"
WHERE rp."RoleName" = 'Manager' AND p."Module" = 'Leave'
  AND rp."StoreId" = '985262f9-7166-47c9-9edd-1847f620a3a2';
