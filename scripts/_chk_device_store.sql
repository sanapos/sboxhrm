SELECT d."SerialNumber", d."StoreId", d."OwnerId", d."IsClaimed",
       u."Email", u."StoreId" AS user_store
FROM "Devices" d
LEFT JOIN "AspNetUsers" u ON u."Id" = d."OwnerId"
WHERE d."SerialNumber" IN ('1313254900907','1313254900929');
