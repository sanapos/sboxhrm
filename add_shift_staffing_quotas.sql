-- Create ShiftStaffingQuotas table
CREATE TABLE IF NOT EXISTS "ShiftStaffingQuotas" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "StoreId" uuid NOT NULL,
    "ShiftTemplateId" uuid NOT NULL,
    "Department" text NULL,
    "MinEmployees" integer NOT NULL DEFAULT 1,
    "MaxEmployees" integer NOT NULL DEFAULT 10,
    "WarningThreshold" integer NOT NULL DEFAULT 2,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone NULL,
    "CreatedBy" text NULL,
    "UpdatedBy" text NULL,
    CONSTRAINT "PK_ShiftStaffingQuotas" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ShiftStaffingQuotas_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ShiftStaffingQuotas_ShiftTemplates_ShiftTemplateId" FOREIGN KEY ("ShiftTemplateId") REFERENCES "ShiftTemplates" ("Id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_ShiftStaffingQuotas_Store_Shift_Dept"
ON "ShiftStaffingQuotas" ("StoreId", "ShiftTemplateId", COALESCE("Department", ''));

CREATE INDEX IF NOT EXISTS "IX_ShiftStaffingQuotas_StoreId" ON "ShiftStaffingQuotas" ("StoreId");
