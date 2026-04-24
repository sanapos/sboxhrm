docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS <<'SQL'
SELECT COUNT(*) AS total_users FROM "AspNetUsers";
SELECT u."StoreId", s."Name", COUNT(*) AS cnt
  FROM "AspNetUsers" u LEFT JOIN "Stores" s ON s."Id" = u."StoreId"
  GROUP BY u."StoreId", s."Name" ORDER BY cnt DESC;
SELECT u."Id", u."UserName", u."Email", u."StoreId"
  FROM "AspNetUsers" u
  LEFT JOIN "Stores" s ON s."Id" = u."StoreId"
  WHERE u."StoreId" IS NULL OR s."Id" IS NULL
  LIMIT 80;
SQL
