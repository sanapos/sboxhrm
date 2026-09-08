-- Tắt chấm ngoài CT toàn bộ thiết bị Huyền + xóa GPS cũ
UPDATE "AuthorizedMobileDevices"
SET "AllowOutsideCheckIn" = false,
    "UpdatedAt" = NOW() AT TIME ZONE 'UTC'
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND "Deleted" IS NULL
  AND "EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';

DELETE FROM "EmployeeLiveLocations"
WHERE "StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND "EmployeeId" IN (
    'fb278473-8136-4d86-8cdd-c10fdd91ded7',
    '9b239775-82f1-486b-9bbc-848abd6e68d4',
    '033189011896'
  );

SELECT d."DeviceName", d."AllowOutsideCheckIn", d."UpdatedAt"
FROM "AuthorizedMobileDevices" d
WHERE d."StoreId" = 'a336bc4c-7cec-4fa2-b1e6-e8ffc60ac7ad'
  AND d."Deleted" IS NULL
  AND d."EmployeeId" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';
