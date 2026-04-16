-- Check which tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema='public' AND table_type='BASE TABLE'
AND table_name IN ('SalaryProfiles','MealMenus','MealSessions','MealMenuItems','MealSessionShifts','MealRecords','ProductGroups','ProductItems','ProductionEntries','ProductPriceTiers','ShiftSalaryLevels')
ORDER BY table_name;
