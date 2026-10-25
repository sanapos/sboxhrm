-- Add Size and Color columns to Assets table
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Size" TEXT;
ALTER TABLE "Assets" ADD COLUMN IF NOT EXISTS "Color" TEXT;
