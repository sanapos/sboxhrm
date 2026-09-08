SELECT u."Id", u."UserName", u."Email", u."IsActive"
FROM "Employees" e
JOIN "AspNetUsers" u ON u."Id" = e."ApplicationUserId"
WHERE e."Id" = 'fb278473-8136-4d86-8cdd-c10fdd91ded7';
