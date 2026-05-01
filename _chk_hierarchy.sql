SELECT 
  e."FirstName" || ' ' || e."LastName" AS name,
  e."Id" AS emp_id,
  e."ApplicationUserId" AS user_id,
  e."DepartmentId" AS dept_id,
  d."Name" AS dept,
  d."ParentDepartmentId" AS parent_dept_id,
  d."ManagerId" AS dept_mgr_emp_id,
  e."DirectManagerEmployeeId" AS direct_mgr_emp_id,
  e."ManagerId" AS mgr_user_id
FROM "Employees" e
LEFT JOIN "Departments" d ON e."DepartmentId" = d."Id"
WHERE e."FirstName" ~* '(Liễu|Mỹ|Quốc|Linh)'
   OR e."LastName" ~* '(Liễu|Mỹ|Quốc|Linh)';

SELECT '---DEPTS---' AS sep;
SELECT 
  d."Id" AS dept_id,
  d."Name",
  d."ParentDepartmentId",
  d."ManagerId" AS mgr_emp_id,
  d."HierarchyPath",
  (SELECT em."FirstName" || ' ' || em."LastName" FROM "Employees" em WHERE em."Id" = d."ManagerId") AS mgr_name
FROM "Departments" d
WHERE d."Deleted" IS NULL
ORDER BY COALESCE(d."HierarchyPath",'');
