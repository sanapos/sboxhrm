DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name LIKE '%FK_Leaves_Shift%' AND table_name = 'Leaves'
    ) THEN
        EXECUTE (
            SELECT 'ALTER TABLE "Leaves" DROP CONSTRAINT "' || constraint_name || '"'
            FROM information_schema.table_constraints 
            WHERE constraint_name LIKE '%FK_Leaves_Shift%' AND table_name = 'Leaves'
            LIMIT 1
        );
    END IF;
END $$;

DROP INDEX IF EXISTS "IX_Leaves_ShiftId";
