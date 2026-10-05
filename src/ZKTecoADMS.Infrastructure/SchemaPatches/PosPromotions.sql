-- Chương trình khuyến mãi tự áp ở màn bán + ghi lại khuyến mãi đã áp trên hóa đơn (báo cáo hiệu quả)
CREATE TABLE IF NOT EXISTS "PosPromotions" (
    "Id" uuid NOT NULL PRIMARY KEY,
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT NOW(),
    "UpdatedAt" timestamp without time zone NULL,
    "UpdatedBy" text NULL,
    "CreatedBy" text NULL,
    "IsActive" boolean NOT NULL DEFAULT true,
    "LastModified" timestamp without time zone NULL,
    "LastModifiedBy" text NULL,
    "Deleted" timestamp without time zone NULL,
    "DeletedBy" text NULL,
    "StoreId" uuid NOT NULL,
    "Name" character varying(200) NOT NULL DEFAULT '',
    "Type" character varying(30) NOT NULL DEFAULT 'time_discount',
    "Priority" integer NOT NULL DEFAULT 0,
    "Stackable" boolean NOT NULL DEFAULT false,
    "ValidFrom" timestamp without time zone NULL,
    "ValidTo" timestamp without time zone NULL,
    "DaysOfWeekMask" integer NOT NULL DEFAULT 0,
    "TimeFromMinutes" integer NULL,
    "TimeToMinutes" integer NULL,
    "MembersOnly" boolean NOT NULL DEFAULT false,
    "ConfigJson" text NOT NULL DEFAULT '{}',
    "Note" character varying(500) NULL
);
CREATE INDEX IF NOT EXISTS "IX_PosPromotions_Store" ON "PosPromotions" ("StoreId", "IsActive");
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PromotionsJson" text NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "PromotionDiscount" numeric(18,2) NOT NULL DEFAULT 0;
