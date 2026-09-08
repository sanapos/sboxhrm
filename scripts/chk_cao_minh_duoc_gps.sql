-- Cao Minh Được — GPS / thiết bị / live location
SELECT e."EmployeeCode", e."FirstName", e."LastName",
       e."Id"::text AS emp_id, e."ApplicationUserId"::text AS app_user_id,
       s."Name" AS store_name
FROM "Employees" e
JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE e."Deleted" IS NULL
  AND (e."LastName" ILIKE '%Được%' AND e."FirstName" ILIKE '%Minh%'
       OR e."LastName" ILIKE '%Duoc%' AND e."FirstName" ILIKE '%Minh%'
       OR (e."FirstName" || ' ' || e."LastName") ILIKE '%Cao%Minh%Được%'
       OR (e."LastName" || ' ' || e."FirstName") ILIKE '%Cao%Minh%Được%');

SELECT amd."DeviceName", amd."DeviceModel", amd."EmployeeId", amd."EmployeeName",
       amd."IsAuthorized", amd."AllowOutsideCheckIn",
       amd."LastUsedAt", amd."UpdatedAt"
FROM "AuthorizedMobileDevices" amd
WHERE amd."Deleted" IS NULL
  AND (amd."EmployeeName" ILIKE '%Cao%Minh%'
       OR amd."EmployeeName" ILIKE '%Minh%Được%'
       OR amd."EmployeeName" ILIKE '%Minh%Duoc%');

-- Live location (nếu có emp id từ query trên)
SELECT l."StoreId", l."EmployeeId", l."Latitude", l."Longitude", l."Accuracy",
       l."UpdatedAt",
       l."UpdatedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh' AS updated_vn,
       NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh' AS now_vn,
       EXTRACT(EPOCH FROM (NOW() - l."UpdatedAt"))/60 AS age_minutes
FROM "EmployeeLiveLocations" l
WHERE l."EmployeeId" IN (
  SELECT COALESCE(e."Id"::text, e."EmployeeCode", e."ApplicationUserId"::text)
  FROM "Employees" e
  WHERE e."Deleted" IS NULL
    AND (e."LastName" ILIKE '%Được%' OR e."LastName" ILIKE '%Duoc%')
    AND e."FirstName" ILIKE '%Minh%'
);

-- Chấm công mobile hôm nay (GPS punch)
SELECT m."OdooEmployeeId", m."PunchTime", m."Latitude", m."Longitude",
       m."LocationName", m."PunchType"
FROM "MobileAttendanceRecords" m
WHERE m."Deleted" IS NULL
  AND m."PunchTime" >= (CURRENT_DATE AT TIME ZONE 'Asia/Ho_Chi_Minh')
  AND m."OdooEmployeeId" IN (
    SELECT e."EmployeeCode" FROM "Employees" e
    WHERE e."Deleted" IS NULL AND e."LastName" ILIKE '%Được%' AND e."FirstName" ILIKE '%Minh%'
    UNION
    SELECT e."Id"::text FROM "Employees" e
    WHERE e."Deleted" IS NULL AND e."LastName" ILIKE '%Được%' AND e."FirstName" ILIKE '%Minh%'
  )
ORDER BY m."PunchTime" DESC
LIMIT 20;
