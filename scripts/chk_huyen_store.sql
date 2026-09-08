SELECT u."Id"::text AS user_id, u."UserName", u."StoreId"::text AS user_store_id,
       e."Id"::text AS emp_id, e."StoreId"::text AS emp_store_id, s."Name" AS store_name
FROM "AspNetUsers" u
JOIN "Employees" e ON e."ApplicationUserId" = u."Id"
JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE e."EmployeeCode" = '033189011896';

SELECT d."StoreId"::text, d."EmployeeId", d."DeviceModel", d."AllowOutsideCheckIn"
FROM "AuthorizedMobileDevices" d
WHERE d."EmployeeId" IN ('9b239775-82f1-486b-9bbc-848abd6e68d4','fb278473-8136-4d86-8cdd-c10fdd91ded7');
