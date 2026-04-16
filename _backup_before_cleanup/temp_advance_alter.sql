ALTER TABLE public."AdvanceRequests" ADD COLUMN IF NOT EXISTS "PaymentMethod" varchar(50) NULL;
ALTER TABLE public."AdvanceRequests" ADD COLUMN IF NOT EXISTS "PaidDate" timestamp NULL;
