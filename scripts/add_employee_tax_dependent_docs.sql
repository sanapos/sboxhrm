-- Hồ sơ giấy tờ + phiếu đăng ký người phụ thuộc (TNCN)
ALTER TABLE "EmployeeTaxDeductions"
  ADD COLUMN IF NOT EXISTS "DependentRegistrationFormUrl" character varying(1000) NULL;

ALTER TABLE "EmployeeTaxDeductions"
  ADD COLUMN IF NOT EXISTS "DependentDocumentsJson" text NULL;
