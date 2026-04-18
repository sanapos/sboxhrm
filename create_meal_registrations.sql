CREATE TABLE IF NOT EXISTS "MealRegistrations" (
    "Id" uuid NOT NULL DEFAULT gen_random_uuid(),
    "EmployeeUserId" uuid NOT NULL,
    "EmployeeName" varchar(200) NOT NULL DEFAULT '',
    "MealSessionId" uuid NOT NULL,
    "Date" timestamp NOT NULL,
    "IsRegistered" boolean NOT NULL DEFAULT true,
    "RegisteredAt" timestamp NOT NULL DEFAULT now(),
    "CancelledAt" timestamp,
    "Note" varchar(500),
    "StoreId" uuid,
    "CreatedAt" timestamp NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp,
    "UpdatedBy" uuid,
    "CreatedBy" uuid,
    PRIMARY KEY ("Id"),
    CONSTRAINT "FK_MealRegistrations_Users" FOREIGN KEY ("EmployeeUserId") REFERENCES "AspNetUsers"("Id"),
    CONSTRAINT "FK_MealRegistrations_MealSessions" FOREIGN KEY ("MealSessionId") REFERENCES "MealSessions"("Id"),
    CONSTRAINT "FK_MealRegistrations_Stores" FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id")
);
CREATE INDEX IF NOT EXISTS "IX_MealRegistrations_EmployeeUserId" ON "MealRegistrations"("EmployeeUserId");
CREATE INDEX IF NOT EXISTS "IX_MealRegistrations_MealSessionId" ON "MealRegistrations"("MealSessionId");
CREATE INDEX IF NOT EXISTS "IX_MealRegistrations_Date" ON "MealRegistrations"("Date");
CREATE UNIQUE INDEX IF NOT EXISTS "IX_MealRegistrations_Unique" ON "MealRegistrations"("EmployeeUserId", "MealSessionId", "Date");
