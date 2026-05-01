-- Backfill Employee.ApplicationUserId by matching to AspNetUsers within the same Store.
-- Priority of match keys:
--   1. UserName == EmployeeCode
--   2. Email == CompanyEmail
--   3. PhoneNumber == EmployeeCode (some legacy)
--   4. PhoneNumber == Employee.PhoneNumber

WITH candidates AS (
    SELECT DISTINCT ON (e."Id")
        e."Id"  AS emp_id,
        u."Id"  AS user_id,
        e."FirstName" || ' ' || e."LastName" AS name,
        e."EmployeeCode",
        u."UserName",
        CASE
            WHEN u."UserName" = e."EmployeeCode" THEN 1
            WHEN u."Email" = e."CompanyEmail" THEN 2
            WHEN u."PhoneNumber" = e."EmployeeCode" THEN 3
            WHEN u."PhoneNumber" = e."PhoneNumber" AND e."PhoneNumber" IS NOT NULL AND e."PhoneNumber" <> '' THEN 4
            ELSE 99
        END AS priority
    FROM "Employees" e
    JOIN "AspNetUsers" u
      ON u."StoreId" = e."StoreId"
     AND u."IsActive" = true
    WHERE e."ApplicationUserId" IS NULL
      AND e."StoreId" IS NOT NULL
      AND (
            u."UserName" = e."EmployeeCode"
         OR u."Email" = e."CompanyEmail"
         OR u."PhoneNumber" = e."EmployeeCode"
         OR (u."PhoneNumber" = e."PhoneNumber" AND e."PhoneNumber" IS NOT NULL AND e."PhoneNumber" <> '')
      )
      -- Avoid linking the same AspNetUser to multiple Employees
      AND NOT EXISTS (
          SELECT 1 FROM "Employees" e2 WHERE e2."ApplicationUserId" = u."Id"
      )
    ORDER BY e."Id",
             CASE
                 WHEN u."UserName" = e."EmployeeCode" THEN 1
                 WHEN u."Email" = e."CompanyEmail" THEN 2
                 WHEN u."PhoneNumber" = e."EmployeeCode" THEN 3
                 ELSE 4
             END
)
UPDATE "Employees" e
SET "ApplicationUserId" = c.user_id
FROM candidates c
WHERE e."Id" = c.emp_id
RETURNING e."Id", e."FirstName", e."LastName", e."EmployeeCode", e."ApplicationUserId";

-- Show remaining orphans (per store) so you know what still needs manual linking
SELECT 'STILL ORPHAN' AS what, e."StoreId"::text AS store_id, e."Id"::text AS emp_id,
       e."EmployeeCode", e."FirstName", e."LastName"
FROM "Employees" e
WHERE e."ApplicationUserId" IS NULL
  AND e."Deleted" IS NULL
ORDER BY e."StoreId", e."FirstName"
LIMIT 50;
