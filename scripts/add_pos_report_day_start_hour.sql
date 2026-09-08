-- POS: giờ cắt ngày kinh doanh / ngày qua đêm cho báo cáo & cuối ngày.
ALTER TABLE "PosStoreSellSettings"
  ADD COLUMN IF NOT EXISTS "ReportDayStartHour" integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN "PosStoreSellSettings"."ReportDayStartHour" IS
  '0=nửa đêm VN; >0=ngày qua đêm bắt đầu giờ đó (UTC+7)';
