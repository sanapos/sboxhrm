-- Check remaining tables used by SampleDataController

-- Departments columns
SELECT 'Departments' as tbl, column_name FROM information_schema.columns WHERE table_name='Departments' ORDER BY ordinal_position;

-- Employees columns
SELECT 'Employees' as tbl, column_name FROM information_schema.columns WHERE table_name='Employees' ORDER BY ordinal_position;

-- ShiftTemplates columns
SELECT 'ShiftTemplates' as tbl, column_name FROM information_schema.columns WHERE table_name='ShiftTemplates' ORDER BY ordinal_position;

-- SalaryProfiles columns
SELECT 'SalaryProfiles' as tbl, column_name FROM information_schema.columns WHERE table_name='SalaryProfiles' ORDER BY ordinal_position;

-- Devices columns  
SELECT 'Devices' as tbl, column_name FROM information_schema.columns WHERE table_name='Devices' ORDER BY ordinal_position;

-- DeviceInfos columns
SELECT 'DeviceInfos' as tbl, column_name FROM information_schema.columns WHERE table_name='DeviceInfos' ORDER BY ordinal_position;

-- Holidays columns
SELECT 'Holidays' as tbl, column_name FROM information_schema.columns WHERE table_name='Holidays' ORDER BY ordinal_position;

-- TransactionCategories columns 
SELECT 'TransactionCategories' as tbl, column_name FROM information_schema.columns WHERE table_name='TransactionCategories' ORDER BY ordinal_position;

-- RolePermissions columns
SELECT 'RolePermissions' as tbl, column_name FROM information_schema.columns WHERE table_name='RolePermissions' ORDER BY ordinal_position;

-- TaskAssignees columns
SELECT 'TaskAssignees' as tbl, column_name FROM information_schema.columns WHERE table_name='TaskAssignees' ORDER BY ordinal_position;

-- ContentCategories existence
SELECT 'ContentCategories' as tbl, column_name FROM information_schema.columns WHERE table_name='ContentCategories' ORDER BY ordinal_position;

-- WorkSchedules columns  
SELECT 'WorkSchedules' as tbl, column_name FROM information_schema.columns WHERE table_name='WorkSchedules' ORDER BY ordinal_position;

-- AttendanceLogs columns
SELECT 'AttendanceLogs' as tbl, column_name FROM information_schema.columns WHERE table_name='AttendanceLogs' ORDER BY ordinal_position;

-- Shifts columns  
SELECT 'Shifts' as tbl, column_name FROM information_schema.columns WHERE table_name='Shifts' ORDER BY ordinal_position;
