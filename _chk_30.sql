SELECT a."Id", a."AttendanceTime", a."AttendanceState", a."PIN", du."EmployeeId", du."Name"
FROM "AttendanceLogs" a
JOIN "DeviceUsers" du ON du."Id"=a."EmployeeId"
WHERE du."EmployeeId"='02adc168-1ddb-4309-b06b-4e3e1c482241'::uuid
  AND a."AttendanceTime" >= '2026-04-29' AND a."AttendanceTime" < '2026-05-02'
ORDER BY a."AttendanceTime";

SELECT "Id","TicketCode","Type","Status","Amount","ViolationDate","MinutesLateOrEarly","ActualPunchTime"
FROM "PenaltyTickets"
WHERE "EmployeeId"='02adc168-1ddb-4309-b06b-4e3e1c482241'::uuid
ORDER BY "ViolationDate";

SELECT "Id","Type","TransactionDate","Amount","Description","Status"
FROM "PaymentTransactions"
WHERE "EmployeeId"='02adc168-1ddb-4309-b06b-4e3e1c482241'::uuid
  AND "TransactionDate" >= '2026-04-29'
ORDER BY "TransactionDate";
