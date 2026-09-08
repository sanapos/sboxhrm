-- Thiết bị chưa gán cửa hàng
SELECT COUNT(*) AS unassigned_total
FROM "Devices" WHERE "StoreId" IS NULL;

-- Thiết bị theo cửa hàng (có gán)
SELECT s."Name" AS store_name, s."Code" AS store_code,
       a."Name" AS agent_name, a."Code" AS agent_code,
       COUNT(d."Id") AS device_count,
       COUNT(*) FILTER (WHERE d."DeviceStatus" = 'Online') AS online_count
FROM "Devices" d
JOIN "Stores" s ON s."Id" = d."StoreId"
LEFT JOIN "Agents" a ON a."Id" = s."AgentId"
WHERE d."StoreId" IS NOT NULL
GROUP BY s."Id", s."Name", s."Code", a."Name", a."Code"
ORDER BY agent_name NULLS LAST, store_name;

-- Tổng theo đại lý
SELECT COALESCE(a."Name", '(Chưa có đại lý)') AS agent_name,
       COALESCE(a."Code", '-') AS agent_code,
       COUNT(d."Id") AS device_count,
       COUNT(*) FILTER (WHERE d."StoreId" IS NULL) AS unassigned_in_group
FROM "Devices" d
LEFT JOIN "Stores" s ON s."Id" = d."StoreId"
LEFT JOIN "Agents" a ON a."Id" = s."AgentId"
GROUP BY a."Id", a."Name", a."Code"
ORDER BY device_count DESC;

-- Chi tiết thiết bị chưa gán
SELECT d."SerialNumber", d."DeviceName", d."DeviceStatus", d."IsClaimed", d."LastOnline"
FROM "Devices" d
WHERE d."StoreId" IS NULL
ORDER BY d."LastOnline" DESC NULLS LAST
LIMIT 20;
