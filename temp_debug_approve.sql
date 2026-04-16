-- Check user roles for Nguyễn Văn Quốc, Nguyễn Văn Linh
SELECT u."Id", u."UserName", u."Email", u."Role", u."IsActive",
       CONCAT(e."LastName", ' ', e."FirstName") as emp_name
FROM "AspNetUsers" u
LEFT JOIN "Employees" e ON e."ApplicationUserId" = u."Id"
WHERE CONCAT(e."LastName", ' ', e."FirstName") ILIKE '%Nguy%n V%n%'
   OR u."UserName" ILIKE '%quoc%'
   OR u."UserName" ILIKE '%linh%'
ORDER BY emp_name;

-- Check RolePermission for Leave module per role
SELECT rp."RoleName", p."Module", rp."CanView", rp."CanCreate", rp."CanEdit", 
       rp."CanDelete", rp."CanExport", rp."CanApprove", rp."IsActive"
FROM "RolePermissions" rp
JOIN "Permissions" p ON p."Id" = rp."PermissionId"
WHERE p."Module" = 'Leave'
ORDER BY rp."RoleName";

-- Check all roles in system
SELECT DISTINCT "Role", COUNT(*) FROM "AspNetUsers" GROUP BY "Role";

-- Check the latest leave and its approval records
SELECT l."Id", CONCAT(emp."LastName", ' ', emp."FirstName") as employee, 
       l."Status", l."CreatedAt",
       la."StepOrder", la."StepName", la."AssignedUserId", la."AssignedUserName", la."Status" as approval_status
FROM "Leaves" l
JOIN "Employees" emp ON emp."ApplicationUserId" = l."EmployeeUserId"
LEFT JOIN "LeaveApprovalRecords" la ON la."LeaveId" = l."Id"
ORDER BY l."CreatedAt" DESC
LIMIT 15;
