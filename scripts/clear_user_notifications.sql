-- Clear all in-app notifications for one user (by email)
-- Usage: set email in WHERE clauses below, or pass via sed on server

SELECT "Id", "Email", "UserName", "Role"
FROM "AspNetUsers"
WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
   OR LOWER("UserName") = LOWER('ngthihanh2011@gmail.com');

SELECT COUNT(*) AS before_count
FROM "Notifications" n
WHERE n."TargetUserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
     OR LOWER("UserName") = LOWER('ngthihanh2011@gmail.com')
);

DELETE FROM "Notifications"
WHERE "TargetUserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
     OR LOWER("UserName") = LOWER('ngthihanh2011@gmail.com')
);

SELECT COUNT(*) AS after_count
FROM "Notifications" n
WHERE n."TargetUserId" IN (
  SELECT "Id" FROM "AspNetUsers"
  WHERE LOWER("Email") = LOWER('ngthihanh2011@gmail.com')
     OR LOWER("UserName") = LOWER('ngthihanh2011@gmail.com')
);
