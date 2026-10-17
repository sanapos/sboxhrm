-- Khuyến mãi theo chi nhánh: null / rỗng = mọi chi nhánh.
ALTER TABLE "PosPromotions" ADD COLUMN IF NOT EXISTS "BranchIdsJson" text NULL;
