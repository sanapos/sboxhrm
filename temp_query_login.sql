SELECT u."UserName", u."Email", s."Code" FROM "AspNetUsers" u JOIN "Stores" s ON u."StoreId" = s."Id" LIMIT 15;
