SELECT e."EmployeeCode", e."FirstName", e."LastName", e."ApplicationUserId"::text
FROM "Employees" e
JOIN "Stores" s ON s."Id" = e."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND (e."FirstName" ILIKE '%Huyền%' OR e."LastName" ILIKE '%Huyền%' OR e."FirstName" ILIKE '%Thu%');

SELECT amd."EmployeeName", amd."EmployeeId", amd."DeviceName", amd."DeviceModel",
       amd."IsAuthorized", amd."AllowOutsideCheckIn", amd."RequirePhotoProof",
       amd."AuthorizedAt", amd."LastUsedAt", amd."UpdatedAt"
FROM "AuthorizedMobileDevices" amd
JOIN "Stores" s ON s."Id" = amd."StoreId"
WHERE s."Name" ILIKE '%Trường Phát%'
  AND amd."Deleted" IS NULL
  AND (amd."EmployeeName" ILIKE '%Huyền%' OR amd."EmployeeName" ILIKE '%Thu%');
