#!/bin/bash
set -euo pipefail
K58=$(cat /tmp/k58_sale_v2.html)
K80=$(cat /tmp/k80_sale_v2.html)
docker exec -i zkteco_postgres psql -U postgres -d ZKTecoADMS -v ON_ERROR_STOP=1 <<SQL
UPDATE "PosPrintTemplateCatalogs"
SET "HtmlContent" = \$k58\$${K58}\$k58\$,
    "UpdatedAt" = NOW(),
    "UpdatedBy" = 'system-k58-vn'
WHERE "DocumentType" = 1 AND "PaperSize" = 0 AND "Deleted" IS NULL;

UPDATE "PosPrintTemplateCatalogs"
SET "HtmlContent" = \$k80\$${K80}\$k80\$,
    "UpdatedAt" = NOW(),
    "UpdatedBy" = 'system-k58-vn'
WHERE "DocumentType" = 1 AND "PaperSize" = 1 AND "Deleted" IS NULL;

UPDATE "PosPrintTemplates"
SET "HtmlContent" = \$k58\$${K58}\$k58\$,
    "UpdatedAt" = NOW(),
    "UpdatedBy" = 'system-k58-vn'
WHERE "DocumentType" = 1 AND "PaperSize" = 0 AND "Deleted" IS NULL
  AND (
    "SourceCatalogId" IS NOT NULL
    OR "HtmlContent" LIKE '%"So HD"%'
    OR "HtmlContent" LIKE '%So HD:%'
    OR "HtmlContent" LIKE '%Cam on quy khach%'
  );

UPDATE "PosPrintTemplates"
SET "HtmlContent" = \$k80\$${K80}\$k80\$,
    "UpdatedAt" = NOW(),
    "UpdatedBy" = 'system-k58-vn'
WHERE "DocumentType" = 1 AND "PaperSize" = 1 AND "Deleted" IS NULL
  AND (
    "SourceCatalogId" IS NOT NULL
    OR "HtmlContent" LIKE '%"So HD"%'
    OR "HtmlContent" LIKE '%So HD:%'
    OR "HtmlContent" LIKE '%Cam on quy khach%'
  );

SELECT 'catalog' AS kind, "Name", "PaperSize", "UpdatedBy",
       ("HtmlContent" LIKE '%Số HĐ%') AS has_sohd,
       ("HtmlContent" LIKE '%Cảm ơn%') AS has_camon,
       ("HtmlContent" LIKE '%So HD%') AS still_unsigned
FROM "PosPrintTemplateCatalogs"
WHERE "DocumentType"=1 AND "PaperSize" IN (0,1) AND "Deleted" IS NULL;

SELECT 'store_k58' AS kind, COUNT(*) AS n,
       COUNT(*) FILTER (WHERE "HtmlContent" LIKE '%Số HĐ%') AS with_sohd,
       COUNT(*) FILTER (WHERE "HtmlContent" LIKE '%So HD%') AS still_unsigned
FROM "PosPrintTemplates"
WHERE "DocumentType"=1 AND "PaperSize"=0 AND "Deleted" IS NULL;
SQL
