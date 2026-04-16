-- Full schema dump: all tables and their columns on server
SELECT t.table_name, c.column_name, c.data_type, c.is_nullable, c.character_maximum_length
FROM information_schema.tables t
JOIN information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name, c.ordinal_position;
