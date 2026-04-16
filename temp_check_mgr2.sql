-- Check employee manager relationships
SELECT 
    e."Id" as emp_id,
    CONCAT(e."LastName", ' ', e."FirstName") as emp_name,
    e."ManagerId" as mgr_user_id,
    e."DirectManagerEmployeeId" as direct_mgr_emp_id,
    e."DepartmentId" as dept_id,
    e."ApplicationUserId" as app_user_id,
    u."FullName" as user_fullname,
    u."Role" as user_role
FROM "Employees" e
LEFT JOIN "AspNetUsers" u ON u."Id" = e."ApplicationUserId"
ORDER BY emp_name;

-- What does Employee.ManagerId resolve to?
SELECT 
    CONCAT(e."LastName", ' ', e."FirstName") as employee,
    e."ManagerId" as mgr_user_id,
    mgr_u."FullName" as manager_name,
    mgr_u."Role" as manager_role,
    mgr_u."Id" as manager_user_id
FROM "Employees" e
LEFT JOIN "AspNetUsers" mgr_u ON mgr_u."Id" = e."ManagerId"
ORDER BY employee;

-- Department managers
SELECT 
    d."Id" as dept_id,
    d."Name" as dept_name,
    d."ManagerId" as dept_mgr_emp_id,
    CONCAT(mgr_e."LastName", ' ', mgr_e."FirstName") as dept_manager_name
FROM "Departments" d
LEFT JOIN "Employees" mgr_e ON mgr_e."Id" = d."ManagerId";

-- DirectManagerEmployeeId chain
SELECT 
    CONCAT(e."LastName", ' ', e."FirstName") as employee,
    e."DirectManagerEmployeeId",
    CONCAT(dm."LastName", ' ', dm."FirstName") as direct_manager
FROM "Employees" e
LEFT JOIN "Employees" dm ON dm."Id" = e."DirectManagerEmployeeId"
ORDER BY employee;

-- Recent leave approval records
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
LIMIT 20;
