-- Create EmployeeLiveLocations table for real-time GPS tracking
CREATE TABLE IF NOT EXISTS "EmployeeLiveLocations" (
    "Id"         uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId"    uuid NOT NULL,
    "EmployeeId" varchar(100) NOT NULL,
    "Latitude"   double precision NOT NULL DEFAULT 0,
    "Longitude"  double precision NOT NULL DEFAULT 0,
    "Accuracy"   double precision NULL,
    "UpdatedAt"  timestamp without time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT "PK_EmployeeLiveLocations" PRIMARY KEY ("Id")
);

-- Unique constraint: one row per employee per store
CREATE UNIQUE INDEX IF NOT EXISTS "IX_EmployeeLiveLocations_StoreId_EmployeeId"
    ON "EmployeeLiveLocations" ("StoreId", "EmployeeId");

-- Index for fast lookup by store
CREATE INDEX IF NOT EXISTS "IX_EmployeeLiveLocations_StoreId"
    ON "EmployeeLiveLocations" ("StoreId");
