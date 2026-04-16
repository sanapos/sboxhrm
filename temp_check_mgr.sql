-- Check employee manager relationships
SELECT 
    e."Id" as emp_id,
    e."FullName" as emp_name,
    e."ManagerId" as mgr_user_id,
    e."DirectManagerEmployeeId" as direct_mgr_emp_id,
    e."DepartmentId" as dept_id,
    e."ApplicationUserId" as app_user_id,
    u."FullName" as user_fullname,
    u."Role" as user_role
FROM "Employees" e
LEFT JOIN "AspNetUsers" u ON u."Id" = e."ApplicationUserId"
ORDER BY e."FullName";

-- Check what ManagerId points to
SELECT 
    e."FullName" as employee,
    e."ManagerId" as mgr_user_id,
    mgr_u."FullName" as manager_name,
    mgr_u."Role" as manager_role
FROM "Employees" e
LEFT JOIN "AspNetUsers" mgr_u ON mgr_u."Id" = e."ManagerId"
ORDER BY e."FullName";

-- Check department managers
SELECT 
    d."Id" as dept_id,
    d."Name" as dept_name,
    d."ManagerId" as dept_mgr_emp_id,
    mgr_e."FullName" as dept_manager_name
FROM "Departments" d
LEFT JOIN "Employees" mgr_e ON mgr_e."Id" = d."ManagerId";

-- Check DirectManagerEmployeeId chain
SELECT 
    e."FullName" as employee,
    e."DirectManagerEmployeeId",
    dm."FullName" as direct_manager
FROM "Employees" e
LEFT JOIN "Employees" dm ON dm."Id" = e."DirectManagerEmployeeId"
ORDER BY e."FullName";
