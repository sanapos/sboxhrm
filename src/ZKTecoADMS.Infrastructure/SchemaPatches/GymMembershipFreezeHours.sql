-- Gym: bảo lưu thẻ + khung giờ tập (thẻ sáng / giờ thấp điểm).
ALTER TABLE "PosCustomerSessionBalances" ADD COLUMN IF NOT EXISTS "FrozenAt" timestamp without time zone NULL;
ALTER TABLE "PosCustomerSessionBalances" ADD COLUMN IF NOT EXISTS "FrozenUntil" timestamp without time zone NULL;
ALTER TABLE "PosCustomerSessionBalances" ADD COLUMN IF NOT EXISTS "AccessHours" character varying(40) NULL;
ALTER TABLE "PosProducts" ADD COLUMN IF NOT EXISTS "GymAccessHours" character varying(40) NULL;
