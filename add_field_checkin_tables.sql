-- ================================================
-- Check-in điểm bán (Field Check-in)
-- Tạo bảng: FieldLocationAssignments + VisitReports
-- ================================================

-- 1. Bảng giao điểm cho nhân viên
CREATE TABLE IF NOT EXISTS "FieldLocationAssignments" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "StoreId" UUID NOT NULL REFERENCES "Stores"("Id"),
    "EmployeeId" VARCHAR(100) NOT NULL,
    "EmployeeName" VARCHAR(200) NOT NULL DEFAULT '',
    "LocationId" UUID NOT NULL REFERENCES "MobileWorkLocations"("Id"),
    "DayOfWeek" INT NULL,
    "SortOrder" INT NOT NULL DEFAULT 1,
    "Note" VARCHAR(500) NULL,
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "CreatedBy" VARCHAR(200) NULL,
    "UpdatedAt" TIMESTAMP NULL,
    "UpdatedBy" VARCHAR(200) NULL,
    "LastModified" TIMESTAMP NULL,
    "LastModifiedBy" VARCHAR(200) NULL,
    "Deleted" TIMESTAMP NULL,
    "DeletedBy" VARCHAR(200) NULL
);

CREATE INDEX IF NOT EXISTS "IX_FieldLocationAssign_Employee_Location"
    ON "FieldLocationAssignments" ("StoreId", "EmployeeId", "LocationId", "DayOfWeek");

-- 2. Bảng báo cáo check-in tại điểm
CREATE TABLE IF NOT EXISTS "VisitReports" (
    "Id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "StoreId" UUID NOT NULL REFERENCES "Stores"("Id"),
    "EmployeeId" VARCHAR(100) NOT NULL,
    "EmployeeName" VARCHAR(200) NOT NULL DEFAULT '',
    "LocationId" UUID NOT NULL REFERENCES "MobileWorkLocations"("Id"),
    "LocationName" VARCHAR(200) NULL,
    "VisitDate" TIMESTAMP NOT NULL,
    "CheckInTime" TIMESTAMP NULL,
    "CheckOutTime" TIMESTAMP NULL,
    "TimeSpentMinutes" INT NULL,
    "CheckInLatitude" DOUBLE PRECISION NULL,
    "CheckInLongitude" DOUBLE PRECISION NULL,
    "CheckInDistance" DOUBLE PRECISION NULL,
    "CheckOutLatitude" DOUBLE PRECISION NULL,
    "CheckOutLongitude" DOUBLE PRECISION NULL,
    "CheckOutDistance" DOUBLE PRECISION NULL,
    "PhotoUrlsJson" TEXT NULL,
    "ReportNote" VARCHAR(2000) NULL,
    "ReportDataJson" TEXT NULL,
    "Status" VARCHAR(50) NOT NULL DEFAULT 'draft',
    "ReviewedBy" VARCHAR(200) NULL,
    "ReviewedAt" TIMESTAMP NULL,
    "ReviewNote" VARCHAR(500) NULL,
    "IsActive" BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedAt" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "CreatedBy" VARCHAR(200) NULL,
    "UpdatedAt" TIMESTAMP NULL,
    "UpdatedBy" VARCHAR(200) NULL,
    "LastModified" TIMESTAMP NULL,
    "LastModifiedBy" VARCHAR(200) NULL,
    "Deleted" TIMESTAMP NULL,
    "DeletedBy" VARCHAR(200) NULL
);

CREATE INDEX IF NOT EXISTS "IX_VisitReport_Employee_Date"
    ON "VisitReports" ("StoreId", "EmployeeId", "VisitDate");

CREATE INDEX IF NOT EXISTS "IX_VisitReport_Location_Date"
    ON "VisitReports" ("StoreId", "LocationId", "VisitDate");

CREATE INDEX IF NOT EXISTS "IX_VisitReport_Status"
    ON "VisitReports" ("StoreId", "Status");

-- 3. Permission module cho Field Check-in
INSERT INTO "Permissions" ("Id", "Module", "ModuleDisplayName", "Description", "DisplayOrder", "CreatedAt")
VALUES ('11111111-1111-1111-1111-111111111042', 'FieldCheckIn', 'Check-in điểm bán', 'Quản lý check-in điểm bán, giao điểm, báo cáo tại điểm', 42, CURRENT_TIMESTAMP)
ON CONFLICT ("Id") DO NOTHING;

SELECT 'Done: FieldLocationAssignments + VisitReports tables created' AS result;
