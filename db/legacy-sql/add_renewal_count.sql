-- Add RenewalCount column to Stores table
ALTER TABLE "Stores" ADD COLUMN IF NOT EXISTS "RenewalCount" INTEGER NOT NULL DEFAULT 0;
