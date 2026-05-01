SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND lower(table_name) LIKE '%attend%';
SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND lower(table_name) LIKE '%log%';
