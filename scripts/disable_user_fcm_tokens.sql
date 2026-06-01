UPDATE "UserDeviceTokens" SET "IsDisabled" = true
WHERE "UserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
);

SELECT COUNT(*) AS active_tokens
FROM "UserDeviceTokens"
WHERE "UserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
) AND NOT "IsDisabled";
