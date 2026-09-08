SELECT r."StoreId" AS record_store, d."StoreId" AS device_store, d."SerialNumber"
FROM "MobileAttendanceRecords" r
LEFT JOIN "Devices" d ON d."SerialNumber" = 'MOBILE'
WHERE r."Id" = '024a4575-864e-4f69-8d4f-32b4f243e182';

SELECT "Id", "SerialNumber", "StoreId" FROM "Devices" WHERE "SerialNumber" = 'MOBILE';
