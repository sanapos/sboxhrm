-- Bảo hành: phiếu tiếp nhận đầy đủ (số phiếu, liên hệ, tình trạng, phụ kiện, hẹn trả, phụ trách),
-- phí sửa + phiếu thu, bước «Đã trả khách» (DeliveredDate; trạng thái giữ Hoàn tất / Từ chối).
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "ClaimNo" character varying(30) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "ContactName" character varying(150) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "ContactPhone" character varying(30) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "DeviceCondition" character varying(500) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "Accessories" character varying(500) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "ExpectedReturnDate" timestamp without time zone NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "AssignedTo" character varying(150) NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "Fee" numeric(18,2) NOT NULL DEFAULT 0;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "FeePaid" boolean NOT NULL DEFAULT false;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "CashTransactionId" uuid NULL;
ALTER TABLE "PosWarrantyClaims" ADD COLUMN IF NOT EXISTS "DeliveredDate" timestamp without time zone NULL;
CREATE INDEX IF NOT EXISTS "IX_PosWarrantyClaims_StoreId_ClaimNo" ON "PosWarrantyClaims" ("StoreId", "ClaimNo");

-- Một lần: phiếu sửa đã đóng từ trước khi có bước «Đã trả khách» coi như đã trả máy,
-- không thì cả lịch sử cũ hiện thành «máy đang ở cửa hàng».
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'PosWarrantyService.delivered_backfill') THEN
        UPDATE "PosWarrantyClaims"
           SET "DeliveredDate" = COALESCE("ResolvedDate", "ReceivedDate")
         WHERE "Status" IN (2, 3) AND "DeliveredDate" IS NULL;
        INSERT INTO "__SchemaPatches" ("Name") VALUES ('PosWarrantyService.delivered_backfill');
    END IF;
END $$;
