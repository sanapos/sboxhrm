-- Migration: Fix Feedbacks table and create missing tables for seed data
-- Date: 2025-06-04

BEGIN;

-- ============================================
-- 1. Fix Feedbacks table - add missing AuditableEntity columns
-- ============================================
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "IsActive" boolean NOT NULL DEFAULT true;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "Deleted" timestamp without time zone;
ALTER TABLE "Feedbacks" ADD COLUMN IF NOT EXISTS "DeletedBy" text;

-- ============================================
-- 2. Create ProductGroups table
-- ============================================
CREATE TABLE IF NOT EXISTS "ProductGroups" (
    "Id" uuid NOT NULL,
    "Name" character varying(100) NOT NULL,
    "Description" character varying(500),
    "SortOrder" integer NOT NULL DEFAULT 0,
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductGroups" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductGroups_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ProductGroups_StoreId" ON "ProductGroups" ("StoreId");

-- ============================================
-- 3. Create ProductItems table
-- ============================================
CREATE TABLE IF NOT EXISTS "ProductItems" (
    "Id" uuid NOT NULL,
    "Code" character varying(50) NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Unit" character varying(50),
    "Description" character varying(500),
    "SortOrder" integer NOT NULL DEFAULT 0,
    "ProductGroupId" uuid NOT NULL,
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductItems" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductItems_ProductGroups_ProductGroupId" FOREIGN KEY ("ProductGroupId") REFERENCES "ProductGroups" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductItems_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ProductItems_ProductGroupId" ON "ProductItems" ("ProductGroupId");
CREATE INDEX IF NOT EXISTS "IX_ProductItems_StoreId" ON "ProductItems" ("StoreId");

-- ============================================
-- 4. Create ProductPriceTiers table
-- ============================================
CREATE TABLE IF NOT EXISTS "ProductPriceTiers" (
    "Id" uuid NOT NULL,
    "ProductItemId" uuid NOT NULL,
    "MinQuantity" integer NOT NULL,
    "MaxQuantity" integer,
    "UnitPrice" numeric(18,2) NOT NULL,
    "TierLevel" integer NOT NULL DEFAULT 1,
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductPriceTiers" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductPriceTiers_ProductItems_ProductItemId" FOREIGN KEY ("ProductItemId") REFERENCES "ProductItems" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductPriceTiers_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ProductPriceTiers_ProductItemId" ON "ProductPriceTiers" ("ProductItemId");
CREATE INDEX IF NOT EXISTS "IX_ProductPriceTiers_StoreId" ON "ProductPriceTiers" ("StoreId");

-- ============================================
-- 5. Create ProductionEntries table
-- ============================================
CREATE TABLE IF NOT EXISTS "ProductionEntries" (
    "Id" uuid NOT NULL,
    "EmployeeId" uuid NOT NULL,
    "ProductItemId" uuid NOT NULL,
    "WorkDate" timestamp without time zone NOT NULL,
    "Quantity" numeric NOT NULL,
    "UnitPrice" numeric,
    "Amount" numeric,
    "Note" character varying(500),
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_ProductionEntries" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ProductionEntries_Employees_EmployeeId" FOREIGN KEY ("EmployeeId") REFERENCES "Employees" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductionEntries_ProductItems_ProductItemId" FOREIGN KEY ("ProductItemId") REFERENCES "ProductItems" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ProductionEntries_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_EmployeeId" ON "ProductionEntries" ("EmployeeId");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_ProductItemId" ON "ProductionEntries" ("ProductItemId");
CREATE INDEX IF NOT EXISTS "IX_ProductionEntries_StoreId" ON "ProductionEntries" ("StoreId");

-- ============================================
-- 6. Create MealSessions table
-- ============================================
CREATE TABLE IF NOT EXISTS "MealSessions" (
    "Id" uuid NOT NULL,
    "Name" character varying(100) NOT NULL,
    "StartTime" interval NOT NULL,
    "EndTime" interval NOT NULL,
    "Description" character varying(500),
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MealSessions" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealSessions_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_MealSessions_StoreId" ON "MealSessions" ("StoreId");

-- ============================================
-- 7. Create MealMenus table
-- ============================================
CREATE TABLE IF NOT EXISTS "MealMenus" (
    "Id" uuid NOT NULL,
    "Date" timestamp without time zone NOT NULL,
    "DayOfWeek" integer NOT NULL DEFAULT 0,
    "MealSessionId" uuid NOT NULL,
    "Note" character varying(500),
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    -- AuditableEntity
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_MealMenus" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealMenus_MealSessions_MealSessionId" FOREIGN KEY ("MealSessionId") REFERENCES "MealSessions" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealMenus_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_MealMenus_MealSessionId" ON "MealMenus" ("MealSessionId");
CREATE INDEX IF NOT EXISTS "IX_MealMenus_StoreId" ON "MealMenus" ("StoreId");

-- ============================================
-- 8. Create MealMenuItems table (child of MealMenu, Entity<Guid>)
-- ============================================
CREATE TABLE IF NOT EXISTS "MealMenuItems" (
    "Id" uuid NOT NULL,
    "MealMenuId" uuid NOT NULL,
    "DishName" character varying(200) NOT NULL,
    "Description" character varying(500),
    "Category" character varying(100),
    "SortOrder" integer NOT NULL DEFAULT 0,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealMenuItems" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealMenuItems_MealMenus_MealMenuId" FOREIGN KEY ("MealMenuId") REFERENCES "MealMenus" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MealMenuItems_MealMenuId" ON "MealMenuItems" ("MealMenuId");

-- ============================================
-- 9. Create MealSessionShifts table (many-to-many MealSession <-> Shift)
-- ============================================
CREATE TABLE IF NOT EXISTS "MealSessionShifts" (
    "Id" uuid NOT NULL,
    "MealSessionId" uuid NOT NULL,
    "ShiftTemplateId" uuid NOT NULL,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealSessionShifts" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealSessionShifts_MealSessions_MealSessionId" FOREIGN KEY ("MealSessionId") REFERENCES "MealSessions" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealSessionShifts_ShiftTemplates_ShiftTemplateId" FOREIGN KEY ("ShiftTemplateId") REFERENCES "ShiftTemplates" ("Id") ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS "IX_MealSessionShifts_MealSessionId" ON "MealSessionShifts" ("MealSessionId");
CREATE INDEX IF NOT EXISTS "IX_MealSessionShifts_ShiftTemplateId" ON "MealSessionShifts" ("ShiftTemplateId");

-- ============================================
-- 10. Create MealRecords table (Entity<Guid>)
-- ============================================
CREATE TABLE IF NOT EXISTS "MealRecords" (
    "Id" uuid NOT NULL,
    "AttendanceId" uuid,
    "EmployeeUserId" uuid NOT NULL,
    "PIN" character varying(20),
    "MealSessionId" uuid NOT NULL,
    "MealTime" timestamp without time zone NOT NULL,
    "Date" timestamp without time zone NOT NULL,
    "ShiftId" uuid,
    "DeviceId" uuid,
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_MealRecords" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealRecords_AttendanceLogs_AttendanceId" FOREIGN KEY ("AttendanceId") REFERENCES "AttendanceLogs" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_MealRecords_AspNetUsers_EmployeeUserId" FOREIGN KEY ("EmployeeUserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealRecords_MealSessions_MealSessionId" FOREIGN KEY ("MealSessionId") REFERENCES "MealSessions" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealRecords_Devices_DeviceId" FOREIGN KEY ("DeviceId") REFERENCES "Devices" ("Id") ON DELETE SET NULL,
    CONSTRAINT "FK_MealRecords_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_MealRecords_AttendanceId" ON "MealRecords" ("AttendanceId");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_EmployeeUserId" ON "MealRecords" ("EmployeeUserId");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_MealSessionId" ON "MealRecords" ("MealSessionId");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_DeviceId" ON "MealRecords" ("DeviceId");
CREATE INDEX IF NOT EXISTS "IX_MealRecords_StoreId" ON "MealRecords" ("StoreId");

-- ============================================
-- 11. Create ShiftSalaryLevels table (extends Entity, not AuditableEntity)
-- ============================================
CREATE TABLE IF NOT EXISTS "ShiftSalaryLevels" (
    "Id" uuid NOT NULL,
    "ShiftTemplateId" uuid NOT NULL,
    "LevelName" character varying(200) NOT NULL,
    "SortOrder" integer NOT NULL DEFAULT 0,
    "RateType" character varying(20) NOT NULL DEFAULT 'fixed',
    "FixedRate" numeric(18,2) NOT NULL DEFAULT 0,
    "HourlyRate" numeric(18,2) NOT NULL DEFAULT 0,
    "Multiplier" numeric(5,2) NOT NULL DEFAULT 1.0,
    "ShiftAllowance" numeric(18,2) NOT NULL DEFAULT 0,
    "IsNightShift" boolean NOT NULL DEFAULT false,
    "EmployeeIds" text,
    "Description" character varying(500),
    "IsActive" boolean NOT NULL DEFAULT true,
    "StoreId" uuid,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_ShiftSalaryLevels" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ShiftSalaryLevels_ShiftTemplates_ShiftTemplateId" FOREIGN KEY ("ShiftTemplateId") REFERENCES "ShiftTemplates" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ShiftSalaryLevels_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ShiftSalaryLevels_ShiftTemplateId" ON "ShiftSalaryLevels" ("ShiftTemplateId");
CREATE INDEX IF NOT EXISTS "IX_ShiftSalaryLevels_StoreId" ON "ShiftSalaryLevels" ("StoreId");

COMMIT;
