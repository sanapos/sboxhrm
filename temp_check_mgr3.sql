-- Check AspNetUsers columns
SELECT column_name FROM information_schema.columns WHERE table_name = 'AspNetUsers' AND column_name ILIKE '%name%' OR (table_name = 'AspNetUsers' AND column_name ILIKE '%full%');

-- Employee.ManagerId -> who?
SELECT 
    CONCAT(e."LastName", ' ', e."FirstName") as employee,
    e."ManagerId" as mgr_user_id,
    mgr_u."UserName" as manager_username,
    mgr_u."Email" as manager_email,
    mgr_u."Role" as manager_role
FROM "Employees" e
LEFT JOIN "AspNetUsers" mgr_u ON mgr_u."Id" = e."ManagerId"
WHERE CONCAT(e."LastName", ' ', e."FirstName") ILIKE '%Nguy%'
ORDER BY employee;

-- Check if API picked up the new code - latest approval records
SELECT 
    la."LeaveId",
    la."StepOrder",
    la."StepName",
    la."AssignedUserId",
    la."AssignedUserName",
    la."Status",
    l."CreatedAt" as leave_created
FROM "LeaveApprovalRecords" la
JOIN "Leaves" l ON l."Id" = la."LeaveId"
ORDER BY l."CreatedAt" DESC
LIMIT 10;

-- Who is the Admin user?
SELECT "Id", "UserName", "Email", "Role" FROM "AspNetUsers" WHERE "Role" = 'Admin' OR "Id" = 'e61af725-5b67-4342-8771-5a6a596d9d87';
