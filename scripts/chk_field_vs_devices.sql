-- So sánh thiết bị "chấm ngoài CT" vs nhân viên trên bản đồ theo dõi
-- Store: Trường Phát
WITH store AS (
  SELECT "Id" FROM "Stores" WHERE "Name" ILIKE '%Trường Phát%' LIMIT 1
)
SELECT 'devices_outside_authorized' AS metric, COUNT(*) AS cnt
FROM "AuthorizedMobileDevices" d, store s
WHERE d."StoreId" = s."Id" AND d."Deleted" IS NULL
  AND d."IsAuthorized" AND d."AllowOutsideCheckIn";

WITH store AS (
  SELECT "Id" FROM "Stores" WHERE "Name" ILIKE '%Trường Phát%' LIMIT 1
)
SELECT 'devices_outside_any' AS metric, COUNT(*) AS cnt
FROM "AuthorizedMobileDevices" d, store s
WHERE d."StoreId" = s."Id" AND d."Deleted" IS NULL AND d."AllowOutsideCheckIn";

-- Thiết bị ngoài CT + chi tiết EmployeeId (có thể trùng NV nếu 2 máy)
SELECT d."EmployeeId", d."EmployeeName", d."DeviceModel", d."IsAuthorized", d."AllowOutsideCheckIn"
FROM "AuthorizedMobileDevices" d
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%' AND d."Deleted" IS NULL AND d."AllowOutsideCheckIn"
ORDER BY d."EmployeeName", d."DeviceModel";

-- NV active có khớp allowOutside qua emp id / code / app user
WITH store AS (SELECT "Id" FROM "Stores" WHERE "Name" ILIKE '%Trường Phát%' LIMIT 1),
outside_keys AS (
  SELECT d."EmployeeId" AS key
  FROM "AuthorizedMobileDevices" d, store s
  WHERE d."StoreId" = s."Id" AND d."Deleted" IS NULL
    AND d."IsAuthorized" AND d."AllowOutsideCheckIn"
)
SELECT e."EmployeeCode", e."FirstName", e."LastName",
       e."Id"::text AS emp_id, e."ApplicationUserId"::text AS app_user_id,
       EXISTS (
         SELECT 1 FROM outside_keys k
         WHERE k.key IN (e."Id"::text, e."ApplicationUserId"::text, e."EmployeeCode")
       ) AS map_would_track
FROM "Employees" e, store s
WHERE e."StoreId" = s."Id" AND e."Deleted" IS NULL
  AND e."WorkStatus" = 0
ORDER BY map_would_track DESC, e."LastName";

-- EmployeeId trên thiết bị KHÔNG khớp NV nào
SELECT d."EmployeeId", d."EmployeeName", d."DeviceModel", d."IsAuthorized"
FROM "AuthorizedMobileDevices" d
JOIN "Stores" s ON s."Id" = d."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%' AND d."Deleted" IS NULL
  AND d."AllowOutsideCheckIn" AND d."IsAuthorized"
  AND NOT EXISTS (
    SELECT 1 FROM "Employees" e
    WHERE e."StoreId" = d."StoreId" AND e."Deleted" IS NULL
      AND d."EmployeeId" IN (e."Id"::text, e."ApplicationUserId"::text, e."EmployeeCode")
  );
