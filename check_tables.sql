SELECT table_name FROM information_schema.tables 
WHERE table_schema='public' AND table_type='BASE TABLE'
AND table_name IN ('Benefits','MealMenus','MealSessions','ProductGroups','ProductItems','ProductionEntries','ProductPriceTiers','ShiftSalaryLevels')
ORDER BY table_name;
