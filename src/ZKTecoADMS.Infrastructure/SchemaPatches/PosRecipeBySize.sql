-- Định lượng NVL theo size: dòng định lượng gắn một biến thể hoặc một đơn vị bán («L = 1 M»); cả hai null = mọi size.
-- Một NVL được khai riêng cho từng size.
ALTER TABLE "PosProductRecipeLines" ADD COLUMN IF NOT EXISTS "VariantId" uuid NULL;
ALTER TABLE "PosProductRecipeLines" ADD COLUMN IF NOT EXISTS "UnitId" uuid NULL;
DROP INDEX IF EXISTS "IX_PosProductRecipeLines_Parent_Component_Active";
DROP INDEX IF EXISTS "IX_PosProductRecipeLines_Parent_Variant_Component_Active";
CREATE UNIQUE INDEX IF NOT EXISTS "IX_PosProductRecipeLines_Parent_Size_Component_Active"
    ON "PosProductRecipeLines" ("ParentProductId",
        COALESCE("VariantId", '00000000-0000-0000-0000-000000000000'::uuid),
        COALESCE("UnitId", '00000000-0000-0000-0000-000000000000'::uuid), "ComponentProductId")
    WHERE "Deleted" IS NULL;
CREATE INDEX IF NOT EXISTS "IX_PosProductRecipeLines_VariantId" ON "PosProductRecipeLines" ("VariantId");
