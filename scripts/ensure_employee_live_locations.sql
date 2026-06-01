-- Idempotent: GPS live location table for field-checkin report-location
CREATE TABLE IF NOT EXISTS "EmployeeLiveLocations" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "Latitude" double precision NOT NULL,
    "Longitude" double precision NOT NULL,
    "Accuracy" double precision NULL,
    "UpdatedAt" timestamp without time zone NOT NULL,
    CONSTRAINT "PK_EmployeeLiveLocations" PRIMARY KEY ("Id")
);
