-- Đổi tên hiển thị module FieldCheckIn → Bản đồ nhân sự
UPDATE "Permissions"
SET "ModuleDisplayName" = 'Bản đồ nhân sự',
    "Description" = 'Vị trí trực tuyến NV chấm ngoài CT trên bản đồ'
WHERE "Module" = 'FieldCheckIn';

SELECT "Module", "ModuleDisplayName", "Description"
FROM "Permissions"
WHERE "Module" = 'FieldCheckIn';
