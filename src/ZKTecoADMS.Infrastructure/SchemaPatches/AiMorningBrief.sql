-- Bản tin sáng tự động (AI): thiết lập theo cửa hàng
CREATE TABLE IF NOT EXISTS "AiMorningBriefSettings" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Enabled" boolean NOT NULL DEFAULT FALSE,
    "SendMinute" integer NOT NULL DEFAULT 420,
    "Recipients" character varying(200) NOT NULL DEFAULT 'owner,manager',
    "Sections" character varying(200) NOT NULL DEFAULT 'sales,stock,approvals,attendance,debt'
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_AiMorningBriefSettings_Store" ON "AiMorningBriefSettings" ("StoreId");

-- Nhật ký bản tin đã sinh / đã gửi: mỗi cửa hàng mỗi ngày một dòng (khóa chống gửi trùng)
CREATE TABLE IF NOT EXISTS "AiMorningBriefLogs" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "BriefDate" timestamp without time zone NOT NULL,
    "Status" character varying(20) NOT NULL DEFAULT 'generating',
    "SentAt" timestamp without time zone NULL,
    "RecipientCount" integer NOT NULL DEFAULT 0,
    "AiUsed" boolean NOT NULL DEFAULT FALSE,
    "Text" text NOT NULL DEFAULT '',
    "AiText" text NULL,
    "AiError" character varying(500) NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_AiMorningBriefLogs_Store_Date" ON "AiMorningBriefLogs" ("StoreId", "BriefDate");
