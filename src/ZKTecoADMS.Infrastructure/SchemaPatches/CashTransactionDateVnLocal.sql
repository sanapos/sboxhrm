-- Thống nhất CashTransaction.TransactionDate về giờ VN local.
-- Trước đây phiếu tự sinh (POS sync, lương, ứng…) lưu UTC, phiếu tạo tay lưu VN local.
-- Giờ tất cả đều lưu VN local → cộng 7 giờ cho các phiếu đang lưu UTC.
--
-- Phiếu UTC: SourceType IS NOT NULL AND SourceType <> 'manual'
--         OR  SourceType IS NULL nhưng TransactionDate ≈ CreatedAt (phiếu cũ trước khi có SourceType)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'CashTransactionDateVnLocal'
  ) THEN
    UPDATE "CashTransactions"
    SET "TransactionDate" = "TransactionDate" + INTERVAL '7 hours'
    WHERE ("SourceType" IS NOT NULL AND "SourceType" <> 'manual')
       OR ("SourceType" IS NULL
           AND "TransactionDate" > "CreatedAt" - INTERVAL '5 minutes'
           AND "TransactionDate" < "CreatedAt" + INTERVAL '5 minutes');

    INSERT INTO "__SchemaPatches" ("Name", "AppliedAt")
    VALUES ('CashTransactionDateVnLocal', NOW());
  END IF;
END $$;
