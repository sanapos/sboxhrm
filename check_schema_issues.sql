-- Compare server schema with expected schema from EF Core
-- Check for common missing columns across all tables

-- 1. Check all tables for missing AuditableEntity columns
SELECT t.table_name, 
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='Deleted') THEN 'Y' ELSE 'N' END as "Deleted",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='DeletedBy') THEN 'Y' ELSE 'N' END as "DeletedBy",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='IsActive') THEN 'Y' ELSE 'N' END as "IsActive",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='LastModified') THEN 'Y' ELSE 'N' END as "LastMod",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='LastModifiedBy') THEN 'Y' ELSE 'N' END as "LastModBy"
FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
  AND t.table_name NOT LIKE 'AspNet%' AND t.table_name NOT LIKE '__EF%'
  AND (
    NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='Deleted')
    OR NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='IsActive')
  )
ORDER BY t.table_name;

-- 2. Check for tables with Entity base but missing CreatedBy/UpdatedBy
SELECT t.table_name,
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='CreatedAt') THEN 'Y' ELSE 'N' END as "CreatedAt",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='CreatedBy') THEN 'Y' ELSE 'N' END as "CreatedBy",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='UpdatedAt') THEN 'Y' ELSE 'N' END as "UpdatedAt",
  CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='UpdatedBy') THEN 'Y' ELSE 'N' END as "UpdatedBy"
FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
  AND t.table_name NOT LIKE 'AspNet%' AND t.table_name NOT LIKE '__EF%'
  AND (
    NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='CreatedAt')
    OR NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='CreatedBy')
  )
ORDER BY t.table_name;

-- 3. Check important missing columns for specific tables
-- StoreId missing
SELECT 'Missing StoreId' as issue, t.table_name
FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
  AND t.table_name IN ('SalaryProfiles','Overtimes','Leaves','Shifts','WorkSchedules','Holidays','Departments','Employees','PenaltyTickets','AdvanceRequests','CashTransactions','InternalCommunications','Feedbacks','WorkTasks','TransactionCategories','PenaltySettings')
  AND NOT EXISTS(SELECT 1 FROM information_schema.columns c WHERE c.table_name=t.table_name AND c.column_name='StoreId')
ORDER BY t.table_name;

-- 4. Check column count per table
SELECT table_name, COUNT(*) as col_count
FROM information_schema.columns 
WHERE table_schema='public'
  AND table_name NOT LIKE 'AspNet%' AND table_name NOT LIKE '__EF%'
GROUP BY table_name
ORDER BY table_name;
