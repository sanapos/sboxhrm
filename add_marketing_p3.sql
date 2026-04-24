-- Phase 3: NotificationTemplate + MarketingCampaign. Idempotent.

CREATE TABLE IF NOT EXISTS "NotificationTemplates" (
    "Id"            uuid         NOT NULL PRIMARY KEY,
    "Code"          varchar(100) NOT NULL,
    "Title"         varchar(200) NOT NULL,
    "Body"          text         NOT NULL,
    "VariablesJson" jsonb        NULL,
    "Channels"      integer      NOT NULL DEFAULT 1,
    "Locale"        varchar(10)  NOT NULL DEFAULT 'vi-VN',
    "IsActive"      boolean      NOT NULL DEFAULT true,
    "CreatedAt"     timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"     text         NULL,
    "UpdatedAt"     timestamp    NULL,
    "UpdatedBy"     text         NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "UX_NotificationTemplates_Code"
    ON "NotificationTemplates" ("Code");

CREATE TABLE IF NOT EXISTS "MarketingCampaigns" (
    "Id"               uuid         NOT NULL PRIMARY KEY,
    "Name"             varchar(200) NOT NULL,
    "Description"      text         NULL,
    "TemplateId"       uuid         NULL REFERENCES "NotificationTemplates"("Id") ON DELETE SET NULL,
    "AudienceJson"     jsonb        NOT NULL DEFAULT '{}'::jsonb,
    "Channels"         integer      NOT NULL DEFAULT 3,
    "ScheduleAt"       timestamp    NULL,
    "Status"           integer      NOT NULL DEFAULT 0,
    "AnnouncementId"   uuid         NULL,
    "RecipientCount"   integer      NOT NULL DEFAULT 0,
    "DeliveredCount"   integer      NOT NULL DEFAULT 0,
    "OpenedCount"      integer      NOT NULL DEFAULT 0,
    "ClickedCount"     integer      NOT NULL DEFAULT 0,
    "CreatedByUserId"  uuid         NOT NULL,
    "LaunchedAt"       timestamp    NULL,
    "CreatedAt"        timestamp    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    "CreatedBy"        text         NULL,
    "UpdatedAt"        timestamp    NULL,
    "UpdatedBy"        text         NULL
);
CREATE INDEX IF NOT EXISTS "IX_MarketingCampaigns_Status"
    ON "MarketingCampaigns" ("Status");
CREATE INDEX IF NOT EXISTS "IX_MarketingCampaigns_ScheduleAt"
    ON "MarketingCampaigns" ("ScheduleAt");
