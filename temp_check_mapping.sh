echo "=== Employee ApplicationUserId mapping ==="
docker exec zkteco_postgres psql -U postgres -d ZKTecoADMS -c '
SELECT e."Id" as emp_id, e."EmployeeCode", e."FirstName", e."LastName", e."ApplicationUserId" as user_id,
  u."UserName"
FROM "Employees" e
LEFT JOIN "AspNetUsers" u ON u."Id" = e."ApplicationUserId"
WHERE e."StoreId" = (SELECT "Id" FROM "Stores" WHERE "Code" = '\''demo'\'' LIMIT 1);
'
