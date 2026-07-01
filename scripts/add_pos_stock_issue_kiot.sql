-- Xuất hủy / xuất dùng nội bộ: trạng thái, loại phiếu, giá vốn dòng
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "Kind" integer NOT NULL DEFAULT 0;
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "Status" integer NOT NULL DEFAULT 1;
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "IssuedAt" timestamp without time zone;
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "IssuedBy" character varying(200);
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "CategoryName" character varying(100);
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "RecipientName" character varying(200);
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "CompletedAt" timestamp without time zone;
ALTER TABLE "PosStockIssues" ADD COLUMN IF NOT EXISTS "TotalValue" numeric(18,4) NOT NULL DEFAULT 0;

ALTER TABLE "PosStockIssueLines" ADD COLUMN IF NOT EXISTS "CostPrice" numeric(18,4) NOT NULL DEFAULT 0;
ALTER TABLE "PosStockIssueLines" ADD COLUMN IF NOT EXISTS "UnitName" character varying(50);
ALTER TABLE "PosStockIssueLines" ADD COLUMN IF NOT EXISTS "LineNote" character varying(500);

CREATE INDEX IF NOT EXISTS "IX_PosStockIssues_StoreId_Kind_Status"
    ON "PosStockIssues"("StoreId", "Kind", "Status");
