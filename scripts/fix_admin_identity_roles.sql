-- Repair admin portal accounts: user.Role set but missing AspNetUserRoles
INSERT INTO "AspNetUserRoles" ("UserId", "RoleId")
SELECT u."Id", r."Id"
FROM "AspNetUsers" u
JOIN "AspNetRoles" r ON r."NormalizedName" = UPPER(u."Role")
WHERE u."Role" IN ('SuperAdmin', 'Agent')
  AND NOT EXISTS (
    SELECT 1 FROM "AspNetUserRoles" ur
    WHERE ur."UserId" = u."Id" AND ur."RoleId" = r."Id"
  );

SELECT u."Email", u."Role", COALESCE(string_agg(r."Name", ', '), '(none)') as identity_roles
FROM "AspNetUsers" u
LEFT JOIN "AspNetUserRoles" ur ON ur."UserId" = u."Id"
LEFT JOIN "AspNetRoles" r ON r."Id" = ur."RoleId"
WHERE u."Role" IN ('SuperAdmin', 'Agent')
GROUP BY u."Email", u."Role"
ORDER BY u."Role", u."Email";
