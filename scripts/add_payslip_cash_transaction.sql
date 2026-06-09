ALTER TABLE "Payslips" ADD COLUMN IF NOT EXISTS "CashTransactionId" uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'FK_Payslips_CashTransactions_CashTransactionId'
  ) THEN
    ALTER TABLE "Payslips"
      ADD CONSTRAINT "FK_Payslips_CashTransactions_CashTransactionId"
      FOREIGN KEY ("CashTransactionId") REFERENCES "CashTransactions" ("Id") ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "IX_Payslips_CashTransactionId"
  ON "Payslips" ("CashTransactionId");
