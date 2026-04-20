UPDATE "AspNetUsers" SET "LockoutEnd"=NULL, "AccessFailedCount"=0 WHERE "UserName"='demo@gmail.com';
SELECT "UserName","LockoutEnd","AccessFailedCount" FROM "AspNetUsers" WHERE "UserName"='demo@gmail.com';
