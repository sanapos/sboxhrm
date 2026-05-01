-- Link Linh's Employee row to her ApplicationUser
UPDATE "Employees"
SET "ApplicationUserId" = 'e6525df7-f02d-448f-9052-fb1dbbf0f8c0'
WHERE "Id" = '41b1b6b1-558b-49ad-a5b8-e974aa945fe1'
  AND "ApplicationUserId" IS NULL;

-- Verify
SELECT "Id", "FirstName", "LastName", "ApplicationUserId"
FROM "Employees"
WHERE "Id" = '41b1b6b1-558b-49ad-a5b8-e974aa945fe1';

-- Look for OTHER orphaned Employee rows where a matching AspNetUser exists by name/email
SELECT 'ORPHANS' AS what, e."Id"::text AS emp_id, e."FirstName", e."LastName",
       u."Id"::text AS candidate_user_id, u."Email", u."Role"
FROM "Employees" e
LEFT JOIN "AspNetUsers" u
  ON LOWER(TRIM(CONCAT(u."FirstName",' ',u."LastName"))) = LOWER(TRIM(CONCAT(e."FirstName",' ',e."LastName")))
 AND u."IsActive" = true
WHERE e."ApplicationUserId" IS NULL
  AND u."Id" IS NOT NULL
ORDER BY e."FirstName";
