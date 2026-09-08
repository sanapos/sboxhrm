SELECT COUNT(*) AS store_count FROM "Stores" WHERE "AgentId" = 'c97c96e9-12f9-4a6c-8c6b-f60e2641b212';

SELECT s."Name", s."Code" FROM "Stores" s WHERE s."AgentId" = 'c97c96e9-12f9-4a6c-8c6b-f60e2641b212' LIMIT 5;
