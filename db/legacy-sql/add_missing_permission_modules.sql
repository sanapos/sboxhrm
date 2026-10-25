-- Add missing permission modules that exist in Flutter navItems but not in DB
-- These modules need to exist so role permissions can be configured for them

-- MobileDeviceRegistration
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'MobileDeviceRegistration', 'Đăng ký CC Mobile', 'Đăng ký thiết bị chấm công mobile', 44
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'MobileDeviceRegistration');

-- MobileAttendanceApproval
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'MobileAttendanceApproval', 'Duyệt CC Mobile', 'Duyệt chấm công mobile', 45
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'MobileAttendanceApproval');

-- Meal
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'Meal', 'Chấm cơm', 'Quản lý chấm cơm', 46
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'Meal');

-- Feedback
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'Feedback', 'Phản ánh / Ý kiến', 'Quản lý phản ánh, ý kiến nhân viên', 47
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'Feedback');

-- FieldCheckIn (may already exist from old seed, re-add if missing)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'FieldCheckIn', 'Check-in điểm bán', 'Quản lý check-in điểm bán', 48
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'FieldCheckIn');

-- ProductSalary (sub-setting for Production)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder")
SELECT gen_random_uuid(), 'ProductSalary', 'Lương sản phẩm', 'Thiết lập lương theo sản phẩm', 49
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'ProductSalary');
