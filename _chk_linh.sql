-- Find any user/employee referencing 'Linh' and the user e61af725
SELECT 'USER e61af725' AS what, "Id"::text, "FirstName", "LastName", "Email", "UserName", "Role", "IsActive"
FROM "AspNetUsers" WHERE "Id" = 'e61af725-5b67-4342-8771-5a6a596d9d87';

SELECT 'USERS Linh' AS what, "Id"::text, "FirstName", "LastName", "Email", "UserName", "Role", "IsActive"
FROM "AspNetUsers" WHERE "FirstName" ILIKE '%Linh%' OR "LastName" ILIKE '%Linh%';

SELECT 'EMP Linh' AS what, e."Id"::text, e."FirstName", e."LastName",
       e."ApplicationUserId"::text, e."ManagerId"::text, e."DirectManagerEmployeeId"::text
FROM "Employees" e WHERE e."FirstName" ILIKE '%Linh%' OR e."LastName" ILIKE '%Linh%';
