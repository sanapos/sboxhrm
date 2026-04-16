SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename LIKE 'Field%' OR tablename LIKE 'Visit%' OR tablename LIKE 'Journey%') ORDER BY 1;
SELECT conname, conrelid::regclass, confrelid::regclass FROM pg_constraint WHERE conname LIKE '%FieldLocations%';
