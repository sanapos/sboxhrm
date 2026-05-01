SELECT u."Id"::text, u."UserName", u."FirstName", u."LastName", t."Id"::text AS token_id, t."Platform", t."IsDisabled", t."LastUsedAt"
FROM "AspNetUsers" u
LEFT JOIN "UserDeviceTokens" t ON t."UserId" = u."Id"
WHERE u."Id" IN ('e6525df7-f02d-448f-9052-fb1dbbf0f8c0','73154f85-665e-46f0-9498-d1f622e3c8cd','c04d9143-0103-41a3-bd60-2fdf0b7e39f9')
ORDER BY u."FirstName";