-- Cập nhật biểu thuế TNCN 5 bậc (2026) + giảm trừ gia cảnh mới.
UPDATE "TaxSettings" SET
  "PersonalDeduction" = 15500000,
  "DependentDeduction" = 6200000,
  "TaxBracket1Max" = 10000000, "TaxRate1" = 5,
  "TaxBracket2Max" = 30000000, "TaxRate2" = 10,
  "TaxBracket3Max" = 60000000, "TaxRate3" = 20,
  "TaxBracket4Max" = 100000000, "TaxRate4" = 30,
  "TaxBracket5Max" = 100000000, "TaxRate5" = 35,
  "TaxBracket6Max" = 100000000, "TaxRate6" = 35,
  "TaxRate7" = 35,
  "UpdatedAt" = NOW()
WHERE "Deleted" IS NULL;
