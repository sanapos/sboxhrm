UPDATE "UserDeviceTokens"
SET "IsDisabled" = false
WHERE "UserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
);

SELECT u."Email", t."IsDisabled", t."Platform"
FROM "UserDeviceTokens" t
JOIN "AspNetUsers" u ON u."Id" = t."UserId"
WHERE LOWER(u."Email") = LOWER('ngthihanh2011@gmail.com');
