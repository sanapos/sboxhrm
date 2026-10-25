-- Migration: Add MealRegistrations table for meal pre-registration
-- Date: 2026-04-14

CREATE TABLE IF NOT EXISTS "MealRegistrations" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "EmployeeUserId" uuid NOT NULL,
    "EmployeeName" character varying(200) NOT NULL DEFAULT '',
    "MealSessionId" uuid NOT NULL,
    "Date" timestamp without time zone NOT NULL,
    "IsRegistered" boolean NOT NULL DEFAULT true,
    "RegisteredAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "CancelledAt" timestamp without time zone NULL,
    "Note" character varying(500) NULL,
    "StoreId" uuid NULL,
    CONSTRAINT "PK_MealRegistrations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealRegistrations_AspNetUsers" FOREIGN KEY ("EmployeeUserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealRegistrations_MealSessions" FOREIGN KEY ("MealSessionId") REFERENCES "MealSessions" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_MealRegistrations_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE SET NULL
);

-- Unique: one registration per employee per session per date
CREATE UNIQUE INDEX IF NOT EXISTS "IX_MealRegistrations_Employee_Session_Date"
ON "MealRegistrations" ("EmployeeUserId", "MealSessionId", "Date");

-- Query performance indexes
CREATE INDEX IF NOT EXISTS "IX_MealRegistrations_Store_Date"
ON "MealRegistrations" ("StoreId", "Date");

CREATE INDEX IF NOT EXISTS "IX_MealRegistrations_Session_Date"
ON "MealRegistrations" ("MealSessionId", "Date", "IsRegistered");
