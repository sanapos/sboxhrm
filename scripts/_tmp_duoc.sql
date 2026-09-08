SELECT e."EmployeeCode", e."FirstName", e."LastName", e."Id"::text, e."ApplicationUserId"::text, e."WorkStatus", s."Name"
FROM "Employees" e JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE e."Id" = '53c1bcbd-f8c2-47da-bca3-684b80a08c04' OR e."ApplicationUserId" = '53c1bcbd-f8c2-47da-bca3-684b80a08c04';

SELECT * FROM "EmployeeLiveLocations" WHERE "EmployeeId" = '53c1bcbd-f8c2-47da-bca3-684b80a08c04';

SELECT j."JourneyDate", j."Status", j."StartTime", j."UpdatedAt", LEFT(j."RoutePointsJson", 200) AS route_preview
FROM "JourneyTrackings" j
WHERE j."EmployeeId" IN ('53c1bcbd-f8c2-47da-bca3-684b80a08c04')
  AND j."Deleted" IS NULL
ORDER BY j."JourneyDate" DESC LIMIT 5;

SELECT v."VisitDate", v."LocationName", v."CheckInTime", v."CheckInLatitude", v."CheckInLongitude", v."Status"
FROM "VisitReports" v
WHERE v."EmployeeId" = '53c1bcbd-f8c2-47da-bca3-684b80a08c04' AND v."Deleted" IS NULL
ORDER BY v."CheckInTime" DESC LIMIT 10;

SELECT m."PunchTime", m."Latitude", m."Longitude", m."LocationName", m."PunchType"
FROM "MobileAttendanceRecords" m
WHERE (m."OdooEmployeeId" = '53c1bcbd-f8c2-47da-bca3-684b80a08c04')
  AND m."Deleted" IS NULL AND m."PunchTime" >= NOW() - INTERVAL '7 days'
ORDER BY m."PunchTime" DESC LIMIT 10;
