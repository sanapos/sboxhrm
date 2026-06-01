-- Unlock SuperAdmin and disable lockout
UPDATE "AspNetUsers"
SET "LockoutEnd" = NULL,
    "AccessFailedCount" = 0,
    "LockoutEnabled" = false,
    "IsActive" = true,
    "EmailConfirmed" = true
WHERE LOWER("Email") = 'sanapos.vn@gmail.com'
   OR LOWER("UserName") IN ('superadmin', 'sanapos.vn@gmail.com');

SELECT "Email", "UserName", "LockoutEnabled", "LockoutEnd", "AccessFailedCount", "IsActive"
FROM "AspNetUsers"
WHERE LOWER("Email") = 'sanapos.vn@gmail.com';
