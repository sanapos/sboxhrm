SELECT "StoreId",
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE "Deleted" IS NULL) AS not_deleted,
  COUNT(*) FILTER (WHERE "ResignationDate" IS NULL) AS active,
  COUNT(*) FILTER (WHERE "DateOfBirth" IS NOT NULL AND EXTRACT(MONTH FROM "DateOfBirth")=EXTRACT(MONTH FROM CURRENT_DATE)) AS bday_month,
  COUNT(*) FILTER (WHERE "DateOfBirth" IS NOT NULL AND EXTRACT(MONTH FROM "DateOfBirth")=EXTRACT(MONTH FROM CURRENT_DATE) AND "ResignationDate" IS NULL) AS bday_returned,
  COUNT(*) FILTER (WHERE "DateOfBirth" IS NOT NULL AND EXTRACT(MONTH FROM "DateOfBirth")=EXTRACT(MONTH FROM CURRENT_DATE) AND "ResignationDate" IS NULL AND "Deleted" IS NULL) AS bday_visible_after_fix
FROM "Employees"
GROUP BY "StoreId"
ORDER BY total DESC
LIMIT 10;
