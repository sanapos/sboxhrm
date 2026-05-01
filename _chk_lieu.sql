SELECT e."FirstName", e."LastName", e."EmployeeCode", e."Id" as EmpId FROM "Employees" e WHERE e."FirstName" ILIKE '%Li%u%' OR e."LastName" ILIKE '%Li%u%' OR e."EmployeeCode" ILIKE '%0358968313%';
