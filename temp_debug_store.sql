-- Check which store each user belongs to
SELECT u."Id", u."UserName", u."Role", u."StoreId",
       CONCAT(e."LastName", ' ', e."FirstName") as emp_name
FROM "AspNetUsers" u
LEFT JOIN "Employees" e ON e."ApplicationUserId" = u."Id"
WHERE u."Id" IN (
    'e6525df7-f02d-448f-9052-fb1dbbf0f8c0',  -- NV Linh
    '73154f85-665e-46f0-9498-d1f622e3c8cd',  -- NV Quoc
    'e61af725-5b67-4342-8771-5a6a596d9d87'   -- Admin demo
);

-- Check RolePermission for Manager in each store specifically
SELECT rp."RoleName", rp."StoreId", p."Module",
       rp."CanView", rp."CanApprove", rp."CanEdit", rp."CanDelete", rp."IsActive"
FROM "RolePermissions" rp
JOIN "Permissions" p ON p."Id" = rp."PermissionId"
WHERE rp."RoleName" = 'Manager' AND p."Module" = 'Leave';

-- Check if there's a StoreId mismatch
SELECT rp."StoreId" as perm_store, u."StoreId" as user_store
FROM "RolePermissions" rp
JOIN "Permissions" p ON p."Id" = rp."PermissionId"
CROSS JOIN "AspNetUsers" u
WHERE rp."RoleName" = 'Manager' AND p."Module" = 'Leave'
  AND u."Id" = '73154f85-665e-46f0-9498-d1f622e3c8cd';
