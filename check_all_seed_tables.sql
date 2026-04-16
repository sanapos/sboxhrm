-- Comprehensive check of all tables used by SeedSampleData
-- Check InternalCommunications columns
SELECT 'InternalCommunications' as tbl, column_name FROM information_schema.columns WHERE table_name='InternalCommunications' ORDER BY ordinal_position;

-- Check if these tables exist
SELECT table_name FROM information_schema.tables 
WHERE table_schema='public' AND table_type='BASE TABLE'
AND table_name IN ('TaskAssignees','ContentCategories','CommunicationComments','CommunicationReactions','RolePermissions','Permissions','WorkTasks','InternalCommunications','DeviceInfos')
ORDER BY table_name;

-- Check WorkTasks columns
SELECT 'WorkTasks' as tbl, column_name FROM information_schema.columns WHERE table_name='WorkTasks' ORDER BY ordinal_position;

-- Check CashTransactions columns  
SELECT 'CashTransactions' as tbl, column_name FROM information_schema.columns WHERE table_name='CashTransactions' ORDER BY ordinal_position;

-- Check PenaltyTickets columns
SELECT 'PenaltyTickets' as tbl, column_name FROM information_schema.columns WHERE table_name='PenaltyTickets' ORDER BY ordinal_position;

-- Check AdvanceRequests columns
SELECT 'AdvanceRequests' as tbl, column_name FROM information_schema.columns WHERE table_name='AdvanceRequests' ORDER BY ordinal_position;

-- Check Overtimes columns
SELECT 'Overtimes' as tbl, column_name FROM information_schema.columns WHERE table_name='Overtimes' ORDER BY ordinal_position;

-- Check Leaves columns
SELECT 'Leaves' as tbl, column_name FROM information_schema.columns WHERE table_name='Leaves' ORDER BY ordinal_position;
