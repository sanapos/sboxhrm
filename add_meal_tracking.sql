-- ================================================================
-- Migration: Add Meal Tracking (Chấm cơm) tables
-- Date: 2026-04-06
-- ================================================================

-- Thêm DeviceType vào bảng Devices (0=Attendance, 1=Meal)
ALTER TABLE "Devices" ADD COLUMN IF NOT EXISTS "DeviceType" INT NOT NULL DEFAULT 0;

-- Bảng bữa ăn (Bữa trưa, Bữa tối...)
CREATE TABLE IF NOT EXISTS "MealSessions" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" VARCHAR(100) NOT NULL,
    "StartTime" TIME NOT NULL,
    "EndTime" TIME NOT NULL,
    "Description" VARCHAR(500),
    "StoreId" UUID,
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" VARCHAR(256),
    "CreatedBy" VARCHAR(256),
    "LastModified" TIMESTAMP WITHOUT TIME ZONE,
    "LastModifiedBy" VARCHAR(256),
    "Deleted" TIMESTAMP WITHOUT TIME ZONE,
    "DeletedBy" VARCHAR(256)
);

-- Mapping ca làm việc ↔ bữa ăn
CREATE TABLE IF NOT EXISTS "MealSessionShifts" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "MealSessionId" UUID NOT NULL REFERENCES "MealSessions"("Id") ON DELETE CASCADE,
    "ShiftTemplateId" UUID NOT NULL REFERENCES "ShiftTemplates"("Id") ON DELETE CASCADE,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" VARCHAR(256),
    "CreatedBy" VARCHAR(256),
    UNIQUE("MealSessionId", "ShiftTemplateId")
);

-- Menu món ăn theo ngày và bữa
CREATE TABLE IF NOT EXISTS "MealMenus" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "Date" DATE NOT NULL,
    "DayOfWeek" INT NOT NULL,
    "MealSessionId" UUID NOT NULL REFERENCES "MealSessions"("Id") ON DELETE CASCADE,
    "Note" VARCHAR(500),
    "StoreId" UUID,
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" VARCHAR(256),
    "CreatedBy" VARCHAR(256),
    "LastModified" TIMESTAMP WITHOUT TIME ZONE,
    "LastModifiedBy" VARCHAR(256),
    "Deleted" TIMESTAMP WITHOUT TIME ZONE,
    "DeletedBy" VARCHAR(256)
);

-- Món ăn cụ thể trong menu
CREATE TABLE IF NOT EXISTS "MealMenuItems" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "MealMenuId" UUID NOT NULL REFERENCES "MealMenus"("Id") ON DELETE CASCADE,
    "DishName" VARCHAR(200) NOT NULL,
    "Description" VARCHAR(500),
    "Category" VARCHAR(100),
    "SortOrder" INT NOT NULL DEFAULT 0,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" VARCHAR(256),
    "CreatedBy" VARCHAR(256)
);

-- Bản ghi chấm cơm
CREATE TABLE IF NOT EXISTS "MealRecords" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "AttendanceId" UUID REFERENCES "AttendanceLogs"("Id"),
    "EmployeeUserId" UUID NOT NULL,
    "PIN" VARCHAR(20),
    "MealSessionId" UUID NOT NULL REFERENCES "MealSessions"("Id"),
    "MealTime" TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    "Date" DATE NOT NULL,
    "ShiftId" UUID,
    "DeviceId" UUID REFERENCES "Devices"("Id"),
    "StoreId" UUID,
    "CreatedAt" TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    "UpdatedAt" TIMESTAMP WITHOUT TIME ZONE,
    "UpdatedBy" VARCHAR(256),
    "CreatedBy" VARCHAR(256)
);

-- Indexes cho performance
CREATE INDEX IF NOT EXISTS "IX_MealRecords_StoreId_Date" ON "MealRecords" ("StoreId", "Date");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_EmployeeUserId_Date" ON "MealRecords" ("EmployeeUserId", "Date");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_MealSessionId_Date" ON "MealRecords" ("MealSessionId", "Date");
CREATE INDEX IF NOT EXISTS "IX_MealMenus_StoreId_Date" ON "MealMenus" ("StoreId", "Date");
CREATE INDEX IF NOT EXISTS "IX_MealSessions_StoreId" ON "MealSessions" ("StoreId");

-- Unique constraint: 1 employee, 1 meal session, 1 day
CREATE UNIQUE INDEX IF NOT EXISTS "IX_MealRecords_Unique_Employee_Session_Date"
    ON "MealRecords" ("EmployeeUserId", "MealSessionId", "Date");

-- Thêm permission cho module Meal
INSERT INTO "Permissions" ("Id", "Module", "Action", "Description", "CreatedAt")
VALUES
    (gen_random_uuid(), 'Meal', 'View', 'Xem chấm cơm', NOW()),
    (gen_random_uuid(), 'Meal', 'Create', 'Tạo bữa ăn/menu', NOW()),
    (gen_random_uuid(), 'Meal', 'Edit', 'Sửa bữa ăn/menu', NOW()),
    (gen_random_uuid(), 'Meal', 'Delete', 'Xóa bữa ăn/menu', NOW()),
    (gen_random_uuid(), 'Meal', 'Report', 'Báo cáo chấm cơm', NOW())
ON CONFLICT DO NOTHING;
