-- Khóa đơn tạm đa máy (P0a)
BEGIN;

ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockVersion" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedByUserId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedByEmployeeId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedByDisplayName" character varying(200) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedByDeviceId" character varying(80) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedByDeviceName" character varying(120) NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockedAt" timestamp without time zone NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "LockExpiresAt" timestamp without time zone NULL;

CREATE INDEX IF NOT EXISTS "IX_PosSaleOrders_StoreId_LockExpiresAt"
    ON "PosSaleOrders" ("StoreId", "LockExpiresAt")
    WHERE "Deleted" IS NULL AND "Status" = 0;

COMMIT;

SELECT 'add_pos_sale_draft_lock applied' AS status;
