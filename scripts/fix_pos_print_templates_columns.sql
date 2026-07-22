-- EF AuditableEntity cần LastModified / LastModifiedBy (bảng tạo ban đầu thiếu).
ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "LastModified" timestamp without time zone;
ALTER TABLE "PosPrintTemplates" ADD COLUMN IF NOT EXISTS "LastModifiedBy" text;
