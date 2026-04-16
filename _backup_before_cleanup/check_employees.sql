SELECT u."Id", u."UserName", r."Name" as "Role" 
FROM "AspNetUsers" u 
JOIN "AspNetUserRoles" ur ON u."Id" = ur."UserId" 
JOIN "AspNetRoles" r ON ur."RoleId" = r."Id";

