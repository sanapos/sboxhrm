SELECT e."EmployeeCode", e."CompanyEmail", e."FirstName", e."LastName", u."UserName", u."Email", u."PhoneNumber", u."Role"
FROM "Employees" e
LEFT JOIN "AspNetUsers" u ON u."StoreId" = e."StoreId" AND u."IsActive" = true
WHERE e."Id" IN ('0138a77b-c6ba-49e0-9740-d2c3d7fc7686','c4f3cd27-c5bb-4728-b170-b3346dd6b61f','b10eba80-f36e-4d15-91ce-8c9939d02231','41b1b6b1-558b-49ad-a5b8-e974aa945fe1')
  AND (u."UserName" = e."EmployeeCode" OR u."Email" = e."CompanyEmail" OR u."PhoneNumber" = e."PhoneNumber" OR (u."FirstName"||' '||u."LastName") ILIKE '%'||e."FirstName"||'%')
ORDER BY e."EmployeeCode";