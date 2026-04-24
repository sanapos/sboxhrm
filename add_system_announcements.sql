-- =====================================================================
-- Phase 1: SuperAdmin Announcements / Broadcast / Marketing foundation
-- Tạo bảng SystemAnnouncements + AnnouncementDeliveries
-- Idempotent — có thể chạy lại nhiều lần.
-- =====================================================================

CREATE TABLE IF NOT EXISTS "SystemAnnouncements" (
    "Id"               uuid         NOT NULL PRIMARY KEY,
    "Title"            varchar(200) NOT NULL,
    "Content"          text         NOT NULL,
    "Kind"             integer      NOT NULL DEFAULT 0,
    "Severity"         integer      NOT NULL DEFAULT 0,
    "Status"           integer      NOT NULL DEFAULT 0,
    "Channels"         integer      NOT NULL DEFAULT 3, -- InApp(1)|Banner(2)
    "AudienceJson"     jsonb        NOT NULL DEFAULT '{}'::jsonb,
    "ScheduleAt"       timestamp    NULL,
    "ExpiresAt"        timestamp    NULL,
    "RequireAck"       boolean      NOT NULL DEFAULT false,
    "AllowDismiss"     boolean      NOT NULL DEFAULT true,
    "ImageUrl"         varchar(500) NULL,
    "ActionUrl"        varchar(500) NULL,
    "ActionLabel"      varchar(100) NULL,
    "RecipientCount"   integer      NOT NULL DEFAULT 0,
    "DeliveredCount"   integer      NOT NULL DEFAULT 0,
    "SeenCount"        integer      NOT NULL DEFAULT 0,
    "ClickedCount"     integer      NOT NULL DEFAULT 0,
    "AckedCount"       integer      NOT NULL DEFAULT 0,
    "SentAt"           timestamp    NULL,
    "CreatedAt"        timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"        text         NULL,
    "UpdatedAt"        timestamp    NULL,
    "UpdatedBy"        text         NULL
);

CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_Status"
    ON "SystemAnnouncements" ("Status");
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_ScheduleAt"
    ON "SystemAnnouncements" ("ScheduleAt");
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_ExpiresAt"
    ON "SystemAnnouncements" ("ExpiresAt");
CREATE INDEX IF NOT EXISTS "IX_SystemAnnouncements_Status_Expires"
    ON "SystemAnnouncements" ("Status", "ExpiresAt");

CREATE TABLE IF NOT EXISTS "AnnouncementDeliveries" (
    "Id"             uuid       NOT NULL PRIMARY KEY,
    "AnnouncementId" uuid       NOT NULL,
    "UserId"         uuid       NOT NULL,
    "StoreId"        uuid       NULL,
    "Channel"        integer    NOT NULL DEFAULT 1,
    "Status"         integer    NOT NULL DEFAULT 0,
    "DeliveredAt"    timestamp  NULL,
    "SeenAt"         timestamp  NULL,
    "ClickedAt"      timestamp  NULL,
    "AckedAt"        timestamp  NULL,
    "DismissedAt"    timestamp  NULL,
    "ErrorMessage"   varchar(500) NULL,
    "CreatedAt"      timestamp  NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"      text       NULL,
    "UpdatedAt"      timestamp  NULL,
    "UpdatedBy"      text       NULL,
    CONSTRAINT "FK_AnnouncementDeliveries_Announcement"
        FOREIGN KEY ("AnnouncementId") REFERENCES "SystemAnnouncements"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_AnnouncementDeliveries_User"
        FOREIGN KEY ("UserId") REFERENCES "AspNetUsers"("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_AnnouncementDeliveries_Store"
        FOREIGN KEY ("StoreId") REFERENCES "Stores"("Id") ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "IX_AnnouncementDeliveries_AnnId"
    ON "AnnouncementDeliveries" ("AnnouncementId");
CREATE INDEX IF NOT EXISTS "IX_AnnouncementDeliveries_UserId"
    ON "AnnouncementDeliveries" ("UserId");
CREATE INDEX IF NOT EXISTS "IX_AnnouncementDeliveries_StoreId"
    ON "AnnouncementDeliveries" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_AnnouncementDeliveries_User_Status"
    ON "AnnouncementDeliveries" ("UserId", "Status");
CREATE UNIQUE INDEX IF NOT EXISTS "UX_AnnouncementDeliveries_Ann_User_Channel"
    ON "AnnouncementDeliveries" ("AnnouncementId", "UserId", "Channel");
