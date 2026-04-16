-- Full schema dump: table_name, column_name, data_type, is_nullableSELECT table_name, column_name, data_type, is_nullable, character_maximum_length FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, ordinal_position;
SELECT table_name, column_name, data_type, is_nullable, character_maximum_length
FROM information_schema.columns 
WHERE table_schema='public' 
ORDER BY table_name, ordinal_position;
