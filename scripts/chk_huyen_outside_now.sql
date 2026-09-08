-- Trường Phát: thiết bị Nguyễn Thị Thu Huyền
SELECT d."Id", d."DeviceId", d."DeviceName", d."EmployeeId", d."EmployeeName",
       d."IsAuthorized", d."AllowOutsideCheckIn", d."UpdatedAt", d."Deleted"
FROM "AuthorizedMobileDevices" d
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND d."Deleted" IS NULL
  AND (
    d."EmployeeId" IN (
      'fb278473-8136-4d86-8cdd-c10fdd91ded7',
      '9b239775-82f1-486b-9bbc-848abd6e68d4',
      '033189011896'
    )
    OR d."EmployeeName" ILIKE '%Huyền%'
  )
ORDER BY d."UpdatedAt" DESC;

SELECT l."EmployeeId", l."Latitude", l."Longitude", l."UpdatedAt"
FROM "EmployeeLiveLocations" l
WHERE l."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND l."EmployeeId" IN (
    'fb278473-8136-4d86-8cdd-c10fdd91ded7',
    '9b239775-82f1-486b-9bbc-848abd6e68d4',
    '033189011896'
  );
