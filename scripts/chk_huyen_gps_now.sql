-- GPS / vị trí Nguyễn Thị Thu Huyền — Trường Phát
SELECT e."EmployeeCode", e."FirstName", e."LastName",
       e."Id"::text AS emp_id, e."ApplicationUserId"::text AS app_user_id
FROM "Employees" e
JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE e."EmployeeCode" = '033189011896';

SELECT amd."DeviceName", amd."DeviceModel", amd."EmployeeId", amd."IsAuthorized",
       amd."AllowOutsideCheckIn", amd."AuthorizedAt", amd."LastUsedAt", amd."UpdatedAt"
FROM "AuthorizedMobileDevices" amd
JOIN "Stores" s ON s."Id" = amd."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND amd."Deleted" IS NULL
  AND (amd."EmployeeId" IN (
        'fb278473-8136-4d86-8cdd-c10fdd91ded7',
        '9b239775-82f1-486b-9bbc-848abd6e68d4',
        '033189011896'
      ) OR amd."EmployeeName" ILIKE '%Huyền%');

SELECT l."EmployeeId", l."Latitude", l."Longitude", l."Accuracy",
       l."UpdatedAt",
       l."UpdatedAt" AT TIME ZONE 'UTC' AS updated_utc,
       l."UpdatedAt" AT TIME ZONE 'Asia/Ho_Chi_Minh' AS updated_vn,
       NOW() AT TIME ZONE 'Asia/Ho_Chi_Minh' AS now_vn
FROM "EmployeeLiveLocations" l
JOIN "Stores" s ON s."Id" = l."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND l."EmployeeId" IN (
        'fb278473-8136-4d86-8cdd-c10fdd91ded7',
        '9b239775-82f1-486b-9bbc-848abd6e68d4',
        '033189011896'
      );

-- Tất cả live locations store Trường Phát (mới nhất)
SELECT l."EmployeeId", l."Latitude", l."Longitude", l."UpdatedAt"
FROM "EmployeeLiveLocations" l
JOIN "Stores" s ON s."Id" = l."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
ORDER BY l."UpdatedAt" DESC;
