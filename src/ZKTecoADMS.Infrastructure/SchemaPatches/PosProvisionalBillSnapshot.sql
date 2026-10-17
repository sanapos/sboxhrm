-- Tạm tính: lưu lúc in + số tiền lớn nhất đã in cho khách → báo cáo «Nguy cơ gian lận» thấy đơn bị giảm sau tạm tính.
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillRequestedAt" timestamp without time zone NULL;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillRequestedTotal" numeric(18,2) NULL;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillRequestedBy" character varying(200) NULL;
ALTER TABLE "PosResourceSessions" ADD COLUMN IF NOT EXISTS "BillRequestCount" integer NOT NULL DEFAULT 0;

-- Báo cáo nguy cơ quét theo cửa hàng + thời gian.
CREATE INDEX IF NOT EXISTS "IX_PosCancelReturnAudits_Store_OccurredAt"
    ON "PosCancelReturnAudits" ("StoreId", "OccurredAt");
