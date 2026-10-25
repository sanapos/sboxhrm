-- Migration: Add Production & ProductSalary permission modules + update service packages
-- Database: PostgreSQL (workFina)

-- 1. Add Production permission module (if not exists)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt", "CreatedBy")
SELECT gen_random_uuid(), 'Production', 'Sản lượng', 'Nhập sản lượng, tính lương sản phẩm', 43, NOW(), 'System'
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'Production');

-- 2. Add ProductSalary permission module (if not exists)
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt", "CreatedBy")
SELECT gen_random_uuid(), 'ProductSalary', 'Lương sản phẩm', 'Nhóm sản phẩm, sản phẩm, đơn giá theo bậc', 44, NOW(), 'System'
WHERE NOT EXISTS (SELECT 1 FROM "Permissions" WHERE "Module" = 'ProductSalary');

-- 3. Update ALL service packages: append Production and ProductSalary to AllowedModules
-- This adds the modules to every package that doesn't already have them
UPDATE "ServicePackages"
SET "AllowedModules" = 
    CASE 
        WHEN "AllowedModules" IS NULL OR "AllowedModules" = '[]' OR "AllowedModules" = '' 
        THEN '["Production","ProductSalary"]'
        ELSE 
            CASE 
                WHEN "AllowedModules"::text LIKE '%Production%' THEN "AllowedModules"
                ELSE RTRIM("AllowedModules"::text, ']') || ',"Production","ProductSalary"]'
            END
    END
WHERE "AllowedModules"::text NOT LIKE '%Production%';
