-- Create FieldLocations table (customer shops registered by field employees)
-- This is separate from MobileWorkLocations (company branches for attendance)

CREATE TABLE IF NOT EXISTS "FieldLocations" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "Name" varchar(300) NOT NULL,
    "Address" varchar(500),
    "ContactName" varchar(200),
    "ContactPhone" varchar(50),
    "ContactEmail" varchar(200),
    "Note" text,
    "Latitude" double precision NOT NULL DEFAULT 0,
    "Longitude" double precision NOT NULL DEFAULT 0,
    "Radius" integer NOT NULL DEFAULT 200,
    "PhotoUrlsJson" text DEFAULT '[]',
    "RegisteredByEmployeeId" varchar(100),
    "RegisteredByEmployeeName" varchar(200),
    "Category" varchar(100),
    "IsApproved" boolean NOT NULL DEFAULT true,
    "IsActive" boolean NOT NULL DEFAULT true,
    "CreatedBy" text,
    "CreatedAt" timestamp with time zone DEFAULT NOW(),
    "UpdatedBy" text,
    "UpdatedAt" timestamp with time zone,
    "Deleted" timestamp with time zone,
    "DeletedBy" text,
    CONSTRAINT "PK_FieldLocations" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_FieldLocations_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "IX_FieldLocations_StoreId" ON "FieldLocations" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_FieldLocations_RegisteredByEmployeeId" ON "FieldLocations" ("RegisteredByEmployeeId");

-- Update FieldLocationAssignments FK from MobileWorkLocations to FieldLocations
-- First drop the old FK constraint if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints 
               WHERE constraint_name = 'FK_FieldLocationAssignments_MobileWorkLocations_LocationId') THEN
        ALTER TABLE "FieldLocationAssignments" 
        DROP CONSTRAINT "FK_FieldLocationAssignments_MobileWorkLocations_LocationId";
    END IF;
END $$;

-- Add new FK to FieldLocations (only if not exists)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints 
                   WHERE constraint_name = 'FK_FieldLocationAssignments_FieldLocations_LocationId') THEN
        ALTER TABLE "FieldLocationAssignments" 
        ADD CONSTRAINT "FK_FieldLocationAssignments_FieldLocations_LocationId" 
        FOREIGN KEY ("LocationId") REFERENCES "FieldLocations"("Id") ON DELETE CASCADE;
    END IF;
END $$;

-- Update VisitReports FK similarly
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.table_constraints 
               WHERE constraint_name = 'FK_VisitReports_MobileWorkLocations_LocationId') THEN
        ALTER TABLE "VisitReports" 
        DROP CONSTRAINT "FK_VisitReports_MobileWorkLocations_LocationId";
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints 
                   WHERE constraint_name = 'FK_VisitReports_FieldLocations_LocationId') THEN
        ALTER TABLE "VisitReports" 
        ADD CONSTRAINT "FK_VisitReports_FieldLocations_LocationId" 
        FOREIGN KEY ("LocationId") REFERENCES "FieldLocations"("Id") ON DELETE CASCADE;
    END IF;
END $$;

SELECT 'FieldLocations table created and FK constraints updated!' AS result;
