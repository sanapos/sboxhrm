-- Maintenance windows for SuperAdmin (Phase 2). Idempotent.
CREATE TABLE IF NOT EXISTS "MaintenanceWindows" (
    "Id"                     uuid         NOT NULL PRIMARY KEY,
    "Title"                  varchar(200) NOT NULL,
    "Message"                text         NOT NULL,
    "StartAt"                timestamp    NOT NULL,
    "EndAt"                  timestamp    NOT NULL,
    "AffectedModulesJson"    jsonb        NULL,
    "IsActive"               boolean      NOT NULL DEFAULT false,
    "BlockAccess"            boolean      NOT NULL DEFAULT true,
    "NotifyBeforeMinutesCsv" varchar(100) NULL,
    "NotifiedMinutesCsv"     varchar(100) NULL,
    "StartNotified"          boolean      NOT NULL DEFAULT false,
    "EndNotified"            boolean      NOT NULL DEFAULT false,
    "CreatedByUserId"        uuid         NOT NULL,
    "CreatedAt"              timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"              text         NULL,
    "UpdatedAt"              timestamp    NULL,
    "UpdatedBy"              text         NULL
);

CREATE INDEX IF NOT EXISTS "IX_MaintenanceWindows_Active_Range"
    ON "MaintenanceWindows" ("IsActive", "StartAt", "EndAt");
