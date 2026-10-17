-- Chuyển quỹ theo chi nhánh; cước khách trả thẳng hãng khi đối soát COD; phiếu đã trả mà Status còn chờ → Hoàn thành.
ALTER TABLE "FundTransfers" ADD COLUMN IF NOT EXISTS "BranchId" uuid NULL;
ALTER TABLE "PosSaleOrders" ADD COLUMN IF NOT EXISTS "DeliveryCodDirectAmount" numeric(18,2) NULL;
UPDATE "CashTransactions" SET "Status" = 2 WHERE "IsPaid" = true AND "Status" NOT IN (2, 3);
