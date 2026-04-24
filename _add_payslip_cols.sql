ALTER TABLE "Payslips"
  ADD COLUMN IF NOT EXISTS "Allowances" numeric,
  ADD COLUMN IF NOT EXISTS "SocialInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "HealthInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "UnemploymentInsurance" numeric,
  ADD COLUMN IF NOT EXISTS "Tax" numeric;
