-- Performance indexes for mobile attendance scalability (thousands of concurrent devices)
-- Run this against the PostgreSQL database

-- MobileAttendanceRecords: Most queried table (history, pending, punch count)
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileAttendanceRecords_Employee_PunchTime"
    ON public."MobileAttendanceRecords" ("OdooEmployeeId", "PunchTime" DESC)
    WHERE "Deleted" IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileAttendanceRecords_Store_Status"
    ON public."MobileAttendanceRecords" ("StoreId", "Status")
    WHERE "Deleted" IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileAttendanceRecords_Store_PunchDate"
    ON public."MobileAttendanceRecords" ("StoreId", ("PunchTime"::date), "OdooEmployeeId")
    WHERE "Deleted" IS NULL;

-- AuthorizedMobileDevices: Checked on every punch + device registration
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_AuthorizedMobileDevices_DeviceId_Store"
    ON public."AuthorizedMobileDevices" ("DeviceId", "StoreId")
    WHERE "Deleted" IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_AuthorizedMobileDevices_Employee_Store"
    ON public."AuthorizedMobileDevices" ("EmployeeId", "StoreId")
    WHERE "Deleted" IS NULL;

-- MobileWorkLocations: Loaded for WiFi check + punch verification
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileWorkLocations_Active"
    ON public."MobileWorkLocations" ("IsActive", "StoreId")
    WHERE "Deleted" IS NULL;

-- MobileAttendanceSettings: Loaded on every settings/punch request
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileAttendanceSettings_Store"
    ON public."MobileAttendanceSettings" ("StoreId")
    WHERE "Deleted" IS NULL;

-- MobileFaceRegistrations: Loaded for device status + face verify
CREATE INDEX CONCURRENTLY IF NOT EXISTS "IX_MobileFaceRegistrations_Employee_Store"
    ON public."MobileFaceRegistrations" ("OdooEmployeeId", "StoreId")
    WHERE "Deleted" IS NULL;
