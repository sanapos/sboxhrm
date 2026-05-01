SELECT e."Id", e."FirstName", e."LastName", e."StoreId"
FROM "Employees" e
WHERE e."FirstName" ILIKE '%liễu%' OR e."LastName" ILIKE '%liễu%' OR e."FirstName" ILIKE '%lieu%' OR e."LastName" ILIKE '%lieu%';

SELECT a."Id", a."EmployeeId", e."FirstName", e."LastName", a."AttendanceTime", a."AttendanceState", a."DeviceId"
FROM "AttendanceLogs" a LEFT JOIN "Employees" e ON e."Id"=a."EmployeeId"
WHERE a."AttendanceTime"::date = '2026-05-01'
ORDER BY a."AttendanceTime" LIMIT 50;

SELECT count(*) AS pen_count FROM "PenaltySettings";
SELECT "Id","StoreId","LateMinutes1","LatePenalty1","LateMinutes2","LatePenalty2","LateMinutes3","LatePenalty3" FROM "PenaltySettings";

SELECT a."Id", a."EmployeeId", e."FirstName", e."LastName", a."AttendanceTime", a."AttendanceState"
FROM "AttendanceLogs" a LEFT JOIN "Employees" e ON e."Id"=a."EmployeeId"
WHERE a."AttendanceTime"::date = '2026-05-01'
ORDER BY a."AttendanceTime" LIMIT 50;

SELECT count(*) FROM "PenaltyTickets" WHERE "CreatedAt"::date = '2026-05-01';

SELECT "Id","EmployeeId","Type","Amount","Description","TransactionDate","CreatedAt"
FROM "PaymentTransactions" WHERE "CreatedAt"::date = '2026-05-01' OR "Type"='Penalty'
ORDER BY "CreatedAt" DESC LIMIT 20;
