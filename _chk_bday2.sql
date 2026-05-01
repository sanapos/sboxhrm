SELECT "EmployeeCode", "FirstName", "LastName", "DateOfBirth", "ResignationDate", "Deleted", "IsActive"
FROM "Employees"
WHERE "StoreId"='985262f9-7166-47c9-9edd-1847f620a3a2'
ORDER BY "DateOfBirth" NULLS LAST;
