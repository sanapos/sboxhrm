-- Thống nhất CashTransaction.TransactionDate về giờ VN local (các báo cáo thu chi / sổ HKD / đối soát đọc giờ VN).
-- Trước đây phiếu tự sinh (POS, lương, ứng, phạt…) lưu UTC, phiếu tạo tay lưu VN local.
-- Code ghi phiếu đã đổi sang giờ VN → cộng 7 giờ cho các phiếu CÒN lưu UTC.
--
-- Chỉ phiếu đang lưu UTC: CreatedAt luôn là UTC nên phiếu UTC có TransactionDate ≈ CreatedAt (±10 phút);
-- phiếu đã ghi giờ VN có TransactionDate ≈ CreatedAt + 7h → không bị cộng lần nữa
-- (bản vá ra đời cùng lúc code đổi giờ nhưng chưa từng chạy vì thiếu bảng "__SchemaPatches").
-- Phiếu tay (SourceType = 'manual') giữ nguyên.
CREATE TABLE IF NOT EXISTS "__SchemaPatches" (
  "Name" character varying(200) NOT NULL PRIMARY KEY,
  "AppliedAt" timestamp with time zone NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "__SchemaPatches" WHERE "Name" = 'CashTransactionDateVnLocal'
  ) THEN
    UPDATE "CashTransactions"
    SET "TransactionDate" = "TransactionDate" + INTERVAL '7 hours'
    WHERE ("SourceType" IS NULL OR "SourceType" <> 'manual')
      AND "TransactionDate" > "CreatedAt" - INTERVAL '10 minutes'
      AND "TransactionDate" < "CreatedAt" + INTERVAL '10 minutes';

    INSERT INTO "__SchemaPatches" ("Name", "AppliedAt")
    VALUES ('CashTransactionDateVnLocal', NOW());
  END IF;
END $$;
