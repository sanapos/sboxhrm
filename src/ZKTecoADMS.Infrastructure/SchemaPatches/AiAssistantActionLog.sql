-- Nhật ký thao tác Trợ lý ảo: đề xuất chờ xác nhận, kết quả, hoàn tác
CREATE TABLE IF NOT EXISTS "AiActionLogs" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "UserId" uuid NOT NULL,
    "Kind" character varying(60) NOT NULL DEFAULT '',
    "Title" character varying(200) NOT NULL DEFAULT '',
    "Risk" character varying(10) NOT NULL DEFAULT 'normal',
    "Prompt" text NULL,
    "PendingJson" text NOT NULL DEFAULT '',
    "Status" character varying(20) NOT NULL DEFAULT 'proposed',
    "ResultMessage" text NULL,
    "DocNo" character varying(60) NULL,
    "DocId" character varying(60) NULL,
    "UndoJson" text NULL,
    "ExecutedAt" timestamp without time zone NULL,
    "UndoneAt" timestamp without time zone NULL
);
CREATE INDEX IF NOT EXISTS "IX_AiActionLogs_Store_Created" ON "AiActionLogs" ("StoreId", "CreatedAt");
CREATE INDEX IF NOT EXISTS "IX_AiActionLogs_User_Status" ON "AiActionLogs" ("UserId", "Status");

-- Hồ sơ cửa hàng cho Trợ lý ảo (chủ cửa hàng tự viết)
CREATE TABLE IF NOT EXISTS "AiStoreProfiles" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Content" text NOT NULL DEFAULT ''
);
CREATE UNIQUE INDEX IF NOT EXISTS "IX_AiStoreProfiles_Store" ON "AiStoreProfiles" ("StoreId");
