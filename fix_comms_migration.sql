-- Migration: Fix InternalCommunications + create ContentCategories
-- Date: 2025-06-04

BEGIN;

-- ============================================
-- 1. Create ContentCategories table
-- ============================================
CREATE TABLE IF NOT EXISTS "ContentCategories" (
    "Id" uuid NOT NULL,
    "StoreId" uuid NOT NULL,
    "Name" character varying(200) NOT NULL,
    "Description" character varying(500),
    "ContentType" integer NOT NULL DEFAULT 0,
    "IconName" character varying(100),
    "Color" character varying(10),
    "DisplayOrder" integer NOT NULL DEFAULT 0,
    "ParentCategoryId" uuid,
    "IsActive" boolean NOT NULL DEFAULT true,
    -- Entity base
    "CreatedAt" timestamp without time zone NOT NULL DEFAULT now(),
    "UpdatedAt" timestamp without time zone,
    "UpdatedBy" text,
    "CreatedBy" text,
    CONSTRAINT "PK_ContentCategories" PRIMARY KEY ("Id"),
    CONSTRAINT "FK_ContentCategories_Stores_StoreId" FOREIGN KEY ("StoreId") REFERENCES "Stores" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_ContentCategories_ContentCategories_ParentCategoryId" FOREIGN KEY ("ParentCategoryId") REFERENCES "ContentCategories" ("Id") ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS "IX_ContentCategories_StoreId" ON "ContentCategories" ("StoreId");
CREATE INDEX IF NOT EXISTS "IX_ContentCategories_ParentCategoryId" ON "ContentCategories" ("ParentCategoryId");

-- ============================================
-- 2. Add CategoryId column to InternalCommunications
-- ============================================
ALTER TABLE "InternalCommunications" ADD COLUMN IF NOT EXISTS "CategoryId" uuid;
ALTER TABLE "InternalCommunications" ADD CONSTRAINT "FK_InternalCommunications_ContentCategories_CategoryId" FOREIGN KEY ("CategoryId") REFERENCES "ContentCategories" ("Id") ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS "IX_InternalCommunications_CategoryId" ON "InternalCommunications" ("CategoryId");

COMMIT;
