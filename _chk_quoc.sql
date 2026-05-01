SELECT u."UserName", u."FirstName", u."LastName", u."StoreId", u."Role", u."IsActive"
FROM "AspNetUsers" u
WHERE u."FirstName" ILIKE '%Quốc%' OR u."FirstName" ILIKE '%Quoc%' OR u."UserName" ILIKE '%quoc%' OR u."UserName" ILIKE '%049094008190%'
LIMIT 10;
