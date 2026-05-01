SELECT table_name FROM information_schema.tables WHERE table_name ILIKE '%shift%' OR table_name ILIKE '%schedule%' ORDER BY 1;
