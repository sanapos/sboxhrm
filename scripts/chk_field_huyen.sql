-- Field check-in data: Trường Phát + Nguyễn Thị Thu Huyền
SELECT e."EmployeeCode", e."Id"::text AS emp_id, e."ApplicationUserId"::text AS app_user_id
FROM "Employees" e
JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND e."EmployeeCode" = '033189011896';

SELECT j."EmployeeId", j."Status", j."JourneyDate", j."StartTime", j."UpdatedAt",
       LEFT(j."RoutePointsJson", 100) AS route_preview
FROM "JourneyTrackings" j
JOIN "Stores" s ON s."Id" = j."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND j."JourneyDate" >= (CURRENT_DATE AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
  AND j."Deleted" IS NULL
  AND (j."EmployeeId" IN ('fb278473-8136-4d86-8cdd-c10fdd91ded7','9b239775-82f1-486b-9bbc-848abd6e68d4','033189011896')
       OR j."EmployeeName" ILIKE '%Huyền%');

SELECT v."EmployeeId", v."EmployeeName", v."LocationName", v."Status",
       v."CheckInTime", v."CheckOutTime", v."CheckInLatitude", v."CheckInLongitude"
FROM "VisitReports" v
JOIN "Stores" s ON s."Id" = v."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND v."VisitDate" >= (CURRENT_DATE AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
  AND v."Deleted" IS NULL
  AND (v."EmployeeId" IN ('fb278473-8136-4d86-8cdd-c10fdd91ded7','9b239775-82f1-486b-9bbc-848abd6e68d4','033189011896')
       OR v."EmployeeName" ILIKE '%Huyền%');

SELECT l."EmployeeId", l."Latitude", l."Longitude", l."UpdatedAt"
FROM "EmployeeLiveLocations" l
JOIN "Stores" s ON s."Id" = l."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND l."EmployeeId" IN ('fb278473-8136-4d86-8cdd-c10fdd91ded7','9b239775-82f1-486b-9bbc-848abd6e68d4','033189011896');

SELECT a."EmployeeId", a."EmployeeName", a."DayOfWeek", a."IsActive", fl."Name" AS location_name
FROM "FieldLocationAssignments" a
JOIN "FieldLocations" fl ON fl."Id" = a."LocationId"
JOIN "Stores" s ON s."Id" = a."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND a."Deleted" IS NULL
  AND (a."EmployeeId" IN ('fb278473-8136-4d86-8cdd-c10fdd91ded7','9b239775-82f1-486b-9bbc-848abd6e68d4','033189011896')
       OR a."EmployeeName" ILIKE '%Huyền%');

-- Recent visits (7 days)
SELECT v."VisitDate"::date, v."EmployeeId", v."LocationName", v."Status", v."CheckInTime"
FROM "VisitReports" v
JOIN "Stores" s ON s."Id" = v."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND v."Deleted" IS NULL
  AND (v."EmployeeId" IN ('fb278473-8136-4d86-8cdd-c10fdd91ded7','9b239775-82f1-486b-9bbc-848abd6e68d4','033189011896')
       OR v."EmployeeName" ILIKE '%Huyền%')
ORDER BY v."CheckInTime" DESC NULLS LAST
LIMIT 10;
