\d "Holidays"
\d "Employees"
SELECT * FROM "Holidays" WHERE EXTRACT(MONTH FROM "Date")=4 AND EXTRACT(DAY FROM "Date")=30;
SELECT "Id","FullName","EmployeeCode","EnrollNumber" FROM "Employees" WHERE "FullName" ILIKE '%li%u%' OR "EmployeeCode"='0358968313' OR "EnrollNumber"='0358968313';
