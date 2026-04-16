-- Check WorkSchedules data mapping - column is "EmployeeId" in DB
SELECT ws."EmployeeId" as stored_id, e."Id" as emp_id, e."ApplicationUserId" as app_user_id, e."FirstName"
FROM "WorkSchedules" ws
LEFT JOIN "Employees" e ON e."Id" = ws."EmployeeId"
LIMIT 5;

-- Also check if any stored EmployeeId matches ApplicationUserId instead
SELECT ws."EmployeeId" as stored_id, e."Id" as emp_id, e."ApplicationUserId"
FROM "WorkSchedules" ws
LEFT JOIN "Employees" e ON e."ApplicationUserId" = ws."EmployeeId"
WHERE e."Id" IS NOT NULL
LIMIT 5;
