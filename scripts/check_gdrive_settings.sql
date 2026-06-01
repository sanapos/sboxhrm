\echo '=== All google_drive AppSettings (all stores) ==='
SELECT "Key",
  CASE
    WHEN "Key" = 'google_drive_credentials_json' THEN
      CASE WHEN COALESCE(TRIM("Value"), '') <> '' THEN 'configured (' || length("Value")::text || ' chars)' ELSE 'empty' END
    ELSE COALESCE(LEFT("Value", 60), '(null)')
  END AS value_preview,
  "StoreId",
  "Group"
FROM "AppSettings"
WHERE "Key" LIKE 'google_drive%'
ORDER BY "Key", "StoreId" NULLS FIRST;

\echo '=== Service account email from credentials (client_email only) ==='
SELECT substring("Value" from '"client_email"\s*:\s*"([^"]+)"') AS client_email
FROM "AppSettings"
WHERE "Key" = 'google_drive_credentials_json'
  AND COALESCE(TRIM("Value"), '') <> ''
LIMIT 1;
