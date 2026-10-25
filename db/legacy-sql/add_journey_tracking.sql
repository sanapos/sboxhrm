-- Journey Tracking table for field staff route management
-- Tracks daily journeys with GPS route, travel time, site time

CREATE TABLE IF NOT EXISTS "JourneyTrackings" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "EmployeeId" character varying(100) NOT NULL,
    "EmployeeName" character varying(200) NOT NULL DEFAULT '',
    "JourneyDate" timestamp without time zone NOT NULL,
    "StartTime" timestamp without time zone,
    "EndTime" timestamp without time zone,
    "Status" character varying(30) NOT NULL DEFAULT 'not_started',
    "TotalDistanceKm" double precision NOT NULL DEFAULT 0,
    "TotalTravelMinutes" integer NOT NULL DEFAULT 0,
    "TotalOnSiteMinutes" integer NOT NULL DEFAULT 0,
    "CheckedInCount" integer NOT NULL DEFAULT 0,
    "AssignedCount" integer NOT NULL DEFAULT 0,
    "RoutePointsJson" text,
    "Note" character varying(1000),
    "ReviewedBy" character varying(200),
    "ReviewedAt" timestamp without time zone,
    "ReviewNote" character varying(500),
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone,
    "LastModifiedBy" text,
    "Deleted" timestamp without time zone,
    "DeletedBy" text,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_JourneyTrackings" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_JourneyTrackings_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "IX_Journey_Employee_Date" ON "JourneyTrackings" ("StoreId", "EmployeeId", "JourneyDate");
CREATE INDEX IF NOT EXISTS "IX_Journey_Status" ON "JourneyTrackings" ("StoreId", "Status");
