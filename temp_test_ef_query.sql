-- Simulate the exact EF Core query for GetWeeklyMealMenu
SELECT m."Id", m."Date", m."DayOfWeek", m."MealSessionId", m."Note", m."IsActive", m."StoreId", m."CreatedAt",
       ms."Name" as session_name, ms."StartTime", ms."PricePerMeal",
       mi."Id" as item_id, mi."DishName", mi."Category", mi."SortOrder"
FROM "MealMenus" m
LEFT JOIN "MealSessions" ms ON m."MealSessionId" = ms."Id"
LEFT JOIN "MealMenuItems" mi ON m."Id" = mi."MealMenuId"
WHERE m."Deleted" IS NULL
  AND m."StoreId" = '985262f9-7166-47c9-9edd-1847f620a3a2'
  AND m."Date" >= '2026-04-13' AND m."Date" < '2026-04-20'
  AND m."IsActive" = true
ORDER BY m."Date", ms."StartTime", mi."SortOrder";
