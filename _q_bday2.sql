SELECT "EmployeeCode", "FirstName", "LastName", "DateOfBirth", "WorkStatus", "Deleted"
FROM "Employees"
WHERE EXTRACT(MONTH FROM "DateOfBirth") = 4 AND EXTRACT(DAY FROM "DateOfBirth") = 29;