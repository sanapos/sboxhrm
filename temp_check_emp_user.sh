docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT e."Id" as emp_id, e."EmployeeCode", e."FirstName", e."LastName", u."Id" as user_id, u."UserName"
FROM "Employees" e
LEFT JOIN "AspNetUsers" u ON u."Email" = e."Email" OR u."UserName" = e."Email"
WHERE e."StoreId" = (SELECT "Id" FROM "Stores" WHERE "Code" = '\''demo'\'' LIMIT 1)
LIMIT 20;
'
