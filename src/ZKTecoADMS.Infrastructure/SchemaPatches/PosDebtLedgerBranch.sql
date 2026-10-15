-- Sổ công nợ theo chi nhánh: mỗi dòng gắn chi nhánh của chứng từ (đơn bán / phiếu nhập / phiếu trả / thu trả nợ).
ALTER TABLE "PosDebtLedgerEntries" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
CREATE INDEX IF NOT EXISTS "IX_PosDebtLedgerEntries_Branch" ON "PosDebtLedgerEntries" ("StoreId", "BranchId", "PartyType", "At");

CREATE TABLE IF NOT EXISTS "__SchemaPatches" (
  "Name" character varying(200) NOT NULL PRIMARY KEY,
  "AppliedAt" timestamp with time zone NOT NULL DEFAULT now()
);

-- Một lần: gán chi nhánh cho dòng sổ cũ theo chứng từ gốc (dòng không xác định được giữ NULL = trụ sở).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'PosDebtLedgerBranch') THEN
    UPDATE "PosDebtLedgerEntries" e SET "BranchId" = o."BranchId"
      FROM "PosSaleOrders" o
     WHERE e."BranchId" IS NULL AND e."DocId" = o."Id" AND e."DocType" IN ('Sale','SaleCancel','Return','ReturnVoid');
    UPDATE "PosDebtLedgerEntries" e SET "BranchId" = r."BranchId"
      FROM "PosStockReceipts" r
     WHERE e."BranchId" IS NULL AND e."DocId" = r."Id" AND e."DocType" IN ('Receipt','ReceiptCancel');
    UPDATE "PosDebtLedgerEntries" e SET "BranchId" = r."BranchId"
      FROM "PosPurchaseReturns" r
     WHERE e."BranchId" IS NULL AND e."DocId" = r."Id" AND e."DocType" IN ('PurchaseReturn','PurchaseReturnCancel');
    UPDATE "PosDebtLedgerEntries" e SET "BranchId" = r."BranchId"
      FROM "PosSupplierPayments" p JOIN "PosStockReceipts" r ON r."Id" = p."StockReceiptId"
     WHERE e."BranchId" IS NULL AND e."DocId" = p."Id" AND e."PartyType" = 'supplier' AND e."DocType" = 'Payment';
    UPDATE "PosDebtLedgerEntries" e SET "BranchId" = o."BranchId"
      FROM "PosCustomerPayments" p JOIN "PosSaleOrders" o ON o."Id" = p."SaleOrderId"
     WHERE e."BranchId" IS NULL AND e."DocId" = p."Id" AND e."PartyType" = 'customer' AND e."DocType" = 'Payment';
    INSERT INTO "__SchemaPatches" ("Name", "AppliedAt") VALUES ('PosDebtLedgerBranch', NOW());
  END IF;
END $$;
